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
# Copyright (C) 2026 Lin Song <linsongui@gmail.com>
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
    [ -z "$def_iface" ] && def_iface=$(ip -4 route list 0/0 2>/dev/null | grep -m 1 -Po '(?<=dev )(\S+)')
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
    | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
  if [ -z "$SERVER_LAN_IP" ] || ! check_ip "$SERVER_LAN_IP"; then
    exiterr "Could not detect server's LAN IP on interface '$NET_IFACE'."
  fi
}

detect_lan_subnet() {
  LAN_CIDR=$(ip -4 addr show dev "$NET_IFACE" 2>/dev/null \
    | grep -oP '\d+(\.\d+){3}/\d+' | head -n 1)
  if [ -z "$LAN_CIDR" ]; then
    LAN_CIDR="${SERVER_LAN_IP}/24"
  fi
}

detect_vpn_subnet() {
  # Detect IKEv2/XAuth subnet
  # Try ikev2.conf first, then fall back to ipsec.conf xauth-psk section
  VPN_POOL=""
  if [ "$HAS_IKEV2" = 1 ]; then
    VPN_POOL=$(grep -oP 'rightaddresspool=\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
      "$IKEV2_CONF" | head -n 1)
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
    VPN_SUBNET_PREFIX=$(printf '%s' "$POOL_START" | grep -oP '^\d+\.\d+\.\d+')
    VPN_SUBNET="${VPN_SUBNET_PREFIX}.0/24"
    VPN_SERVER_IP="${VPN_SUBNET_PREFIX}.1"
  else
    VPN_SUBNET="192.168.43.0/24"
    VPN_SERVER_IP="192.168.43.1"
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
  L2TP_SERVER_IP=$(grep -oP 'local ip\s*=\s*\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
    "$XL2TPD_CONF" | head -n 1)
  if [ -z "$L2TP_SERVER_IP" ] || ! check_ip "$L2TP_SERVER_IP"; then
    L2TP_SERVER_IP="192.168.42.1"
  fi
  # Parse ip range to derive subnet
  L2TP_POOL_LINE=$(grep -oP 'ip range\s*=\s*\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
    "$XL2TPD_CONF" | head -n 1)
  if [ -n "$L2TP_POOL_LINE" ]; then
    L2TP_POOL_START=$(printf '%s' "$L2TP_POOL_LINE" | cut -d '-' -f 1)
    L2TP_SUBNET_PREFIX=$(printf '%s' "$L2TP_POOL_START" | grep -oP '^\d+\.\d+\.\d+')
    L2TP_SUBNET="${L2TP_SUBNET_PREFIX}.0/24"
  else
    L2TP_SUBNET_PREFIX=$(printf '%s' "$L2TP_SERVER_IP" | grep -oP '^\d+\.\d+\.\d+')
    L2TP_SUBNET="${L2TP_SUBNET_PREFIX}.0/24"
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
    apt-get -yqq install avahi-daemon avahi-utils dnsmasq libnss-mdns >/dev/null \
      || exiterr "'apt-get install' failed."
  elif [ "$os_type" = "alpine" ]; then
    apk update || exiterr "'apk update' failed."
    apk add avahi avahi-tools dnsmasq || exiterr "'apk add' failed."
  else
    # CentOS/RHEL/Rocky/Alma/Amazon
    if command -v dnf >/dev/null 2>&1; then
      dnf -y -q install avahi avahi-tools dnsmasq nss-mdns >/dev/null \
        || exiterr "'dnf install' failed."
    else
      yum -y -q install avahi avahi-tools dnsmasq nss-mdns >/dev/null \
        || exiterr "'yum install' failed."
    fi
  fi
}

configure_avahi() {
  bigecho "Configuring avahi-daemon..."
  AVAHI_CONF="/etc/avahi/avahi-daemon.conf"
  mkdir -p /etc/avahi
  conf_bk_bonjour "$AVAHI_CONF"
  # avahi needs multicast on the LAN for service discovery; omitting
  # allow-interfaces avoids restricting it to specific interfaces.
cat > "$AVAHI_CONF" <<EOF
[server]
use-ipv4=yes
use-ipv6=yes
enable-dbus=yes
disallow-other-stacks=no

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

configure_nss() {
  bigecho "Configuring NSS for mDNS..."
  NSS_CONF="/etc/nsswitch.conf"
  if [ ! -f "$NSS_CONF" ]; then
    return
  fi
  # Check if mdns is already configured
  if grep -q 'mdns' "$NSS_CONF" 2>/dev/null; then
    return
  fi
  conf_bk_bonjour "$NSS_CONF"
  # Add mdns4_minimal and mdns4 to the hosts line
  if [ "$os_type" = "alpine" ]; then
    sed -i '/^hosts:/ {
      /mdns/! s/dns/mdns4_minimal [NOTFOUND=return] dns mdns4/
    }' "$NSS_CONF"
  else
    sed --follow-symlinks -i '/^hosts:/ {
      /mdns/! s/dns/mdns4_minimal [NOTFOUND=return] dns mdns4/
    }' "$NSS_CONF"
  fi
}

assign_vpn_server_ip() {
  # For IKEv2/XAuth: add VPN_SERVER_IP to loopback (needed as dnsmasq listen address)
  if [ "$HAS_IKEV2" = 1 ] || [ "$HAS_XAUTH" = 1 ]; then
    bigecho "Assigning VPN server IP ($VPN_SERVER_IP) to loopback..."
    if ! ip addr show dev lo 2>/dev/null | grep -q "$VPN_SERVER_IP"; then
      ip addr add "${VPN_SERVER_IP}/32" dev lo || exiterr "Failed to add $VPN_SERVER_IP to loopback."
    fi
    # Make it persistent via /etc/rc.local
    RC_LOCAL="/etc/rc.local"
    if [ "$os_type" = "alpine" ]; then
      RC_LOCAL_ALPINE="/etc/local.d/bonjour-vpn.start"
      mkdir -p /etc/local.d
cat > "$RC_LOCAL_ALPINE" <<EOF
#!/bin/bash
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
#!/bin/bash

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
    if ! ip addr show dev lo 2>/dev/null | grep -q "$L2TP_SERVER_IP"; then
      bigecho "Assigning L2TP server IP ($L2TP_SERVER_IP) to loopback..."
      ip addr add "${L2TP_SERVER_IP}/32" dev lo || exiterr "Failed to add $L2TP_SERVER_IP to loopback."
    fi
    # Persist in rc.local / local.d alongside the IKEv2/XAuth IP
    if [ "$os_type" = "alpine" ]; then
      RC_LOCAL_ALPINE="/etc/local.d/bonjour-vpn.start"
      if [ -f "$RC_LOCAL_ALPINE" ] && ! grep -q "$L2TP_SERVER_IP" "$RC_LOCAL_ALPINE"; then
        sed -i "$ a ip addr add ${L2TP_SERVER_IP}/32 dev lo 2>/dev/null" "$RC_LOCAL_ALPINE"
      fi
    else
      RC_LOCAL="/etc/rc.local"
      if [ -f "$RC_LOCAL" ] && ! grep -q "$L2TP_SERVER_IP" "$RC_LOCAL"; then
        sed --follow-symlinks -i "/exit 0/i ip addr add ${L2TP_SERVER_IP}/32 dev lo 2>/dev/null" "$RC_LOCAL"
      fi
    fi
  fi
}

update_vpn_dns_config() {
  bigecho "Updating VPN DNS configuration..."
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
    # Set modecfgdomains="local, ." — the "local" triggers unicast DNS for .local
    # names on Apple devices (required for Bonjour). The "." (root domain) acts as
    # a catch-all so VPN DNS handles ALL queries, preventing DNS leak to the
    # client's default (cellular/WiFi) DNS.
    NEW_MODECFGDOMAINS='  modecfgdomains="local, ."'
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
    # Set modecfgdomains="local, ." in xauth-psk section (same as IKEv2)
    NEW_XAUTH_DOMAINS='  modecfgdomains="local, ."'
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
  else
    IPT_FILE=/etc/sysconfig/iptables
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

# avahi-browse flags:
#   -a all services  -r resolve  -p parseable  -t terminate  -k no-db-lookup
# -k is critical: without it, avahi translates service types to friendly names.
BROWSE_OUTPUT=$(timeout 20 avahi-browse -arptk 2>/dev/null || true)

if [ -z "$BROWSE_OUTPUT" ]; then
  exit 0
fi

RESOLVED=$(printf '%s\n' "$BROWSE_OUTPUT" | grep '^=;' | grep ';IPv4;' || true)
[ -z "$RESOLVED" ] && exit 0

# --- Generate hosts file (hostname -> IP) for addn-hosts ---
printf '%s\n' "$RESOLVED" | awk -F';' '{
  addr=$8; host=$7
  if (addr != "" && host != "" && addr !~ /:/) {
    gsub(/[ \t]+$/, "", host)
    gsub(/[ \t]+$/, "", addr)
    if (!seen[host]++) print addr " " host
  }
}' | sort -t' ' -k2 > "$HOSTS_TMP"

if [ -s "$HOSTS_TMP" ]; then
  mv -f "$HOSTS_TMP" "$HOSTS_FILE"
else
  rm -f "$HOSTS_TMP"
fi

# --- Generate DNS-SD service records for dnsmasq ---
# Pure awk — no shell loops or sed — to avoid escaping issues with
# backslashes and special chars in avahi service names.
printf '%s\n' "$RESOLVED" | awk -F';' '
  BEGIN {
    print "# Auto-generated by bonjour-vpn-resolve - do not edit"
  }

  $1 != "=" { next }

  {
    name  = $4
    stype = $5
    host  = $7
    port  = $9
    txt   = $10

    if (name == "" || stype == "" || host == "") next

    # avahi -p escapes spaces as \032. Convert back to literal spaces.
    gsub(/\\032/, " ", name)
    # Skip entries with remaining avahi escapes (\058=colon, \091=bracket, etc.)
    if (name ~ /\\/) next

    if (!type_seen[stype]++) types[++ntypes] = stype

    key = name SUBSEP stype
    if (inst_seen[key]++) next

    fqdn = name "." stype ".local"

    idx = ++ninst
    inst_ptr[idx] = "ptr-record=" stype ".local," fqdn
    inst_srv[idx] = "srv-host=" fqdn "," host "," (port != "" ? port : "0")

    if (txt != "") {
      gsub(/" "/, ",", txt)
      sub(/^"/, "", txt)
      sub(/"$/, "", txt)
      inst_txt[idx] = "txt-record=" fqdn "," txt
    }
  }

  END {
    for (i = 1; i <= ntypes; i++)
      print "ptr-record=_services._dns-sd._udp.local," types[i] ".local"
    print ""
    for (i = 1; i <= ninst; i++) {
      print inst_ptr[i]
      print inst_srv[i]
      if (inst_txt[i] != "") print inst_txt[i]
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

  # --- Script 2: Event watcher (persistent, triggers resolve on changes) ---
  WATCHER_SCRIPT="/usr/local/bin/bonjour-vpn-watch"
cat > "$WATCHER_SCRIPT" <<'WATCHER_EOF'
#!/bin/bash
# Real-time Bonjour service watcher — runs as a persistent service.
# Listens passively to mDNS multicast for service add/remove events.
# When a change is detected, waits for the burst to settle (debounce),
# then triggers a full resolve to regenerate dnsmasq records.
#
# Zero CPU/network overhead when nothing changes — avahi-browse just
# listens to multicast packets already on the network.

RESOLVE_CMD="/usr/local/bin/bonjour-vpn-resolve"
DEBOUNCE_SEC=3

# Initial full resolve on startup
"$RESOLVE_CMD"

# Watch for service changes. avahi-browse without -t runs continuously,
# outputting +/- lines as services appear and disappear.
# -a = all services, -p = parseable, -k = no db lookup (raw type names)
# NOT using -r (resolve) here — the watcher only needs to detect changes,
# not resolve details. The full resolve script handles that.
while true; do
  # Start the watcher. It blocks until an event arrives.
  # Read one event, then enter debounce loop.
  EVENT=$(avahi-browse -apk 2>/dev/null | head -n 1)

  if [ -z "$EVENT" ]; then
    # avahi-browse exited unexpectedly (avahi-daemon restarted, etc.)
    # Wait and retry
    sleep 5
    continue
  fi

  # Debounce: devices announce multiple services at once (5-10 events in
  # quick succession). Wait for the burst to settle before running resolve.
  while true; do
    # Try to read another event with a timeout
    NEXT=$(timeout "$DEBOUNCE_SEC" avahi-browse -apk 2>/dev/null | head -n 1) || true
    if [ -z "$NEXT" ]; then
      # No events for DEBOUNCE_SEC seconds — burst is over
      break
    fi
    # Got another event, keep waiting
  done

  # Burst settled — run full resolve
  "$RESOLVE_CMD"
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
# If avahi-daemon restarts, restart the watcher too
ExecStartPre=/usr/local/bin/bonjour-vpn-resolve

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable bonjour-vpn-watch.service 2>/dev/null
    systemctl start bonjour-vpn-watch.service 2>/dev/null
  else
    # Alpine / non-systemd: fall back to cron (no persistent services)
    # Run resolve every minute as the best alternative
    CRON_LINE="* * * * * $RESOLVE_SCRIPT"
    (crontab -l 2>/dev/null | grep -v 'bonjour-vpn'; echo "$CRON_LINE") | crontab -
    # Run once now
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
  - modecfgdomains="local, ." ensures VPN DNS handles all queries
    ("local" triggers Bonjour unicast, "." catches everything else)
  - mDNS capture rule provides additional fallback for multicast queries
  - dnsmasq serves .local records discovered by the real-time service watcher
  - Non-.local queries forwarded to upstream DNS

VPN clients can now:
  - Resolve .local hostnames (e.g., printer.local)
  - Browse network services via DNS-SD (e.g., printers, AirPlay)
  - Use standard DNS for all other queries (via dnsmasq upstream forwarding)
EOF
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
  [ -f /etc/nsswitch.conf.bak.bonjour-vpn ] && echo "  /etc/nsswitch.conf.bak.bonjour-vpn"
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

EOF
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
configure_nss
assign_vpn_server_ip
update_vpn_dns_config
update_iptables
enable_services
create_cache_warmer
verify_setup
print_summary

exit 0
