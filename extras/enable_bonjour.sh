#!/bin/bash
#
# Script to enable Bonjour/mDNS and local network discovery for VPN clients
# Supports IKEv2, IPsec/XAuth ("Cisco IPsec"), and IPsec/L2TP modes
#
# DO NOT RUN THIS SCRIPT ON YOUR PC OR MAC!
#
# Uses avahi-daemon + dnsmasq as a DNS-SD proxy so that VPN clients can discover
# and resolve .local services on the server's LAN (printers, AirPlay, etc.)
#
# The latest version of this script is available at:
# https://github.com/hwdsl2/setup-ipsec-vpn
#
# Copyright (C) 2024-2026 Lin Song <linsongui@gmail.com>
# Copyright (C) 2026 James Blain
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

exiterr()  { echo "Error: $1" >&2; exit 1; }
bigecho()  { echo "## $1"; }

conf_bk_bonjour() {
  if [ -f "$1" ] && [ ! -f "$1.bak.bonjour-vpn" ]; then
    /bin/cp -f "$1" "$1.bak.bonjour-vpn"
  fi
}

check_ip() {
  IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "$IP_REGEX"
}

check_ip6() {
  # Minimal IPv6 sanity check: must contain ":" and only hex/colon/dot chars.
  # Full RFC 4291 validation is overkill; we only need to filter obviously
  # invalid strings from parsed config files.
  printf '%s' "$1" | tr -d '\n' | grep -Eq '^[0-9a-fA-F:]+$' && \
  printf '%s' "$1" | grep -q ':'
}

check_root() {
  if [ "$(id -u)" != 0 ]; then
    exiterr "Script must be run as root. Try 'sudo bash $0'"
  fi
}

check_os() {
  rh_file="/etc/redhat-release"
  if [ -f "$rh_file" ]; then
    os_type=centos
    if grep -q "Red Hat" "$rh_file"; then
      os_type=rhel
    fi
    [ -f /etc/oracle-release ] && os_type=ol
    grep -qi rocky "$rh_file" && os_type=rocky
    grep -qi alma "$rh_file" && os_type=alma
    if grep -q "release 7" "$rh_file"; then
      os_ver=7
    elif grep -q "release 8" "$rh_file"; then
      os_ver=8
    elif grep -q "release 9" "$rh_file"; then
      os_ver=9
    elif grep -q "release 10" "$rh_file"; then
      os_ver=10
    else
      exiterr "This script only supports CentOS/RHEL 7-10."
    fi
  elif grep -qs "Amazon Linux release 2 " /etc/system-release; then
    os_type=amzn
    os_ver=2
  else
    os_type=$(lsb_release -si 2>/dev/null)
    [ -z "$os_type" ] && [ -f /etc/os-release ] && os_type=$(. /etc/os-release && printf '%s' "$ID")
    case $os_type in
      [Uu]buntu)
        os_type=ubuntu
        ;;
      [Dd]ebian|[Kk]ali|[Rr]aspbian)
        os_type=debian
        ;;
      [Aa]lpine)
        os_type=alpine
        ;;
      *)
cat 1>&2 <<'EOF'
Error: This script only supports one of the following OS:
       Ubuntu, Debian, CentOS/RHEL, Rocky Linux, AlmaLinux,
       Oracle Linux, Amazon Linux 2 or Alpine Linux
EOF
        exit 1
        ;;
    esac
  fi
}

check_vpn_modes() {
  IKEV2_CONF="/etc/ipsec.d/ikev2.conf"
  IPSEC_CONF="/etc/ipsec.conf"
  XL2TPD_CONF="/etc/xl2tpd/xl2tpd.conf"
  PPP_OPTIONS="/etc/ppp/options.xl2tpd"
  HAS_IKEV2=0
  HAS_XAUTH=0
  HAS_L2TP=0
  IKEV2_ONLY=0
  if [ -f "$IKEV2_CONF" ] && grep -qs "conn ikev2-cp" "$IKEV2_CONF"; then
    HAS_IKEV2=1
  fi
  # Check if IKEv2-only mode is enabled (ikev1-policy=drop in config setup)
  # When active, XAuth and L2TP configs exist but are not usable
  if [ -f "$IPSEC_CONF" ] && grep -qs "ikev1-policy=drop" "$IPSEC_CONF"; then
    IKEV2_ONLY=1
  fi
  if [ "$IKEV2_ONLY" = 0 ]; then
    if [ -f "$IPSEC_CONF" ] && grep -qs "conn xauth-psk" "$IPSEC_CONF"; then
      HAS_XAUTH=1
    fi
    if [ -f "$XL2TPD_CONF" ]; then
      HAS_L2TP=1
    fi
  fi
  if [ "$HAS_IKEV2" = 0 ] && [ "$HAS_XAUTH" = 0 ] && [ "$HAS_L2TP" = 0 ]; then
    exiterr "No VPN modes are configured. At least one of IKEv2, XAuth, or L2TP must be set up."
  fi
}

check_ipsec_running() {
  if ! service ipsec status >/dev/null 2>&1; then
    exiterr "IPsec service is not running. Start it with 'service ipsec start'."
  fi
}

check_already_configured() {
  if [ -f /etc/dnsmasq.d/bonjour-vpn.conf ]; then
    echo "Bonjour/mDNS for VPN is already configured on this server."
    printf '%s' "Do you want to reconfigure? [y/N] "
    read -r response
    case $response in
      [yY][eE][sS]|[yY])
        echo
        ;;
      *)
        echo "Abort. No changes were made." >&2
        exit 1
        ;;
    esac
  fi
}

check_existing_dns() {
  # Check if another DNS server (BIND, dnsmasq, unbound, etc.) is running.
  # If it listens on all interfaces, it will grab any new loopback IP we add,
  # blocking dnsmasq from binding. We detect this and use an alternate IP.
  DNS_PORT_CONFLICT=0
  if [ ! -f /etc/dnsmasq.d/bonjour-vpn.conf ]; then
    # Check for any process listening on port 53 (excluding systemd-resolved)
    if ss -ulnp 2>/dev/null | grep ':53 ' | grep -v 'systemd-resolve' | grep -qv 'dnsmasq'; then
      DNS_PORT_CONFLICT=1
      echo "Note: A DNS server is already running on this server."
      echo "      dnsmasq will use an alternate IP to avoid conflicts."
    fi
    if pgrep -x dnsmasq >/dev/null 2>&1; then
      echo "Note: dnsmasq is already running on this server."
      echo "      This script will add a VPN-specific config to /etc/dnsmasq.d/."
    fi
  fi
}

detect_iface() {
  def_iface=$(route 2>/dev/null | grep -m 1 '^default' | grep -o '[^ ]*$')
  if [ "$os_type" != "alpine" ]; then
    [ -z "$def_iface" ] && def_iface=$(ip -4 route list 0/0 2>/dev/null | grep -m 1 -o 'dev [^ ]*' | sed 's/dev //')
  fi
  def_state=$(cat "/sys/class/net/$def_iface/operstate" 2>/dev/null)
  if [ -n "$def_state" ] && [ "$def_state" != "down" ]; then
    NET_IFACE="$def_iface"
  else
    eth0_state=$(cat "/sys/class/net/eth0/operstate" 2>/dev/null)
    if [ -z "$eth0_state" ] || [ "$eth0_state" = "down" ]; then
      exiterr "Could not detect the default network interface."
    fi
    NET_IFACE=eth0
  fi
}

detect_server_lan_ip() {
  SERVER_LAN_IP=$(ip -4 addr show dev "$NET_IFACE" 2>/dev/null \
    | grep -oE 'inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 | awk '{print $2}')
  if [ -z "$SERVER_LAN_IP" ] || ! check_ip "$SERVER_LAN_IP"; then
    exiterr "Could not detect server's LAN IP on interface '$NET_IFACE'."
  fi
}

detect_lan_subnet() {
  LAN_CIDR=$(ip -4 addr show dev "$NET_IFACE" 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | head -n 1)
  if [ -z "$LAN_CIDR" ]; then
    LAN_CIDR="${SERVER_LAN_IP}/24"
  fi
}

detect_vpn_subnet() {
  # Detect IKEv2/XAuth subnet
  # Try ikev2.conf first, then fall back to ipsec.conf xauth-psk section
  VPN_POOL=""
  if [ "$HAS_IKEV2" = 1 ]; then
    VPN_POOL=$(grep 'rightaddresspool=' "$IKEV2_CONF" | head -n 1 \
      | sed 's/.*rightaddresspool=//' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    if [ -z "$VPN_POOL" ]; then
      VPN_POOL=$(grep 'rightaddresspool=' "$IKEV2_CONF" | head -n 1 \
        | sed 's/.*rightaddresspool=//' | cut -d ',' -f 1 | tr -d '[:space:]')
    fi
  fi
  if [ -z "$VPN_POOL" ] && [ "$HAS_XAUTH" = 1 ]; then
    VPN_POOL=$(sed -n '/conn xauth-psk/,/^conn /{ s/.*rightaddresspool=\([0-9.]*-[0-9.]*\).*/\1/p; }' \
      "$IPSEC_CONF" | head -n 1)
  fi
  if [ -n "$VPN_POOL" ]; then
    POOL_START=$(printf '%s' "$VPN_POOL" | cut -d '-' -f 1)
    VPN_SUBNET_PREFIX=$(printf '%s' "$POOL_START" | cut -d. -f1-3)
    VPN_SUBNET="${VPN_SUBNET_PREFIX}.0/24"
    VPN_SERVER_IP="${VPN_SUBNET_PREFIX}.1"
  else
    VPN_SUBNET_PREFIX="192.168.43"
    VPN_SUBNET="${VPN_SUBNET_PREFIX}.0/24"
    VPN_SERVER_IP="${VPN_SUBNET_PREFIX}.1"
  fi
  # If another DNS server will conflict on port 53 for this IP,
  # use .2 instead of .1 (outside the default pool range of .10-.250)
  if [ "$DNS_PORT_CONFLICT" = 1 ]; then
    VPN_SERVER_IP="${VPN_SUBNET_PREFIX}.2"
  fi
  XAUTH_SERVER_IP="$VPN_SERVER_IP"
  if ! check_ip "$VPN_SERVER_IP"; then
    exiterr "Could not determine VPN server IP from pool configuration."
  fi
}

detect_l2tp_subnet() {
  if [ "$HAS_L2TP" = 0 ]; then
    return
  fi
  # Parse local ip from xl2tpd.conf
  L2TP_SERVER_IP=$(grep 'local ip' "$XL2TPD_CONF" | head -n 1 \
    | sed 's/.*=\s*//' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
  if [ -z "$L2TP_SERVER_IP" ] || ! check_ip "$L2TP_SERVER_IP"; then
    L2TP_SERVER_IP="192.168.42.1"
  fi
  # Parse ip range to derive subnet
  L2TP_POOL_LINE=$(grep 'ip range' "$XL2TPD_CONF" | head -n 1 \
    | sed 's/.*=\s*//' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
  if [ -n "$L2TP_POOL_LINE" ]; then
    L2TP_POOL_START=$(printf '%s' "$L2TP_POOL_LINE" | cut -d '-' -f 1)
    L2TP_SUBNET_PREFIX=$(printf '%s' "$L2TP_POOL_START" | cut -d. -f1-3)
    L2TP_SUBNET="${L2TP_SUBNET_PREFIX}.0/24"
  else
    L2TP_SUBNET_PREFIX=$(printf '%s' "$L2TP_SERVER_IP" | cut -d. -f1-3)
    L2TP_SUBNET="${L2TP_SUBNET_PREFIX}.0/24"
  fi
}

detect_vpn_ipv6() {
  # Detect if the VPN has IPv6 enabled by checking for an IPv6 pool in
  # rightaddresspool. Only IKEv2 mode supports IPv6 in this project.
  #
  # Pool format in ikev2.conf when IPv6 is enabled:
  #   rightaddresspool=192.168.43.10-192.168.43.250,fddd:500:500:500::1000-fddd:500:500:500::1fff
  #
  # We extract:
  #   VPN_POOL_IPV6          - the raw IPv6 range (start-end)
  #   VPN_POOL_IPV6_START    - the first IP in the pool
  #   VPN_SUBNET_IPV6        - the /64 subnet (derived from pool prefix)
  #   VPN_SERVER_IP_IPV6     - the server's IPv6 address (first ::1 in the subnet)
  #
  # Sets HAS_IPV6=1 if a valid IPv6 pool is found, otherwise HAS_IPV6=0.
  HAS_IPV6=0
  VPN_POOL_IPV6=""
  VPN_POOL_IPV6_START=""
  VPN_SUBNET_IPV6=""
  VPN_SERVER_IP_IPV6=""

  if [ "$HAS_IKEV2" = 1 ] && [ -f "$IKEV2_CONF" ]; then
    # Grab the rightaddresspool line, take the substring after the first comma
    # (that's where the IPv6 range lives when present), then isolate the
    # "start-end" form by cutting at whitespace.
    VPN_POOL_IPV6=$(grep 'rightaddresspool=' "$IKEV2_CONF" | head -n 1 \
      | sed 's/.*rightaddresspool=//' | tr -d '"' \
      | awk -F, '{for (i=2; i<=NF; i++) print $i}' \
      | awk '{print $1}' | grep ':' | head -n 1)
  fi

  if [ -n "$VPN_POOL_IPV6" ]; then
    VPN_POOL_IPV6_START=$(printf '%s' "$VPN_POOL_IPV6" | cut -d '-' -f 1)
    if check_ip6 "$VPN_POOL_IPV6_START"; then
      # Derive the /64 subnet from the pool start address. For compressed
      # form (fddd:500:500:500::1000) take everything before "::"; for
      # expanded form (fddd:500:500:500:0:0:0:1000) take the first 4
      # colon-separated groups. Both yield fddd:500:500:500::/64.
      if printf '%s' "$VPN_POOL_IPV6_START" | grep -q '::'; then
        VPN_SUBNET_IPV6="$(printf '%s' "$VPN_POOL_IPV6_START" | sed 's/::.*//')::/64"
      else
        VPN_SUBNET_IPV6="$(printf '%s' "$VPN_POOL_IPV6_START" | cut -d: -f1-4)::/64"
      fi
      # Server IP is ::1 in the pool's /64 (outside the client range)
      VPN_SERVER_IP_IPV6=$(printf '%s' "$VPN_POOL_IPV6_START" \
        | sed -E 's/:[0-9a-fA-F]*$/:1/')
      HAS_IPV6=1
    fi
  fi
}

parse_upstream_dns() {
  # Try ikev2.conf first
  DNS_LINE=""
  if [ "$HAS_IKEV2" = 1 ]; then
    DNS_LINE=$(grep -m 1 'modecfgdns=' "$IKEV2_CONF")
  fi
  # If not found, try ipsec.conf (conn xauth-psk section)
  if [ -z "$DNS_LINE" ] && [ "$HAS_XAUTH" = 1 ]; then
    DNS_LINE=$(sed -n '/conn xauth-psk/,/^conn /{ /modecfgdns=/p; }' "$IPSEC_CONF" | head -n 1)
  fi
  # If not found, try options.xl2tpd (ms-dns lines)
  if [ -z "$DNS_LINE" ] && [ "$HAS_L2TP" = 1 ] && [ -f "$PPP_OPTIONS" ]; then
    MS_DNS1=$(grep -m 1 '^ms-dns ' "$PPP_OPTIONS" | awk '{print $2}')
    MS_DNS2=$(grep '^ms-dns ' "$PPP_OPTIONS" | sed -n '2p' | awk '{print $2}')
    if [ -n "$MS_DNS1" ]; then
      UPSTREAM_DNS1="$MS_DNS1"
      UPSTREAM_DNS2="${MS_DNS2:-8.8.4.4}"
      # Filter out our own IPs from previous runs
      if [ "$UPSTREAM_DNS1" = "$VPN_SERVER_IP" ] || [ "$UPSTREAM_DNS1" = "$L2TP_SERVER_IP" ]; then
        UPSTREAM_DNS1="$UPSTREAM_DNS2"
        UPSTREAM_DNS2="8.8.4.4"
      fi
      [ -z "$UPSTREAM_DNS1" ] && UPSTREAM_DNS1="8.8.8.8"
      return
    fi
  fi
  if [ -z "$DNS_LINE" ]; then
    UPSTREAM_DNS1="8.8.8.8"
    UPSTREAM_DNS2="8.8.4.4"
    return
  fi
  # Parse modecfgdns= format
  # Formats: modecfgdns=8.8.8.8  or  modecfgdns="8.8.8.8 8.8.4.4"
  DNS_RAW=$(printf '%s' "$DNS_LINE" | sed 's/.*modecfgdns=//' | tr -d '"' | tr -d "'" | tr -s ' ')
  # If it already contains our VPN_SERVER_IP (from a previous run), skip it
  DNS_RAW_CLEANED=""
  for dns_entry in $DNS_RAW; do
    if [ "$dns_entry" != "$VPN_SERVER_IP" ] && [ "$dns_entry" != "$L2TP_SERVER_IP" ] && check_ip "$dns_entry"; then
      DNS_RAW_CLEANED="$DNS_RAW_CLEANED $dns_entry"
    fi
  done
  DNS_RAW_CLEANED=$(printf '%s' "$DNS_RAW_CLEANED" | sed 's/^ //')
  UPSTREAM_DNS1=$(printf '%s' "$DNS_RAW_CLEANED" | awk '{print $1}')
  UPSTREAM_DNS2=$(printf '%s' "$DNS_RAW_CLEANED" | awk '{print $2}')
  [ -z "$UPSTREAM_DNS1" ] && UPSTREAM_DNS1="8.8.8.8"
  [ -z "$UPSTREAM_DNS2" ] && UPSTREAM_DNS2="8.8.4.4"
}

install_packages() {
  bigecho "Installing required packages..."
  if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get -yqq update || apt-get -yqq update || exiterr "'apt-get update' failed."
    apt-get -yqq install avahi-daemon avahi-utils dnsmasq >/dev/null \
      || exiterr "'apt-get install' failed."
  elif [ "$os_type" = "alpine" ]; then
    apk update || exiterr "'apk update' failed."
    apk add avahi avahi-tools dnsmasq || exiterr "'apk add' failed."
  else
    # CentOS/RHEL/Rocky/Alma/Amazon
    if command -v dnf >/dev/null 2>&1; then
      dnf -y -q install avahi avahi-tools dnsmasq >/dev/null \
        || exiterr "'dnf install' failed."
    else
      yum -y -q install avahi avahi-tools dnsmasq >/dev/null \
        || exiterr "'yum install' failed."
    fi
  fi
}

configure_avahi() {
  bigecho "Configuring avahi-daemon..."
  AVAHI_CONF="/etc/avahi/avahi-daemon.conf"
  mkdir -p /etc/avahi
  conf_bk_bonjour "$AVAHI_CONF"
  # Scope avahi to the LAN interface so it only discovers services on the
  # physical network, not on VPN tunnels or other virtual interfaces.
cat > "$AVAHI_CONF" <<EOF
[server]
use-ipv4=yes
use-ipv6=yes
enable-dbus=yes
disallow-other-stacks=no
allow-interfaces=$NET_IFACE

[wide-area]
enable-wide-area=yes

[publish]
publish-addresses=yes
publish-hinfo=yes
publish-workstation=no
publish-domain=yes
publish-aaaa-on-ipv4=yes
publish-a-on-ipv6=no

[reflector]
enable-reflector=yes
reflect-ipv=no

[rlimits]
rlimit-core=0
rlimit-data=4194304
rlimit-fsize=0
rlimit-nofile=768
rlimit-stack=4194304
rlimit-nproc=100
EOF
}

check_systemd_resolved() {
  RESOLVED_ACTIVE=0
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
      RESOLVED_ACTIVE=1
    fi
  fi
}

configure_dnsmasq() {
  bigecho "Configuring dnsmasq..."
  DNSMASQ_CONF="/etc/dnsmasq.conf"
  DNSMASQ_D="/etc/dnsmasq.d"
  DNSMASQ_VPN_CONF="${DNSMASQ_D}/bonjour-vpn.conf"
  # Create dnsmasq.d directory if needed
  mkdir -p "$DNSMASQ_D"
  # Ensure main config includes the .d directory (check both commented and uncommented forms)
  if [ -f "$DNSMASQ_CONF" ]; then
    if grep -qs "^conf-dir=/etc/dnsmasq.d" "$DNSMASQ_CONF"; then
      : # Already has an active conf-dir line, nothing to do
    elif grep -qs "^#conf-dir=/etc/dnsmasq.d" "$DNSMASQ_CONF"; then
      # Uncomment the existing commented-out line
      conf_bk_bonjour "$DNSMASQ_CONF"
      if [ "$os_type" = "alpine" ]; then
        sed -i 's|^#conf-dir=/etc/dnsmasq.d.*|conf-dir=/etc/dnsmasq.d/,*.conf|' "$DNSMASQ_CONF"
      else
        sed --follow-symlinks -i 's|^#conf-dir=/etc/dnsmasq.d.*|conf-dir=/etc/dnsmasq.d/,*.conf|' "$DNSMASQ_CONF"
      fi
    else
      # No conf-dir line at all, add one
      conf_bk_bonjour "$DNSMASQ_CONF"
      echo "conf-dir=/etc/dnsmasq.d/,*.conf" >> "$DNSMASQ_CONF"
    fi
  else
    echo "conf-dir=/etc/dnsmasq.d/,*.conf" > "$DNSMASQ_CONF"
  fi
  # Build listen-address directive with all applicable VPN server IPs
  LISTEN_IPS=""
  check_systemd_resolved
  if [ "$RESOLVED_ACTIVE" = 0 ]; then
    LISTEN_IPS="127.0.0.1"
  fi
  if [ "$HAS_IKEV2" = 1 ] || [ "$HAS_XAUTH" = 1 ]; then
    if [ -n "$LISTEN_IPS" ]; then
      LISTEN_IPS="${LISTEN_IPS},${VPN_SERVER_IP}"
    else
      LISTEN_IPS="${VPN_SERVER_IP}"
    fi
  fi
  if [ "$HAS_L2TP" = 1 ]; then
    if [ -n "$LISTEN_IPS" ]; then
      LISTEN_IPS="${LISTEN_IPS},${L2TP_SERVER_IP}"
    else
      LISTEN_IPS="${L2TP_SERVER_IP}"
    fi
  fi
  # Append the IPv6 server address if the VPN has IPv6 enabled. dnsmasq
  # accepts comma-separated IPv4 and IPv6 addresses in the same
  # listen-address directive, and bind-interfaces still works for both.
  if [ "$HAS_IPV6" = 1 ] && [ -n "$VPN_SERVER_IP_IPV6" ]; then
    LISTEN_IPS="${LISTEN_IPS},${VPN_SERVER_IP_IPV6}"
  fi
  LISTEN_ADDR="listen-address=${LISTEN_IPS}"
  # Build upstream DNS server lines
  DNS_SERVERS=""
  if [ -n "$UPSTREAM_DNS1" ]; then
    DNS_SERVERS="server=$UPSTREAM_DNS1"
  fi
  if [ -n "$UPSTREAM_DNS2" ]; then
    DNS_SERVERS=$(printf '%s\nserver=%s' "$DNS_SERVERS" "$UPSTREAM_DNS2")
  fi
cat > "$DNSMASQ_VPN_CONF" <<EOF
# Bonjour/mDNS proxy for VPN clients (IKEv2, XAuth, L2TP)
# Added by enable_bonjour.sh

# Listen on VPN server IPs (and localhost if systemd-resolved is not active)
${LISTEN_ADDR}
bind-interfaces

# Do not read /etc/resolv.conf for upstream servers
no-resolv

# Upstream DNS servers for all other queries
${DNS_SERVERS}

# Try upstream servers in order — ensures the local/internal DNS server
# is queried first before falling back to public DNS. Without this,
# dnsmasq may race both servers and a faster NXDOMAIN from public DNS
# can override a valid response from the internal DNS server.
strict-order

# Performance tuning
cache-size=1000
dns-forward-max=150

# Security: do not forward plain names or bogus private reverse lookups
domain-needed
bogus-priv

# Hosts file with .local hostnames, populated by the cache-warmer
addn-hosts=/etc/bonjour-vpn-hosts

# DNS-SD service records (PTR/SRV/TXT) are auto-generated by the
# cache-warmer into /etc/dnsmasq.d/bonjour-vpn-services.conf

# Logging (uncomment for debugging)
# log-queries
# log-facility=/var/log/dnsmasq-bonjour.log
EOF
  # Create empty hosts file so dnsmasq doesn't complain
  touch /etc/bonjour-vpn-hosts
}

assign_vpn_server_ip() {
  # For IKEv2/XAuth: add VPN_SERVER_IP to loopback (needed as dnsmasq listen address)
  if [ "$HAS_IKEV2" = 1 ] || [ "$HAS_XAUTH" = 1 ]; then
    bigecho "Assigning VPN server IP ($VPN_SERVER_IP) to loopback..."
    if ! ip addr show dev lo 2>/dev/null | grep -q "${VPN_SERVER_IP}/"; then
      ip addr add "${VPN_SERVER_IP}/32" dev lo || exiterr "Failed to add $VPN_SERVER_IP to loopback."
    fi
    # Make it persistent via /etc/rc.local
    RC_LOCAL="/etc/rc.local"
    if [ "$os_type" = "alpine" ]; then
      RC_LOCAL_ALPINE="/etc/local.d/bonjour-vpn.start"
      mkdir -p /etc/local.d
cat > "$RC_LOCAL_ALPINE" <<EOF
#!/bin/sh
# Added by enable_bonjour.sh - Bonjour/mDNS VPN support
ip addr add ${VPN_SERVER_IP}/32 dev lo 2>/dev/null
EOF
      chmod +x "$RC_LOCAL_ALPINE"
      rc-update add local default 2>/dev/null
    else
      if [ -f "$RC_LOCAL" ]; then
        if ! grep -qs "# Added by enable_bonjour.sh" "$RC_LOCAL"; then
          conf_bk_bonjour "$RC_LOCAL"
          sed --follow-symlinks -i '/^exit 0$/d' "$RC_LOCAL"
cat >> "$RC_LOCAL" <<EOF

# Added by enable_bonjour.sh - Bonjour/mDNS VPN support
ip addr add ${VPN_SERVER_IP}/32 dev lo 2>/dev/null
exit 0
EOF
        fi
      else
cat > "$RC_LOCAL" <<EOF
#!/bin/sh

# Added by enable_bonjour.sh - Bonjour/mDNS VPN support
ip addr add ${VPN_SERVER_IP}/32 dev lo 2>/dev/null
exit 0
EOF
      fi
      chmod +x "$RC_LOCAL"
    fi
  fi
  # For L2TP: add L2TP_SERVER_IP to loopback too.
  # xl2tpd only assigns this IP to ppp interfaces when clients connect.
  # dnsmasq needs it always available to bind to.
  if [ "$HAS_L2TP" = 1 ] && [ -n "$L2TP_SERVER_IP" ]; then
    if ! ip addr show dev lo 2>/dev/null | grep -q "${L2TP_SERVER_IP}/"; then
      bigecho "Assigning L2TP server IP ($L2TP_SERVER_IP) to loopback..."
      ip addr add "${L2TP_SERVER_IP}/32" dev lo || exiterr "Failed to add $L2TP_SERVER_IP to loopback."
    fi
    # Persist in rc.local / local.d alongside the IKEv2/XAuth IP
    if [ "$os_type" = "alpine" ]; then
      RC_LOCAL_ALPINE="/etc/local.d/bonjour-vpn.start"
      if [ -f "$RC_LOCAL_ALPINE" ] && ! grep -q "${L2TP_SERVER_IP}/32" "$RC_LOCAL_ALPINE"; then
        sed -i "$ a ip addr add ${L2TP_SERVER_IP}/32 dev lo 2>/dev/null" "$RC_LOCAL_ALPINE"
      fi
    else
      RC_LOCAL="/etc/rc.local"
      if [ -f "$RC_LOCAL" ] && ! grep -q "${L2TP_SERVER_IP}/32" "$RC_LOCAL"; then
        sed --follow-symlinks -i "/^exit 0$/i ip addr add ${L2TP_SERVER_IP}/32 dev lo 2>/dev/null" "$RC_LOCAL"
      fi
    fi
  fi
  # For IPv6: add VPN_SERVER_IP_IPV6 to loopback. dnsmasq's bind-interfaces
  # requires the address to exist before the service starts. Must match the
  # listen-address entry added by configure_dnsmasq().
  if [ "$HAS_IPV6" = 1 ] && [ -n "$VPN_SERVER_IP_IPV6" ]; then
    if ! ip -6 addr show dev lo 2>/dev/null | grep -q "${VPN_SERVER_IP_IPV6}/"; then
      bigecho "Assigning VPN server IPv6 ($VPN_SERVER_IP_IPV6) to loopback..."
      ip -6 addr add "${VPN_SERVER_IP_IPV6}/128" dev lo \
        || exiterr "Failed to add $VPN_SERVER_IP_IPV6 to loopback."
    fi
    # Persist
    if [ "$os_type" = "alpine" ]; then
      RC_LOCAL_ALPINE="/etc/local.d/bonjour-vpn.start"
      if [ -f "$RC_LOCAL_ALPINE" ] && ! grep -q "${VPN_SERVER_IP_IPV6}/128" "$RC_LOCAL_ALPINE"; then
        sed -i "$ a ip -6 addr add ${VPN_SERVER_IP_IPV6}/128 dev lo 2>/dev/null" "$RC_LOCAL_ALPINE"
      fi
    else
      RC_LOCAL="/etc/rc.local"
      if [ -f "$RC_LOCAL" ] && ! grep -q "${VPN_SERVER_IP_IPV6}/128" "$RC_LOCAL"; then
        sed --follow-symlinks -i \
          "/^exit 0$/i ip -6 addr add ${VPN_SERVER_IP_IPV6}/128 dev lo 2>/dev/null" "$RC_LOCAL"
      fi
    fi
  fi
}

update_vpn_dns_config() {
  bigecho "Updating VPN DNS configuration..."
  # NOTE: We intentionally do NOT push IPv6 DNS entries in modecfgdns. On
  # Libreswan up through 5.3, the INTERNAL_IP6_DNS config-payload attribute
  # is serialized with 17 bytes instead of the 16 bytes mandated by
  # RFC 5996, and strongSwan clients reject the IKE_AUTH response with
  # "invalid attribute length 17 for INTERNAL_IP6_DNS", breaking the tunnel
  # completely. IPv6 mDNS proxying still works via the IPv4 DNS endpoint —
  # VPN clients resolve AAAA records against the IPv4 VPN_SERVER_IP and get
  # fddd:500:500:500:* answers back unchanged.
  # --- IKEv2 ---
  if [ "$HAS_IKEV2" = 1 ]; then
    echo "  Updating IKEv2 config ($IKEV2_CONF)..."
    conf_bk_bonjour "$IKEV2_CONF"
    NEW_MODECFGDNS="  modecfgdns=\"${VPN_SERVER_IP} ${UPSTREAM_DNS1}\""
    if [ "$os_type" = "alpine" ]; then
      sed -i "s|^[[:space:]]*modecfgdns=.*|${NEW_MODECFGDNS}|" "$IKEV2_CONF"
    else
      sed --follow-symlinks -i "s|^[[:space:]]*modecfgdns=.*|${NEW_MODECFGDNS}|" "$IKEV2_CONF"
    fi
    # Set modecfgdomains — three domains serve distinct purposes:
    #   "local"          — iOS unicast DNS-SD for .local and hostname resolution
    #   "vpn.internal"   — macOS Wide-Area Bonjour browse domain (Finder Network)
    #   "."              — catch-all so VPN DNS handles ALL queries (no DNS leak)
    # IKEv1/XAuth: only the first domain is sent (protocol limitation).
    NEW_MODECFGDOMAINS='  modecfgdomains="local, vpn.internal, ."'
    if grep -qs 'modecfgdomains=' "$IKEV2_CONF"; then
      if [ "$os_type" = "alpine" ]; then
        sed -i "s|^[[:space:]]*modecfgdomains=.*|${NEW_MODECFGDOMAINS}|" "$IKEV2_CONF"
      else
        sed --follow-symlinks -i "s|^[[:space:]]*modecfgdomains=.*|${NEW_MODECFGDOMAINS}|" "$IKEV2_CONF"
      fi
    else
      if [ "$os_type" = "alpine" ]; then
        sed -i "/modecfgdns=/a\\${NEW_MODECFGDOMAINS}" "$IKEV2_CONF"
      else
        sed --follow-symlinks -i "/modecfgdns=/a\\${NEW_MODECFGDOMAINS}" "$IKEV2_CONF"
      fi
    fi
    chmod 600 "$IKEV2_CONF" 2>/dev/null
  fi
  # --- XAuth ---
  if [ "$HAS_XAUTH" = 1 ]; then
    echo "  Updating XAuth config ($IPSEC_CONF)..."
    conf_bk_bonjour "$IPSEC_CONF"
    # Parse existing modecfgdns from xauth-psk section
    XAUTH_DNS_LINE=$(sed -n '/conn xauth-psk/,/^conn /{ /modecfgdns=/p; }' "$IPSEC_CONF" | head -n 1)
    XAUTH_DNS_RAW=$(printf '%s' "$XAUTH_DNS_LINE" | sed 's/.*modecfgdns=//' | tr -d '"' | tr -d "'" | tr -s ' ')
    # Clean out our own IP from previous runs
    XAUTH_ORIG_DNS=""
    for dns_entry in $XAUTH_DNS_RAW; do
      if [ "$dns_entry" != "$VPN_SERVER_IP" ] && check_ip "$dns_entry"; then
        [ -z "$XAUTH_ORIG_DNS" ] && XAUTH_ORIG_DNS="$dns_entry"
      fi
    done
    [ -z "$XAUTH_ORIG_DNS" ] && XAUTH_ORIG_DNS="$UPSTREAM_DNS1"
    NEW_XAUTH_DNS="  modecfgdns=\"${VPN_SERVER_IP} ${XAUTH_ORIG_DNS}\""
    # Replace modecfgdns only within the conn xauth-psk section
    if [ "$os_type" = "alpine" ]; then
      sed -i "/conn xauth-psk/,/^conn /{
        s|^[[:space:]]*modecfgdns=.*|${NEW_XAUTH_DNS}|
      }" "$IPSEC_CONF"
    else
      sed --follow-symlinks -i "/conn xauth-psk/,/^conn /{
        s|^[[:space:]]*modecfgdns=.*|${NEW_XAUTH_DNS}|
      }" "$IPSEC_CONF"
    fi
    # Set modecfgdomains in xauth-psk section (same as IKEv2).
    # IKEv1 only sends the first domain ("local") — vpn.internal is
    # effectively IKEv2-only, which is fine since Finder/iOS are IKEv2.
    NEW_XAUTH_DOMAINS='  modecfgdomains="local, vpn.internal, ."'
    XAUTH_HAS_DOMAINS=$(sed -n '/conn xauth-psk/,/^conn /{ /modecfgdomains=/p; }' "$IPSEC_CONF")
    if [ -n "$XAUTH_HAS_DOMAINS" ]; then
      if [ "$os_type" = "alpine" ]; then
        sed -i "/conn xauth-psk/,/^conn /{
          s|^[[:space:]]*modecfgdomains=.*|${NEW_XAUTH_DOMAINS}|
        }" "$IPSEC_CONF"
      else
        sed --follow-symlinks -i "/conn xauth-psk/,/^conn /{
          s|^[[:space:]]*modecfgdomains=.*|${NEW_XAUTH_DOMAINS}|
        }" "$IPSEC_CONF"
      fi
    else
      if [ "$os_type" = "alpine" ]; then
        sed -i "/conn xauth-psk/,/^conn /{
          /modecfgdns=/a\\
${NEW_XAUTH_DOMAINS}
        }" "$IPSEC_CONF"
      else
        sed --follow-symlinks -i "/conn xauth-psk/,/^conn /{
          /modecfgdns=/a\\
${NEW_XAUTH_DOMAINS}
        }" "$IPSEC_CONF"
      fi
    fi
    chmod 600 "$IPSEC_CONF" 2>/dev/null
  fi
  # --- L2TP ---
  if [ "$HAS_L2TP" = 1 ] && [ -f "$PPP_OPTIONS" ]; then
    echo "  Updating L2TP config ($PPP_OPTIONS)..."
    conf_bk_bonjour "$PPP_OPTIONS"
    # Parse existing ms-dns entries
    L2TP_DNS1=$(grep -m 1 '^ms-dns ' "$PPP_OPTIONS" | awk '{print $2}')
    L2TP_DNS2=$(grep '^ms-dns ' "$PPP_OPTIONS" | sed -n '2p' | awk '{print $2}')
    # Determine the original first DNS (skip our own IP from previous runs)
    L2TP_ORIG_DNS="$L2TP_DNS1"
    if [ "$L2TP_ORIG_DNS" = "$L2TP_SERVER_IP" ]; then
      L2TP_ORIG_DNS="$L2TP_DNS2"
    fi
    [ -z "$L2TP_ORIG_DNS" ] && L2TP_ORIG_DNS="$UPSTREAM_DNS1"
    # Remove all existing ms-dns lines
    if [ "$os_type" = "alpine" ]; then
      sed -i '/^ms-dns /d' "$PPP_OPTIONS"
    else
      sed --follow-symlinks -i '/^ms-dns /d' "$PPP_OPTIONS"
    fi
    # Append new ms-dns lines: L2TP_SERVER_IP as primary, original as secondary
    printf 'ms-dns %s\n' "$L2TP_SERVER_IP" >> "$PPP_OPTIONS"
    printf 'ms-dns %s\n' "$L2TP_ORIG_DNS" >> "$PPP_OPTIONS"
  fi
}

update_iptables() {
  bigecho "Updating IPTables rules..."
  # Determine the iptables save file
  if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] \
    || [ "$os_type" = "alpine" ]; then
    IPT_FILE=/etc/iptables.rules
    IPT_FILE2=/etc/iptables/rules.v4
    IPT6_FILE=/etc/ip6tables.rules
    IPT6_FILE2=/etc/iptables/rules.v6
  else
    IPT_FILE=/etc/sysconfig/iptables
    IPT6_FILE=/etc/sysconfig/ip6tables
  fi
  # Add rules for IKEv2/XAuth subnet (they share the same subnet)
  if [ "$HAS_IKEV2" = 1 ] || [ "$HAS_XAUTH" = 1 ]; then
    if ! iptables -C INPUT -s "$VPN_SUBNET" -p udp --dport 53 -j ACCEPT 2>/dev/null; then
      iptables -I INPUT 1 -s "$VPN_SUBNET" -p udp --dport 53 -j ACCEPT
    fi
    if ! iptables -C INPUT -s "$VPN_SUBNET" -p tcp --dport 53 -j ACCEPT 2>/dev/null; then
      iptables -I INPUT 1 -s "$VPN_SUBNET" -p tcp --dport 53 -j ACCEPT
    fi
    if ! iptables -C INPUT -s "$VPN_SUBNET" -p udp --dport 5353 -j ACCEPT 2>/dev/null; then
      iptables -I INPUT 1 -s "$VPN_SUBNET" -p udp --dport 5353 -j ACCEPT
    fi
    # mDNS capture: redirect multicast mDNS from VPN clients to dnsmasq
    if ! iptables -t nat -C PREROUTING -s "$VPN_SUBNET" -d 224.0.0.251 -p udp --dport 5353 -j DNAT --to-destination "${VPN_SERVER_IP}:53" 2>/dev/null; then
      iptables -t nat -I PREROUTING -s "$VPN_SUBNET" -d 224.0.0.251 -p udp --dport 5353 -j DNAT --to-destination "${VPN_SERVER_IP}:53"
    fi
  fi
  # Add rules for L2TP subnet
  if [ "$HAS_L2TP" = 1 ]; then
    if ! iptables -C INPUT -s "$L2TP_SUBNET" -p udp --dport 53 -j ACCEPT 2>/dev/null; then
      iptables -I INPUT 1 -s "$L2TP_SUBNET" -p udp --dport 53 -j ACCEPT
    fi
    if ! iptables -C INPUT -s "$L2TP_SUBNET" -p tcp --dport 53 -j ACCEPT 2>/dev/null; then
      iptables -I INPUT 1 -s "$L2TP_SUBNET" -p tcp --dport 53 -j ACCEPT
    fi
    if ! iptables -C INPUT -s "$L2TP_SUBNET" -p udp --dport 5353 -j ACCEPT 2>/dev/null; then
      iptables -I INPUT 1 -s "$L2TP_SUBNET" -p udp --dport 5353 -j ACCEPT
    fi
    # mDNS capture: redirect multicast mDNS from L2TP clients to dnsmasq
    if ! iptables -t nat -C PREROUTING -s "$L2TP_SUBNET" -d 224.0.0.251 -p udp --dport 5353 -j DNAT --to-destination "${L2TP_SERVER_IP}:53" 2>/dev/null; then
      iptables -t nat -I PREROUTING -s "$L2TP_SUBNET" -d 224.0.0.251 -p udp --dport 5353 -j DNAT --to-destination "${L2TP_SERVER_IP}:53"
    fi
  fi
  # ===== IPv6 rules =====
  # Only apply if the VPN has IPv6 enabled AND ip6tables is actually usable.
  # Some kernels/containers lack ip6_tables or nf_nat_ipv6 — in that case
  # we log a warning and skip the IPv6 rules rather than failing the install.
  if [ "$HAS_IPV6" = 1 ] && [ -n "$VPN_SUBNET_IPV6" ] && [ -n "$VPN_SERVER_IP_IPV6" ]; then
    if ip6tables -t nat -L PREROUTING -n >/dev/null 2>&1; then
      # INPUT: allow DNS from the IPv6 VPN subnet
      if ! ip6tables -C INPUT -s "$VPN_SUBNET_IPV6" -p udp --dport 53 -j ACCEPT 2>/dev/null; then
        ip6tables -I INPUT 1 -s "$VPN_SUBNET_IPV6" -p udp --dport 53 -j ACCEPT
      fi
      if ! ip6tables -C INPUT -s "$VPN_SUBNET_IPV6" -p tcp --dport 53 -j ACCEPT 2>/dev/null; then
        ip6tables -I INPUT 1 -s "$VPN_SUBNET_IPV6" -p tcp --dport 53 -j ACCEPT
      fi
      if ! ip6tables -C INPUT -s "$VPN_SUBNET_IPV6" -p udp --dport 5353 -j ACCEPT 2>/dev/null; then
        ip6tables -I INPUT 1 -s "$VPN_SUBNET_IPV6" -p udp --dport 5353 -j ACCEPT
      fi
      # mDNS capture: redirect multicast mDNS (ff02::fb) from VPN clients to dnsmasq.
      # ff02::fb is the link-local mDNS multicast group (RFC 6762). IPv6 mDNS
      # clients send queries here; our DNAT captures them and forwards to dnsmasq
      # listening on the VPN server IPv6 address.
      if ! ip6tables -t nat -C PREROUTING -s "$VPN_SUBNET_IPV6" -d ff02::fb -p udp --dport 5353 -j DNAT --to-destination "[${VPN_SERVER_IP_IPV6}]:53" 2>/dev/null; then
        ip6tables -t nat -I PREROUTING -s "$VPN_SUBNET_IPV6" -d ff02::fb -p udp --dport 5353 -j DNAT --to-destination "[${VPN_SERVER_IP_IPV6}]:53"
      fi
    else
      echo "  Note: ip6tables nat table not available; skipping IPv6 rules" >&2
    fi
  fi
  # Save iptables rules
  if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] \
    || [ "$os_type" = "alpine" ]; then
    iptables-save > "$IPT_FILE"
    if [ -f "$IPT_FILE2" ]; then
      /bin/cp -f "$IPT_FILE" "$IPT_FILE2"
    fi
  else
    iptables-save > "$IPT_FILE"
  fi
  # Save ip6tables rules if IPv6 was configured
  if [ "$HAS_IPV6" = 1 ] && command -v ip6tables-save >/dev/null 2>&1; then
    if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] \
      || [ "$os_type" = "alpine" ]; then
      ip6tables-save > "$IPT6_FILE" 2>/dev/null || true
      if [ -f "$IPT6_FILE2" ]; then
        /bin/cp -f "$IPT6_FILE" "$IPT6_FILE2" 2>/dev/null || true
      fi
    else
      ip6tables-save > "$IPT6_FILE" 2>/dev/null || true
    fi
  fi
}

create_cache_warmer() {
  bigecho "Creating mDNS service monitor..."
  # Two scripts:
  #   1. bonjour-vpn-resolve — does a full service discovery and generates dnsmasq records
  #   2. bonjour-vpn-watch   — watches for mDNS events and triggers resolve when services change
  #
  # Architecture (real-time, event-driven):
  #   avahi-browse (passive watcher) --[event]--> debounce 3s --> full resolve --> dnsmasq restart
  #
  # The watcher listens to multicast mDNS traffic that's already on the network.
  # Zero CPU/network overhead when nothing changes. Near-instant updates when
  # a device appears or disappears.

  # --- Script 1: Full resolve (one-shot discovery + dnsmasq config generation) ---
  RESOLVE_SCRIPT="/usr/local/bin/bonjour-vpn-resolve"
cat > "$RESOLVE_SCRIPT" <<'RESOLVE_EOF'
#!/bin/bash
# Full Bonjour service discovery — generates dnsmasq DNS-SD records.
# Called by the watcher on service changes, and once at boot.

HOSTS_FILE="/etc/bonjour-vpn-hosts"
HOSTS_TMP="${HOSTS_FILE}.tmp"
SERVICES_FILE="/etc/dnsmasq.d/bonjour-vpn-services.conf"
SERVICES_TMP="${SERVICES_FILE}.tmp"
# Only include AAAA records when the VPN has IPv6 enabled. On IPv4-only
# VPNs, returning AAAA for .local names is a behavioral change the user
# did not opt into. The marker is maintained by enable_bonjour.sh and the
# IPv6 sync script.
IPV6_ENABLED=0
[ -f /var/lib/bonjour-vpn/ipv6-enabled ] && IPV6_ENABLED=1

# avahi-browse flags:
#   -a all services  -r resolve  -p parseable  -t terminate  -k no-db-lookup
# -k is critical: without it, avahi translates service types to friendly names.
BROWSE_OUTPUT=$(timeout 20 avahi-browse -arptk 2>/dev/null || true)

if [ -z "$BROWSE_OUTPUT" ]; then
  exit 0
fi

# Keep both IPv4 and IPv6 resolved entries. avahi-browse outputs each
# resolved service once per protocol (IPv4 or IPv6) and once per address
# it knows about, so the same hostname can appear with both an A record
# and an AAAA record — which is exactly what we want for dnsmasq's
# addn-hosts (it serves A for IPv4 addresses and AAAA for IPv6).
RESOLVED=$(printf '%s\n' "$BROWSE_OUTPUT" | grep '^=;' || true)
[ -z "$RESOLVED" ] && exit 0

# --- Generate hosts file (hostname -> IP) for addn-hosts ---
# addn-hosts accepts both IPv4 and IPv6 entries in the same file. dnsmasq
# automatically serves A records from IPv4 entries and AAAA records from
# IPv6 entries. We deduplicate by (address, host) pair so a hostname that
# has both IPv4 and IPv6 addresses yields two lines in the hosts file.
printf '%s\n' "$RESOLVED" | awk -F';' -v ipv6="$IPV6_ENABLED" '{
  addr=$8; host=$7
  if (addr != "" && host != "") {
    # Strip IPv6 zone suffix like "fe80::1%eth0" — dnsmasq does not accept
    # scoped addresses in addn-hosts. Link-local addresses on the LAN are
    # not routable to VPN clients anyway, so dropping them is safe.
    sub(/%[^ ]*/, "", addr)
    gsub(/[ \t]+$/, "", host)
    gsub(/[ \t]+$/, "", addr)
    # Skip IPv6 link-local (fe80::/10) — not useful to VPN clients.
    if (addr ~ /^fe80:/ || addr ~ /^fe[89ab][0-9a-f]:/) next
    # Skip all IPv6 addresses when the VPN does not have IPv6 enabled.
    if (ipv6 != "1" && addr ~ /:/) next
    key = addr SUBSEP host
    if (!seen[key]++) print addr " " host
  }
}' | sort > "$HOSTS_TMP"

if [ -s "$HOSTS_TMP" ]; then
  mv -f "$HOSTS_TMP" "$HOSTS_FILE"
else
  rm -f "$HOSTS_TMP"
fi

# --- Generate DNS-SD service records for dnsmasq ---
# Records are generated under BOTH .local and vpn.internal:
#   .local        — iOS unicast DNS-SD and IKEv1/XAuth clients
#   vpn.internal  — macOS Finder Network browsing (Wide-Area Bonjour)
# The vpn.internal domain is a non-.local unicast browse domain that
# macOS discovers via lb._dns-sd._udp.vpn.internal PTR records. macOS
# refuses to do unicast DNS-SD for .local (multicast only), so the
# second domain is required for Finder's Network sidebar to work.
# SRV hostnames always point to .local names (resolved via VPN DNS).
VPN_BROWSE_DOMAIN="vpn.internal"
printf '%s\n' "$RESOLVED" | awk -F';' -v bd="$VPN_BROWSE_DOMAIN" '
  BEGIN {
    print "# Auto-generated by bonjour-vpn-resolve - do not edit"
    print ""
    print "# Wide-Area Bonjour browse domain announcement"
    print "# Tells macOS to browse " bd " for services via unicast DNS-SD"
    print "ptr-record=b._dns-sd._udp." bd "," bd
    print "ptr-record=lb._dns-sd._udp." bd "," bd
    print "ptr-record=db._dns-sd._udp." bd "," bd
  }

  $1 != "=" { next }

  {
    name  = $4
    stype = $5
    host  = $7
    addr  = $8
    port  = $9
    txt   = $10

    if (name == "" || stype == "" || host == "") next

    # avahi -p escapes spaces as \032. Convert back to literal spaces.
    gsub(/\\032/, " ", name)
    # Skip entries with remaining avahi escapes (\058=colon, \091=bracket, etc.)
    if (name ~ /\\/) next
    # Strip IPv6 zone suffix from address
    sub(/%[^ ]*/, "", addr)
    gsub(/[ \t]+$/, "", addr)

    if (!type_seen[stype]++) types[++ntypes] = stype

    key = name SUBSEP stype
    if (inst_seen[key]++) next

    p = (port != "" ? port : "0")

    # Build records for both domains. For vpn.internal, replace spaces
    # with hyphens in the instance name. macOS constructs SMB URLs like
    # smb://<instance>.<type>.<domain> — spaces in the URL cause the
    # SMB client to fail (EHOSTUNREACH after 30s timeout) because
    # unicast DNS cannot resolve hostnames with spaces. Hyphens work.
    wa_name = name
    gsub(/ /, "-", wa_name)
    fqdn_local = name "." stype ".local"
    fqdn_wa    = wa_name "." stype "." bd

    idx = ++ninst
    # .local records (iOS, XAuth)
    inst_ptr_l[idx] = "ptr-record=" stype ".local," fqdn_local
    inst_srv_l[idx] = "srv-host=" fqdn_local "," host "," p
    # vpn.internal records (macOS Finder). SRV target stays .local.
    inst_ptr_w[idx] = "ptr-record=" stype "." bd "," fqdn_wa
    inst_srv_w[idx] = "srv-host=" fqdn_wa "," host "," p
    # A record for the service instance FQDN under vpn.internal.
    # macOS Finder constructs SMB URLs using the service instance name
    # (e.g., smb://BAM File Server._smb._tcp.vpn.internal) instead of
    # following the SRV target hostname. dnsmasq's host-record= can't
    # handle spaces in DNS labels, but address= can (it uses / as the
    # delimiter, so spaces are preserved in the domain name).
    if (addr != "" && addr !~ /:/) {
      inst_addr_w[idx] = "address=/" fqdn_wa "/" addr
    }

    if (txt != "") {
      gsub(/" "/, ",", txt)
      sub(/^"/, "", txt)
      sub(/"$/, "", txt)
      inst_txt_l[idx] = "txt-record=" fqdn_local "," txt
      inst_txt_w[idx] = "txt-record=" fqdn_wa "," txt
    }
  }

  END {
    # Service type enumeration — both domains
    print ""
    print "# Service types (.local)"
    for (i = 1; i <= ntypes; i++)
      print "ptr-record=_services._dns-sd._udp.local," types[i] ".local"
    print ""
    print "# Service types (" bd ")"
    for (i = 1; i <= ntypes; i++)
      print "ptr-record=_services._dns-sd._udp." bd "," types[i] "." bd
    # Service instances — .local
    print ""
    print "# Service instances (.local)"
    for (i = 1; i <= ninst; i++) {
      print inst_ptr_l[i]
      print inst_srv_l[i]
      if (inst_txt_l[i] != "") print inst_txt_l[i]
    }
    # Service instances — vpn.internal
    print ""
    print "# Service instances (" bd ")"
    for (i = 1; i <= ninst; i++) {
      print inst_ptr_w[i]
      print inst_srv_w[i]
      if (inst_txt_w[i] != "") print inst_txt_w[i]
      if (inst_addr_w[i] != "") print inst_addr_w[i]
    }
  }
' > "$SERVICES_TMP"

if [ -s "$SERVICES_TMP" ]; then
  mv -f "$SERVICES_TMP" "$SERVICES_FILE"
else
  rm -f "$SERVICES_TMP"
fi

# Restart dnsmasq to load new records (restarts in milliseconds)
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart dnsmasq 2>/dev/null || true
elif command -v rc-service >/dev/null 2>&1; then
  rc-service dnsmasq restart 2>/dev/null || true
fi
RESOLVE_EOF
  chmod +x "$RESOLVE_SCRIPT"

  # --- Script 2: IPv6 state sync (detects post-install IPv6 changes) ---
  # Handles the case where a user installs Bonjour on an IPv4-only VPN, then
  # later enables IPv6 on the VPN (either by re-running ikev2.sh with IPv6 or
  # manually editing ikev2.conf). Without this script, the user would have to
  # remember to re-run enable_bonjour.sh to pick up the new IPv6 state.
  # Called periodically by the watcher and at watcher startup. Idempotent.
  SYNC_SCRIPT="/usr/local/sbin/bonjour-vpn-ipv6-sync"
  mkdir -p /var/lib/bonjour-vpn
cat > "$SYNC_SCRIPT" <<'SYNC_EOF'
#!/bin/bash
# Bonjour VPN IPv6 state sync — reconciles dnsmasq/ip6tables/loopback
# with the current VPN IPv6 configuration in /etc/ipsec.d/ikev2.conf.
#
# Detects transitions:
#   - IPv6 off -> on:   assign IPv6 to lo, add dnsmasq listen, add ip6tables rules
#   - IPv6 on  -> off:  reverse all of the above
#   - IPv6 on  -> on':  (pool changed) tear down old, apply new
#
# Idempotent: running repeatedly with no state change is a no-op. Safe to
# call from the watcher's main loop every iteration.

IKEV2_CONF="/etc/ipsec.d/ikev2.conf"
STATE_FILE="/var/lib/bonjour-vpn/ipv6-state"
DNSMASQ_VPN_CONF="/etc/dnsmasq.d/bonjour-vpn.conf"
BONJOUR_MARK="# Added by enable_bonjour.sh"

# Minimal OS detection — needed for sed -i and iptables-save paths.
SYNC_OS_TYPE="linux"
if [ -f /etc/os-release ]; then
  case "$(. /etc/os-release && printf '%s' "$ID")" in
    alpine) SYNC_OS_TYPE="alpine" ;;
  esac
fi

# Only run as root
if [ "$(id -u)" != 0 ]; then
  exit 0
fi

# Portable sed -i: use --follow-symlinks on non-Alpine (GNU sed), plain
# -i on Alpine (BusyBox sed). Matches the project convention.
sedi() {
  if [ "$SYNC_OS_TYPE" = "alpine" ]; then
    sed -i "$@"
  else
    sed --follow-symlinks -i "$@"
  fi
}

check_ip6() {
  printf '%s' "$1" | tr -d '\n' | grep -Eq '^[0-9a-fA-F:]+$' && \
  printf '%s' "$1" | grep -q ':'
}

# ---------------- Parse current state from ikev2.conf ----------------
HAS_IPV6=0
VPN_POOL_IPV6=""
VPN_POOL_IPV6_START=""
VPN_SUBNET_IPV6=""
VPN_SERVER_IP_IPV6=""

if [ -f "$IKEV2_CONF" ]; then
  VPN_POOL_IPV6=$(grep 'rightaddresspool=' "$IKEV2_CONF" 2>/dev/null | head -n 1 \
    | sed 's/.*rightaddresspool=//' | tr -d '"' \
    | awk -F, '{for (i=2; i<=NF; i++) print $i}' \
    | awk '{print $1}' | grep ':' | head -n 1)
fi

if [ -n "$VPN_POOL_IPV6" ]; then
  VPN_POOL_IPV6_START=$(printf '%s' "$VPN_POOL_IPV6" | cut -d '-' -f 1)
  if check_ip6 "$VPN_POOL_IPV6_START"; then
    if printf '%s' "$VPN_POOL_IPV6_START" | grep -q '::'; then
      VPN_SUBNET_IPV6="$(printf '%s' "$VPN_POOL_IPV6_START" | sed 's/::.*//')::/64"
    else
      VPN_SUBNET_IPV6="$(printf '%s' "$VPN_POOL_IPV6_START" | cut -d: -f1-4)::/64"
    fi
    VPN_SERVER_IP_IPV6=$(printf '%s' "$VPN_POOL_IPV6_START" \
      | sed -E 's/:[0-9a-fA-F]*$/:1/')
    HAS_IPV6=1
  fi
fi

# ---------------- Load last known state ----------------
PREV_HAS_IPV6=0
PREV_VPN_POOL_IPV6=""
PREV_VPN_SERVER_IP_IPV6=""
PREV_VPN_SUBNET_IPV6=""
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$STATE_FILE" 2>/dev/null || true
  PREV_HAS_IPV6="${HAS_IPV6_SAVED:-0}"
  PREV_VPN_POOL_IPV6="${VPN_POOL_IPV6_SAVED:-}"
  PREV_VPN_SERVER_IP_IPV6="${VPN_SERVER_IP_IPV6_SAVED:-}"
  PREV_VPN_SUBNET_IPV6="${VPN_SUBNET_IPV6_SAVED:-}"
fi

# ---------------- Short-circuit if nothing changed ----------------
if [ "$HAS_IPV6" = "$PREV_HAS_IPV6" ] \
   && [ "$VPN_POOL_IPV6" = "$PREV_VPN_POOL_IPV6" ] \
   && [ "$VPN_SERVER_IP_IPV6" = "$PREV_VPN_SERVER_IP_IPV6" ] \
   && [ "$VPN_SUBNET_IPV6" = "$PREV_VPN_SUBNET_IPV6" ]; then
  exit 0
fi

CHANGED=0

# ---------------- Helper: tear down a previous IPv6 config ----------------
teardown_ipv6() {
  local old_ip="$1"
  local old_subnet="$2"
  [ -z "$old_ip" ] && [ -z "$old_subnet" ] && return 0
  if [ -n "$old_ip" ]; then
    ip -6 addr del "${old_ip}/128" dev lo 2>/dev/null || true
    # Strip persistence lines
    if [ -f /etc/rc.local ]; then
      sedi "\|${old_ip}/128|d" /etc/rc.local 2>/dev/null || true
    fi
    if [ -f /etc/local.d/bonjour-vpn.start ]; then
      sedi "\|${old_ip}/128|d" /etc/local.d/bonjour-vpn.start 2>/dev/null || true
    fi
    # Remove from dnsmasq listen-address line
    if [ -f "$DNSMASQ_VPN_CONF" ]; then
      # Match ",<ip>" or "<ip>," or bare "<ip>"
      sedi \
        -e "s|,${old_ip}||g" \
        -e "s|${old_ip},||g" \
        -e "s|=${old_ip}$|=127.0.0.1|" \
        "$DNSMASQ_VPN_CONF" 2>/dev/null || true
    fi
  fi
  if [ -n "$old_subnet" ] && [ -n "$old_ip" ] \
     && command -v ip6tables >/dev/null 2>&1; then
    ip6tables -D INPUT -s "$old_subnet" -p udp --dport 53 -j ACCEPT 2>/dev/null || true
    ip6tables -D INPUT -s "$old_subnet" -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
    ip6tables -D INPUT -s "$old_subnet" -p udp --dport 5353 -j ACCEPT 2>/dev/null || true
    ip6tables -t nat -D PREROUTING -s "$old_subnet" -d ff02::fb -p udp --dport 5353 \
      -j DNAT --to-destination "[${old_ip}]:53" 2>/dev/null || true
  fi
  CHANGED=1
}

# ---------------- Helper: apply a new IPv6 config ----------------
apply_ipv6() {
  local new_ip="$1"
  local new_subnet="$2"
  [ -z "$new_ip" ] || [ -z "$new_subnet" ] && return 0
  # Loopback assignment
  if ! ip -6 addr show dev lo 2>/dev/null | grep -q "${new_ip}/"; then
    ip -6 addr add "${new_ip}/128" dev lo 2>/dev/null || return 1
  fi
  # Persistence — only modify rc.local if enable_bonjour.sh created it
  # (check for sentinel marker to avoid touching unrelated rc.local files)
  if [ -f /etc/rc.local ] && grep -qs "$BONJOUR_MARK" /etc/rc.local; then
    if ! grep -q "${new_ip}/128" /etc/rc.local 2>/dev/null; then
      sedi "/^exit 0$/i ip -6 addr add ${new_ip}/128 dev lo 2>/dev/null" /etc/rc.local 2>/dev/null || true
    fi
  fi
  if [ -f /etc/local.d/bonjour-vpn.start ]; then
    if ! grep -q "${new_ip}/128" /etc/local.d/bonjour-vpn.start 2>/dev/null; then
      printf 'ip -6 addr add %s/128 dev lo 2>/dev/null\n' "$new_ip" \
        >> /etc/local.d/bonjour-vpn.start
    fi
  fi
  # dnsmasq listen-address — append IPv6 to existing line if not present
  if [ -f "$DNSMASQ_VPN_CONF" ] && ! grep -q "$new_ip" "$DNSMASQ_VPN_CONF" 2>/dev/null; then
    sedi "s|^listen-address=\(.*\)$|listen-address=\1,${new_ip}|" "$DNSMASQ_VPN_CONF" 2>/dev/null || true
  fi
  # ip6tables — only apply if kernel supports it
  if command -v ip6tables >/dev/null 2>&1 \
     && ip6tables -t nat -L PREROUTING -n >/dev/null 2>&1; then
    if ! ip6tables -C INPUT -s "$new_subnet" -p udp --dport 53 -j ACCEPT 2>/dev/null; then
      ip6tables -I INPUT 1 -s "$new_subnet" -p udp --dport 53 -j ACCEPT 2>/dev/null || true
    fi
    if ! ip6tables -C INPUT -s "$new_subnet" -p tcp --dport 53 -j ACCEPT 2>/dev/null; then
      ip6tables -I INPUT 1 -s "$new_subnet" -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
    fi
    if ! ip6tables -C INPUT -s "$new_subnet" -p udp --dport 5353 -j ACCEPT 2>/dev/null; then
      ip6tables -I INPUT 1 -s "$new_subnet" -p udp --dport 5353 -j ACCEPT 2>/dev/null || true
    fi
    if ! ip6tables -t nat -C PREROUTING -s "$new_subnet" -d ff02::fb -p udp --dport 5353 \
         -j DNAT --to-destination "[${new_ip}]:53" 2>/dev/null; then
      ip6tables -t nat -I PREROUTING -s "$new_subnet" -d ff02::fb -p udp --dport 5353 \
        -j DNAT --to-destination "[${new_ip}]:53" 2>/dev/null || true
    fi
  fi
  CHANGED=1
  return 0
}

# ---------------- Tear down the old config (if any) ----------------
if [ "$PREV_HAS_IPV6" = 1 ]; then
  teardown_ipv6 "$PREV_VPN_SERVER_IP_IPV6" "$PREV_VPN_SUBNET_IPV6"
fi

# ---------------- Apply the new config (if any) ----------------
if [ "$HAS_IPV6" = 1 ]; then
  apply_ipv6 "$VPN_SERVER_IP_IPV6" "$VPN_SUBNET_IPV6" || true
fi

# ---------------- Persist new state ----------------
mkdir -p /var/lib/bonjour-vpn
cat > "$STATE_FILE" <<STATE
# Auto-generated by bonjour-vpn-ipv6-sync - do not edit
HAS_IPV6_SAVED='${HAS_IPV6}'
VPN_POOL_IPV6_SAVED='${VPN_POOL_IPV6}'
VPN_SERVER_IP_IPV6_SAVED='${VPN_SERVER_IP_IPV6}'
VPN_SUBNET_IPV6_SAVED='${VPN_SUBNET_IPV6}'
STATE
chmod 600 "$STATE_FILE" 2>/dev/null || true
# Maintain the ipv6-enabled marker for the resolve script's AAAA gating
if [ "$HAS_IPV6" = 1 ]; then
  touch /var/lib/bonjour-vpn/ipv6-enabled
else
  rm -f /var/lib/bonjour-vpn/ipv6-enabled
fi

# ---------------- Restart dnsmasq if we changed anything ----------------
if [ "$CHANGED" = 1 ]; then
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart dnsmasq 2>/dev/null || true
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service dnsmasq restart 2>/dev/null || true
  fi
  # Save updated ip6tables rules for persistence across reboots.
  # Must run on BOTH apply (HAS_IPV6=1) and teardown (HAS_IPV6=0) —
  # teardown deletes rules from the running kernel, and the save file
  # must reflect that deletion so stale rules don't return after reboot.
  if command -v ip6tables-save >/dev/null 2>&1; then
    if [ "$SYNC_OS_TYPE" = "alpine" ]; then
      ip6tables-save > /etc/ip6tables.rules 2>/dev/null || true
    elif [ -f /etc/redhat-release ] || [ -f /etc/system-release ]; then
      ip6tables-save > /etc/sysconfig/ip6tables 2>/dev/null || true
    else
      ip6tables-save > /etc/ip6tables.rules 2>/dev/null || true
      [ -f /etc/iptables/rules.v6 ] && \
        /bin/cp -f /etc/ip6tables.rules /etc/iptables/rules.v6 2>/dev/null || true
    fi
  fi
fi
exit 0
SYNC_EOF
  chmod 755 "$SYNC_SCRIPT"

  # --- Script 3: Event watcher (persistent, triggers resolve on changes) ---
  WATCHER_SCRIPT="/usr/local/bin/bonjour-vpn-watch"
cat > "$WATCHER_SCRIPT" <<'WATCHER_EOF'
#!/bin/bash
# Real-time Bonjour service watcher — runs as a persistent service.
# Listens passively to mDNS multicast for service add/remove events.
# When a change is detected, waits for the burst to settle (debounce),
# then triggers a full resolve to regenerate dnsmasq records.
#
# Also periodically (at least once per IDLE_TIMEOUT seconds) runs the
# IPv6 sync script so that post-install VPN IPv6 changes get picked up
# automatically without requiring the user to re-run enable_bonjour.sh.
#
# Zero CPU/network overhead when nothing changes — avahi-browse just
# listens to multicast packets already on the network.

RESOLVE_CMD="/usr/local/bin/bonjour-vpn-resolve"
SYNC_CMD="/usr/local/sbin/bonjour-vpn-ipv6-sync"
DEBOUNCE_SEC=3
# Max seconds to wait for an avahi event before looping around to
# re-check VPN IPv6 state. Keeps the state-sync loop responsive even
# on quiet networks with no mDNS activity.
IDLE_TIMEOUT=60

# Initial IPv6 state sync + full resolve on startup
[ -x "$SYNC_CMD" ] && "$SYNC_CMD" 2>/dev/null || true
"$RESOLVE_CMD"

# Watch for service changes using a single long-running avahi-browse
# process. Uses `read -t` for both idle timeout (IPv6 sync) and debounce,
# avoiding the overhead of spawning a new avahi-browse per event.
# -a = all services, -p = parseable, -k = no db lookup (raw type names)
while true; do
  # Re-run the IPv6 sync before entering the browse loop. Idempotent and
  # cheap (stat + compare) when nothing changed.
  [ -x "$SYNC_CMD" ] && "$SYNC_CMD" 2>/dev/null || true

  # Start a persistent browse with a hard timeout slightly longer than
  # IDLE_TIMEOUT. The timeout ensures avahi-browse is killed even on a
  # completely silent network (no mDNS packets = no writes = no SIGPIPE),
  # which would otherwise leave bash waiting for the pipeline to finish.
  timeout "$((IDLE_TIMEOUT + 5))" avahi-browse -apk 2>/dev/null | while true; do
    # Wait up to IDLE_TIMEOUT for an event. If none, break out to the
    # outer loop so the IPv6 sync runs again.
    if ! read -r -t "$IDLE_TIMEOUT" EVENT; then
      break
    fi

    # Got an event — debounce: keep reading until the burst settles
    # (no new events for DEBOUNCE_SEC seconds), with a 30s wall-clock cap
    # to prevent indefinite deferral on a chatty network.
    DEBOUNCE_START=$(date +%s)
    while read -r -t "$DEBOUNCE_SEC" _NEXT; do
      [ $(( $(date +%s) - DEBOUNCE_START )) -ge 30 ] && break
    done

    # Burst settled — run full resolve
    "$RESOLVE_CMD"
  done
done
WATCHER_EOF
  chmod +x "$WATCHER_SCRIPT"

  # --- Set up the service ---
  if command -v systemctl >/dev/null 2>&1; then
    # Remove old timer-based setup if present (upgrade path)
    systemctl stop bonjour-vpn-cache-warm.timer 2>/dev/null
    systemctl disable bonjour-vpn-cache-warm.timer 2>/dev/null
    /bin/rm -f /etc/systemd/system/bonjour-vpn-cache-warm.timer
    /bin/rm -f /etc/systemd/system/bonjour-vpn-cache-warm.service
    /bin/rm -f /usr/local/bin/bonjour-vpn-cache-warm

cat > /etc/systemd/system/bonjour-vpn-watch.service <<'EOF'
[Unit]
Description=Bonjour VPN mDNS service watcher
After=avahi-daemon.service dnsmasq.service network-online.target
Wants=avahi-daemon.service
Requires=avahi-daemon.service

[Service]
Type=simple
ExecStart=/usr/local/bin/bonjour-vpn-watch
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable bonjour-vpn-watch.service 2>/dev/null
    systemctl start bonjour-vpn-watch.service 2>/dev/null
  else
    # Alpine / non-systemd: fall back to cron (no persistent services).
    # Run both the IPv6 sync and resolve every minute.
    CRON_LINE="* * * * * $SYNC_SCRIPT 2>/dev/null; $RESOLVE_SCRIPT"
    (crontab -l 2>/dev/null | grep -v 'bonjour-vpn'; echo "$CRON_LINE") | crontab -
    # Run once now
    "$SYNC_SCRIPT" 2>/dev/null || true
    "$RESOLVE_SCRIPT" 2>/dev/null || true
  fi
}

verify_setup() {
  bigecho "Verifying setup..."
  VERIFY_PASS=1

  # Check avahi is running
  if ! pgrep -x avahi-daemon >/dev/null 2>&1; then
    echo "  WARNING: avahi-daemon is not running"
    VERIFY_PASS=0
  else
    echo "  OK: avahi-daemon is running"
  fi

  # Check dnsmasq is running
  if ! pgrep -x dnsmasq >/dev/null 2>&1; then
    echo "  WARNING: dnsmasq is not running"
    VERIFY_PASS=0
  else
    echo "  OK: dnsmasq is running"
  fi

  # Check VPN server IP is on loopback (IKEv2/XAuth only)
  if [ "$HAS_IKEV2" = 1 ] || [ "$HAS_XAUTH" = 1 ]; then
    if ip addr show dev lo 2>/dev/null | grep -q "$VPN_SERVER_IP"; then
      echo "  OK: $VPN_SERVER_IP is assigned to loopback"
    else
      echo "  WARNING: $VPN_SERVER_IP not found on loopback"
      VERIFY_PASS=0
    fi
  fi

  # Check modecfgdomains is set correctly (local + catch-all)
  if [ "$HAS_IKEV2" = 1 ]; then
    if grep -q 'modecfgdomains=.*local.*\.' "$IKEV2_CONF" 2>/dev/null; then
      echo "  OK: IKEv2 modecfgdomains set (local + catch-all)"
    else
      echo "  WARNING: IKEv2 modecfgdomains not set correctly"
      VERIFY_PASS=0
    fi
  fi

  # Check mDNS capture iptables rule for IKEv2/XAuth subnet
  if [ "$HAS_IKEV2" = 1 ] || [ "$HAS_XAUTH" = 1 ]; then
    if iptables -t nat -C PREROUTING -s "$VPN_SUBNET" -d 224.0.0.251 -p udp --dport 5353 -j DNAT --to-destination "${VPN_SERVER_IP}:53" 2>/dev/null; then
      echo "  OK: mDNS capture rule active for $VPN_SUBNET"
    else
      echo "  WARNING: mDNS capture rule missing for $VPN_SUBNET"
      VERIFY_PASS=0
    fi
  fi

  # Check mDNS capture iptables rule for L2TP subnet
  if [ "$HAS_L2TP" = 1 ] && [ -n "$L2TP_SUBNET" ]; then
    if iptables -t nat -C PREROUTING -s "$L2TP_SUBNET" -d 224.0.0.251 -p udp --dport 5353 -j DNAT --to-destination "${L2TP_SERVER_IP}:53" 2>/dev/null; then
      echo "  OK: mDNS capture rule active for $L2TP_SUBNET"
    else
      echo "  WARNING: mDNS capture rule missing for $L2TP_SUBNET"
      VERIFY_PASS=0
    fi
  fi

  # Check L2TP DNS settings
  if [ "$HAS_L2TP" = 1 ] && [ -f "$PPP_OPTIONS" ]; then
    if grep -q "^ms-dns ${L2TP_SERVER_IP}$" "$PPP_OPTIONS" 2>/dev/null; then
      echo "  OK: L2TP primary ms-dns set to $L2TP_SERVER_IP"
    else
      echo "  WARNING: L2TP ms-dns not updated in options.xl2tpd"
      VERIFY_PASS=0
    fi
  fi

  # Check if bonjour-vpn-hosts has entries (from cache warmer)
  if [ -s /etc/bonjour-vpn-hosts ]; then
    HOST_COUNT=$(wc -l < /etc/bonjour-vpn-hosts)
    echo "  OK: cache warmer found $HOST_COUNT host(s) on the LAN"
  else
    echo "  NOTE: no hosts found yet (LAN may have no Bonjour devices, or watcher needs a moment)"
  fi

  # Check if DNS-SD services config was generated
  if [ -s /etc/dnsmasq.d/bonjour-vpn-services.conf ]; then
    SVC_COUNT=$(grep -c '^ptr-record=_services' /etc/dnsmasq.d/bonjour-vpn-services.conf 2>/dev/null || echo 0)
    INST_COUNT=$(grep -c '^srv-host=' /etc/dnsmasq.d/bonjour-vpn-services.conf 2>/dev/null || echo 0)
    echo "  OK: DNS-SD config generated ($SVC_COUNT service types, $INST_COUNT instances)"
  else
    echo "  NOTE: DNS-SD services config not yet generated"
  fi

  # Try a DNS-SD meta-query if dig is available
  if command -v dig >/dev/null 2>&1; then
    QUERY_IP="$VPN_SERVER_IP"
    [ "$HAS_IKEV2" = 0 ] && [ "$HAS_XAUTH" = 0 ] && [ "$HAS_L2TP" = 1 ] && QUERY_IP="$L2TP_SERVER_IP"
    SD_RESULT=$(dig +short +time=3 +tries=1 @"$QUERY_IP" _services._dns-sd._udp.local PTR 2>/dev/null)
    if [ -n "$SD_RESULT" ]; then
      SVC_COUNT=$(printf '%s\n' "$SD_RESULT" | wc -l)
      echo "  OK: DNS-SD query returned $SVC_COUNT service type(s)"
    else
      echo "  NOTE: DNS-SD meta-query returned no results (watcher may need a moment to discover services)"
    fi
  fi

  if [ "$VERIFY_PASS" = 0 ]; then
    echo
    echo "  Some checks failed. Review the warnings above and check service logs."
  fi
}

enable_services() {
  bigecho "Enabling and starting services..."
  if [ "$os_type" = "alpine" ]; then
    # Ensure D-Bus is running (required by avahi)
    rc-update add dbus default 2>/dev/null
    rc-service dbus start 2>/dev/null
    rc-update add avahi-daemon default 2>/dev/null
    rc-service avahi-daemon restart 2>/dev/null
    rc-update add dnsmasq default 2>/dev/null
    rc-service dnsmasq restart 2>/dev/null
    rc-service ipsec restart 2>/dev/null
    if [ "$HAS_L2TP" = 1 ]; then
      rc-service xl2tpd restart 2>/dev/null
    fi
  else
    # Ensure D-Bus is running (required by avahi)
    systemctl enable dbus 2>/dev/null
    systemctl start dbus 2>/dev/null
    systemctl enable avahi-daemon 2>/dev/null
    systemctl restart avahi-daemon 2>/dev/null
    systemctl enable dnsmasq 2>/dev/null
    systemctl restart dnsmasq 2>/dev/null
    mkdir -p /run/pluto
    service ipsec restart 2>/dev/null
    if [ "$HAS_L2TP" = 1 ]; then
      service xl2tpd restart 2>/dev/null
    fi
  fi
}

print_summary() {
  # Build VPN modes list
  VPN_MODES=""
  [ "$HAS_IKEV2" = 1 ] && VPN_MODES="IKEv2"
  if [ "$HAS_XAUTH" = 1 ]; then
    [ -n "$VPN_MODES" ] && VPN_MODES="${VPN_MODES}, "
    VPN_MODES="${VPN_MODES}IPsec/XAuth"
  fi
  if [ "$HAS_L2TP" = 1 ]; then
    [ -n "$VPN_MODES" ] && VPN_MODES="${VPN_MODES}, "
    VPN_MODES="${VPN_MODES}IPsec/L2TP"
  fi
  # Build dnsmasq listen address display
  LISTEN_DISPLAY=""
  if [ "$HAS_IKEV2" = 1 ] || [ "$HAS_XAUTH" = 1 ]; then
    LISTEN_DISPLAY="$VPN_SERVER_IP (IKEv2/XAuth)"
  fi
  if [ "$HAS_L2TP" = 1 ]; then
    [ -n "$LISTEN_DISPLAY" ] && LISTEN_DISPLAY="${LISTEN_DISPLAY}, "
    LISTEN_DISPLAY="${LISTEN_DISPLAY}${L2TP_SERVER_IP} (L2TP)"
  fi
  if [ "$HAS_IPV6" = 1 ] && [ -n "$VPN_SERVER_IP_IPV6" ]; then
    [ -n "$LISTEN_DISPLAY" ] && LISTEN_DISPLAY="${LISTEN_DISPLAY}, "
    LISTEN_DISPLAY="${LISTEN_DISPLAY}${VPN_SERVER_IP_IPV6} (IPv6)"
  fi
cat <<EOF

================================================
Bonjour/mDNS for VPN Clients - Setup Complete
================================================

Architecture:
  VPN Client --[IPsec tunnel]--> dnsmasq :53 ---> upstream DNS
                                      |
                            [static .local records]
                                      ^
                          [real-time service watcher]
                                      |
                          avahi-browse ---> LAN multicast mDNS

Configuration:
  Network interface:      $NET_IFACE
  Server LAN IP:          $SERVER_LAN_IP
  VPN modes configured:   $VPN_MODES
  Upstream DNS:           $UPSTREAM_DNS1, $UPSTREAM_DNS2
  dnsmasq listen IPs:     $LISTEN_DISPLAY
EOF
  if [ "$HAS_IKEV2" = 1 ]; then
cat <<EOF

  IKEv2 mode:
    VPN subnet:           $VPN_SUBNET
    VPN server IP:        $VPN_SERVER_IP (on loopback)
    Primary DNS:          $VPN_SERVER_IP (dnsmasq)
    mDNS capture:         VPN client Bonjour queries redirected to dnsmasq
EOF
  fi
  if [ "$HAS_XAUTH" = 1 ]; then
cat <<EOF

  XAuth mode:
    VPN subnet:           $VPN_SUBNET
    VPN server IP:        $XAUTH_SERVER_IP (on loopback)
    Primary DNS:          $VPN_SERVER_IP (dnsmasq)
    mDNS capture:         VPN client Bonjour queries redirected to dnsmasq
EOF
  fi
  if [ "$HAS_IPV6" = 1 ]; then
cat <<EOF

  IPv6 (IKEv2):
    IPv6 VPN subnet:      $VPN_SUBNET_IPV6
    IPv6 server IP:       $VPN_SERVER_IP_IPV6 (on loopback)
    IPv6 mDNS capture:    ff02::fb port 5353 -> dnsmasq via ip6tables DNAT
EOF
  fi
  if [ "$HAS_L2TP" = 1 ]; then
cat <<EOF

  L2TP mode:
    VPN subnet:           $L2TP_SUBNET
    L2TP server IP:       $L2TP_SERVER_IP (on loopback)
    Primary DNS:          $L2TP_SERVER_IP (dnsmasq)
    mDNS capture:         VPN client Bonjour queries redirected to dnsmasq
EOF
  fi
cat <<'EOF'

How it works:
  - ALL DNS goes through the VPN tunnel to dnsmasq (no DNS leak)
  - modecfgdomains="local, vpn.internal, ." ensures VPN DNS handles all queries
    ("local" triggers Bonjour unicast, "." catches everything else)
  - mDNS capture rule provides additional fallback for multicast queries
  - dnsmasq serves .local records discovered by the real-time service watcher
  - Non-.local queries forwarded to upstream DNS

VPN clients can now:
  - Resolve .local hostnames (e.g., printer.local)
  - Browse network services via DNS-SD (e.g., printers, AirPlay)
  - Use standard DNS for all other queries (via dnsmasq upstream forwarding)
EOF
  if [ "$HAS_IPV6" = 1 ]; then
cat <<'EOF'

Note: IPv6 DNS is NOT pushed via modecfgdns because Libreswan <= 5.3
  encodes INTERNAL_IP6_DNS with the wrong attribute length (17 bytes
  instead of 16), causing strongSwan clients to reject IKE_AUTH.
  IPv6 .local resolution still works — clients query the IPv4 DNS
  endpoint and dnsmasq returns AAAA records regardless of source AF.
EOF
  fi
cat <<EOF

Client notes:
  - Existing VPN clients must disconnect and reconnect
  - macOS/iOS: Works automatically (all DNS routed through VPN)
  - Windows: Install "Bonjour Print Services" or "Bonjour for Windows" for full support
  - Android: Limited mDNS support; .local hostname resolution works
  - Linux: Works if systemd-resolved or avahi is configured on the client

Troubleshooting:
  Test .local resolution from VPN client:
    dig @${VPN_SERVER_IP} printer.local
    dig @${VPN_SERVER_IP} _printer._tcp.local PTR
  Browse LAN services on the server:
    avahi-browse -art
EOF
  if [ "$os_type" = "alpine" ]; then
cat <<EOF
  Check dnsmasq status:
    cat /var/log/messages | grep dnsmasq
  Check avahi-daemon status:
    rc-service avahi-daemon status
EOF
  else
cat <<EOF
  Check dnsmasq status:
    journalctl -u dnsmasq --no-pager -n 20
  Check avahi-daemon status:
    systemctl status avahi-daemon
EOF
  fi
cat <<'EOF'

Backup files (suffix .bak.bonjour-vpn):
EOF
  [ -f /etc/avahi/avahi-daemon.conf.bak.bonjour-vpn ] && echo "  /etc/avahi/avahi-daemon.conf.bak.bonjour-vpn"
  [ -f /etc/ipsec.d/ikev2.conf.bak.bonjour-vpn ] && echo "  /etc/ipsec.d/ikev2.conf.bak.bonjour-vpn"
  [ -f /etc/ipsec.conf.bak.bonjour-vpn ] && echo "  /etc/ipsec.conf.bak.bonjour-vpn"
  [ -f /etc/ppp/options.xl2tpd.bak.bonjour-vpn ] && echo "  /etc/ppp/options.xl2tpd.bak.bonjour-vpn"
  [ -f /etc/dnsmasq.conf.bak.bonjour-vpn ] && echo "  /etc/dnsmasq.conf.bak.bonjour-vpn"
  [ -f /etc/rc.local.bak.bonjour-vpn ] && echo "  /etc/rc.local.bak.bonjour-vpn"
cat <<'EOF'

To disable Bonjour/mDNS for VPN, run: sudo bash disable_bonjour.sh
EOF
}

# =====================================================
# Main
# =====================================================

check_root
check_os
check_vpn_modes
check_ipsec_running
check_already_configured
check_existing_dns
detect_iface
detect_server_lan_ip
detect_lan_subnet
detect_vpn_subnet
detect_l2tp_subnet
detect_vpn_ipv6
parse_upstream_dns

# Build VPN modes display for confirmation prompt
VPN_MODES_DISPLAY=""
[ "$HAS_IKEV2" = 1 ] && VPN_MODES_DISPLAY="IKEv2"
if [ "$HAS_XAUTH" = 1 ]; then
  [ -n "$VPN_MODES_DISPLAY" ] && VPN_MODES_DISPLAY="${VPN_MODES_DISPLAY}, "
  VPN_MODES_DISPLAY="${VPN_MODES_DISPLAY}IPsec/XAuth"
fi
if [ "$HAS_L2TP" = 1 ]; then
  [ -n "$VPN_MODES_DISPLAY" ] && VPN_MODES_DISPLAY="${VPN_MODES_DISPLAY}, "
  VPN_MODES_DISPLAY="${VPN_MODES_DISPLAY}IPsec/L2TP"
fi

cat <<EOF

Bonjour/mDNS for VPN Setup

Detected configuration:
  OS type:            $os_type
  Network interface:  $NET_IFACE
  Server LAN IP:      $SERVER_LAN_IP
  LAN subnet:         $LAN_CIDR
  VPN modes:          $VPN_MODES_DISPLAY
EOF
if [ "$HAS_IKEV2" = 1 ] || [ "$HAS_XAUTH" = 1 ]; then
cat <<EOF
  IKEv2/XAuth subnet: $VPN_SUBNET
  IKEv2/XAuth IP:     $VPN_SERVER_IP
EOF
fi
if [ "$HAS_L2TP" = 1 ]; then
cat <<EOF
  L2TP subnet:        $L2TP_SUBNET
  L2TP server IP:     $L2TP_SERVER_IP
EOF
fi
if [ "$HAS_IPV6" = 1 ]; then
cat <<EOF
  IPv6 pool:          $VPN_POOL_IPV6
  IPv6 server IP:     $VPN_SERVER_IP_IPV6
EOF
fi
cat <<EOF
  Upstream DNS:       $UPSTREAM_DNS1, $UPSTREAM_DNS2

This script will:
  1. Install avahi-daemon and dnsmasq
  2. Configure avahi to discover services on the LAN
  3. Configure dnsmasq to proxy .local queries via mDNS
EOF
if [ "$HAS_IKEV2" = 1 ] || [ "$HAS_XAUTH" = 1 ]; then
cat <<EOF
  4. Add $VPN_SERVER_IP to loopback as the VPN DNS endpoint
EOF
fi
cat <<EOF
  5. Update VPN configs to push dnsmasq as primary DNS
  6. Add iptables rules for DNS access from VPN clients
  7. Set modecfgdomains="local, vpn.internal, ." to route ALL client DNS queries
     through the VPN (replaces any existing modecfgdomains setting)
EOF
if [ "$HAS_IPV6" = 1 ]; then
cat <<EOF
  8. Set up IPv6 mDNS proxy (dnsmasq + ip6tables for $VPN_SUBNET_IPV6)
EOF
fi
echo
printf '%s' "Do you want to continue? [y/N] "
read -r response
case $response in
  [yY][eE][sS]|[yY])
    echo
    ;;
  *)
    echo "Abort. No changes were made." >&2
    exit 1
    ;;
esac

install_packages
configure_avahi
configure_dnsmasq
assign_vpn_server_ip
update_vpn_dns_config
update_iptables
enable_services
create_cache_warmer
# Seed the IPv6 sync state file with the current state so the watcher's
# first tick doesn't misfire a transition. The sync script is a no-op
# when state matches what's in /var/lib/bonjour-vpn/ipv6-state.
if [ -x /usr/local/sbin/bonjour-vpn-ipv6-sync ]; then
  /usr/local/sbin/bonjour-vpn-ipv6-sync 2>/dev/null || true
fi
# Write the IPv6-enabled marker so the resolve script knows whether to
# include AAAA records. On IPv4-only VPNs, returning AAAA for .local
# names is a silent behavioral change — gate it on actual IPv6 state.
mkdir -p /var/lib/bonjour-vpn
if [ "$HAS_IPV6" = 1 ]; then
  touch /var/lib/bonjour-vpn/ipv6-enabled
else
  rm -f /var/lib/bonjour-vpn/ipv6-enabled
fi
verify_setup
print_summary

exit 0
