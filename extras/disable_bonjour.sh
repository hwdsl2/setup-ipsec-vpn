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

BONJOUR_STATE_DIR="/var/lib/bonjour-vpn"
BONJOUR_CONFIG_STATE="${BONJOUR_STATE_DIR}/config"
BONJOUR_LOCK_FILE="/run/bonjour-vpn.lock"
FIREWALL_TX_DIR=""
FIREWALL_PERSIST_FILE=""
FIREWALL_PERSIST_FILE2=""
FIREWALL_PERSIST6_FILE=""
FIREWALL_PERSIST6_FILE2=""
FIREWALL_BACKEND="iptables"

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
       Oracle Linux or Alpine Linux
EOF
        exit 1
        ;;
    esac
  fi
}

acquire_bonjour_lock() {
  local old_umask
  command -v flock >/dev/null 2>&1 \
    || exiterr "The required flock command is unavailable."
  old_umask=$(umask)
  umask 077
  exec 9>"$BONJOUR_LOCK_FILE"
  umask "$old_umask"
  flock -w 30 9 || exiterr "Timed out waiting for another Bonjour VPN operation."
  trap cleanup_bonjour_operation EXIT
  trap 'cleanup_bonjour_operation; exit 1' HUP INT TERM
}

cleanup_bonjour_operation() {
  if [ -n "$FIREWALL_TX_DIR" ]; then
    rollback_firewall_transaction >/dev/null 2>&1 || true
  fi
  release_bonjour_lock
}

release_bonjour_lock() {
  flock -u 9 2>/dev/null || true
  exec 9>&- 2>/dev/null || true
}

load_saved_config() {
  HAVE_SAVED_STATE=0
  if [ -f "$BONJOUR_CONFIG_STATE" ]; then
    # Root-owned state created by enable_bonjour.sh; contains no credentials.
    # shellcheck disable=SC1090
    . "$BONJOUR_CONFIG_STATE"
    VPN_SUBNET=${VPN_SUBNET_SAVED:-}
    VPN_SERVER_IP=${VPN_SERVER_IP_SAVED:-}
    L2TP_SUBNET=${L2TP_SUBNET_SAVED:-}
    L2TP_SERVER_IP=${L2TP_SERVER_IP_SAVED:-}
    VPN_SUBNET_IPV6=${VPN_SUBNET_IPV6_SAVED:-}
    VPN_SERVER_IP_IPV6=${VPN_SERVER_IP_IPV6_SAVED:-}
    HAVE_SAVED_STATE=1
    if [ -z "$VPN_SUBNET_IPV6" ] && [ -f "$BONJOUR_STATE_DIR/ipv6-state" ]; then
      # Upgrade path from the original IPv6 branch. This root-owned state file
      # contains only network coordinates, never credentials.
      # shellcheck disable=SC1090,SC1091
      . "$BONJOUR_STATE_DIR/ipv6-state"
      if [ "${HAS_IPV6_SAVED:-0}" = 1 ]; then
        VPN_SUBNET_IPV6=${VPN_SUBNET_IPV6_SAVED:-}
        VPN_SERVER_IP_IPV6=${VPN_SERVER_IP_IPV6_SAVED:-}
      fi
    fi
    return 0
  fi
  return 1
}

check_restore_drift() {
  local file key expected actual
  [ -f "$BONJOUR_CONFIG_STATE" ] || return 0
  for file in /etc/avahi/avahi-daemon.conf /etc/ipsec.d/ikev2.conf \
    /etc/ipsec.conf /etc/ppp/options.xl2tpd /etc/nsswitch.conf \
    /etc/dnsmasq.conf /etc/rc.local /etc/network/if-pre-up.d/iptablesload; do
    [ -f "$file.bak.bonjour-vpn" ] || continue
    key=$(printf '%s' "$file" | tr '/.-' '___' | tr '[:lower:]' '[:upper:]')
    eval "expected=\${${key}_MANAGED_HASH:-}"
    [ -n "$expected" ] || continue
    actual=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
    [ "$actual" = "$expected" ] \
      || exiterr "Refusing to overwrite $file because it changed after Bonjour VPN was enabled. Restore it manually or reconcile the changes first."
  done
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
  printf '%s\n' "$1" | awk '
    !/^[0-9A-Fa-f:]+$/ || !/:/ || /:::/ { exit 1 }
    {
      value=$0
      compressed=gsub(/::/, "::", value)
      if (compressed > 1) exit 1
      n=split(value, part, ":")
      used=0
      for (i=1; i<=n; i++) {
        if (part[i] == "") continue
        if (length(part[i]) > 4) exit 1
        used++
      }
      if ((compressed == 0 && used != 8) || (compressed == 1 && used >= 8)) exit 1
    }
  '
}

detect_vpn_server_ip() {
  if load_saved_config; then
    return
  fi
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
  # anyway, as installed by enable_bonjour.sh).
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
  VPN_SUBNET_PREFIX=$(printf '%s\n' "$VPN_SERVER_IP" \
    | sed -n 's/^\([0-9][0-9.]*\)\.[0-9][0-9]*$/\1/p')
  VPN_SUBNET="${VPN_SUBNET_PREFIX}.0/24"
  # Upgrade fallback for installations created by the original IPv6 branch.
  # Current installations load IPv6 coordinates from the common config state
  # before reaching this compatibility path.
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
    L2TP_SUBNET_PREFIX=$(printf '%s\n' "$L2TP_SERVER_IP" \
      | sed -n 's/^\([0-9][0-9.]*\)\.[0-9][0-9]*$/\1/p')
    L2TP_SUBNET="${L2TP_SUBNET_PREFIX}.0/24"
  else
    # Try to detect from xl2tpd.conf (backed up or current)
    XL2TPD_CONF="/etc/xl2tpd/xl2tpd.conf"
    if [ -f "${XL2TPD_CONF}.bak.bonjour-vpn" ]; then
      L2TP_SERVER_IP=$(sed -n 's/^[[:space:]]*local ip[[:space:]]*=[[:space:]]*\([0-9][0-9.]*\).*/\1/p' \
        "${XL2TPD_CONF}.bak.bonjour-vpn" | head -n 1)
    elif [ -f "$XL2TPD_CONF" ]; then
      L2TP_SERVER_IP=$(sed -n 's/^[[:space:]]*local ip[[:space:]]*=[[:space:]]*\([0-9][0-9.]*\).*/\1/p' \
        "$XL2TPD_CONF" | head -n 1)
    fi
    if [ -n "$L2TP_SERVER_IP" ] && [ "$L2TP_SERVER_IP" != "$VPN_SERVER_IP" ]; then
      L2TP_SUBNET_PREFIX=$(printf '%s\n' "$L2TP_SERVER_IP" \
        | sed -n 's/^\([0-9][0-9.]*\)\.[0-9][0-9]*$/\1/p')
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
  # Restore an older hwdsl2 loader if Bonjour added IPv6 persistence to it.
  restore_config_file "/etc/network/if-pre-up.d/iptablesload" || true
}

remove_vpn_server_ip() {
  bigecho "Removing VPN server IPs from loopback..."
  if [ -n "$VPN_SERVER_IP" ] \
    && ip addr show dev lo 2>/dev/null | grep -q "$VPN_SERVER_IP"; then
    ip addr del "${VPN_SERVER_IP}/32" dev lo 2>/dev/null
  fi
  # Also remove L2TP server IP if it was added
  if [ -n "$L2TP_SERVER_IP" ] && [ "$L2TP_SERVER_IP" != "$VPN_SERVER_IP" ]; then
    if ip addr show dev lo 2>/dev/null | grep -q "$L2TP_SERVER_IP"; then
      ip addr del "${L2TP_SERVER_IP}/32" dev lo 2>/dev/null
    fi
  fi
  # Remove the managed IPv6 VPN server IP from loopback.
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
      sed --follow-symlinks -i '/# Added by enable_bonjour.sh/d' "$RC_LOCAL"
      sed --follow-symlinks -i "\|ip addr add ${VPN_SERVER_IP}/32 dev lo|d" "$RC_LOCAL"
      [ -n "$L2TP_SERVER_IP" ] && sed --follow-symlinks -i "\|ip addr add ${L2TP_SERVER_IP}/32 dev lo|d" "$RC_LOCAL"
    fi
    # Also strip the managed IPv6 loopback-add line.
    if [ -f "$RC_LOCAL" ] && [ -n "$VPN_SERVER_IP_IPV6" ]; then
      sed --follow-symlinks -i "\|ip -6 addr add ${VPN_SERVER_IP_IPV6}|d" "$RC_LOCAL" 2>/dev/null || true
    fi
  fi
}

remove_dnsmasq_vpn_conf() {
  bigecho "Removing dnsmasq Bonjour VPN configuration..."
  /bin/rm -f /etc/dnsmasq.d/bonjour-vpn.conf
  /bin/rm -f /etc/dnsmasq.d/.bonjour-vpn.conf.candidate
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
    systemctl stop bonjour-vpn-prepare.service 2>/dev/null
    systemctl disable bonjour-vpn-prepare.service 2>/dev/null
    /bin/rm -f /etc/systemd/system/bonjour-vpn-watch.service
    /bin/rm -f /etc/systemd/system/bonjour-vpn-prepare.service
    # Also clean up old timer-based setup (upgrade path)
    systemctl stop bonjour-vpn-cache-warm.timer 2>/dev/null
    systemctl disable bonjour-vpn-cache-warm.timer 2>/dev/null
    /bin/rm -f /etc/systemd/system/bonjour-vpn-cache-warm.timer
    /bin/rm -f /etc/systemd/system/bonjour-vpn-cache-warm.service
    /bin/rm -f /etc/systemd/system/dnsmasq.service.d/bonjour-vpn.conf
    rmdir /etc/systemd/system/dnsmasq.service.d 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null
  fi
  if [ -x /etc/init.d/bonjour-vpn-prepare ]; then
    rc-service bonjour-vpn-prepare stop 2>/dev/null || true
    rc-update del bonjour-vpn-prepare default 2>/dev/null || true
    /bin/rm -f /etc/init.d/bonjour-vpn-prepare
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
  /bin/rm -f /etc/.bonjour-vpn-hosts.candidate /etc/.bonjour-vpn-hosts.last-good
  /bin/rm -f /etc/dnsmasq.d/.bonjour-vpn-services.conf.candidate \
    /etc/dnsmasq.d/.bonjour-vpn-services.conf.last-good
}

detect_firewall_backend() {
  FIREWALL_BACKEND=iptables
  FIREWALL_PERSIST_FILE2=""
  FIREWALL_PERSIST6_FILE=""
  FIREWALL_PERSIST6_FILE2=""
  if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] \
    || [ "$os_type" = "alpine" ]; then
    FIREWALL_PERSIST_FILE=/etc/iptables.rules
    [ -f /etc/iptables/rules.v4 ] && FIREWALL_PERSIST_FILE2=/etc/iptables/rules.v4
    FIREWALL_PERSIST6_FILE=/etc/ip6tables.rules
    [ -f /etc/iptables/rules.v6 ] && FIREWALL_PERSIST6_FILE2=/etc/iptables/rules.v6
  elif grep -qs "hwdsl2 VPN script" /etc/sysconfig/nftables.conf; then
    FIREWALL_BACKEND=nftables
    FIREWALL_PERSIST_FILE=/etc/sysconfig/nftables.conf
  else
    FIREWALL_PERSIST_FILE=/etc/sysconfig/iptables
    FIREWALL_PERSIST6_FILE=/etc/sysconfig/ip6tables
  fi
}

uses_ipv6_firewall() {
  [ -n "${VPN_SUBNET_IPV6:-}" ] && [ -n "${VPN_SERVER_IP_IPV6:-}" ]
}

start_firewall_transaction() {
  local tx_dir
  install -d -m 700 "$BONJOUR_STATE_DIR"
  tx_dir=$(mktemp -d "$BONJOUR_STATE_DIR/.firewall.XXXXXX") \
    || exiterr "Could not create a firewall transaction directory."
  chmod 700 "$tx_dir"
  detect_firewall_backend
  if uses_ipv6_firewall; then
    for command_name in ip6tables ip6tables-save ip6tables-restore; do
      command -v "$command_name" >/dev/null 2>&1 \
        || { /bin/rm -rf "$tx_dir"; exiterr "Could not find $command_name for IPv6 cleanup and rollback."; }
    done
  fi
  iptables-save > "$tx_dir/live.v4" \
    || { /bin/rm -rf "$tx_dir"; exiterr "Could not snapshot the live IPv4 firewall."; }
  if [ "$FIREWALL_BACKEND" = nftables ]; then
    { echo "flush ruleset"; nft list ruleset; } > "$tx_dir/live.nft" \
      || { /bin/rm -rf "$tx_dir"; exiterr "Could not snapshot the live nftables firewall."; }
  elif uses_ipv6_firewall; then
    command -v ip6tables-save >/dev/null 2>&1 \
      || { /bin/rm -rf "$tx_dir"; exiterr "Could not find ip6tables-save for IPv6 rollback."; }
    ip6tables-save > "$tx_dir/live.v6" \
      || { /bin/rm -rf "$tx_dir"; exiterr "Could not snapshot the live IPv6 firewall."; }
  fi
  if [ -f "$FIREWALL_PERSIST_FILE" ]; then
    printf '1\n' > "$tx_dir/persist.had"
    /bin/cp -p "$FIREWALL_PERSIST_FILE" "$tx_dir/persist.before" \
      || { /bin/rm -rf "$tx_dir"; exiterr "Could not snapshot the persistent firewall."; }
  else
    printf '0\n' > "$tx_dir/persist.had"
  fi
  if [ -n "$FIREWALL_PERSIST_FILE2" ] && [ -f "$FIREWALL_PERSIST_FILE2" ]; then
    printf '1\n' > "$tx_dir/persist2.had"
    /bin/cp -p "$FIREWALL_PERSIST_FILE2" "$tx_dir/persist2.before" \
      || { /bin/rm -rf "$tx_dir"; exiterr "Could not snapshot the secondary persistent firewall."; }
  else
    printf '0\n' > "$tx_dir/persist2.had"
  fi
  if [ "$FIREWALL_BACKEND" != nftables ] && uses_ipv6_firewall; then
    if [ -f "$FIREWALL_PERSIST6_FILE" ]; then
      printf '1\n' > "$tx_dir/persist6.had"
      /bin/cp -p "$FIREWALL_PERSIST6_FILE" "$tx_dir/persist6.before" \
        || { /bin/rm -rf "$tx_dir"; exiterr "Could not snapshot the persistent IPv6 firewall."; }
    else
      printf '0\n' > "$tx_dir/persist6.had"
    fi
    if [ -n "$FIREWALL_PERSIST6_FILE2" ] && [ -f "$FIREWALL_PERSIST6_FILE2" ]; then
      printf '1\n' > "$tx_dir/persist62.had"
      /bin/cp -p "$FIREWALL_PERSIST6_FILE2" "$tx_dir/persist62.before" \
        || { /bin/rm -rf "$tx_dir"; exiterr "Could not snapshot the secondary persistent IPv6 firewall."; }
    else
      printf '0\n' > "$tx_dir/persist62.had"
    fi
  fi
  FIREWALL_TX_DIR="$tx_dir"
}

restore_persistent_file() {
  local had_file="$1" backup="$2" destination="$3"
  [ -n "$destination" ] || return 0
  if [ "$(cat "$had_file" 2>/dev/null || echo 0)" = 1 ]; then
    /bin/cp -p "$backup" "$destination"
  else
    /bin/rm -f "$destination"
  fi
}

rollback_firewall_transaction() {
  [ -n "$FIREWALL_TX_DIR" ] || return 0
  if [ "$FIREWALL_BACKEND" = nftables ] && [ -f "$FIREWALL_TX_DIR/live.nft" ]; then
    nft -f "$FIREWALL_TX_DIR/live.nft" 2>/dev/null || true
  else
    iptables-restore < "$FIREWALL_TX_DIR/live.v4" 2>/dev/null || true
    if [ -f "$FIREWALL_TX_DIR/live.v6" ]; then
      ip6tables-restore < "$FIREWALL_TX_DIR/live.v6" 2>/dev/null || true
    fi
  fi
  restore_persistent_file "$FIREWALL_TX_DIR/persist.had" \
    "$FIREWALL_TX_DIR/persist.before" "$FIREWALL_PERSIST_FILE" || true
  restore_persistent_file "$FIREWALL_TX_DIR/persist2.had" \
    "$FIREWALL_TX_DIR/persist2.before" "$FIREWALL_PERSIST_FILE2" || true
  if [ -f "$FIREWALL_TX_DIR/persist6.had" ]; then
    restore_persistent_file "$FIREWALL_TX_DIR/persist6.had" \
      "$FIREWALL_TX_DIR/persist6.before" "$FIREWALL_PERSIST6_FILE" || true
    restore_persistent_file "$FIREWALL_TX_DIR/persist62.had" \
      "$FIREWALL_TX_DIR/persist62.before" "$FIREWALL_PERSIST6_FILE2" || true
  fi
  /bin/rm -f "${FIREWALL_PERSIST_FILE}.bonjour-vpn.candidate"
  [ -n "$FIREWALL_PERSIST_FILE2" ] \
    && /bin/rm -f "${FIREWALL_PERSIST_FILE2}.bonjour-vpn.candidate"
  [ -n "$FIREWALL_PERSIST6_FILE" ] \
    && /bin/rm -f "${FIREWALL_PERSIST6_FILE}.bonjour-vpn.candidate"
  [ -n "$FIREWALL_PERSIST6_FILE2" ] \
    && /bin/rm -f "${FIREWALL_PERSIST6_FILE2}.bonjour-vpn.candidate"
  /bin/rm -rf "$FIREWALL_TX_DIR"
  FIREWALL_TX_DIR=""
}

finish_firewall_transaction() {
  /bin/rm -rf "$FIREWALL_TX_DIR"
  FIREWALL_TX_DIR=""
}

remove_nft_allow_rules() {
  local table chain handle
  for table in firewalld nftables_svc; do
    [ "$table" = firewalld ] && chain=filter_INPUT || chain=INPUT
    nft list chain inet "$table" "$chain" >/dev/null 2>&1 || continue
    while true; do
      handle=$(nft -a list chain inet "$table" "$chain" 2>/dev/null \
        | awk 'index($0, "comment \"bonjour-vpn:") { for (i=1; i<=NF; i++) if ($i == "handle") { print $(i+1); exit } }')
      [ -n "$handle" ] || break
      nft delete rule inet "$table" "$chain" handle "$handle" || return 1
    done
  done
}

persist_firewall() {
  local candidate candidate2 candidate6 candidate62
  candidate="${FIREWALL_PERSIST_FILE}.bonjour-vpn.candidate"
  if [ "$FIREWALL_BACKEND" = nftables ]; then
    {
      echo "# Modified by hwdsl2 VPN script"
      echo "flush ruleset"
      nft list ruleset
    } > "$candidate" || return 1
    if ! nft -c -f "$candidate" >/dev/null 2>&1; then
      sed -i '/xt target "MASQUERADE"/s/xt target "MASQUERADE"/masquerade/' "$candidate"
    fi
    nft -c -f "$candidate" >/dev/null 2>&1 || return 1
  else
    {
      echo "# Modified by hwdsl2 VPN script"
      iptables-save
    } > "$candidate" || return 1
    if iptables-restore --help 2>&1 | grep -q -- '--test'; then
      iptables-restore --test < "$candidate" >/dev/null 2>&1 || return 1
    fi
  fi
  chmod 600 "$candidate" || return 1
  mv -f "$candidate" "$FIREWALL_PERSIST_FILE" || return 1
  if [ -n "$FIREWALL_PERSIST_FILE2" ]; then
    candidate2="${FIREWALL_PERSIST_FILE2}.bonjour-vpn.candidate"
    /bin/cp -p "$FIREWALL_PERSIST_FILE" "$candidate2" || return 1
    mv -f "$candidate2" "$FIREWALL_PERSIST_FILE2" || return 1
  fi
  if [ "$FIREWALL_BACKEND" != nftables ] && uses_ipv6_firewall; then
    candidate6="${FIREWALL_PERSIST6_FILE}.bonjour-vpn.candidate"
    {
      echo "# Modified by hwdsl2 VPN script"
      ip6tables-save
    } > "$candidate6" || return 1
    if ip6tables-restore --help 2>&1 | grep -q -- '--test'; then
      ip6tables-restore --test < "$candidate6" >/dev/null 2>&1 || return 1
    fi
    chmod 600 "$candidate6" || return 1
    mv -f "$candidate6" "$FIREWALL_PERSIST6_FILE" || return 1
    if [ -n "$FIREWALL_PERSIST6_FILE2" ]; then
      candidate62="${FIREWALL_PERSIST6_FILE2}.bonjour-vpn.candidate"
      /bin/cp -p "$FIREWALL_PERSIST6_FILE" "$candidate62" || return 1
      mv -f "$candidate62" "$FIREWALL_PERSIST6_FILE2" || return 1
    fi
  fi
}

remove_ipv4_bonjour_rules() {
  local subnet="$1" endpoint="$2"
  [ -n "$subnet" ] && [ -n "$endpoint" ] || return 0
  while iptables -D INPUT -s "$subnet" -p udp --dport 53 -j ACCEPT 2>/dev/null; do
    FIREWALL_RULES_REMOVED=$((FIREWALL_RULES_REMOVED + 1))
  done
  while iptables -D INPUT -s "$subnet" -p tcp --dport 53 -j ACCEPT 2>/dev/null; do
    FIREWALL_RULES_REMOVED=$((FIREWALL_RULES_REMOVED + 1))
  done
  while iptables -D INPUT -s "$subnet" -p udp --dport 5353 -j ACCEPT 2>/dev/null; do
    FIREWALL_RULES_REMOVED=$((FIREWALL_RULES_REMOVED + 1))
  done
  while iptables -t nat -D PREROUTING -s "$subnet" -d 224.0.0.251 \
    -p udp --dport 5353 -j DNAT --to-destination "${endpoint}:53" 2>/dev/null; do
    FIREWALL_RULES_REMOVED=$((FIREWALL_RULES_REMOVED + 1))
  done
}

remove_iptables_rules() {
  bigecho "Removing firewall rules..."
  start_firewall_transaction
  FIREWALL_RULES_REMOVED=0
  # Remove DNS and mDNS capture rules for the IKEv2/XAuth VPN subnet.
  remove_ipv4_bonjour_rules "$VPN_SUBNET" "$VPN_SERVER_IP"
  # Remove DNS rules for L2TP subnet (if different from VPN subnet)
  if [ -n "$L2TP_SUBNET" ] && [ "$L2TP_SUBNET" != "$VPN_SUBNET" ]; then
    remove_ipv4_bonjour_rules "$L2TP_SUBNET" "$L2TP_SERVER_IP"
  fi
  # Remove IPv6 firewall rules installed by enable_bonjour.sh.
  if [ -n "$VPN_SUBNET_IPV6" ] && [ -n "$VPN_SERVER_IP_IPV6" ] \
     && command -v ip6tables >/dev/null 2>&1; then
    while ip6tables -D INPUT -s "$VPN_SUBNET_IPV6" -p udp --dport 53 -j ACCEPT 2>/dev/null; do
      FIREWALL_RULES_REMOVED=$((FIREWALL_RULES_REMOVED + 1))
    done
    while ip6tables -D INPUT -s "$VPN_SUBNET_IPV6" -p tcp --dport 53 -j ACCEPT 2>/dev/null; do
      FIREWALL_RULES_REMOVED=$((FIREWALL_RULES_REMOVED + 1))
    done
    while ip6tables -D INPUT -s "$VPN_SUBNET_IPV6" -p udp --dport 5353 -j ACCEPT 2>/dev/null; do
      FIREWALL_RULES_REMOVED=$((FIREWALL_RULES_REMOVED + 1))
    done
    while ip6tables -t nat -D PREROUTING -s "$VPN_SUBNET_IPV6" -d ff02::fb -p udp --dport 5353 -j DNAT --to-destination "[${VPN_SERVER_IP_IPV6}]:53" 2>/dev/null; do
      FIREWALL_RULES_REMOVED=$((FIREWALL_RULES_REMOVED + 1))
    done
  fi
  if [ "${HAVE_SAVED_STATE:-0}" != 1 ] && [ "$FIREWALL_RULES_REMOVED" -eq 0 ]; then
    rollback_firewall_transaction
    exiterr "No matching legacy Bonjour firewall rules were found. Refusing to continue with an inferred /24 subnet; reconcile the firewall rules manually first."
  fi
  if [ "$FIREWALL_BACKEND" = nftables ]; then
    remove_nft_allow_rules \
      || { rollback_firewall_transaction; exiterr "Could not remove native nftables Bonjour rules."; }
  fi
  persist_firewall \
    || { rollback_firewall_transaction; exiterr "Could not validate and persist the updated firewall."; }
  finish_firewall_transaction
}

restore_service_states() {
  bigecho "Restoring service state..."
  if [ "${HAVE_SAVED_STATE:-0}" != 1 ] \
    || [ "${SERVICE_STATE_VERSION_SAVED:-0}" != 2 ]; then
    echo "  Note: no complete pre-feature service-state record exists; leaving service enablement and activity unchanged."
    return
  fi
  if [ "$os_type" = "alpine" ]; then
    if [ "${DNSMASQ_WAS_ENABLED_SAVED:-0}" = 1 ]; then
      rc-update add dnsmasq default 2>/dev/null
    else
      rc-update del dnsmasq default 2>/dev/null
    fi
    if [ "${DNSMASQ_WAS_ACTIVE_SAVED:-0}" = 1 ]; then
      rc-service dnsmasq restart 2>/dev/null
    else
      rc-service dnsmasq stop 2>/dev/null
    fi
    if [ "${AVAHI_WAS_ENABLED_SAVED:-0}" = 1 ]; then
      rc-update add avahi-daemon default 2>/dev/null
    else
      rc-update del avahi-daemon default 2>/dev/null
    fi
    if [ "${AVAHI_WAS_ACTIVE_SAVED:-0}" = 1 ]; then
      rc-service avahi-daemon restart 2>/dev/null
    else
      rc-service avahi-daemon stop 2>/dev/null
    fi
    if [ "${DBUS_WAS_ENABLED_SAVED:-0}" = 1 ]; then
      rc-update add dbus default 2>/dev/null
    else
      rc-update del dbus default 2>/dev/null
    fi
    if [ "${DBUS_WAS_ACTIVE_SAVED:-0}" = 1 ]; then
      rc-service dbus start 2>/dev/null
    elif [ "${AVAHI_WAS_ACTIVE_SAVED:-0}" != 1 ]; then
      rc-service dbus stop 2>/dev/null
    fi
  else
    if [ "${DNSMASQ_WAS_ENABLED_SAVED:-0}" = 1 ]; then
      systemctl enable dnsmasq.service 2>/dev/null
    else
      systemctl disable dnsmasq.service 2>/dev/null
    fi
    if [ "${DNSMASQ_WAS_ACTIVE_SAVED:-0}" = 1 ]; then
      systemctl reset-failed dnsmasq.service 2>/dev/null || true
      systemctl restart dnsmasq.service 2>/dev/null
    else
      systemctl stop dnsmasq.service 2>/dev/null
    fi
    if [ "${AVAHI_WAS_ENABLED_SAVED:-0}" = 1 ]; then
      systemctl enable avahi-daemon.service 2>/dev/null
    else
      systemctl disable avahi-daemon.service 2>/dev/null
    fi
    if [ "${AVAHI_WAS_ACTIVE_SAVED:-0}" = 1 ]; then
      systemctl restart avahi-daemon.service 2>/dev/null
    else
      systemctl stop avahi-daemon.service 2>/dev/null
    fi
    if [ "${AVAHI_SOCKET_WAS_ENABLED_SAVED:-0}" = 1 ]; then
      systemctl enable avahi-daemon.socket 2>/dev/null
    else
      systemctl disable avahi-daemon.socket 2>/dev/null
    fi
    if [ "${AVAHI_SOCKET_WAS_ACTIVE_SAVED:-0}" = 1 ]; then
      systemctl start avahi-daemon.socket 2>/dev/null
    else
      systemctl stop avahi-daemon.socket 2>/dev/null
    fi
    if [ "${DBUS_WAS_ACTIVE_SAVED:-0}" = 1 ]; then
      systemctl start dbus.service 2>/dev/null
    elif [ "${AVAHI_WAS_ACTIVE_SAVED:-0}" != 1 ]; then
      systemctl stop dbus.service 2>/dev/null
    fi
  fi
}

restart_services() {
  bigecho "Reloading VPN services..."
  if [ "$os_type" = "alpine" ]; then
    rc-service ipsec restart 2>/dev/null
    if [ "${HAS_L2TP_SAVED:-0}" = 1 ] || [ -n "$L2TP_SERVER_IP" ]; then
      rc-service xl2tpd restart 2>/dev/null
    fi
  else
    mkdir -p /run/pluto
    service ipsec restart 2>/dev/null
    if [ "${HAS_L2TP_SAVED:-0}" = 1 ] || [ -n "$L2TP_SERVER_IP" ]; then
      service xl2tpd restart 2>/dev/null
    fi
  fi
}

remove_bonjour_state() {
  /bin/rm -f "$BONJOUR_STATE_DIR/config" "$BONJOUR_STATE_DIR/.config.candidate" \
    "$BONJOUR_STATE_DIR/empty-count" "$BONJOUR_STATE_DIR/ipv6-state" \
    "$BONJOUR_STATE_DIR/ipv6-enabled"
  find "$BONJOUR_STATE_DIR" -maxdepth 1 -type f -name '.browse.*' -delete 2>/dev/null || true
  for stale_dir in "$BONJOUR_STATE_DIR"/.dnsmasq-install-test.*; do
    [ -d "$stale_dir" ] && /bin/rm -rf "$stale_dir"
  done
  rmdir "$BONJOUR_STATE_DIR" 2>/dev/null || true
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
  - Removed mDNS resolver and watcher scripts
  - Removed VPN server IP (IPv4 and IPv6) from loopback interface
  - Removed VPN server IP entries from boot scripts
  - Removed DNS/mDNS iptables and ip6tables rules for VPN subnets
  - Removed /var/lib/bonjour-vpn state directory
  - Restored the prior dnsmasq and avahi-daemon service states
  - Restarted the configured VPN services

VPN clients must disconnect and reconnect to receive the updated DNS settings.

Note: avahi-daemon and dnsmasq packages were NOT uninstalled.
      To remove them manually:
        Ubuntu/Debian: apt-get remove avahi-daemon dnsmasq
        CentOS/RHEL:   yum remove avahi dnsmasq
        Alpine:        apk del avahi dnsmasq
EOF
}

main() {
  check_root
  check_os
  check_bonjour_configured
  detect_vpn_server_ip
  check_restore_drift

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
  - Remove Bonjour VPN runtime scripts and state directory (/var/lib/bonjour-vpn)
  - Restore the prior dnsmasq, avahi-daemon and D-Bus service states
  - Restart the configured VPN services

EOF
confirm_or_abort "Do you want to continue? [y/N] "

acquire_bonjour_lock
  remove_iptables_rules
  restore_configs
  remove_vpn_server_ip
  remove_cache_warmer
  remove_dnsmasq_vpn_conf
  restore_service_states
  restart_services
  remove_bonjour_state
  print_summary
}

if [ "${BONJOUR_VPN_LIBRARY_ONLY:-0}" != 1 ]; then
  main "$@"
fi
