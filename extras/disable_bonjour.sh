#!/bin/bash
#
# Script to disable Bonjour/mDNS and local network discovery for VPN clients
# Supports IKEv2, IPsec/XAuth ("Cisco IPsec"), and IPsec/L2TP modes
#
# DO NOT RUN THIS SCRIPT ON YOUR PC OR MAC!
#
# Reverses all changes made by enable_bonjour.sh
#
# The latest version of this script is available at:
# https://github.com/hwdsl2/setup-ipsec-vpn
#
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
  elif grep -qs "Amazon Linux release 2 " /etc/system-release; then
    os_type=amzn
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

check_bonjour_configured() {
  if [ ! -f /etc/dnsmasq.d/bonjour-vpn.conf ]; then
    exiterr "Bonjour/mDNS for VPN does not appear to be configured. File /etc/dnsmasq.d/bonjour-vpn.conf not found."
  fi
}

abort_and_exit() {
  echo "Abort. No changes were made." >&2
  exit 1
}

confirm_or_abort() {
  printf '%s' "$1"
  read -r response
  case $response in
    [yY][eE][sS]|[yY])
      echo
      ;;
    *)
      abort_and_exit
      ;;
  esac
}

check_ip6() {
  printf '%s' "$1" | tr -d '\n' | grep -Eq '^[0-9a-fA-F:]+$' && \
  printf '%s' "$1" | grep -q ':'
}

detect_vpn_server_ip() {
  # Parse VPN server IP(s) from the dnsmasq config
  # Extract all non-localhost IPs from listen-address line
  LISTEN_LINE=$(grep 'listen-address=' /etc/dnsmasq.d/bonjour-vpn.conf | head -n 1 \
    | sed 's/.*listen-address=//' | tr -d '[:space:]')
  VPN_SERVER_IP=""
  L2TP_SERVER_IP=""
  VPN_SERVER_IP_IPV6=""
  # Parse comma-separated IPs — IPv4 addresses go into VPN_SERVER_IP /
  # L2TP_SERVER_IP (first two IPv4 values); any IPv6 literal becomes
  # VPN_SERVER_IP_IPV6 (the first one wins — there should only be one
  # anyway, added by enable_bonjour.sh Phase 2+3).
  OLDIFS="$IFS"
  IFS=','
  for ip_addr in $LISTEN_LINE; do
    if [ "$ip_addr" = "127.0.0.1" ]; then
      continue
    fi
    if check_ip6 "$ip_addr"; then
      if [ -z "$VPN_SERVER_IP_IPV6" ]; then
        VPN_SERVER_IP_IPV6="$ip_addr"
      fi
      continue
    fi
    # First non-localhost IPv4 is the IKEv2/XAuth server IP
    if [ -z "$VPN_SERVER_IP" ]; then
      VPN_SERVER_IP="$ip_addr"
    elif [ -z "$L2TP_SERVER_IP" ]; then
      L2TP_SERVER_IP="$ip_addr"
    fi
  done
  IFS="$OLDIFS"
  if [ -z "$VPN_SERVER_IP" ]; then
    VPN_SERVER_IP="192.168.43.1"
  fi
  # Derive IKEv2/XAuth subnet
  VPN_SUBNET_PREFIX=$(printf '%s' "$VPN_SERVER_IP" | cut -d. -f1-3)
  VPN_SUBNET="${VPN_SUBNET_PREFIX}.0/24"
  # Pull IPv6 subnet info from the sync state file if present — this is the
  # authoritative source because the sync script may have applied an IPv6
  # config that's not currently in ikev2.conf (or vice-versa) due to
  # transitions. Falls back to dnsmasq listen-address + /64 derivation.
  VPN_SUBNET_IPV6=""
  STATE_FILE="/var/lib/bonjour-vpn/ipv6-state"
  if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    . "$STATE_FILE" 2>/dev/null || true
    if [ "${HAS_IPV6_SAVED:-0}" = 1 ]; then
      [ -z "$VPN_SERVER_IP_IPV6" ] && VPN_SERVER_IP_IPV6="${VPN_SERVER_IP_IPV6_SAVED:-}"
      VPN_SUBNET_IPV6="${VPN_SUBNET_IPV6_SAVED:-}"
    fi
  fi
  # If we have an IPv6 server IP but no subnet, derive a /64 from it.
  if [ -n "$VPN_SERVER_IP_IPV6" ] && [ -z "$VPN_SUBNET_IPV6" ]; then
    if printf '%s' "$VPN_SERVER_IP_IPV6" | grep -q '::'; then
      VPN_SUBNET_IPV6="$(printf '%s' "$VPN_SERVER_IP_IPV6" | sed 's/::.*//')::/64"
    else
      VPN_SUBNET_IPV6="$(printf '%s' "$VPN_SERVER_IP_IPV6" | cut -d: -f1-4)::/64"
    fi
  fi
  # Derive L2TP subnet if detected
  if [ -n "$L2TP_SERVER_IP" ]; then
    L2TP_SUBNET_PREFIX=$(printf '%s' "$L2TP_SERVER_IP" | cut -d. -f1-3)
    L2TP_SUBNET="${L2TP_SUBNET_PREFIX}.0/24"
  else
    # Try to detect from xl2tpd.conf (backed up or current)
    XL2TPD_CONF="/etc/xl2tpd/xl2tpd.conf"
    if [ -f "${XL2TPD_CONF}.bak.bonjour-vpn" ]; then
      L2TP_SERVER_IP=$(grep 'local ip' "${XL2TPD_CONF}.bak.bonjour-vpn" \
        | head -n 1 | sed 's/.*=\s*//' | tr -d '[:space:]')
    elif [ -f "$XL2TPD_CONF" ]; then
      L2TP_SERVER_IP=$(grep 'local ip' "$XL2TPD_CONF" \
        | head -n 1 | sed 's/.*=\s*//' | tr -d '[:space:]')
    fi
    if [ -n "$L2TP_SERVER_IP" ] && [ "$L2TP_SERVER_IP" != "$VPN_SERVER_IP" ]; then
      L2TP_SUBNET_PREFIX=$(printf '%s' "$L2TP_SERVER_IP" | cut -d. -f1-3)
      L2TP_SUBNET="${L2TP_SUBNET_PREFIX}.0/24"
    else
      L2TP_SERVER_IP=""
      L2TP_SUBNET=""
    fi
  fi
}

restore_config_file() {
  local file="$1"
  local backup="${file}.bak.bonjour-vpn"
  if [ -f "$backup" ]; then
    /bin/cp -f "$backup" "$file"
    /bin/rm -f "$backup"
    echo "  Restored: $file"
    return 0
  fi
  return 1
}

restore_configs() {
  bigecho "Restoring configuration files..."
  # Restore avahi-daemon.conf
  restore_config_file "/etc/avahi/avahi-daemon.conf" || true
  # Restore ikev2.conf
  restore_config_file "/etc/ipsec.d/ikev2.conf" || true
  # Restore ipsec.conf (XAuth DNS settings)
  restore_config_file "/etc/ipsec.conf" || true
  # Restore options.xl2tpd (L2TP DNS settings)
  restore_config_file "/etc/ppp/options.xl2tpd" || true
  # Restore nsswitch.conf
  restore_config_file "/etc/nsswitch.conf" || true
  # Restore dnsmasq.conf (if we backed it up)
  restore_config_file "/etc/dnsmasq.conf" || true
  # Restore rc.local (if we backed it up)
  restore_config_file "/etc/rc.local" || true
}

remove_vpn_server_ip() {
  bigecho "Removing VPN server IPs from loopback..."
  if ip addr show dev lo 2>/dev/null | grep -q "$VPN_SERVER_IP"; then
    ip addr del "${VPN_SERVER_IP}/32" dev lo 2>/dev/null
  fi
  # Also remove L2TP server IP if it was added
  if [ -n "$L2TP_SERVER_IP" ] && [ "$L2TP_SERVER_IP" != "$VPN_SERVER_IP" ]; then
    if ip addr show dev lo 2>/dev/null | grep -q "$L2TP_SERVER_IP"; then
      ip addr del "${L2TP_SERVER_IP}/32" dev lo 2>/dev/null
    fi
  fi
  # Remove the IPv6 VPN server IP from loopback if the sync script added it
  if [ -n "$VPN_SERVER_IP_IPV6" ]; then
    if ip -6 addr show dev lo 2>/dev/null | grep -q "$VPN_SERVER_IP_IPV6"; then
      ip -6 addr del "${VPN_SERVER_IP_IPV6}/128" dev lo 2>/dev/null
    fi
  fi
  # Remove from Alpine local.d script
  if [ "$os_type" = "alpine" ]; then
    /bin/rm -f /etc/local.d/bonjour-vpn.start
  else
    # Clean up rc.local entries added by enable_bonjour.sh
    RC_LOCAL="/etc/rc.local"
    if [ -f "$RC_LOCAL" ] && grep -qs "# Added by enable_bonjour.sh" "$RC_LOCAL"; then
      # If we already restored from backup, the lines are gone. Otherwise remove them.
      if grep -qs "# Added by enable_bonjour.sh" "$RC_LOCAL"; then
        sed --follow-symlinks -i '/# Added by enable_bonjour.sh/,/^$/d' "$RC_LOCAL"
        sed --follow-symlinks -i "/ip addr add ${VPN_SERVER_IP}/d" "$RC_LOCAL"
      fi
    fi
    # Also strip any IPv6 loopback-add line added by Phase 3 / the sync script
    if [ -f "$RC_LOCAL" ] && [ -n "$VPN_SERVER_IP_IPV6" ]; then
      sed --follow-symlinks -i "\|ip -6 addr add ${VPN_SERVER_IP_IPV6}|d" "$RC_LOCAL" 2>/dev/null || true
    fi
  fi
}

remove_dnsmasq_vpn_conf() {
  bigecho "Removing dnsmasq Bonjour VPN configuration..."
  /bin/rm -f /etc/dnsmasq.d/bonjour-vpn.conf
  /bin/rm -f /etc/dnsmasq.d/bonjour-vpn-services.conf
  /bin/rm -f /etc/dnsmasq.d/bonjour-vpn-services.conf.tmp
  /bin/rm -f /etc/bonjour-vpn-hosts
}

remove_cache_warmer() {
  bigecho "Removing mDNS service monitor..."
  # Remove systemd watcher service
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop bonjour-vpn-watch.service 2>/dev/null
    systemctl disable bonjour-vpn-watch.service 2>/dev/null
    /bin/rm -f /etc/systemd/system/bonjour-vpn-watch.service
    # Also clean up old timer-based setup (upgrade path)
    systemctl stop bonjour-vpn-cache-warm.timer 2>/dev/null
    systemctl disable bonjour-vpn-cache-warm.timer 2>/dev/null
    /bin/rm -f /etc/systemd/system/bonjour-vpn-cache-warm.timer
    /bin/rm -f /etc/systemd/system/bonjour-vpn-cache-warm.service
    systemctl daemon-reload 2>/dev/null
  fi
  # Remove cron entry (Alpine / non-systemd)
  if crontab -l 2>/dev/null | grep -q 'bonjour-vpn'; then
    crontab -l 2>/dev/null | grep -v 'bonjour-vpn' | crontab -
  fi
  # Remove all scripts
  /bin/rm -f /usr/local/bin/bonjour-vpn-resolve
  /bin/rm -f /usr/local/bin/bonjour-vpn-watch
  /bin/rm -f /usr/local/bin/bonjour-vpn-cache-warm
  /bin/rm -f /usr/local/sbin/bonjour-vpn-ipv6-sync
  # Remove the sync state directory. Use rm -rf only on files we own —
  # /var/lib/bonjour-vpn/ is created by enable_bonjour.sh for this purpose,
  # so deleting it here is safe.
  /bin/rm -rf /var/lib/bonjour-vpn 2>/dev/null || true
}

remove_iptables_rules() {
  bigecho "Removing IPTables rules..."
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
  # Remove DNS rules for IKEv2/XAuth VPN subnet
  while iptables -D INPUT -s "$VPN_SUBNET" -p udp --dport 53 -j ACCEPT 2>/dev/null; do :; done
  while iptables -D INPUT -s "$VPN_SUBNET" -p tcp --dport 53 -j ACCEPT 2>/dev/null; do :; done
  while iptables -D INPUT -s "$VPN_SUBNET" -p udp --dport 5353 -j ACCEPT 2>/dev/null; do :; done
  # Remove mDNS capture DNAT rules for IKEv2/XAuth VPN subnet
  while iptables -t nat -D PREROUTING -s "$VPN_SUBNET" -d 224.0.0.251 -p udp --dport 5353 -j DNAT --to-destination "${VPN_SERVER_IP}:53" 2>/dev/null; do :; done
  # Remove DNS rules for L2TP subnet (if different from VPN subnet)
  if [ -n "$L2TP_SUBNET" ] && [ "$L2TP_SUBNET" != "$VPN_SUBNET" ]; then
    while iptables -D INPUT -s "$L2TP_SUBNET" -p udp --dport 53 -j ACCEPT 2>/dev/null; do :; done
    while iptables -D INPUT -s "$L2TP_SUBNET" -p tcp --dport 53 -j ACCEPT 2>/dev/null; do :; done
    while iptables -D INPUT -s "$L2TP_SUBNET" -p udp --dport 5353 -j ACCEPT 2>/dev/null; do :; done
    # Remove mDNS capture DNAT rules for L2TP subnet
    while iptables -t nat -D PREROUTING -s "$L2TP_SUBNET" -d 224.0.0.251 -p udp --dport 5353 -j DNAT --to-destination "${L2TP_SERVER_IP}:53" 2>/dev/null; do :; done
  fi
  # Remove ip6tables rules if we added any (Phase 4 / Phase 7 sync)
  if [ -n "$VPN_SUBNET_IPV6" ] && [ -n "$VPN_SERVER_IP_IPV6" ] \
     && command -v ip6tables >/dev/null 2>&1; then
    while ip6tables -D INPUT -s "$VPN_SUBNET_IPV6" -p udp --dport 53 -j ACCEPT 2>/dev/null; do :; done
    while ip6tables -D INPUT -s "$VPN_SUBNET_IPV6" -p tcp --dport 53 -j ACCEPT 2>/dev/null; do :; done
    while ip6tables -D INPUT -s "$VPN_SUBNET_IPV6" -p udp --dport 5353 -j ACCEPT 2>/dev/null; do :; done
    while ip6tables -t nat -D PREROUTING -s "$VPN_SUBNET_IPV6" -d ff02::fb -p udp --dport 5353 -j DNAT --to-destination "[${VPN_SERVER_IP_IPV6}]:53" 2>/dev/null; do :; done
  fi
  # Save updated iptables rules
  if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] \
    || [ "$os_type" = "alpine" ]; then
    iptables-save > "$IPT_FILE"
    if [ -f "$IPT_FILE2" ]; then
      /bin/cp -f "$IPT_FILE" "$IPT_FILE2"
    fi
  else
    iptables-save > "$IPT_FILE"
  fi
  # Save updated ip6tables rules. We don't gate on VPN_SUBNET_IPV6 here
  # because even if this install never enabled IPv6, saving the (unchanged)
  # ruleset is harmless and keeps the persistence file in sync.
  if command -v ip6tables-save >/dev/null 2>&1; then
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

stop_dnsmasq() {
  bigecho "Stopping and disabling dnsmasq..."
  if [ "$os_type" = "alpine" ]; then
    rc-service dnsmasq stop 2>/dev/null
    rc-update del dnsmasq default 2>/dev/null
  else
    systemctl stop dnsmasq 2>/dev/null
    systemctl disable dnsmasq 2>/dev/null
  fi
}

restart_services() {
  bigecho "Restarting services..."
  if [ "$os_type" = "alpine" ]; then
    rc-service avahi-daemon restart 2>/dev/null
    rc-service ipsec restart 2>/dev/null
    rc-service xl2tpd restart 2>/dev/null
  else
    systemctl restart avahi-daemon 2>/dev/null
    mkdir -p /run/pluto
    service ipsec restart 2>/dev/null
    service xl2tpd restart 2>/dev/null
  fi
}

print_summary() {
cat <<'EOF'

================================================
Bonjour/mDNS for VPN Clients - Removal Complete
================================================

The following changes were reversed:
  - Restored original avahi-daemon.conf (if backup existed)
  - Restored original ikev2.conf (IKEv2 DNS settings)
  - Restored original ipsec.conf (XAuth DNS settings)
  - Restored original options.xl2tpd (L2TP DNS settings)
  - Restored original nsswitch.conf (if backup existed)
  - Restored original dnsmasq.conf (if backup existed)
  - Removed dnsmasq Bonjour VPN configuration and hosts file
  - Removed DNS-SD services config file
  - Removed mDNS cache warmer, watcher, and IPv6 sync scripts
  - Removed VPN server IP (IPv4 and IPv6) from loopback interface
  - Removed VPN server IP entries from boot scripts
  - Removed DNS/mDNS iptables AND ip6tables rules for VPN subnets
  - Removed /var/lib/bonjour-vpn state directory
  - Stopped and disabled dnsmasq
  - Restarted avahi-daemon with original config
  - Restarted IPsec and xl2tpd services

VPN clients must disconnect and reconnect to receive the updated DNS settings.

Note: avahi-daemon and dnsmasq packages were NOT uninstalled.
      To remove them manually:
        Ubuntu/Debian: apt-get remove avahi-daemon dnsmasq libnss-mdns
        CentOS/RHEL:   yum remove avahi dnsmasq nss-mdns
        Alpine:        apk del avahi dnsmasq
EOF
}

# =====================================================
# Main
# =====================================================

check_root
check_os
check_bonjour_configured
detect_vpn_server_ip

# Build subnet display for confirmation prompt
SUBNET_DISPLAY="$VPN_SUBNET"
if [ -n "$L2TP_SUBNET" ] && [ "$L2TP_SUBNET" != "$VPN_SUBNET" ]; then
  SUBNET_DISPLAY="${VPN_SUBNET}, ${L2TP_SUBNET}"
fi
if [ -n "$VPN_SUBNET_IPV6" ]; then
  SUBNET_DISPLAY="${SUBNET_DISPLAY}, ${VPN_SUBNET_IPV6}"
fi
# Build loopback display for confirmation prompt
LOOPBACK_DISPLAY="$VPN_SERVER_IP"
if [ -n "$VPN_SERVER_IP_IPV6" ]; then
  LOOPBACK_DISPLAY="${LOOPBACK_DISPLAY}, ${VPN_SERVER_IP_IPV6}"
fi

cat <<EOF

Disable Bonjour/mDNS for VPN Clients

This script will reverse all changes made by enable_bonjour.sh:
  - Restore original configuration files from backups
    (ikev2.conf, ipsec.conf, options.xl2tpd, avahi-daemon.conf, etc.)
  - Remove VPN server IP ($LOOPBACK_DISPLAY) from loopback
  - Remove dnsmasq Bonjour configuration
  - Remove iptables/ip6tables rules for DNS from VPN subnets ($SUBNET_DISPLAY)
  - Remove IPv6 sync script and state directory (/var/lib/bonjour-vpn)
  - Stop and disable dnsmasq
  - Restart avahi-daemon, IPsec, and xl2tpd

EOF
confirm_or_abort "Do you want to continue? [y/N] "

restore_configs
remove_vpn_server_ip
remove_cache_warmer
remove_dnsmasq_vpn_conf
remove_iptables_rules
stop_dnsmasq
restart_services
print_summary

exit 0
