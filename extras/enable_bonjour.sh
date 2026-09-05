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

export PATH="${BONJOUR_VPN_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
BONJOUR_VPN_ROOT="${BONJOUR_VPN_ROOT:-}"

exiterr()  { echo "Error: $1" >&2; exit 1; }
bigecho()  { echo "## $1"; }

BONJOUR_STATE_DIR="/var/lib/bonjour-vpn"
BONJOUR_CONFIG_STATE="${BONJOUR_STATE_DIR}/config"
BONJOUR_INCOMPLETE_STATE="${BONJOUR_STATE_DIR}/incomplete"
BONJOUR_LOCK_FILE="/run/bonjour-vpn.lock"
FIREWALL_TX_DIR=""
FIREWALL_PERSIST_FILE=""
FIREWALL_PERSIST_FILE2=""
FIREWALL_PERSIST6_FILE=""
FIREWALL_PERSIST6_FILE2=""
FIREWALL_BACKEND="iptables"
IPV6_FIREWALL_LOADER=""
IPV6_FIREWALL_LOADER_NEEDS_UPDATE=0
IPV6_FIREWALL_LOADER_CANDIDATE=""
DNSMASQ_INSTALL_TEST_DIR=""
DNSMASQ_VPN_CANDIDATE=""
RESOLVE_SCRIPT_CANDIDATE=""
WATCHER_SCRIPT_CANDIDATE=""
RECONFIGURE_CONFIRMED=0
FIREWALL_PERSIST6_FILE_WAS_PRESENT=""
FIREWALL_PERSIST6_FILE2_WAS_PRESENT=""

conf_bk_bonjour() {
  if [ -f "$1" ] && [ ! -f "$1.bak.bonjour-vpn" ]; then
    /bin/cp -p "$1" "$1.bak.bonjour-vpn" \
      || exiterr "Could not back up $1."
  fi
}

append_before_terminal_exit() {
  # Append one managed rc.local line immediately before only the final,
  # effective "exit 0". Earlier exits may be deliberate control flow and
  # must never be deleted or duplicated.
  local target="$1" managed_line="$2" candidate
  candidate=$(mktemp) || exiterr "Could not create an rc.local candidate."
  awk -v managed_line="$managed_line" '
    { content[NR]=$0 }
    END {
      last=NR
      while (last > 0 && content[last] ~ /^[[:space:]]*(#.*)?$/) last--
      terminal=(last > 0 && content[last] ~ /^[[:space:]]*exit[[:space:]]+0([[:space:]]*(#.*)?)?$/)
      for (line=1; line<=NR; line++) {
        if (terminal && line == last) print managed_line
        print content[line]
      }
      if (!terminal) print managed_line
    }
  ' "$target" > "$candidate" \
    || { /bin/rm -f "$candidate"; exiterr "Could not prepare the rc.local update."; }
  /bin/cp "$candidate" "$target" \
    || { /bin/rm -f "$candidate"; exiterr "Could not update $target."; }
  /bin/rm -f "$candidate"
}

ensure_rc_local_managed_line() {
  local target="$1" managed_line="$2"
  [ -f "$target" ] || return 1
  if ! grep -qs "# Added by enable_bonjour.sh" "$target"; then
    conf_bk_bonjour "$target"
    append_before_terminal_exit "$target" \
      "# Added by enable_bonjour.sh - Bonjour/mDNS VPN support"
  fi
  if ! grep -Fxq "$managed_line" "$target"; then
    append_before_terminal_exit "$target" "$managed_line"
  fi
}

install_cache_warmer_cron() {
  local cron_line="$1" legacy_line="* * * * * /usr/local/bin/bonjour-vpn-resolve" current
  current=$(crontab -l 2>/dev/null || true)
  {
    if [ -n "$current" ]; then
      printf '%s\n' "$current" \
        | awk -v wanted="$cron_line" -v legacy="$legacy_line" \
          '$0 != wanted && $0 != legacy'
    fi
    printf '%s\n' "$cron_line"
  } | crontab -
}

check_ip() {
  IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "$IP_REGEX"
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

canonical_ipv6() {
  local input
  input=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  check_ip6 "$input" || return 1
  printf '%s\n' "$input" | awk '
    function padded(value) { return substr("0000" value, length(value) + 1) }
    {
      compressed=index($0, "::")
      if (compressed) {
        left=substr($0, 1, compressed - 1)
        right=substr($0, compressed + 2)
        left_count=(left == "" ? 0 : split(left, left_part, ":"))
        right_count=(right == "" ? 0 : split(right, right_part, ":"))
        zeros=8-left_count-right_count
        output=""
        for (i=1; i<=left_count; i++) output=output (output == "" ? "" : ":") padded(left_part[i])
        for (i=1; i<=zeros; i++) output=output (output == "" ? "" : ":") "0000"
        for (i=1; i<=right_count; i++) output=output (output == "" ? "" : ":") padded(right_part[i])
      } else {
        count=split($0, part, ":")
        output=""
        for (i=1; i<=count; i++) output=output (output == "" ? "" : ":") padded(part[i])
      }
      print output
    }
  '
}

ipv6_in_pool() {
  local pool="$1" address="$2" start end candidate prefix
  start=$(canonical_ipv6 "${pool%-*}") || return 1
  end=$(canonical_ipv6 "${pool#*-}") || return 1
  candidate=$(canonical_ipv6 "$address") || return 1
  prefix=${start%:*:*:*:*}
  [ "${end%:*:*:*:*}" = "$prefix" ] \
    && [ "${candidate%:*:*:*:*}" = "$prefix" ] || return 1
  [[ "$start" > "$end" ]] && return 1
  [[ "$candidate" < "$start" || "$candidate" > "$end" ]] && return 1
  return 0
}

ipv6_in_subnet64() {
  local address subnet_address canonical_address canonical_subnet
  address="$1"
  subnet_address=${2%/64}
  canonical_address=$(canonical_ipv6 "$address") || return 1
  canonical_subnet=$(canonical_ipv6 "$subnet_address") || return 1
  [ "${canonical_address%:*:*:*:*}" = "${canonical_subnet%:*:*:*:*}" ]
}

select_vpn_dns_ipv6() {
  local subnet="$1" pool="$2" previous="${3:-}" subnet_base value candidate
  local pool_start pool_end pool_end_suffix pool_end_value
  pool_start=$(canonical_ipv6 "${pool%-*}") || return 1
  pool_end=$(canonical_ipv6 "${pool#*-}") || return 1
  [[ "$pool_start" > "$pool_end" ]] && return 1
  ipv6_in_subnet64 "${pool%-*}" "$subnet" \
    && ipv6_in_subnet64 "${pool#*-}" "$subnet" || return 1
  if [ -n "$previous" ] && ipv6_in_subnet64 "$previous" "$subnet" \
    && ! ipv6_in_pool "$pool" "$previous"; then
    printf '%s\n' "$previous"
    return 0
  fi
  subnet_base=${subnet%/64}
  printf '%s' "$subnet_base" | grep -q '::$' || return 1
  # Prefer ::1. If a custom pool includes it and ends in the first 16-bit
  # host word, try the first address after that pool. Finally try the top of
  # the /64, which avoids an expensive or lossy 64-bit shell counter.
  candidate="${subnet_base}1"
  if ipv6_dns_candidate_available "$pool" "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi
  pool_end_suffix=${pool_end#*:*:*:*:}
  if [[ "$pool_end_suffix" == 0000:0000:0000:* ]]; then
    pool_end_value=$((16#${pool_end##*:}))
    if [ "$pool_end_value" -lt 65535 ]; then
      value=$((pool_end_value + 1))
      printf -v candidate '%s%x' "$subnet_base" "$value"
      if ipv6_dns_candidate_available "$pool" "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
  fi
  candidate="${subnet_base}ffff:ffff:ffff:ffff"
  if ipv6_dns_candidate_available "$pool" "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

ipv6_dns_candidate_available() {
  local pool="$1" candidate="$2"
  ! ipv6_in_pool "$pool" "$candidate" \
    && ! ipv6_address_exists "$candidate"
}

ipv6_address_exists() {
  local address="$1" device="${2:-}" wanted assigned assigned_canonical addresses
  wanted=$(canonical_ipv6 "$address") || return 1
  if [ -n "$device" ]; then
    addresses=$(ip -6 -o addr show dev "$device" 2>/dev/null \
      | awk '$3 == "inet6" { split($4, value, "/"); print value[1] }')
  else
    addresses=$(ip -6 -o addr show 2>/dev/null \
      | awk '$3 == "inet6" { split($4, value, "/"); print value[1] }')
  fi
  while IFS= read -r assigned; do
    [ -n "$assigned" ] || continue
    assigned_canonical=$(canonical_ipv6 "$assigned") || continue
    [ "$assigned_canonical" = "$wanted" ] && return 0
  done <<EOF
$addresses
EOF
  return 1
}

check_cidr() {
  local cidr="$1" ip prefix
  ip=${cidr%/*}
  prefix=${cidr#*/}
  [ "$ip" != "$cidr" ] && check_ip "$ip" || return 1
  case "$prefix" in ''|*[!0-9]*) return 1 ;; esac
  prefix=$((10#$prefix))
  [ "$prefix" -ge 8 ] && [ "$prefix" -le 30 ]
}

ipv4_to_int() {
  local ip="$1" a b c d old_ifs
  check_ip "$ip" || return 1
  old_ifs=$IFS
  IFS=.
  read -r a b c d <<EOF
$ip
EOF
  IFS=$old_ifs
  printf '%u\n' "$(( (a << 24) + (b << 16) + (c << 8) + d ))"
}

int_to_ipv4() {
  local value="$1"
  printf '%u.%u.%u.%u\n' \
    "$(( (value >> 24) & 255 ))" "$(( (value >> 16) & 255 ))" \
    "$(( (value >> 8) & 255 ))" "$(( value & 255 ))"
}

cidr_bounds() {
  local cidr="$1" ip prefix ip_int mask network broadcast
  check_cidr "$cidr" || return 1
  ip=${cidr%/*}
  prefix=${cidr#*/}
  prefix=$((10#$prefix))
  ip_int=$(ipv4_to_int "$ip") || return 1
  mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
  network=$(( ip_int & mask ))
  broadcast=$(( network | ((~mask) & 0xFFFFFFFF) ))
  printf '%u %u\n' "$network" "$broadcast"
}

ipv4_in_cidr() {
  local ip_int bounds network broadcast
  ip_int=$(ipv4_to_int "$1") || return 1
  bounds=$(cidr_bounds "$2") || return 1
  network=${bounds% *}
  broadcast=${bounds#* }
  [ "$ip_int" -ge "$network" ] && [ "$ip_int" -le "$broadcast" ]
}

extract_ipv4_pool() {
  # Print the first IPv4 start-end range from a comma-separated pool value.
  printf '%s\n' "$1" | sed 's/.*rightaddresspool=//; s/["'"'"']//g' \
    | tr ',' '\n' \
    | sed -n 's/^[[:space:]]*\([0-9][0-9.]*-[0-9][0-9.]*\)[[:space:]]*$/\1/p' \
    | head -n 1
}

configured_vpn_cidrs() {
  [ -f "$IPSEC_CONF" ] || return 0
  sed -n 's/^[[:space:]]*virtual-private=//p' "$IPSEC_CONF" \
    | tr ',' '\n' \
    | sed -n 's/^[[:space:]]*%v4:!\([0-9][0-9.]*\/[0-9][0-9]*\)[[:space:]]*$/\1/p'
}

subnet_for_pool() {
  local pool="$1" fallback="$2" start end cidr best best_prefix prefix
  start=${pool%-*}
  end=${pool#*-}
  check_ip "$start" && check_ip "$end" || return 1
  best=""
  best_prefix=-1
  while IFS= read -r cidr; do
    check_cidr "$cidr" || continue
    if ipv4_in_cidr "$start" "$cidr" && ipv4_in_cidr "$end" "$cidr"; then
      prefix=${cidr#*/}
      if [ "$prefix" -gt "$best_prefix" ]; then
        best="$cidr"
        best_prefix=$prefix
      fi
    fi
  done <<EOF
$(configured_vpn_cidrs)
EOF
  if [ -n "$best" ]; then
    printf '%s\n' "$best"
    return 0
  fi
  if [ -n "$fallback" ] && ipv4_in_cidr "$start" "$fallback" \
    && ipv4_in_cidr "$end" "$fallback"; then
    printf '%s\n' "$fallback"
    return 0
  fi
  return 1
}

pool_contains_ip() {
  local pool="$1" ip="$2" start end value
  start=$(ipv4_to_int "${pool%-*}") || return 1
  end=$(ipv4_to_int "${pool#*-}") || return 1
  value=$(ipv4_to_int "$ip") || return 1
  [ "$value" -ge "$start" ] && [ "$value" -le "$end" ]
}

select_vpn_dns_ip() {
  local cidr="$1" pool="$2" previous="${3:-}" bounds network broadcast value candidate \
    tries pool_start pool_end
  if [ -n "$previous" ] && check_ip "$previous" && ipv4_in_cidr "$previous" "$cidr" \
    && ! pool_contains_ip "$pool" "$previous"; then
    printf '%s\n' "$previous"
    return 0
  fi
  bounds=$(cidr_bounds "$cidr") || return 1
  network=${bounds% *}
  broadcast=${bounds#* }
  pool_start=$(ipv4_to_int "${pool%-*}") || return 1
  pool_end=$(ipv4_to_int "${pool#*-}") || return 1
  [ "$pool_start" -le "$pool_end" ] || return 1
  value=$((network + 1))
  tries=0
  while [ "$value" -lt "$broadcast" ] && [ "$tries" -lt 1024 ]; do
    if [ "$value" -ge "$pool_start" ] && [ "$value" -le "$pool_end" ]; then
      value=$((pool_end + 1))
      continue
    fi
    candidate=$(int_to_ipv4 "$value")
    if ! ip -4 addr show 2>/dev/null | grep -Eq "inet ${candidate}/"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    value=$((value + 1))
    tries=$((tries + 1))
  done
  return 1
}

discover_legacy_vpn_dns_ip() {
  local cidr="$1" pool="$2" root_dir="${BONJOUR_VPN_ROOT:-}"
  local config marker candidate selected="" matches=0
  config="${root_dir}/etc/dnsmasq.d/bonjour-vpn.conf"
  marker='# Added by enable_bonjour.sh'

  # Early Bonjour releases did not persist a consolidated state file. During
  # an explicit reconfigure, reuse their endpoint only when three independent
  # ownership signals agree: the package marker, a matching dnsmasq listener,
  # and the exact mDNS DNAT rule. This avoids selecting a new endpoint and
  # leaving the legacy rule behind, without adopting arbitrary administrator
  # firewall or DNS configuration.
  [ ! -f "$BONJOUR_CONFIG_STATE" ] || return 1
  [ -f "$config" ] && [ ! -L "$config" ] || return 1
  grep -Fxq "$marker" "$config" || return 1

  while IFS= read -r candidate; do
    candidate=$(printf '%s' "$candidate" | tr -d '[:space:]')
    [ -n "$candidate" ] || continue
    check_ip "$candidate" || continue
    ipv4_in_cidr "$candidate" "$cidr" || continue
    pool_contains_ip "$pool" "$candidate" && continue
    loopback_has_ipv4 "$candidate" || continue
    iptables -t nat -C PREROUTING -s "$cidr" -d 224.0.0.251 \
      -p udp --dport 5353 -j DNAT --to-destination "${candidate}:53" \
      2>/dev/null || continue
    [ "$candidate" = "$selected" ] && continue
    selected=$candidate
    matches=$((matches + 1))
  done <<EOF
$(sed -n 's/^[[:space:]]*listen-address[[:space:]]*=[[:space:]]*//p' "$config" \
  | tr ',' '\n')
EOF

  [ "$matches" -eq 1 ] || return 1
  printf '%s\n' "$selected"
}

load_saved_config() {
  SAVED_VPN_SUBNET=""
  SAVED_VPN_SERVER_IP=""
  SAVED_L2TP_SUBNET=""
  SAVED_L2TP_SERVER_IP=""
  SAVED_HAS_IPV6=0
  SAVED_VPN_SUBNET_IPV6=""
  SAVED_VPN_SERVER_IP_IPV6=""
  SAVED_VPN_SERVER_IP_WAS_PRESENT=""
  SAVED_L2TP_SERVER_IP_WAS_PRESENT=""
  SAVED_VPN_SERVER_IP_IPV6_WAS_PRESENT=""
  SAVED_VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT=""
  SAVED_UPSTREAM_DNS1=""
  SAVED_UPSTREAM_DNS2=""
  SAVED_FIREWALL_PERSIST6_FILE_WAS_PRESENT=""
  SAVED_FIREWALL_PERSIST6_FILE2_WAS_PRESENT=""
  if [ -f "$BONJOUR_CONFIG_STATE" ]; then
    # This file is created root-only by this script and contains no credentials.
    # shellcheck disable=SC1090
    . "$BONJOUR_CONFIG_STATE"
    SAVED_VPN_SUBNET=${VPN_SUBNET_SAVED:-}
    SAVED_VPN_SERVER_IP=${VPN_SERVER_IP_SAVED:-}
    SAVED_L2TP_SUBNET=${L2TP_SUBNET_SAVED:-}
    SAVED_L2TP_SERVER_IP=${L2TP_SERVER_IP_SAVED:-}
    SAVED_HAS_IPV6=${HAS_IPV6_SAVED:-0}
    SAVED_VPN_SUBNET_IPV6=${VPN_SUBNET_IPV6_SAVED:-}
    SAVED_VPN_SERVER_IP_IPV6=${VPN_SERVER_IP_IPV6_SAVED:-}
    SAVED_VPN_SERVER_IP_WAS_PRESENT=${VPN_SERVER_IP_WAS_PRESENT_SAVED:-}
    SAVED_L2TP_SERVER_IP_WAS_PRESENT=${L2TP_SERVER_IP_WAS_PRESENT_SAVED:-}
    SAVED_VPN_SERVER_IP_IPV6_WAS_PRESENT=${VPN_SERVER_IP_IPV6_WAS_PRESENT_SAVED:-}
    SAVED_VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT=${VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT_SAVED:-}
    SAVED_UPSTREAM_DNS1=${UPSTREAM_DNS1_SAVED:-}
    SAVED_UPSTREAM_DNS2=${UPSTREAM_DNS2_SAVED:-}
    SAVED_FIREWALL_PERSIST6_FILE_WAS_PRESENT=${FIREWALL_PERSIST6_FILE_WAS_PRESENT_SAVED:-}
    SAVED_FIREWALL_PERSIST6_FILE2_WAS_PRESENT=${FIREWALL_PERSIST6_FILE2_WAS_PRESENT_SAVED:-}
  fi
  if [ "$SAVED_HAS_IPV6" != 1 ] \
    && [ -f "$BONJOUR_STATE_DIR/ipv6-state" ]; then
    # Upgrade path from the original IPv6 branch. This root-owned state file
    # contains only network coordinates, never credentials.
    # shellcheck disable=SC1090,SC1091
    . "$BONJOUR_STATE_DIR/ipv6-state"
    SAVED_HAS_IPV6=${HAS_IPV6_SAVED:-0}
    SAVED_VPN_SUBNET_IPV6=${VPN_SUBNET_IPV6_SAVED:-}
    SAVED_VPN_SERVER_IP_IPV6=${VPN_SERVER_IP_IPV6_SAVED:-}
  fi
}

loopback_has_ipv4() {
  local address="$1"
  [ -n "$address" ] || return 1
  ip -4 -o addr show dev lo 2>/dev/null \
    | awk -v wanted="$address" '$3 == "inet" { split($4, value, "/"); if (value[1] == wanted) found=1 } END { exit !found }'
}

loopback_has_ipv6() {
  local address="$1"
  [ -n "$address" ] || return 1
  ipv6_address_exists "$address" lo
}

ipv6_subnet_route_exists() {
  local subnet="$1"
  [ -n "$subnet" ] || return 1
  [ -n "$(ip -6 route show exact "$subnet" 2>/dev/null)" ]
}

normalize_saved_address_ownership() {
  # Older state did not prove whether a live address or route pre-dated this
  # feature. Preserve runtime objects conservatively. Exact feature boot lines
  # remain separately identifiable and removable during disable.
  if [ -n "$SAVED_VPN_SERVER_IP" ] && [ -z "$SAVED_VPN_SERVER_IP_WAS_PRESENT" ]; then
    SAVED_VPN_SERVER_IP_WAS_PRESENT=1
  fi
  if [ -n "$SAVED_L2TP_SERVER_IP" ] && [ -z "$SAVED_L2TP_SERVER_IP_WAS_PRESENT" ]; then
    SAVED_L2TP_SERVER_IP_WAS_PRESENT=1
  fi
  if [ -n "$SAVED_VPN_SERVER_IP_IPV6" ] \
    && [ -z "$SAVED_VPN_SERVER_IP_IPV6_WAS_PRESENT" ]; then
    SAVED_VPN_SERVER_IP_IPV6_WAS_PRESENT=1
  fi
  if [ -n "$SAVED_VPN_SUBNET_IPV6" ] \
    && [ -z "$SAVED_VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT" ]; then
    SAVED_VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT=1
  fi
}

capture_address_ownership() {
  normalize_saved_address_ownership
  if [ -n "$VPN_SERVER_IP" ] && [ "$VPN_SERVER_IP" = "$SAVED_VPN_SERVER_IP" ]; then
    VPN_SERVER_IP_WAS_PRESENT=${SAVED_VPN_SERVER_IP_WAS_PRESENT:-1}
  elif loopback_has_ipv4 "$VPN_SERVER_IP"; then
    VPN_SERVER_IP_WAS_PRESENT=1
  else
    VPN_SERVER_IP_WAS_PRESENT=0
  fi
  if [ -n "$L2TP_SERVER_IP" ] && [ "$L2TP_SERVER_IP" = "$SAVED_L2TP_SERVER_IP" ]; then
    L2TP_SERVER_IP_WAS_PRESENT=${SAVED_L2TP_SERVER_IP_WAS_PRESENT:-1}
  elif loopback_has_ipv4 "$L2TP_SERVER_IP"; then
    L2TP_SERVER_IP_WAS_PRESENT=1
  else
    L2TP_SERVER_IP_WAS_PRESENT=0
  fi
  if [ -n "$VPN_SERVER_IP_IPV6" ] \
    && [ "$VPN_SERVER_IP_IPV6" = "$SAVED_VPN_SERVER_IP_IPV6" ]; then
    VPN_SERVER_IP_IPV6_WAS_PRESENT=${SAVED_VPN_SERVER_IP_IPV6_WAS_PRESENT:-1}
  elif loopback_has_ipv6 "$VPN_SERVER_IP_IPV6"; then
    VPN_SERVER_IP_IPV6_WAS_PRESENT=1
  else
    VPN_SERVER_IP_IPV6_WAS_PRESENT=0
  fi
  if [ -n "$VPN_SUBNET_IPV6" ] \
    && [ "$VPN_SUBNET_IPV6" = "$SAVED_VPN_SUBNET_IPV6" ] \
    && [ -n "$SAVED_VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT" ]; then
    VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT=$SAVED_VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT
  elif ipv6_subnet_route_exists "$VPN_SUBNET_IPV6"; then
    VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT=1
  else
    VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT=0
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
  LOCK_ACQUIRED=1
  trap cleanup_bonjour_operation EXIT
  trap 'cleanup_bonjour_operation; exit 1' HUP INT TERM
}

cleanup_bonjour_operation() {
  if [ -n "$FIREWALL_TX_DIR" ]; then
    rollback_firewall_transaction >/dev/null 2>&1 || true
  fi
  [ -n "$DNSMASQ_INSTALL_TEST_DIR" ] && /bin/rm -rf "$DNSMASQ_INSTALL_TEST_DIR"
  [ -n "$DNSMASQ_VPN_CANDIDATE" ] && /bin/rm -f "$DNSMASQ_VPN_CANDIDATE"
  [ -n "$RESOLVE_SCRIPT_CANDIDATE" ] && /bin/rm -f "$RESOLVE_SCRIPT_CANDIDATE"
  [ -n "$WATCHER_SCRIPT_CANDIDATE" ] && /bin/rm -f "$WATCHER_SCRIPT_CANDIDATE"
  [ -n "$IPV6_FIREWALL_LOADER_CANDIDATE" ] \
    && /bin/rm -f "$IPV6_FIREWALL_LOADER_CANDIDATE"
  /bin/rm -f "$BONJOUR_STATE_DIR/.config.candidate" \
    "$BONJOUR_STATE_DIR/.incomplete.candidate"
  release_bonjour_lock
}

release_bonjour_lock() {
  if [ "${LOCK_ACQUIRED:-0}" = 1 ]; then
    flock -u 9 2>/dev/null || true
  fi
  exec 9>&- 2>/dev/null || true
  LOCK_ACQUIRED=0
}

capture_service_state() {
  if [ -f "$BONJOUR_CONFIG_STATE" ]; then
    # Preserve a complete pre-feature state across reconfiguration. Older
    # state files did not record service ownership, so missing fields must not
    # be interpreted as "originally disabled" during an upgrade.
    # shellcheck disable=SC1090
    . "$BONJOUR_CONFIG_STATE"
    if [ "${SERVICE_STATE_VERSION_SAVED:-0}" = 2 ] \
      || [ "${SERVICE_STATE_VERSION_SAVED:-0}" = 3 ]; then
      DNSMASQ_WAS_INSTALLED=${DNSMASQ_WAS_INSTALLED_SAVED:-0}
      DNSMASQ_WAS_ENABLED=${DNSMASQ_WAS_ENABLED_SAVED:-0}
      DNSMASQ_WAS_ACTIVE=${DNSMASQ_WAS_ACTIVE_SAVED:-0}
      AVAHI_WAS_ENABLED=${AVAHI_WAS_ENABLED_SAVED:-0}
      AVAHI_WAS_ACTIVE=${AVAHI_WAS_ACTIVE_SAVED:-0}
      DBUS_WAS_ENABLED=${DBUS_WAS_ENABLED_SAVED:-0}
      DBUS_WAS_ACTIVE=${DBUS_WAS_ACTIVE_SAVED:-0}
      AVAHI_SOCKET_WAS_ENABLED=${AVAHI_SOCKET_WAS_ENABLED_SAVED:-0}
      AVAHI_SOCKET_WAS_ACTIVE=${AVAHI_SOCKET_WAS_ACTIVE_SAVED:-0}
      return
    fi
    echo "Note: legacy Bonjour state has no complete service-ownership record; preserving current service state."
  fi
  DNSMASQ_WAS_INSTALLED=0
  DNSMASQ_WAS_ENABLED=0
  DNSMASQ_WAS_ACTIVE=0
  AVAHI_WAS_ENABLED=0
  AVAHI_WAS_ACTIVE=0
  DBUS_WAS_ENABLED=0
  DBUS_WAS_ACTIVE=0
  AVAHI_SOCKET_WAS_ENABLED=0
  AVAHI_SOCKET_WAS_ACTIVE=0
  command -v dnsmasq >/dev/null 2>&1 && DNSMASQ_WAS_INSTALLED=1
  if [ "${os_type:-}" != alpine ] && command -v systemctl >/dev/null 2>&1; then
    systemctl is-enabled --quiet dnsmasq.service 2>/dev/null && DNSMASQ_WAS_ENABLED=1
    systemctl is-active --quiet dnsmasq.service 2>/dev/null && DNSMASQ_WAS_ACTIVE=1
    systemctl is-enabled --quiet avahi-daemon.service 2>/dev/null && AVAHI_WAS_ENABLED=1
    systemctl is-active --quiet avahi-daemon.service 2>/dev/null && AVAHI_WAS_ACTIVE=1
    systemctl is-enabled --quiet avahi-daemon.socket 2>/dev/null && AVAHI_SOCKET_WAS_ENABLED=1
    systemctl is-active --quiet avahi-daemon.socket 2>/dev/null && AVAHI_SOCKET_WAS_ACTIVE=1
    systemctl is-enabled --quiet dbus.service 2>/dev/null && DBUS_WAS_ENABLED=1
    systemctl is-active --quiet dbus.service 2>/dev/null && DBUS_WAS_ACTIVE=1
  elif command -v rc-service >/dev/null 2>&1; then
    rc-update show default 2>/dev/null \
      | awk '$1 == "dnsmasq" { found=1 } END { exit !found }' && DNSMASQ_WAS_ENABLED=1
    rc-service dnsmasq status >/dev/null 2>&1 && DNSMASQ_WAS_ACTIVE=1
    rc-update show default 2>/dev/null \
      | awk '$1 == "avahi-daemon" { found=1 } END { exit !found }' && AVAHI_WAS_ENABLED=1
    rc-service avahi-daemon status >/dev/null 2>&1 && AVAHI_WAS_ACTIVE=1
    rc-update show default 2>/dev/null | awk '$1 == "dbus" { found=1 } END { exit !found }' && DBUS_WAS_ENABLED=1
    rc-service dbus status >/dev/null 2>&1 && DBUS_WAS_ACTIVE=1
  fi
}

write_recovery_state_fields() {
  printf "VPN_SUBNET_SAVED='%s'\n" "${VPN_SUBNET:-}"
  printf "VPN_POOL_SAVED='%s'\n" "${VPN_POOL:-}"
  printf "VPN_SERVER_IP_SAVED='%s'\n" "${VPN_SERVER_IP:-}"
  printf "VPN_SERVER_IP_WAS_PRESENT_SAVED='%s'\n" "${VPN_SERVER_IP_WAS_PRESENT:-1}"
  printf "L2TP_SUBNET_SAVED='%s'\n" "${L2TP_SUBNET:-}"
  printf "L2TP_POOL_SAVED='%s'\n" "${L2TP_POOL_LINE:-}"
  printf "L2TP_SERVER_IP_SAVED='%s'\n" "${L2TP_SERVER_IP:-}"
  printf "L2TP_SERVER_IP_WAS_PRESENT_SAVED='%s'\n" "${L2TP_SERVER_IP_WAS_PRESENT:-1}"
  printf "HAS_IKEV2_SAVED='%s'\n" "${HAS_IKEV2:-0}"
  printf "HAS_XAUTH_SAVED='%s'\n" "${HAS_XAUTH:-0}"
  printf "HAS_L2TP_SAVED='%s'\n" "${HAS_L2TP:-0}"
  printf "HAS_IPV6_SAVED='%s'\n" "${HAS_IPV6:-0}"
  printf "VPN_POOL_IPV6_SAVED='%s'\n" "${VPN_POOL_IPV6:-}"
  printf "VPN_SUBNET_IPV6_SAVED='%s'\n" "${VPN_SUBNET_IPV6:-}"
  printf "VPN_SERVER_IP_IPV6_SAVED='%s'\n" "${VPN_SERVER_IP_IPV6:-}"
  printf "VPN_SERVER_IP_IPV6_WAS_PRESENT_SAVED='%s'\n" "${VPN_SERVER_IP_IPV6_WAS_PRESENT:-1}"
  printf "VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT_SAVED='%s'\n" "${VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT:-1}"
  printf "UPSTREAM_DNS1_SAVED='%s'\n" "${UPSTREAM_DNS1:-}"
  printf "UPSTREAM_DNS2_SAVED='%s'\n" "${UPSTREAM_DNS2:-}"
  printf "DNSMASQ_WAS_INSTALLED_SAVED='%s'\n" "$DNSMASQ_WAS_INSTALLED"
  printf "DNSMASQ_WAS_ENABLED_SAVED='%s'\n" "$DNSMASQ_WAS_ENABLED"
  printf "DNSMASQ_WAS_ACTIVE_SAVED='%s'\n" "$DNSMASQ_WAS_ACTIVE"
  printf "AVAHI_WAS_ENABLED_SAVED='%s'\n" "$AVAHI_WAS_ENABLED"
  printf "AVAHI_WAS_ACTIVE_SAVED='%s'\n" "$AVAHI_WAS_ACTIVE"
  printf "DBUS_WAS_ENABLED_SAVED='%s'\n" "$DBUS_WAS_ENABLED"
  printf "DBUS_WAS_ACTIVE_SAVED='%s'\n" "$DBUS_WAS_ACTIVE"
  printf "AVAHI_SOCKET_WAS_ENABLED_SAVED='%s'\n" "$AVAHI_SOCKET_WAS_ENABLED"
  printf "AVAHI_SOCKET_WAS_ACTIVE_SAVED='%s'\n" "$AVAHI_SOCKET_WAS_ACTIVE"
  printf "SERVICE_STATE_VERSION_SAVED='3'\n"
  printf "FIREWALL_PERSIST6_FILE_WAS_PRESENT_SAVED='%s'\n" \
    "${FIREWALL_PERSIST6_FILE_WAS_PRESENT:-1}"
  printf "FIREWALL_PERSIST6_FILE2_WAS_PRESENT_SAVED='%s'\n" \
    "${FIREWALL_PERSIST6_FILE2_WAS_PRESENT:-1}"
}

save_incomplete_state() {
  local candidate="${BONJOUR_STATE_DIR}/.incomplete.candidate" old_umask
  install -d -m 700 "$BONJOUR_STATE_DIR" \
    || exiterr "Could not create the Bonjour VPN state directory."
  old_umask=$(umask)
  umask 077
  {
    echo "# Incomplete enable operation; contains no credentials."
    write_recovery_state_fields
  } > "$candidate" \
    || { umask "$old_umask"; exiterr "Could not write the Bonjour VPN recovery state."; }
  chmod 600 "$candidate" \
    || { umask "$old_umask"; exiterr "Could not secure the Bonjour VPN recovery state."; }
  mv -f "$candidate" "$BONJOUR_INCOMPLETE_STATE" \
    || { umask "$old_umask"; exiterr "Could not install the Bonjour VPN recovery state."; }
  umask "$old_umask"
}

save_config_state() {
  local candidate="${BONJOUR_STATE_DIR}/.config.candidate" managed_path managed_file managed_key managed_hash old_umask
  install -d -m 700 "$BONJOUR_STATE_DIR"
  old_umask=$(umask)
  umask 077
  {
    echo "# Generated by enable_bonjour.sh; contains no credentials."
    write_recovery_state_fields
    for managed_path in /etc/avahi/avahi-daemon.conf /etc/ipsec.d/ikev2.conf \
      /etc/ipsec.conf /etc/ppp/options.xl2tpd /etc/nsswitch.conf \
      /etc/dnsmasq.conf /etc/rc.local /etc/network/if-pre-up.d/iptablesload; do
      managed_file="${BONJOUR_VPN_ROOT}${managed_path}"
      [ -f "$managed_file.bak.bonjour-vpn" ] || continue
      managed_key=$(printf '%s' "$managed_path" | tr '/.-' '___' | tr '[:lower:]' '[:upper:]')
      managed_hash=$(sha256sum "$managed_file" | awk '{print $1}')
      printf "%s_MANAGED_HASH='%s'\n" "$managed_key" "$managed_hash"
    done
  } > "$candidate" \
    || { umask "$old_umask"; exiterr "Could not write the Bonjour VPN state candidate."; }
  chmod 600 "$candidate" \
    || { umask "$old_umask"; exiterr "Could not secure the Bonjour VPN state candidate."; }
  mv -f "$candidate" "$BONJOUR_CONFIG_STATE" \
    || { umask "$old_umask"; exiterr "Could not install the Bonjour VPN state file."; }
  /bin/rm -f "$BONJOUR_INCOMPLETE_STATE" \
    || { umask "$old_umask"; exiterr "Could not retire the Bonjour VPN recovery state."; }
  umask "$old_umask"
}

remove_legacy_ipv6_runtime() {
  # The consolidated config is now authoritative. Retire files from the
  # original IPv6 branch only after the replacement state was installed, so
  # a failed preflight or firewall transaction leaves the old installation
  # available for recovery.
  /bin/rm -f "$BONJOUR_STATE_DIR/ipv6-state" \
    "$BONJOUR_STATE_DIR/ipv6-enabled"
  /bin/rm -f "${BONJOUR_VPN_LEGACY_SYNC_PATH:-/usr/local/sbin/bonjour-vpn-ipv6-sync}"
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
    if ! grep -Eq "release (7|8|9|10)([.[:space:]]|$)" "$rh_file"; then
      exiterr "This script only supports CentOS/RHEL 7-10."
    fi
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

check_vpn_modes() {
  IKEV2_CONF="${BONJOUR_VPN_ROOT}/etc/ipsec.d/ikev2.conf"
  IPSEC_CONF="${BONJOUR_VPN_ROOT}/etc/ipsec.conf"
  XL2TPD_CONF="${BONJOUR_VPN_ROOT}/etc/xl2tpd/xl2tpd.conf"
  PPP_OPTIONS="${BONJOUR_VPN_ROOT}/etc/ppp/options.xl2tpd"
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
  if [ -f "$BONJOUR_INCOMPLETE_STATE" ]; then
    exiterr "A previous Bonjour VPN enable did not complete. Run disable_bonjour.sh to recover before trying again."
  fi
  if [ -f /etc/dnsmasq.d/bonjour-vpn.conf ]; then
    echo "Bonjour/mDNS for VPN is already configured on this server."
    printf '%s' "Do you want to reconfigure? [y/N] "
    read -r response
    case $response in
      [yY][eE][sS]|[yY])
        RECONFIGURE_CONFIRMED=1
        echo
        ;;
      *)
        echo "Abort. No changes were made." >&2
        exit 1
        ;;
    esac
  fi
}

configuration_fingerprint() {
  local fingerprint_file
  for fingerprint_file in "$IKEV2_CONF" "$IPSEC_CONF" "$XL2TPD_CONF" \
    "$PPP_OPTIONS" "${BONJOUR_VPN_ROOT}/etc/avahi/avahi-daemon.conf" \
    "${BONJOUR_VPN_ROOT}/etc/dnsmasq.conf" \
    "${BONJOUR_VPN_ROOT}/etc/rc.local" \
    "${BONJOUR_VPN_ROOT}/etc/network/if-pre-up.d/iptablesload"; do
    if [ -f "$fingerprint_file" ]; then
      sha256sum "$fingerprint_file"
    else
      printf 'absent  %s\n' "$fingerprint_file"
    fi
  done | sha256sum | awk '{print $1}'
}

revalidate_after_lock() {
  local current_fingerprint
  [ ! -f "$BONJOUR_INCOMPLETE_STATE" ] \
    || exiterr "Another Bonjour VPN operation left an incomplete recovery marker. Run disable_bonjour.sh before trying again."
  if [ -f "${BONJOUR_VPN_ROOT}/etc/dnsmasq.d/bonjour-vpn.conf" ] \
    && [ "$RECONFIGURE_CONFIRMED" != 1 ]; then
    exiterr "Bonjour VPN was configured by another operation while this run was waiting. Re-run the script to review it explicitly."
  fi
  current_fingerprint=$(configuration_fingerprint) \
    || exiterr "Could not revalidate the preflight configuration."
  [ "$current_fingerprint" = "$PREFLIGHT_CONFIG_FINGERPRINT" ] \
    || exiterr "VPN or network configuration changed while waiting for the Bonjour VPN lock. Re-run the script to review the new state."
  load_saved_config
  check_reconfigure_drift
  check_existing_dns
  capture_firewall_persistence_ownership
}

rebase_ikev2_pool_backup() {
  # A VPN administrator must be able to change the IKEv2 address pool and
  # explicitly re-run this script. Prove that the pool is the only
  # administrator-owned difference, then carry that line into the original
  # backup so a later disable preserves the new VPN configuration.
  local current="$1" backup="${1}.bak.bonjour-vpn"
  local current_normalized backup_normalized candidate pool_line
  [ -f "$current" ] && [ -f "$backup" ] || return 1
  current_normalized=$(mktemp) || return 1
  backup_normalized=$(mktemp) || { /bin/rm -f "$current_normalized"; return 1; }
  sed -E \
    -e '/^[[:space:]]*modecfgdns=/d' \
    -e '/^[[:space:]]*modecfgdomains=/d' \
    -e 's|^([[:space:]]*rightaddresspool=).*|\1<vpn-pool>|' \
    "$current" > "$current_normalized" \
    && sed -E \
      -e '/^[[:space:]]*modecfgdns=/d' \
      -e '/^[[:space:]]*modecfgdomains=/d' \
      -e 's|^([[:space:]]*rightaddresspool=).*|\1<vpn-pool>|' \
      "$backup" > "$backup_normalized" \
    || { /bin/rm -f "$current_normalized" "$backup_normalized"; return 1; }
  if ! cmp -s "$current_normalized" "$backup_normalized"; then
    /bin/rm -f "$current_normalized" "$backup_normalized"
    return 1
  fi
  /bin/rm -f "$current_normalized" "$backup_normalized"
  pool_line=$(grep -m 1 '^[[:space:]]*rightaddresspool=' "$current")
  [ -n "$pool_line" ] || return 1
  candidate=$(mktemp) || return 1
  awk -v replacement="$pool_line" '
    !done && /^[[:space:]]*rightaddresspool=/ { print replacement; done=1; next }
    { print }
    END { if (!done) exit 1 }
  ' "$backup" > "$candidate" \
    || { /bin/rm -f "$candidate"; return 1; }
  chmod --reference="$backup" "$candidate" 2>/dev/null || true
  chown --reference="$backup" "$candidate" 2>/dev/null || true
  /bin/cp "$candidate" "$backup" \
    || { /bin/rm -f "$candidate"; return 1; }
  /bin/rm -f "$candidate"
  echo "Note: accepted an explicit IKEv2 address-pool change and updated the uninstall baseline."
  return 0
}

check_reconfigure_drift() {
  local managed_path file key expected actual root_dir="${BONJOUR_VPN_ROOT:-}"
  [ -f "$BONJOUR_CONFIG_STATE" ] || return 0
  for managed_path in /etc/avahi/avahi-daemon.conf /etc/ipsec.d/ikev2.conf \
    /etc/ipsec.conf /etc/ppp/options.xl2tpd /etc/nsswitch.conf \
    /etc/dnsmasq.conf /etc/rc.local /etc/network/if-pre-up.d/iptablesload; do
    file="${root_dir}${managed_path}"
    [ -f "$file.bak.bonjour-vpn" ] || continue
    key=$(printf '%s' "$managed_path" | tr '/.-' '___' | tr '[:lower:]' '[:upper:]')
    expected=$(sed -n "s/^${key}_MANAGED_HASH='\([^']*\)'$/\1/p" \
      "$BONJOUR_CONFIG_STATE" | head -n 1)
    [ -n "$expected" ] || continue
    actual=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
    if [ "$actual" != "$expected" ]; then
      if [ "$managed_path" = /etc/ipsec.d/ikev2.conf ] \
        && rebase_ikev2_pool_backup "$file"; then
        continue
      fi
      exiterr "Refusing to reconfigure because $file changed after Bonjour VPN was enabled. Disable Bonjour VPN before editing managed files, or reconcile the changes manually."
    fi
  done
}

check_existing_dns() {
  local socket_output listeners address
  # Existing instances used by libvirt, LXD or NetworkManager are compatible
  # when they bind only their own addresses. Reject only listeners that would
  # conflict with the VPN DNS endpoints selected by this script.
  [ ! -f /etc/dnsmasq.d/bonjour-vpn.conf ] || return
  if command -v ss >/dev/null 2>&1 \
    && socket_output=$(ss -lntu 2>/dev/null); then
    listeners=$(printf '%s\n' "$socket_output" | awk 'NR > 1 && $5 ~ /:53$/ { print $5 }')
  elif command -v netstat >/dev/null 2>&1 \
    && socket_output=$(netstat -lntu 2>/dev/null); then
    listeners=$(printf '%s\n' "$socket_output" | awk '$4 ~ /:53$/ { print $4 }')
  else
    exiterr "Could not inspect existing DNS listeners with ss or netstat."
  fi
  if printf '%s\n' "$listeners" \
    | grep -Eq '^(0\.0\.0\.0|\*):53$|^\[(::|\*)\]:53$|^:::53$'; then
    exiterr "A wildcard DNS listener is already using port 53. Configure it to use specific addresses before enabling Bonjour VPN."
  fi
  for address in "${VPN_SERVER_IP:-}" "${L2TP_SERVER_IP:-}"; do
    [ -n "$address" ] || continue
    if printf '%s\n' "$listeners" | grep -Fqx "${address}:53"; then
      exiterr "A DNS listener is already using the selected VPN DNS endpoint $address."
    fi
  done
  if [ -n "${VPN_SERVER_IP_IPV6:-}" ] \
    ; then
    local listener_endpoint listener_address wanted_ipv6 listener_ipv6
    wanted_ipv6=$(canonical_ipv6 "$VPN_SERVER_IP_IPV6") \
      || exiterr "The selected IPv6 VPN DNS endpoint is invalid."
    while IFS= read -r listener_endpoint; do
      listener_address=${listener_endpoint%:53}
      listener_address=${listener_address#\[}
      listener_address=${listener_address%\]}
      case "$listener_address" in
        *:*)
          listener_ipv6=$(canonical_ipv6 "$listener_address" 2>/dev/null || true)
          [ -n "$listener_ipv6" ] && [ "$listener_ipv6" = "$wanted_ipv6" ] \
            && exiterr "A DNS listener is already using the selected IPv6 VPN DNS endpoint $VPN_SERVER_IP_IPV6."
          ;;
      esac
    done <<EOF
$listeners
EOF
  fi
  check_systemd_resolved
  if [ "$RESOLVED_ACTIVE" = 0 ] \
    && printf '%s\n' "$listeners" | grep -Fqx '127.0.0.1:53'; then
    exiterr "A DNS listener is already using 127.0.0.1:53, which dnsmasq needs when systemd-resolved is inactive."
  fi
  if pgrep -x dnsmasq >/dev/null 2>&1; then
    echo "Note: one or more dnsmasq instances are already running."
    echo "      Their bound addresses do not conflict with the selected VPN DNS endpoints."
  fi
}

detect_iface() {
  def_iface=$(route 2>/dev/null | grep -m 1 '^default' | grep -o '[^ ]*$')
  if [ "$os_type" != "alpine" ]; then
    [ -z "$def_iface" ] && def_iface=$(ip -4 route list 0/0 2>/dev/null \
      | sed -n 's/.*[[:space:]]dev[[:space:]]\([^[:space:]]*\).*/\1/p' | head -n 1)
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
    | sed -n 's/^[[:space:]]*inet[[:space:]]\([0-9][0-9.]*\)\/.*/\1/p' | head -n 1)
  if [ -z "$SERVER_LAN_IP" ] || ! check_ip "$SERVER_LAN_IP"; then
    exiterr "Could not detect server's LAN IP on interface '$NET_IFACE'."
  fi
}

detect_lan_subnet() {
  LAN_CIDR=$(ip -4 addr show dev "$NET_IFACE" 2>/dev/null \
    | sed -n 's/^[[:space:]]*inet[[:space:]]\([0-9][0-9.]*\/[0-9][0-9]*\).*/\1/p' | head -n 1)
  if [ -z "$LAN_CIDR" ]; then
    LAN_CIDR="${SERVER_LAN_IP}/24"
  fi
}

detect_vpn_subnet() {
  # Detect IKEv2/XAuth subnet
  # Try ikev2.conf first, then fall back to ipsec.conf xauth-psk section
  VPN_POOL=""
  VPN_SUBNET=""
  VPN_SERVER_IP=""
  XAUTH_SERVER_IP=""
  if [ "$HAS_IKEV2" = 0 ] && [ "$HAS_XAUTH" = 0 ]; then
    return
  fi
  if [ "$HAS_IKEV2" = 1 ]; then
    VPN_POOL=$(extract_ipv4_pool "$(grep 'rightaddresspool=' "$IKEV2_CONF" | head -n 1)")
  fi
  if [ -z "$VPN_POOL" ] && [ "$HAS_XAUTH" = 1 ]; then
    VPN_POOL=$(extract_ipv4_pool "$(sed -n '/conn xauth-psk/,/^conn /{ /rightaddresspool=/p; }' \
      "$IPSEC_CONF" | head -n 1)")
  fi
  [ -n "$VPN_POOL" ] || exiterr "Could not determine the IKEv2/XAuth IPv4 pool."
  VPN_SUBNET=$(subnet_for_pool "$VPN_POOL" "192.168.43.0/24") \
    || exiterr "Could not unambiguously determine the configured IKEv2/XAuth subnet."
  load_saved_config
  PREVIOUS_DNS_IP=""
  [ "$SAVED_VPN_SUBNET" = "$VPN_SUBNET" ] && PREVIOUS_DNS_IP="$SAVED_VPN_SERVER_IP"
  if [ -z "$PREVIOUS_DNS_IP" ]; then
    PREVIOUS_DNS_IP=$(discover_legacy_vpn_dns_ip "$VPN_SUBNET" "$VPN_POOL" || true)
  fi
  VPN_SERVER_IP=$(select_vpn_dns_ip "$VPN_SUBNET" "$VPN_POOL" "$PREVIOUS_DNS_IP") \
    || exiterr "Could not select an unused DNS endpoint inside $VPN_SUBNET and outside the client pool."
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
  L2TP_SERVER_IP=$(sed -n 's/^[[:space:]]*local ip[[:space:]]*=[[:space:]]*\([0-9][0-9.]*\).*/\1/p' \
    "$XL2TPD_CONF" | head -n 1)
  if [ -z "$L2TP_SERVER_IP" ] || ! check_ip "$L2TP_SERVER_IP"; then
    L2TP_SERVER_IP="192.168.42.1"
  fi
  # Parse ip range to derive subnet
  L2TP_POOL_LINE=$(sed -n 's/^[[:space:]]*ip range[[:space:]]*=[[:space:]]*\([0-9][0-9.]*-[0-9][0-9.]*\).*/\1/p' \
    "$XL2TPD_CONF" | head -n 1)
  if [ -n "$L2TP_POOL_LINE" ]; then
    L2TP_SUBNET=$(subnet_for_pool "$L2TP_POOL_LINE" "192.168.42.0/24") \
      || exiterr "Could not unambiguously determine the configured L2TP subnet."
  else
    exiterr "Could not determine the configured L2TP client pool."
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
  #   VPN_SERVER_IP_IPV6     - an unused server address outside the client pool
  #
  # Sets HAS_IPV6=1 if a valid IPv6 pool is found, otherwise HAS_IPV6=0.
  HAS_IPV6=0
  VPN_POOL_IPV6=""
  VPN_POOL_IPV6_START=""
  VPN_SUBNET_IPV6=""
  VPN_SERVER_IP_IPV6=""
  load_saved_config

  if [ "$HAS_IKEV2" = 1 ] && [ -f "$IKEV2_CONF" ]; then
    # Select the IPv6 range regardless of its position in the comma-separated
    # pool list.
    VPN_POOL_IPV6=$(grep 'rightaddresspool=' "$IKEV2_CONF" | head -n 1 \
      | sed 's/.*rightaddresspool=//; s/["'"'"']//g' | tr ',' '\n' \
      | sed -n '/:/ { s/^[[:space:]]*//; s/[[:space:]]*$//; p; }' | head -n 1)
  fi

  if [ -n "$VPN_POOL_IPV6" ]; then
    VPN_POOL_IPV6_START=$(printf '%s' "$VPN_POOL_IPV6" | cut -d '-' -f 1)
    VPN_POOL_IPV6_END=$(printf '%s' "$VPN_POOL_IPV6" | cut -d '-' -f 2)
    if check_ip6 "$VPN_POOL_IPV6_START" && check_ip6 "$VPN_POOL_IPV6_END"; then
      VPN_SUBNET_IPV6=$(sed -n 's/^[[:space:]]*virtual-private=.*%v6:!\([^,[:space:]]*\/64\).*/\1/p' \
        "$IPSEC_CONF" 2>/dev/null | head -n 1)
      # Derive the /64 subnet from the pool start address. For compressed
      # form (fddd:500:500:500::1000) take everything before "::"; for
      # expanded form (fddd:500:500:500:0:0:0:1000) take the first 4
      # colon-separated groups. Both yield fddd:500:500:500::/64.
      if [ -z "$VPN_SUBNET_IPV6" ]; then
        if printf '%s' "$VPN_POOL_IPV6_START" | grep -q '::'; then
          VPN_SUBNET_IPV6="$(printf '%s' "$VPN_POOL_IPV6_START" | sed 's/::.*//')::/64"
        else
          VPN_SUBNET_IPV6="$(printf '%s' "$VPN_POOL_IPV6_START" | cut -d: -f1-4)::/64"
        fi
      fi
      subnet_base=${VPN_SUBNET_IPV6%/64}
      if ! check_ip6 "$subnet_base"; then
        exiterr "The detected IPv6 VPN subnet is not a valid /64."
      fi
      if ! printf '%s' "$subnet_base" | grep -q '::$'; then
        exiterr "The configured IPv6 VPN /64 must use the canonical ::/64 form."
      fi
      PREVIOUS_DNS_IP_IPV6=""
      [ "$SAVED_VPN_SUBNET_IPV6" = "$VPN_SUBNET_IPV6" ] \
        && PREVIOUS_DNS_IP_IPV6="$SAVED_VPN_SERVER_IP_IPV6"
      VPN_SERVER_IP_IPV6=$(select_vpn_dns_ipv6 "$VPN_SUBNET_IPV6" \
        "$VPN_POOL_IPV6" "$PREVIOUS_DNS_IP_IPV6") \
        || exiterr "Could not select an unused IPv6 DNS endpoint inside $VPN_SUBNET_IPV6 and outside the client pool."
      HAS_IPV6=1
    fi
  fi
}

is_managed_dns_endpoint() {
  local candidate="${1:-}" endpoint
  [ -n "$candidate" ] || return 1
  for endpoint in "${VPN_SERVER_IP:-}" "${L2TP_SERVER_IP:-}" \
    "${SAVED_VPN_SERVER_IP:-}" "${SAVED_L2TP_SERVER_IP:-}"; do
    [ -n "$endpoint" ] && [ "$candidate" = "$endpoint" ] && return 0
  done
  return 1
}

filter_upstream_dns_list() {
  local dns_entry filtered="" raw="${1:-}"
  for dns_entry in $raw; do
    if ! is_managed_dns_endpoint "$dns_entry" && check_ip "$dns_entry"; then
      filtered="${filtered}${filtered:+ }${dns_entry}"
    fi
  done
  printf '%s\n' "$filtered"
}

select_upstream_dns_pair() {
  local detected1="${1:-}" detected2="${2:-}"
  # A managed IKEv2 line retains only our endpoint plus the primary upstream.
  # If that exact primary still matches our root-owned state and no secondary
  # is present, recover the original pair. A complete changed pair is treated
  # as an administrator override and used as-is.
  if [ -n "$detected1" ] && [ -z "$detected2" ] \
    && [ "$detected1" = "${SAVED_UPSTREAM_DNS1:-}" ] \
    && check_ip "${SAVED_UPSTREAM_DNS1:-}" \
    && check_ip "${SAVED_UPSTREAM_DNS2:-}"; then
    UPSTREAM_DNS1=$SAVED_UPSTREAM_DNS1
    UPSTREAM_DNS2=$SAVED_UPSTREAM_DNS2
    return
  fi
  UPSTREAM_DNS1=${detected1:-8.8.8.8}
  UPSTREAM_DNS2=${detected2:-8.8.4.4}
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
      DNS_RAW_CLEANED=$(filter_upstream_dns_list "$MS_DNS1 $MS_DNS2")
      DETECTED_DNS1=$(printf '%s' "$DNS_RAW_CLEANED" | awk '{print $1}')
      DETECTED_DNS2=$(printf '%s' "$DNS_RAW_CLEANED" | awk '{print $2}')
      select_upstream_dns_pair "$DETECTED_DNS1" "$DETECTED_DNS2"
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
  DNS_RAW_CLEANED=$(filter_upstream_dns_list "$DNS_RAW")
  DETECTED_DNS1=$(printf '%s' "$DNS_RAW_CLEANED" | awk '{print $1}')
  DETECTED_DNS2=$(printf '%s' "$DNS_RAW_CLEANED" | awk '{print $2}')
  select_upstream_dns_pair "$DETECTED_DNS1" "$DETECTED_DNS2"
}

required_packages_installed() {
  local package
  case "$os_type" in
    ubuntu|debian)
      command -v dpkg-query >/dev/null 2>&1 || return 1
      for package in avahi-daemon avahi-utils dnsmasq; do
        [ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null)" = 'install ok installed' ] \
          || return 1
      done
      ;;
    alpine)
      command -v apk >/dev/null 2>&1 || return 1
      for package in avahi avahi-tools dnsmasq; do
        apk info -e "$package" >/dev/null 2>&1 || return 1
      done
      ;;
    *)
      command -v rpm >/dev/null 2>&1 || return 1
      for package in avahi avahi-tools dnsmasq; do
        rpm -q --quiet "$package" >/dev/null 2>&1 || return 1
      done
      ;;
  esac
}

install_packages() {
  if required_packages_installed; then
    bigecho "Required packages are already installed; skipping package operations."
    return 0
  fi
  bigecho "Installing required packages..."
  if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get -yqq update 9>&- || apt-get -yqq update 9>&- || exiterr "'apt-get update' failed."
    apt-get -yqq install avahi-daemon avahi-utils dnsmasq 9>&- >/dev/null \
      || exiterr "'apt-get install' failed."
  elif [ "$os_type" = "alpine" ]; then
    apk update 9>&- || exiterr "'apk update' failed."
    apk add avahi avahi-tools dnsmasq 9>&- || exiterr "'apk add' failed."
  else
    # CentOS/RHEL/Rocky/Alma/Oracle Linux
    if command -v dnf >/dev/null 2>&1; then
      dnf -y -q install avahi avahi-tools dnsmasq 9>&- >/dev/null \
        || exiterr "'dnf install' failed."
    else
      yum -y -q install avahi avahi-tools dnsmasq 9>&- >/dev/null \
        || exiterr "'yum install' failed."
    fi
  fi
}

verify_runtime_providers() {
  command -v avahi-browse >/dev/null 2>&1 \
    || exiterr "The installed Avahi tools do not provide avahi-browse."
  command -v dnsmasq >/dev/null 2>&1 \
    || exiterr "The installed dnsmasq package does not provide dnsmasq."
  if [ "$HAS_IPV6" = 1 ] || [ "$SAVED_HAS_IPV6" = 1 ]; then
    for command_name in ip6tables ip6tables-save ip6tables-restore; do
      command -v "$command_name" >/dev/null 2>&1 \
        || exiterr "IPv6 Bonjour requires $command_name, but it is unavailable."
    done
    ip6tables -t nat -L PREROUTING -n >/dev/null 2>&1 \
      || exiterr "IPv6 Bonjour requires a usable ip6tables nat table."
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl cat avahi-daemon.service >/dev/null 2>&1 \
      || exiterr "The Avahi systemd service is unavailable."
    systemctl cat dnsmasq.service >/dev/null 2>&1 \
      || exiterr "The dnsmasq systemd service is unavailable."
  else
    [ -x /etc/init.d/avahi-daemon ] \
      || exiterr "The Avahi OpenRC service is unavailable."
    [ -x /etc/init.d/dnsmasq ] \
      || exiterr "The dnsmasq OpenRC service is unavailable."
  fi
}

configure_avahi() {
  bigecho "Configuring avahi-daemon..."
  AVAHI_CONF="/etc/avahi/avahi-daemon.conf"
  mkdir -p /etc/avahi
  conf_bk_bonjour "$AVAHI_CONF"
  # Restrict discovery and reflection to the detected LAN-facing interface.
cat > "$AVAHI_CONF" <<EOF
[server]
use-ipv4=yes
use-ipv6=yes
enable-dbus=yes
disallow-other-stacks=no
allow-interfaces=${NET_IFACE}

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

configure_dnsmasq_resolver_hook() {
  local root_dir="${BONJOUR_VPN_ROOT:-}" resolvconf_target start_hooks stop_hooks
  DNSMASQ_RESOLVCONF_DROPIN="${root_dir}/etc/systemd/system/dnsmasq.service.d/bonjour-vpn.conf"
  command -v systemctl >/dev/null 2>&1 || return 0
  check_systemd_resolved
  resolvconf_target=${BONJOUR_VPN_RESOLVCONF_TARGET:-$(readlink -f /sbin/resolvconf 2>/dev/null || true)}
  if [ "$RESOLVED_ACTIVE" = 1 ] \
    && [ "${resolvconf_target##*/}" = resolvectl ]; then
    # Ubuntu's dnsmasq unit calls its resolvconf helper on every start/stop.
    # When /sbin/resolvconf is systemd-resolved's resolvectl compatibility
    # link, that helper tries to configure the loopback device as a DNS link
    # and logs a failure. This feature already uses no-resolv plus explicit
    # upstream servers, so the package hook is both redundant and incorrect.
    # systemd can only reset an entire command list, not remove one command
    # from it. Refuse to install the reset if the effective unit contains any
    # additional administrator or distribution hooks. An existing exact
    # drop-in from this script is safe to retain on reconfiguration.
    if [ -f "$DNSMASQ_RESOLVCONF_DROPIN" ] \
      && [ "$(sed '/^[[:space:]]*$/d' "$DNSMASQ_RESOLVCONF_DROPIN")" = "[Service]
ExecStartPost=
ExecStop=" ]; then
      :
    else
      start_hooks=$(systemctl show dnsmasq.service -p ExecStartPost --value 2>/dev/null || true)
      stop_hooks=$(systemctl show dnsmasq.service -p ExecStop --value 2>/dev/null || true)
      case "$start_hooks" in
        *"argv[]=/usr/share/dnsmasq/systemd-helper start-resolvconf ;"*|\
        *"argv[]=/usr/share/dnsmasq-base/systemd-helper start-resolvconf ;"*) ;;
        *)
          echo "Warning: dnsmasq has non-standard ExecStartPost hooks; leaving them unchanged." >&2
          return 0
          ;;
      esac
      case "$stop_hooks" in
        *"argv[]=/usr/share/dnsmasq/systemd-helper stop-resolvconf ;"*|\
        *"argv[]=/usr/share/dnsmasq-base/systemd-helper stop-resolvconf ;"*) ;;
        *)
          echo "Warning: dnsmasq has non-standard ExecStop hooks; leaving them unchanged." >&2
          return 0
          ;;
      esac
      [ "$(printf '%s\n' "$start_hooks" | awk '{ print gsub(/argv\[\]=/, "&") }')" = 1 ] \
        && [ "$(printf '%s\n' "$stop_hooks" | awk '{ print gsub(/argv\[\]=/, "&") }')" = 1 ] \
        || { echo "Warning: dnsmasq has additional lifecycle hooks; leaving them unchanged." >&2; return 0; }
    fi
    install -d -m 755 "${root_dir}/etc/systemd/system/dnsmasq.service.d"
cat > "$DNSMASQ_RESOLVCONF_DROPIN" <<'EOF'
[Service]
ExecStartPost=
ExecStop=
EOF
    chmod 644 "$DNSMASQ_RESOLVCONF_DROPIN"
  else
    rm -f "$DNSMASQ_RESOLVCONF_DROPIN"
  fi
  systemctl daemon-reload
}

configure_dnsmasq() {
  bigecho "Configuring dnsmasq..."
  DNSMASQ_CONF="/etc/dnsmasq.conf"
  DNSMASQ_D="/etc/dnsmasq.d"
  DNSMASQ_VPN_CONF="${DNSMASQ_D}/bonjour-vpn.conf"
  DNSMASQ_VPN_CANDIDATE="${DNSMASQ_D}/.bonjour-vpn.conf.candidate"
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
  if [ -f "$DNSMASQ_VPN_CONF" ]; then
    # Keep the managed loopback-listener choice stable across reconfiguration.
    # Starting D-Bus/Avahi/dnsmasq can change systemd-resolved's active state
    # after the first candidate was built, but both services can coexist when
    # bound to their distinct loopback addresses.
    if grep -Eq '^listen-address=([^,]*,)*127\.0\.0\.1(,|$)' \
      "$DNSMASQ_VPN_CONF"; then
      LISTEN_IPS="127.0.0.1"
    fi
  elif [ "$RESOLVED_ACTIVE" = 0 ]; then
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
cat > "$DNSMASQ_VPN_CANDIDATE" <<EOF
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

install_dnsmasq_config() {
  local test_dir test_conf conf base
  install -d -m 700 "$BONJOUR_STATE_DIR"
  test_dir=$(mktemp -d "$BONJOUR_STATE_DIR/.dnsmasq-install-test.XXXXXX") \
    || exiterr "Could not create a dnsmasq validation directory."
  DNSMASQ_INSTALL_TEST_DIR="$test_dir"
  test_conf="$test_dir/dnsmasq.conf"
  for conf in "$DNSMASQ_D"/*.conf; do
    [ -f "$conf" ] || continue
    base=${conf##*/}
    [ "$base" = "bonjour-vpn.conf" ] && continue
    /bin/cp -p "$conf" "$test_dir/$base" \
      || exiterr "Could not stage the effective dnsmasq configuration."
  done
  /bin/cp -p "$DNSMASQ_VPN_CANDIDATE" "$test_dir/bonjour-vpn.conf" \
    || exiterr "Could not stage the Bonjour dnsmasq configuration."
  sed "s#$DNSMASQ_D#$test_dir#g" "$DNSMASQ_CONF" > "$test_conf" \
    || exiterr "Could not stage the dnsmasq main configuration."
  if ! dnsmasq --test --conf-file="$test_conf" >/dev/null 2>&1; then
    /bin/rm -rf "$test_dir"
    /bin/rm -f "$DNSMASQ_VPN_CANDIDATE"
    exiterr "The effective dnsmasq configuration failed validation; the live Bonjour config was not replaced."
  fi
  /bin/rm -rf "$test_dir"
  DNSMASQ_INSTALL_TEST_DIR=""
  mv -f "$DNSMASQ_VPN_CANDIDATE" "$DNSMASQ_VPN_CONF"
  chmod 644 "$DNSMASQ_VPN_CONF"
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

remove_managed_boot_address() {
  local family="$1" address="$2" file root_dir="${BONJOUR_VPN_ROOT:-}"
  [ -n "$address" ] || return 0
  for file in "$root_dir/etc/rc.local" "$root_dir/etc/local.d/bonjour-vpn.start"; do
    [ -f "$file" ] || continue
    if [ "$family" = 6 ]; then
      sed --follow-symlinks -i \
        "\|ip -6 addr add ${address}/128 dev lo|d" "$file" 2>/dev/null \
        || sed -i "\|ip -6 addr add ${address}/128 dev lo|d" "$file" \
        || exiterr "Could not remove the obsolete IPv6 loopback boot entry."
    else
      sed --follow-symlinks -i \
        "\|ip addr add ${address}/32 dev lo|d" "$file" 2>/dev/null \
        || sed -i "\|ip addr add ${address}/32 dev lo|d" "$file" \
        || exiterr "Could not remove the obsolete IPv4 loopback boot entry."
    fi
  done
}

remove_managed_boot_ipv6_route() {
  local subnet="$1" file root_dir="${BONJOUR_VPN_ROOT:-}"
  [ -n "$subnet" ] || return 0
  for file in "$root_dir/etc/rc.local" "$root_dir/etc/local.d/bonjour-vpn.start"; do
    [ -f "$file" ] || continue
    sed --follow-symlinks -i \
      "\|ip -6 route add ${subnet} dev lo|d" "$file" 2>/dev/null \
      || sed -i "\|ip -6 route add ${subnet} dev lo|d" "$file" \
      || exiterr "Could not remove the obsolete IPv6 VPN route boot entry."
  done
}

remove_stale_owned_loopback_addresses() {
  if [ -n "$SAVED_VPN_SERVER_IP" ] && [ "$SAVED_VPN_SERVER_IP" != "$VPN_SERVER_IP" ] \
    && [ "${SAVED_VPN_SERVER_IP_WAS_PRESENT:-1}" = 0 ]; then
    if loopback_has_ipv4 "$SAVED_VPN_SERVER_IP"; then
      ip -4 addr del "${SAVED_VPN_SERVER_IP}/32" dev lo \
        || exiterr "Could not remove the obsolete VPN DNS endpoint."
    fi
    remove_managed_boot_address 4 "$SAVED_VPN_SERVER_IP"
  fi
  if [ -n "$SAVED_L2TP_SERVER_IP" ] && [ "$SAVED_L2TP_SERVER_IP" != "$L2TP_SERVER_IP" ] \
    && [ "${SAVED_L2TP_SERVER_IP_WAS_PRESENT:-1}" = 0 ]; then
    if loopback_has_ipv4 "$SAVED_L2TP_SERVER_IP"; then
      ip -4 addr del "${SAVED_L2TP_SERVER_IP}/32" dev lo \
        || exiterr "Could not remove the obsolete L2TP DNS endpoint."
    fi
    remove_managed_boot_address 4 "$SAVED_L2TP_SERVER_IP"
  fi
  if [ -n "$SAVED_VPN_SERVER_IP_IPV6" ] \
    && [ "$SAVED_VPN_SERVER_IP_IPV6" != "$VPN_SERVER_IP_IPV6" ] \
    && [ "${SAVED_VPN_SERVER_IP_IPV6_WAS_PRESENT:-1}" = 0 ]; then
    if loopback_has_ipv6 "$SAVED_VPN_SERVER_IP_IPV6"; then
      ip -6 addr del "${SAVED_VPN_SERVER_IP_IPV6}/128" dev lo \
        || exiterr "Could not remove the obsolete IPv6 VPN DNS endpoint."
    fi
    remove_managed_boot_address 6 "$SAVED_VPN_SERVER_IP_IPV6"
  fi
  if [ -n "$SAVED_VPN_SUBNET_IPV6" ] \
    && [ "$SAVED_VPN_SUBNET_IPV6" != "$VPN_SUBNET_IPV6" ] \
    && [ "${SAVED_VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT:-1}" = 0 ]; then
    if ipv6_subnet_route_exists "$SAVED_VPN_SUBNET_IPV6"; then
      ip -6 route del "$SAVED_VPN_SUBNET_IPV6" dev lo \
        || exiterr "Could not remove the obsolete IPv6 VPN route."
    fi
    remove_managed_boot_ipv6_route "$SAVED_VPN_SUBNET_IPV6"
  fi
}

assign_vpn_server_ip() {
  local root_dir="${BONJOUR_VPN_ROOT:-}"
  # Reconfiguration removes only endpoints that a previous run created.
  # Addresses which pre-dated Bonjour VPN are always preserved.
  remove_stale_owned_loopback_addresses
  # For IKEv2/XAuth: add VPN_SERVER_IP to loopback (needed as dnsmasq listen address)
  if [ "$HAS_IKEV2" = 1 ] || [ "$HAS_XAUTH" = 1 ]; then
    bigecho "Assigning VPN server IP ($VPN_SERVER_IP) to loopback..."
    if ! loopback_has_ipv4 "$VPN_SERVER_IP"; then
      ip addr add "${VPN_SERVER_IP}/32" dev lo || exiterr "Failed to add $VPN_SERVER_IP to loopback."
    fi
    # Make it persistent via /etc/rc.local
    RC_LOCAL="${root_dir}/etc/rc.local"
    if [ "$os_type" = "alpine" ]; then
      RC_LOCAL_ALPINE="${root_dir}/etc/local.d/bonjour-vpn.start"
      mkdir -p "${root_dir}/etc/local.d"
cat > "$RC_LOCAL_ALPINE" <<EOF
#!/bin/sh
# Added by enable_bonjour.sh - Bonjour/mDNS VPN support
ip addr add ${VPN_SERVER_IP}/32 dev lo 2>/dev/null
EOF
      chmod +x "$RC_LOCAL_ALPINE"
      rc-update add local default 2>/dev/null
    else
      if [ -f "$RC_LOCAL" ]; then
        ensure_rc_local_managed_line "$RC_LOCAL" \
          "ip addr add ${VPN_SERVER_IP}/32 dev lo 2>/dev/null"
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
    if ! loopback_has_ipv4 "$L2TP_SERVER_IP"; then
      bigecho "Assigning L2TP server IP ($L2TP_SERVER_IP) to loopback..."
      ip addr add "${L2TP_SERVER_IP}/32" dev lo || exiterr "Failed to add $L2TP_SERVER_IP to loopback."
    fi
    # Persist in rc.local / local.d alongside the IKEv2/XAuth IP
    if [ "$os_type" = "alpine" ]; then
      RC_LOCAL_ALPINE="${root_dir}/etc/local.d/bonjour-vpn.start"
      if [ -f "$RC_LOCAL_ALPINE" ] && ! grep -q "${L2TP_SERVER_IP}/32" "$RC_LOCAL_ALPINE"; then
        printf '%s\n' "ip addr add ${L2TP_SERVER_IP}/32 dev lo 2>/dev/null" \
          >> "$RC_LOCAL_ALPINE"
      fi
    else
      RC_LOCAL="${root_dir}/etc/rc.local"
      if [ -f "$RC_LOCAL" ]; then
        ensure_rc_local_managed_line "$RC_LOCAL" \
          "ip addr add ${L2TP_SERVER_IP}/32 dev lo 2>/dev/null"
      fi
    fi
  fi
  # For IPv6: add VPN_SERVER_IP_IPV6 to loopback. dnsmasq's bind-interfaces
  # requires the address to exist before the service starts. Must match the
  # listen-address entry added by configure_dnsmasq().
  if [ "$HAS_IPV6" = 1 ] && [ -n "$VPN_SERVER_IP_IPV6" ]; then
    if ! loopback_has_ipv6 "$VPN_SERVER_IP_IPV6"; then
      bigecho "Assigning VPN server IPv6 ($VPN_SERVER_IP_IPV6) to loopback..."
      ip -6 addr add "${VPN_SERVER_IP_IPV6}/128" dev lo \
        || exiterr "Failed to add $VPN_SERVER_IP_IPV6 to loopback."
    fi
    if ! ipv6_subnet_route_exists "$VPN_SUBNET_IPV6"; then
      ip -6 route add "$VPN_SUBNET_IPV6" dev lo \
        || exiterr "Failed to add the route for IPv6 VPN clients."
    fi
    # Persist
    if [ "$os_type" = "alpine" ]; then
      RC_LOCAL_ALPINE="${root_dir}/etc/local.d/bonjour-vpn.start"
      if [ -f "$RC_LOCAL_ALPINE" ] && ! grep -q "${VPN_SERVER_IP_IPV6}/128" "$RC_LOCAL_ALPINE"; then
        printf '%s\n' "ip -6 addr add ${VPN_SERVER_IP_IPV6}/128 dev lo 2>/dev/null" \
          >> "$RC_LOCAL_ALPINE"
      fi
      if [ "${VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT:-1}" = 0 ] \
        && [ -f "$RC_LOCAL_ALPINE" ] \
        && ! grep -Fq "ip -6 route add ${VPN_SUBNET_IPV6} dev lo" "$RC_LOCAL_ALPINE"; then
        printf '%s\n' "ip -6 route add ${VPN_SUBNET_IPV6} dev lo 2>/dev/null" \
          >> "$RC_LOCAL_ALPINE"
      fi
    else
      RC_LOCAL="${root_dir}/etc/rc.local"
      if [ -f "$RC_LOCAL" ]; then
        ensure_rc_local_managed_line "$RC_LOCAL" \
          "ip -6 addr add ${VPN_SERVER_IP_IPV6}/128 dev lo 2>/dev/null"
      fi
      if [ "${VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT:-1}" = 0 ] \
        && [ -f "$RC_LOCAL" ]; then
        ensure_rc_local_managed_line "$RC_LOCAL" \
          "ip -6 route add ${VPN_SUBNET_IPV6} dev lo 2>/dev/null"
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
  # completely. Compatible clients can still resolve AAAA records through
  # the IPv4 VPN DNS endpoint when their profile and application use tunnel
  # DNS; dnsmasq can return IPv6 answers to an IPv4 DNS query.
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
    # Set modecfgdomains — two domains serve distinct purposes:
    #   "local"  — iOS/macOS unicast DNS-SD for .local and hostname resolution
    #   "."      — catch-all so VPN DNS handles ALL queries (no DNS leak)
    # IKEv1/XAuth: only the first domain is sent (protocol limitation).
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
    # Set modecfgdomains in xauth-psk section (same as IKEv2).
    # IKEv1 only sends the first domain ("local").
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

capture_firewall_persistence_ownership() {
  if [ -n "$SAVED_FIREWALL_PERSIST6_FILE_WAS_PRESENT" ]; then
    FIREWALL_PERSIST6_FILE_WAS_PRESENT=$SAVED_FIREWALL_PERSIST6_FILE_WAS_PRESENT
  elif [ -f "$BONJOUR_CONFIG_STATE" ]; then
    # Older state did not record ownership; preserve conservatively.
    FIREWALL_PERSIST6_FILE_WAS_PRESENT=1
  elif [ -n "$FIREWALL_PERSIST6_FILE" ] && [ -f "$FIREWALL_PERSIST6_FILE" ]; then
    FIREWALL_PERSIST6_FILE_WAS_PRESENT=1
  else
    FIREWALL_PERSIST6_FILE_WAS_PRESENT=0
  fi
  if [ -n "$SAVED_FIREWALL_PERSIST6_FILE2_WAS_PRESENT" ]; then
    FIREWALL_PERSIST6_FILE2_WAS_PRESENT=$SAVED_FIREWALL_PERSIST6_FILE2_WAS_PRESENT
  elif [ -f "$BONJOUR_CONFIG_STATE" ]; then
    FIREWALL_PERSIST6_FILE2_WAS_PRESENT=1
  elif [ -n "$FIREWALL_PERSIST6_FILE2" ] && [ -f "$FIREWALL_PERSIST6_FILE2" ]; then
    FIREWALL_PERSIST6_FILE2_WAS_PRESENT=1
  else
    FIREWALL_PERSIST6_FILE2_WAS_PRESENT=0
  fi
}

ipv6_persistence_is_empty() {
  awk '
    /^\*/ { table=1 }
    /^-A[[:space:]]/ { unsafe=1 }
    /^:/ && $2 != "ACCEPT" { unsafe=1 }
    END { exit !(table && !unsafe) }
  ' "$1"
}

remove_empty_owned_ipv6_persistence() {
  local file ownership
  [ "$FIREWALL_BACKEND" = iptables ] || return 0
  for file in "$FIREWALL_PERSIST6_FILE" "$FIREWALL_PERSIST6_FILE2"; do
    [ -n "$file" ] || continue
    if [ "$file" = "$FIREWALL_PERSIST6_FILE" ]; then
      ownership=${FIREWALL_PERSIST6_FILE_WAS_PRESENT:-1}
    else
      ownership=${FIREWALL_PERSIST6_FILE2_WAS_PRESENT:-1}
    fi
    if [ "$ownership" = 0 ] && [ -f "$file" ] \
      && ipv6_persistence_is_empty "$file"; then
      /bin/rm -f "$file" || return 1
    fi
  done
}

uses_ipv6_firewall() {
  [ "${HAS_IPV6:-0}" = 1 ] || [ "${SAVED_HAS_IPV6:-0}" = 1 ] \
    || [ -n "${SAVED_VPN_SUBNET_IPV6:-}" ]
}

check_ipv6_firewall_loader() {
  local loader normalized netfilter_ip6_plugin
  IPV6_FIREWALL_LOADER=""
  IPV6_FIREWALL_LOADER_NEEDS_UPDATE=0
  [ "$FIREWALL_BACKEND" = iptables ] && uses_ipv6_firewall || return 0
  case "$os_type" in
    ubuntu|debian)
      netfilter_ip6_plugin=${BONJOUR_VPN_NETFILTER_IP6_PLUGIN:-/usr/share/netfilter-persistent/plugins.d/25-ip6tables}
      if [ "$FIREWALL_PERSIST6_FILE2" = /etc/iptables/rules.v6 ] \
        && [ -x "$netfilter_ip6_plugin" ]; then
        return 0
      fi
      ;;
    alpine) ;;
    *) return 0 ;;
  esac

  loader=${BONJOUR_VPN_IPTABLES_LOADER:-/etc/network/if-pre-up.d/iptablesload}
  [ -f "$loader" ] && [ ! -L "$loader" ] && [ -x "$loader" ] \
    || exiterr "IPv6 Bonjour requires a regular executable hwdsl2 firewall loader at $loader."
  normalized=$(sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d' "$loader")
  case "$normalized" in
    'iptables-restore < /etc/iptables.rules
[ -f /etc/ip6tables.rules ] && ip6tables-restore < /etc/ip6tables.rules
exit 0')
      IPV6_FIREWALL_LOADER="$loader"
      ;;
    'iptables-restore < /etc/iptables.rules
exit 0')
      IPV6_FIREWALL_LOADER="$loader"
      IPV6_FIREWALL_LOADER_NEEDS_UPDATE=1
      ;;
    *)
      exiterr "The hwdsl2 firewall loader has custom commands. Refusing to alter IPv6 persistence."
      ;;
  esac
}

configure_ipv6_firewall_loader() {
  local candidate loader_mode
  [ "$IPV6_FIREWALL_LOADER_NEEDS_UPDATE" = 1 ] || return 0
  [ -n "$IPV6_FIREWALL_LOADER" ] || return 1
  candidate="${IPV6_FIREWALL_LOADER}.bonjour-vpn.candidate"
  IPV6_FIREWALL_LOADER_CANDIDATE="$candidate"
  awk '
    /^exit 0[[:space:]]*$/ && !inserted {
      print "[ -f /etc/ip6tables.rules ] && ip6tables-restore < /etc/ip6tables.rules"
      inserted=1
    }
    { print }
    END { if (!inserted) exit 42 }
  ' "$IPV6_FIREWALL_LOADER" > "$candidate" \
    || { /bin/rm -f "$candidate"; return 1; }
  loader_mode=$(stat -c '%a' "$IPV6_FIREWALL_LOADER" 2>/dev/null \
    || stat -f '%Lp' "$IPV6_FIREWALL_LOADER" 2>/dev/null) \
    || { /bin/rm -f "$candidate"; return 1; }
  chmod "$loader_mode" "$candidate" || { /bin/rm -f "$candidate"; return 1; }
  /bin/sh -n "$candidate" || { /bin/rm -f "$candidate"; return 1; }
  conf_bk_bonjour "$IPV6_FIREWALL_LOADER" \
    || { /bin/rm -f "$candidate"; return 1; }
  mv -f "$candidate" "$IPV6_FIREWALL_LOADER" \
    || { /bin/rm -f "$candidate"; return 1; }
  IPV6_FIREWALL_LOADER_CANDIDATE=""
  IPV6_FIREWALL_LOADER_NEEDS_UPDATE=0
}

start_firewall_transaction() {
  local tx_dir
  install -d -m 700 "$BONJOUR_STATE_DIR"
  tx_dir=$(mktemp -d "$BONJOUR_STATE_DIR/.firewall.XXXXXX") \
    || exiterr "Could not create a firewall transaction directory."
  chmod 700 "$tx_dir"
  detect_firewall_backend
  iptables-save > "$tx_dir/live.v4" \
    || { /bin/rm -rf "$tx_dir"; exiterr "Could not snapshot the live IPv4 firewall."; }
  if [ "$FIREWALL_BACKEND" = nftables ]; then
    { echo "flush ruleset"; nft list ruleset; } > "$tx_dir/live.nft" \
      || { /bin/rm -rf "$tx_dir"; exiterr "Could not snapshot the live nftables firewall."; }
  elif uses_ipv6_firewall; then
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

add_nft_allow_rules() {
  local subnet="$1" family="${2:-ip}" table chain port marker chains_found=0
  marker="bonjour-vpn:${subnet}"
  for table in firewalld nftables_svc; do
    [ "$table" = firewalld ] && chain=filter_INPUT || chain=INPUT
    nft list chain inet "$table" "$chain" >/dev/null 2>&1 || continue
    chains_found=$((chains_found + 1))
    for port in 53 5353; do
      if ! nft list chain inet "$table" "$chain" 2>/dev/null \
        | grep -F "comment \"${marker}:udp:${port}\"" >/dev/null; then
        nft insert rule inet "$table" "$chain" "$family" saddr "$subnet" \
          udp dport "$port" accept comment "\"${marker}:udp:${port}\"" \
          || return 1
      fi
    done
    if ! nft list chain inet "$table" "$chain" 2>/dev/null \
      | grep -F "comment \"${marker}:tcp:53\"" >/dev/null; then
      nft insert rule inet "$table" "$chain" "$family" saddr "$subnet" \
        tcp dport 53 accept comment "\"${marker}:tcp:53\"" \
        || return 1
    fi
  done
  if [ "$chains_found" -eq 0 ]; then
    echo "Warning: no parent firewalld/nftables_svc INPUT chain was found; relying on the iptables-compatible rule." >&2
  fi
  return 0
}

remove_nft_allow_rules_for_subnet() {
  local subnet="$1" table chain handle marker
  [ -n "$subnet" ] || return 0
  marker="bonjour-vpn:${subnet}:"
  for table in firewalld nftables_svc; do
    [ "$table" = firewalld ] && chain=filter_INPUT || chain=INPUT
    nft list chain inet "$table" "$chain" >/dev/null 2>&1 || continue
    while true; do
      handle=$(nft -a list chain inet "$table" "$chain" 2>/dev/null \
        | awk -v marker="$marker" 'index($0, "comment \"" marker) { for (i=1; i<=NF; i++) if ($i == "handle") { print $(i+1); exit } }')
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
      sed -i.bonjour-vpn-sed \
        '/xt target "MASQUERADE"/s/xt target "MASQUERADE"/masquerade/' "$candidate" \
        || return 1
      /bin/rm -f "${candidate}.bonjour-vpn-sed"
    fi
    nft -c -f "$candidate" >/dev/null 2>&1 \
      || { /bin/rm -f "$candidate"; return 1; }
  else
    {
      echo "# Modified by hwdsl2 VPN script"
      iptables-save
    } > "$candidate" || return 1
    if iptables-restore --help 2>&1 | grep -q -- '--test'; then
      iptables-restore --test < "$candidate" >/dev/null 2>&1 \
        || { /bin/rm -f "$candidate"; return 1; }
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
      ip6tables-restore --test < "$candidate6" >/dev/null 2>&1 \
        || { /bin/rm -f "$candidate6"; return 1; }
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

remove_ipv6_bonjour_rules() {
  local subnet="$1" endpoint="$2"
  [ -n "$subnet" ] && [ -n "$endpoint" ] || return 0
  while ip6tables -D INPUT -s "$subnet" -p udp --dport 53 -j ACCEPT 2>/dev/null; do :; done
  while ip6tables -D INPUT -s "$subnet" -p tcp --dport 53 -j ACCEPT 2>/dev/null; do :; done
  while ip6tables -D INPUT -s "$subnet" -p udp --dport 5353 -j ACCEPT 2>/dev/null; do :; done
  while ip6tables -t nat -D PREROUTING -s "$subnet" -d ff02::fb \
    -p udp --dport 5353 -j DNAT --to-destination "[${endpoint}]:53" 2>/dev/null; do :; done
}

remove_ipv4_bonjour_rules() {
  local subnet="$1" endpoint="$2"
  [ -n "$subnet" ] && [ -n "$endpoint" ] || return 0
  while iptables -D INPUT -s "$subnet" -p udp --dport 53 -j ACCEPT 2>/dev/null; do :; done
  while iptables -D INPUT -s "$subnet" -p tcp --dport 53 -j ACCEPT 2>/dev/null; do :; done
  while iptables -D INPUT -s "$subnet" -p udp --dport 5353 -j ACCEPT 2>/dev/null; do :; done
  while iptables -t nat -D PREROUTING -s "$subnet" -d 224.0.0.251 \
    -p udp --dport 5353 -j DNAT --to-destination "${endpoint}:53" 2>/dev/null; do :; done
}

update_iptables() {
  bigecho "Updating IPTables rules..."
  start_firewall_transaction
  if [ -n "$SAVED_VPN_SUBNET" ] \
    && { [ "$SAVED_VPN_SUBNET" != "$VPN_SUBNET" ] \
      || [ "$SAVED_VPN_SERVER_IP" != "$VPN_SERVER_IP" ]; }; then
    remove_ipv4_bonjour_rules "$SAVED_VPN_SUBNET" "$SAVED_VPN_SERVER_IP"
    if [ "$FIREWALL_BACKEND" = nftables ]; then
      remove_nft_allow_rules_for_subnet "$SAVED_VPN_SUBNET" \
        || { rollback_firewall_transaction; exiterr "Could not remove obsolete native nftables VPN DNS rules."; }
    fi
  fi
  if [ -n "$SAVED_L2TP_SUBNET" ] \
    && { [ "$SAVED_L2TP_SUBNET" != "$L2TP_SUBNET" ] \
      || [ "$SAVED_L2TP_SERVER_IP" != "$L2TP_SERVER_IP" ]; }; then
    remove_ipv4_bonjour_rules "$SAVED_L2TP_SUBNET" "$SAVED_L2TP_SERVER_IP"
    if [ "$FIREWALL_BACKEND" = nftables ] \
      && [ "$SAVED_L2TP_SUBNET" != "$SAVED_VPN_SUBNET" ]; then
      remove_nft_allow_rules_for_subnet "$SAVED_L2TP_SUBNET" \
        || { rollback_firewall_transaction; exiterr "Could not remove obsolete native nftables L2TP DNS rules."; }
    fi
  fi
  # Add rules for IKEv2/XAuth subnet (they share the same subnet)
  if [ "$HAS_IKEV2" = 1 ] || [ "$HAS_XAUTH" = 1 ]; then
    if ! iptables -C INPUT -s "$VPN_SUBNET" -p udp --dport 53 -j ACCEPT 2>/dev/null; then
      iptables -I INPUT 1 -s "$VPN_SUBNET" -p udp --dport 53 -j ACCEPT \
        || { rollback_firewall_transaction; exiterr "Could not add the VPN UDP DNS firewall rule."; }
    fi
    if ! iptables -C INPUT -s "$VPN_SUBNET" -p tcp --dport 53 -j ACCEPT 2>/dev/null; then
      iptables -I INPUT 1 -s "$VPN_SUBNET" -p tcp --dport 53 -j ACCEPT \
        || { rollback_firewall_transaction; exiterr "Could not add the VPN TCP DNS firewall rule."; }
    fi
    if ! iptables -C INPUT -s "$VPN_SUBNET" -p udp --dport 5353 -j ACCEPT 2>/dev/null; then
      iptables -I INPUT 1 -s "$VPN_SUBNET" -p udp --dport 5353 -j ACCEPT \
        || { rollback_firewall_transaction; exiterr "Could not add the VPN mDNS firewall rule."; }
    fi
    # mDNS capture: redirect multicast mDNS from VPN clients to dnsmasq
    if ! iptables -t nat -C PREROUTING -s "$VPN_SUBNET" -d 224.0.0.251 -p udp --dport 5353 -j DNAT --to-destination "${VPN_SERVER_IP}:53" 2>/dev/null; then
      iptables -t nat -I PREROUTING -s "$VPN_SUBNET" -d 224.0.0.251 -p udp --dport 5353 -j DNAT --to-destination "${VPN_SERVER_IP}:53" \
        || { rollback_firewall_transaction; exiterr "Could not add the VPN mDNS capture rule."; }
    fi
    if [ "$FIREWALL_BACKEND" = nftables ]; then
      add_nft_allow_rules "$VPN_SUBNET" \
        || { rollback_firewall_transaction; exiterr "Could not add native nftables DNS rules for the VPN subnet."; }
    fi
  fi
  # Add rules for L2TP subnet
  if [ "$HAS_L2TP" = 1 ]; then
    if ! iptables -C INPUT -s "$L2TP_SUBNET" -p udp --dport 53 -j ACCEPT 2>/dev/null; then
      iptables -I INPUT 1 -s "$L2TP_SUBNET" -p udp --dport 53 -j ACCEPT \
        || { rollback_firewall_transaction; exiterr "Could not add the L2TP UDP DNS firewall rule."; }
    fi
    if ! iptables -C INPUT -s "$L2TP_SUBNET" -p tcp --dport 53 -j ACCEPT 2>/dev/null; then
      iptables -I INPUT 1 -s "$L2TP_SUBNET" -p tcp --dport 53 -j ACCEPT \
        || { rollback_firewall_transaction; exiterr "Could not add the L2TP TCP DNS firewall rule."; }
    fi
    if ! iptables -C INPUT -s "$L2TP_SUBNET" -p udp --dport 5353 -j ACCEPT 2>/dev/null; then
      iptables -I INPUT 1 -s "$L2TP_SUBNET" -p udp --dport 5353 -j ACCEPT \
        || { rollback_firewall_transaction; exiterr "Could not add the L2TP mDNS firewall rule."; }
    fi
    # mDNS capture: redirect multicast mDNS from L2TP clients to dnsmasq
    if ! iptables -t nat -C PREROUTING -s "$L2TP_SUBNET" -d 224.0.0.251 -p udp --dport 5353 -j DNAT --to-destination "${L2TP_SERVER_IP}:53" 2>/dev/null; then
      iptables -t nat -I PREROUTING -s "$L2TP_SUBNET" -d 224.0.0.251 -p udp --dport 5353 -j DNAT --to-destination "${L2TP_SERVER_IP}:53" \
        || { rollback_firewall_transaction; exiterr "Could not add the L2TP mDNS capture rule."; }
    fi
    if [ "$FIREWALL_BACKEND" = nftables ]; then
      add_nft_allow_rules "$L2TP_SUBNET" \
        || { rollback_firewall_transaction; exiterr "Could not add native nftables DNS rules for the L2TP subnet."; }
    fi
  fi
  if [ "$SAVED_HAS_IPV6" = 1 ] \
    && { [ "$SAVED_VPN_SUBNET_IPV6" != "$VPN_SUBNET_IPV6" ] \
      || [ "$SAVED_VPN_SERVER_IP_IPV6" != "$VPN_SERVER_IP_IPV6" ]; }; then
    remove_ipv6_bonjour_rules "$SAVED_VPN_SUBNET_IPV6" "$SAVED_VPN_SERVER_IP_IPV6"
    if [ "$FIREWALL_BACKEND" = nftables ]; then
      remove_nft_allow_rules_for_subnet "$SAVED_VPN_SUBNET_IPV6" \
        || { rollback_firewall_transaction; exiterr "Could not remove obsolete native nftables IPv6 DNS rules."; }
    fi
  fi
  if [ "$HAS_IPV6" = 1 ]; then
    if ! ip6tables -C INPUT -s "$VPN_SUBNET_IPV6" -p udp --dport 53 -j ACCEPT 2>/dev/null; then
      ip6tables -I INPUT 1 -s "$VPN_SUBNET_IPV6" -p udp --dport 53 -j ACCEPT \
        || { rollback_firewall_transaction; exiterr "Could not add the IPv6 VPN UDP DNS firewall rule."; }
    fi
    if ! ip6tables -C INPUT -s "$VPN_SUBNET_IPV6" -p tcp --dport 53 -j ACCEPT 2>/dev/null; then
      ip6tables -I INPUT 1 -s "$VPN_SUBNET_IPV6" -p tcp --dport 53 -j ACCEPT \
        || { rollback_firewall_transaction; exiterr "Could not add the IPv6 VPN TCP DNS firewall rule."; }
    fi
    if ! ip6tables -C INPUT -s "$VPN_SUBNET_IPV6" -p udp --dport 5353 -j ACCEPT 2>/dev/null; then
      ip6tables -I INPUT 1 -s "$VPN_SUBNET_IPV6" -p udp --dport 5353 -j ACCEPT \
        || { rollback_firewall_transaction; exiterr "Could not add the IPv6 VPN mDNS firewall rule."; }
    fi
    if ! ip6tables -t nat -C PREROUTING -s "$VPN_SUBNET_IPV6" -d ff02::fb \
      -p udp --dport 5353 -j DNAT --to-destination "[${VPN_SERVER_IP_IPV6}]:53" 2>/dev/null; then
      ip6tables -t nat -I PREROUTING -s "$VPN_SUBNET_IPV6" -d ff02::fb \
        -p udp --dport 5353 -j DNAT --to-destination "[${VPN_SERVER_IP_IPV6}]:53" \
        || { rollback_firewall_transaction; exiterr "Could not add the IPv6 VPN mDNS capture rule."; }
    fi
    if [ "$FIREWALL_BACKEND" = nftables ]; then
      add_nft_allow_rules "$VPN_SUBNET_IPV6" ip6 \
        || { rollback_firewall_transaction; exiterr "Could not add native nftables DNS rules for the IPv6 VPN subnet."; }
    fi
  fi
  persist_firewall \
    || { rollback_firewall_transaction; exiterr "Could not validate and persist the updated firewall."; }
  if [ "$HAS_IPV6" != 1 ]; then
    remove_empty_owned_ipv6_persistence \
      || { rollback_firewall_transaction; exiterr "Could not remove empty Bonjour-owned IPv6 firewall persistence."; }
  fi
  configure_ipv6_firewall_loader \
    || { rollback_firewall_transaction; exiterr "Could not install IPv6 firewall persistence in the hwdsl2 loader."; }
  finish_firewall_transaction
}

create_cache_warmer() {
  bigecho "Installing the mDNS resolver and service monitor..."

  RESOLVE_SCRIPT="/usr/local/bin/bonjour-vpn-resolve"
  RESOLVE_SCRIPT_CANDIDATE=$(mktemp "${RESOLVE_SCRIPT}.candidate.XXXXXX") \
    || exiterr "Could not create the Bonjour VPN resolver candidate."
cat > "$RESOLVE_SCRIPT_CANDIDATE" <<'RESOLVE_EOF'
#!/bin/bash
# Reconcile LAN Bonjour records into the package-managed dnsmasq instance.

export PATH="${BONJOUR_VPN_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"

ROOT_DIR=${BONJOUR_VPN_ROOT:-}
STATE_DIR="$ROOT_DIR/var/lib/bonjour-vpn"
CONFIG_STATE="$STATE_DIR/config"
INCOMPLETE_STATE="$STATE_DIR/incomplete"
LOCK_FILE="$ROOT_DIR/run/bonjour-vpn.lock"
HOSTS_FILE="$ROOT_DIR/etc/bonjour-vpn-hosts"
HOSTS_CANDIDATE="$ROOT_DIR/etc/.bonjour-vpn-hosts.candidate"
HOSTS_LKG="$ROOT_DIR/etc/.bonjour-vpn-hosts.last-good"
DNSMASQ_DIR="$ROOT_DIR/etc/dnsmasq.d"
DNSMASQ_CONF="$ROOT_DIR/etc/dnsmasq.conf"
SERVICES_FILE="$DNSMASQ_DIR/bonjour-vpn-services.conf"
SERVICES_CANDIDATE="$DNSMASQ_DIR/.bonjour-vpn-services.conf.candidate"
SERVICES_LKG="$DNSMASQ_DIR/.bonjour-vpn-services.conf.last-good"
EMPTY_COUNT="$STATE_DIR/empty-count"
BROWSE_TMP=""
DNSMASQ_TEST_DIR=""

cleanup() {
  [ -n "$BROWSE_TMP" ] && rm -f "$BROWSE_TMP"
  rm -f "$HOSTS_CANDIDATE" "$SERVICES_CANDIDATE"
  if [ -n "$DNSMASQ_TEST_DIR" ]; then
    rm -rf "$DNSMASQ_TEST_DIR"
  fi
  if [ "${LOCK_ACQUIRED:-0}" = 1 ]; then
    flock -u 9 2>/dev/null || true
  fi
  exec 9>&- 2>/dev/null || true
}
trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM

acquire_lock() {
  local old_umask
  command -v flock >/dev/null 2>&1 || return 1
  old_umask=$(umask)
  umask 077
  exec 9>"$LOCK_FILE"
  umask "$old_umask"
  flock -w 30 9 || return 1
  LOCK_ACQUIRED=1
}

dnsmasq_active() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active --quiet dnsmasq.service
  else
    rc-service dnsmasq status 9>&- >/dev/null 2>&1
  fi
}

start_dnsmasq() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl reset-failed dnsmasq.service 2>/dev/null || true
    systemctl start dnsmasq.service >/dev/null 2>&1
  else
    rc-service dnsmasq start 9>&- >/dev/null 2>&1
  fi
  dnsmasq_active
}

restart_dnsmasq() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl reset-failed dnsmasq.service 2>/dev/null || true
    systemctl restart dnsmasq.service >/dev/null 2>&1
  else
    rc-service dnsmasq restart 9>&- >/dev/null 2>&1
  fi
  dnsmasq_active
}

reload_dnsmasq_hosts() {
  dnsmasq_active || return 1
  if command -v systemctl >/dev/null 2>&1; then
    systemctl reload dnsmasq.service >/dev/null 2>&1 \
      || restart_dnsmasq \
      || return 1
  else
    rc-service dnsmasq reload 9>&- >/dev/null 2>&1 \
      || rc-service dnsmasq restart 9>&- >/dev/null 2>&1 \
      || return 1
  fi
  dnsmasq_active
}

ensure_loopback_addresses() {
  local state_file="$INCOMPLETE_STATE"
  [ -f "$state_file" ] || state_file="$CONFIG_STATE"
  [ -f "$state_file" ] || return 1
  # Root-owned state created by enable_bonjour.sh; contains no credentials.
  # During a transaction the recovery state is authoritative, including a
  # reconfiguration where the previous completed state still exists. The
  # completed state becomes authoritative after verification removes the
  # recovery marker.
  # shellcheck disable=SC1090
  . "$state_file"
  for address in "${VPN_SERVER_IP_SAVED:-}" "${L2TP_SERVER_IP_SAVED:-}"; do
    [ -n "$address" ] || continue
    if ! ip -4 addr show dev lo 2>/dev/null | grep -Eq "inet ${address}/"; then
      ip addr add "${address}/32" dev lo >/dev/null 2>&1 || return 1
    fi
  done
  if [ "${HAS_IPV6_SAVED:-0}" = 1 ] \
    && [ -n "${VPN_SERVER_IP_IPV6_SAVED:-}" ] \
    && ! ip -6 -o addr show dev lo to "${VPN_SERVER_IP_IPV6_SAVED}/128" 2>/dev/null \
      | grep -q '[[:space:]]inet6[[:space:]]'; then
    ip -6 addr add "${VPN_SERVER_IP_IPV6_SAVED}/128" dev lo >/dev/null 2>&1 \
      || return 1
  fi
  if [ "${HAS_IPV6_SAVED:-0}" = 1 ] \
    && [ -n "${VPN_SUBNET_IPV6_SAVED:-}" ] \
    && [ -z "$(ip -6 route show exact "$VPN_SUBNET_IPV6_SAVED" 2>/dev/null)" ]; then
    ip -6 route add "$VPN_SUBNET_IPV6_SAVED" dev lo >/dev/null 2>&1 \
      || return 1
  fi
}

validate_candidates() {
  local test_conf conf base
  DNSMASQ_TEST_DIR=$(mktemp -d "$ROOT_DIR/etc/.bonjour-vpn-dnsmasq-test.XXXXXX") || return 1
  test_conf="$DNSMASQ_TEST_DIR/dnsmasq.conf"
  for conf in "$DNSMASQ_DIR"/*.conf; do
    [ -f "$conf" ] || continue
    base=${conf##*/}
    [ "$base" = "bonjour-vpn-services.conf" ] && continue
    cp -p "$conf" "$DNSMASQ_TEST_DIR/$base" || return 1
  done
  cp -p "$SERVICES_CANDIDATE" "$DNSMASQ_TEST_DIR/bonjour-vpn-services.conf" || return 1
  if [ -f "$DNSMASQ_TEST_DIR/bonjour-vpn.conf" ]; then
    sed "s#^addn-hosts=.*bonjour-vpn-hosts\$#addn-hosts=$HOSTS_CANDIDATE#" \
      "$DNSMASQ_TEST_DIR/bonjour-vpn.conf" > "$DNSMASQ_TEST_DIR/.bonjour-vpn.conf.new" || return 1
    mv -f "$DNSMASQ_TEST_DIR/.bonjour-vpn.conf.new" "$DNSMASQ_TEST_DIR/bonjour-vpn.conf"
  fi
  sed "s#$DNSMASQ_DIR#$DNSMASQ_TEST_DIR#g" "$DNSMASQ_CONF" > "$test_conf" || return 1
  dnsmasq --test --conf-file="$test_conf" >/dev/null 2>&1
}

restore_previous_files() {
  local hosts_had="$1" services_had="$2"
  if [ "$hosts_had" = 1 ]; then
    cp -p "$HOSTS_LKG" "$HOSTS_FILE"
  else
    rm -f "$HOSTS_FILE"
  fi
  if [ "$services_had" = 1 ]; then
    cp -p "$SERVICES_LKG" "$SERVICES_FILE"
  else
    rm -f "$SERVICES_FILE"
  fi
}

publish_candidates() {
  local hosts_changed=0 services_changed=0 hosts_had=0 services_had=0
  cmp -s "$HOSTS_CANDIDATE" "$HOSTS_FILE" || hosts_changed=1
  cmp -s "$SERVICES_CANDIDATE" "$SERVICES_FILE" || services_changed=1
  if [ "$hosts_changed" = 0 ] && [ "$services_changed" = 0 ]; then
    rm -f "$HOSTS_CANDIDATE" "$SERVICES_CANDIDATE"
    dnsmasq_active || start_dnsmasq
    return
  fi
  if [ -f "$HOSTS_FILE" ]; then
    hosts_had=1
    cp -p "$HOSTS_FILE" "$HOSTS_LKG" || return 1
  fi
  if [ -f "$SERVICES_FILE" ]; then
    services_had=1
    cp -p "$SERVICES_FILE" "$SERVICES_LKG" || return 1
  fi
  mv -f "$HOSTS_CANDIDATE" "$HOSTS_FILE" || return 1
  mv -f "$SERVICES_CANDIDATE" "$SERVICES_FILE" || {
    restore_previous_files "$hosts_had" "$services_had"
    return 1
  }
  if [ "$services_changed" = 1 ]; then
    restart_dnsmasq || {
      restore_previous_files "$hosts_had" "$services_had"
      restart_dnsmasq >/dev/null 2>&1 || true
      return 1
    }
  elif ! reload_dnsmasq_hosts; then
    restore_previous_files "$hosts_had" "$services_had"
    restart_dnsmasq >/dev/null 2>&1 || true
    return 1
  fi
}

install -d -m 700 "$STATE_DIR"

if [ "${1:-}" = "--prepare" ]; then
  # The enable transaction already holds this lock when systemd starts the
  # oneshot prepare unit. Preparation only restores endpoints recorded in a
  # root-owned state file; it does not reconcile or publish DNS records.
  ensure_loopback_addresses || exit 1
  exit 0
fi

if [ "${1:-}" != "--initial-under-parent-lock" ]; then
  acquire_lock || exit 1
fi
ensure_loopback_addresses || exit 1

command -v avahi-browse >/dev/null 2>&1 || exit 1
pgrep -x avahi-daemon >/dev/null 2>&1 || exit 1
BROWSE_TMP=$(mktemp "$STATE_DIR/.browse.XXXXXX") || exit 1
if ! timeout 20 avahi-browse -arptk > "$BROWSE_TMP" 2>/dev/null; then
  exit 1
fi
pgrep -x avahi-daemon >/dev/null 2>&1 || exit 1

if [ "${HAS_IPV6_SAVED:-0}" = 1 ]; then
  RESOLVED=$(grep '^=;' "$BROWSE_TMP" | grep -E ';IPv(4|6);' || true)
else
  RESOLVED=$(grep '^=;' "$BROWSE_TMP" | grep ';IPv4;' || true)
fi
if [ -z "$RESOLVED" ]; then
  count=$(cat "$EMPTY_COUNT" 2>/dev/null || echo 0)
  case "$count" in *[!0-9]*) count=0 ;; esac
  count=$((count + 1))
  printf '%s\n' "$count" > "$EMPTY_COUNT"
  if [ "$count" -lt 2 ]; then
    dnsmasq_active || start_dnsmasq
    exit
  fi
else
  printf '0\n' > "$EMPTY_COUNT"
fi

printf '%s\n' "$RESOLVED" | awk -F';' '{
  addr=$8; host=$7
  if (addr != "" && host != "") {
    # Strip IPv6 zone suffix like "fe80::1%eth0" — dnsmasq does not accept
    # scoped addresses in addn-hosts. Link-local addresses on the LAN are
    # not routable to VPN clients anyway, so dropping them is safe.
    sub(/%[^ ]*/, "", addr)
    gsub(/[ \t]+$/, "", host)
    gsub(/[ \t]+$/, "", addr)
    # Link-local IPv6 addresses cannot be reached by VPN clients and lose
    # their required zone identifier when represented in addn-hosts.
    lower=tolower(addr)
    if (lower ~ /^fe[89ab][0-9a-f]:/) next
    key=addr SUBSEP host
    if (!seen[key]++) print addr " " host
  }
}' | LC_ALL=C sort -u > "$HOSTS_CANDIDATE"

{
  echo "# Auto-generated by bonjour-vpn-resolve - do not edit"
  printf '%s\n' "$RESOLVED" | awk -F';' '
    $1 != "=" { next }
    {
      name=$4; stype=$5; host=$7; port=$9; txt=$10
      if (name == "" || stype == "" || host == "") next
      gsub(/\\032/, " ", name)
      if (name ~ /\\/) next
      fqdn=name "." stype ".local"
      print "ptr-record=_services._dns-sd._udp.local," stype ".local"
      print "ptr-record=" stype ".local," fqdn
      print "srv-host=" fqdn "," host "," (port != "" ? port : "0")
      if (txt != "") {
        # avahi-browse separates TXT strings as quoted values. Keep each
        # value quoted in dnsmasq so a literal comma remains part of that
        # value instead of being silently split into two TXT strings.
        count=split(txt, txt_part, /" "/)
        txt_out=""
        for (i=1; i<=count; i++) {
          sub(/^"/, "", txt_part[i])
          sub(/"$/, "", txt_part[i])
          txt_out=txt_out (i > 1 ? "," : "") "\"" txt_part[i] "\""
        }
        print "txt-record=" fqdn "," txt_out
      }
    }
  ' | LC_ALL=C sort -u
} > "$SERVICES_CANDIDATE"

validate_candidates || exit 1
publish_candidates
RESOLVE_EOF
  chmod 755 "$RESOLVE_SCRIPT_CANDIDATE" \
    || exiterr "Could not secure the Bonjour VPN resolver candidate."
  mv -f "$RESOLVE_SCRIPT_CANDIDATE" "$RESOLVE_SCRIPT" \
    || exiterr "Could not atomically install the Bonjour VPN resolver."
  RESOLVE_SCRIPT_CANDIDATE=""

  WATCHER_SCRIPT="/usr/local/bin/bonjour-vpn-watch"
  WATCHER_SCRIPT_CANDIDATE=$(mktemp "${WATCHER_SCRIPT}.candidate.XXXXXX") \
    || exiterr "Could not create the Bonjour VPN watcher candidate."
cat > "$WATCHER_SCRIPT_CANDIDATE" <<'WATCHER_EOF'
#!/bin/bash
# Persistent event notification plus bounded periodic reconciliation.

export PATH="${BONJOUR_VPN_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
RESOLVE_CMD="${BONJOUR_VPN_RESOLVE_CMD:-/usr/local/bin/bonjour-vpn-resolve}"
DEBOUNCE_SEC=${BONJOUR_VPN_DEBOUNCE_SEC:-3}
RECONCILE_SEC=${BONJOUR_VPN_RECONCILE_SEC:-60}
MAX_BURST_SEC=${BONJOUR_VPN_MAX_BURST_SEC:-30}
RUN_DIR=${BONJOUR_VPN_RUN_DIR:-/run}
BROWSE_PID=""
WATCH_FIFO=""

cleanup() {
  if [ -n "$BROWSE_PID" ] && kill -0 "$BROWSE_PID" 2>/dev/null; then
    kill "$BROWSE_PID" 2>/dev/null || true
    wait "$BROWSE_PID" 2>/dev/null || true
  fi
  exec 3>&- 2>/dev/null || true
  [ -n "$WATCH_FIFO" ] && rm -f "$WATCH_FIFO"
}
trap cleanup EXIT
trap 'cleanup; exit 0' HUP INT TERM

"$RESOLVE_CMD" >/dev/null 2>&1 || true
backoff=1
while true; do
  WATCH_FIFO="$RUN_DIR/bonjour-vpn-watch.$$"
  rm -f "$WATCH_FIFO"
  mkfifo -m 600 "$WATCH_FIFO" || exit 1
  exec 3<>"$WATCH_FIFO"
  rm -f "$WATCH_FIFO"
  WATCH_FIFO=""
  avahi-browse -apk >&3 2>/dev/null &
  BROWSE_PID=$!
  while kill -0 "$BROWSE_PID" 2>/dev/null; do
    if IFS= read -r -t "$RECONCILE_SEC" -u 3 event; then
      burst_start=$(date +%s)
      while IFS= read -r -t "$DEBOUNCE_SEC" -u 3 _next; do
        [ $(( $(date +%s) - burst_start )) -ge "$MAX_BURST_SEC" ] && break
      done
      "$RESOLVE_CMD" >/dev/null 2>&1 || true
      backoff=1
    elif kill -0 "$BROWSE_PID" 2>/dev/null; then
      "$RESOLVE_CMD" >/dev/null 2>&1 || true
    else
      break
    fi
  done
  wait "$BROWSE_PID" 2>/dev/null || true
  exec 3>&-
  BROWSE_PID=""
  sleep "$backoff"
  [ "$backoff" -ge 30 ] || backoff=$((backoff * 2))
  [ "$backoff" -le 30 ] || backoff=30
done
WATCHER_EOF
  chmod 755 "$WATCHER_SCRIPT_CANDIDATE" \
    || exiterr "Could not secure the Bonjour VPN watcher candidate."
  mv -f "$WATCHER_SCRIPT_CANDIDATE" "$WATCHER_SCRIPT" \
    || exiterr "Could not atomically install the Bonjour VPN watcher."
  WATCHER_SCRIPT_CANDIDATE=""

  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop bonjour-vpn-watch.service 2>/dev/null || true
    systemctl disable bonjour-vpn-cache-warm.timer 2>/dev/null || true
    rm -f /etc/systemd/system/bonjour-vpn-cache-warm.timer \
      /etc/systemd/system/bonjour-vpn-cache-warm.service \
      /usr/local/bin/bonjour-vpn-cache-warm

cat > /etc/systemd/system/bonjour-vpn-prepare.service <<'EOF'
[Unit]
Description=Prepare Bonjour VPN DNS endpoints
After=local-fs.target
Before=dnsmasq.service
Wants=dnsmasq.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/bonjour-vpn-resolve --prepare
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/bonjour-vpn-watch.service <<'EOF'
[Unit]
Description=Bonjour VPN mDNS service watcher
After=avahi-daemon.service dnsmasq.service network-online.target
Wants=network-online.target dnsmasq.service
Requires=avahi-daemon.service

[Service]
Type=simple
ExecStart=/usr/local/bin/bonjour-vpn-watch
Restart=always
RestartSec=5
KillMode=control-group
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable bonjour-vpn-prepare.service bonjour-vpn-watch.service >/dev/null 2>&1
  else
cat > /etc/init.d/bonjour-vpn-prepare <<'EOF'
#!/sbin/openrc-run
description="Prepare Bonjour VPN DNS endpoints"

depend() {
  need localmount
  before dnsmasq
}

start() {
  ebegin "Preparing Bonjour VPN DNS endpoints"
  /usr/local/bin/bonjour-vpn-resolve --prepare
  eend $?
}
EOF
    chmod 755 /etc/init.d/bonjour-vpn-prepare
    rc-update add bonjour-vpn-prepare default >/dev/null 2>&1
    CRON_LINE="* * * * * $RESOLVE_SCRIPT >/dev/null 2>&1"
    install_cache_warmer_cron "$CRON_LINE" \
      || exiterr "Could not install the Bonjour VPN cache-warmer cron entry."
  fi
}

start_cache_warmer() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart bonjour-vpn-prepare.service >/dev/null 2>&1 \
      || exiterr "Could not prepare the Bonjour VPN DNS endpoints."
    systemctl restart bonjour-vpn-watch.service >/dev/null 2>&1 \
      || exiterr "Could not start the Bonjour VPN service watcher."
  else
    rc-service bonjour-vpn-prepare start 9>&- >/dev/null 2>&1 \
      || exiterr "Could not prepare the Bonjour VPN DNS endpoints."
    /usr/local/bin/bonjour-vpn-resolve --initial-under-parent-lock 9>&- >/dev/null 2>&1 \
      || exiterr "Could not populate the Bonjour VPN DNS cache."
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
    if loopback_has_ipv4 "$VPN_SERVER_IP"; then
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

  if [ "$HAS_IPV6" = 1 ]; then
    if loopback_has_ipv6 "$VPN_SERVER_IP_IPV6"; then
      echo "  OK: $VPN_SERVER_IP_IPV6 is assigned to loopback"
    else
      echo "  WARNING: $VPN_SERVER_IP_IPV6 not found on loopback"
      VERIFY_PASS=0
    fi
    if ipv6_subnet_route_exists "$VPN_SUBNET_IPV6"; then
      echo "  OK: IPv6 VPN client route active for $VPN_SUBNET_IPV6"
    else
      echo "  WARNING: IPv6 VPN client route missing for $VPN_SUBNET_IPV6"
      VERIFY_PASS=0
    fi
    if ip6tables -t nat -C PREROUTING -s "$VPN_SUBNET_IPV6" -d ff02::fb \
      -p udp --dport 5353 -j DNAT --to-destination "[${VPN_SERVER_IP_IPV6}]:53" 2>/dev/null; then
      echo "  OK: IPv6 mDNS capture rule active for $VPN_SUBNET_IPV6"
    else
      echo "  WARNING: IPv6 mDNS capture rule missing for $VPN_SUBNET_IPV6"
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
    SVC_COUNT=$(grep -c '^ptr-record=_services' /etc/dnsmasq.d/bonjour-vpn-services.conf 2>/dev/null || true)
    INST_COUNT=$(grep -c '^srv-host=' /etc/dnsmasq.d/bonjour-vpn-services.conf 2>/dev/null || true)
    SVC_COUNT=${SVC_COUNT:-0}
    INST_COUNT=${INST_COUNT:-0}
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
    return 1
  fi
  return 0
}

enable_services() {
  bigecho "Enabling and starting services..."
  if [ "$os_type" = "alpine" ]; then
    # Ensure D-Bus is running (required by avahi)
    rc-update add dbus default 9>&- >/dev/null 2>&1 \
      || exiterr "Could not enable D-Bus."
    rc-service dbus start 9>&- >/dev/null 2>&1 \
      || exiterr "Could not start D-Bus."
    rc-update add avahi-daemon default 9>&- >/dev/null 2>&1 \
      || exiterr "Could not enable avahi-daemon."
    rc-service avahi-daemon restart 9>&- >/dev/null 2>&1 \
      || exiterr "Could not restart avahi-daemon."
    rc-update add dnsmasq default 9>&- >/dev/null 2>&1 \
      || exiterr "Could not enable dnsmasq."
    rc-service dnsmasq restart 9>&- >/dev/null 2>&1 \
      || exiterr "Could not restart dnsmasq."
    rc-service ipsec restart 9>&- >/dev/null 2>&1 \
      || exiterr "Could not restart IPsec."
    if [ "$HAS_L2TP" = 1 ]; then
      rc-service xl2tpd restart 9>&- >/dev/null 2>&1 \
        || exiterr "Could not restart xl2tpd."
    fi
  else
    # Ensure D-Bus is running (required by avahi)
    systemctl start dbus >/dev/null 2>&1 \
      || exiterr "Could not start D-Bus."
    systemctl enable avahi-daemon >/dev/null 2>&1 \
      || exiterr "Could not enable avahi-daemon."
    systemctl restart avahi-daemon >/dev/null 2>&1 \
      || exiterr "Could not restart avahi-daemon."
    systemctl enable dnsmasq >/dev/null 2>&1 \
      || exiterr "Could not enable dnsmasq."
    systemctl restart dnsmasq >/dev/null 2>&1 \
      || exiterr "Could not restart dnsmasq."
    mkdir -p /run/pluto
    service ipsec restart >/dev/null 2>&1 \
      || exiterr "Could not restart IPsec."
    if [ "$HAS_L2TP" = 1 ]; then
      service xl2tpd restart >/dev/null 2>&1 \
        || exiterr "Could not restart xl2tpd."
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
  if [ "$HAS_IPV6" = 1 ]; then
cat <<'EOF'

Note: IPv6 DNS is NOT pushed via modecfgdns because Libreswan <= 5.3
  encodes INTERNAL_IP6_DNS with the wrong attribute length (17 bytes
  instead of 16), causing strongSwan clients to reject IKE_AUTH.
  Compatible clients can still query the IPv4 VPN DNS endpoint for
  AAAA records when their profile and application use tunnel DNS.
EOF
  fi
cat <<EOF

Client notes:
  - Existing VPN clients must disconnect and reconnect
  - This is a DNS/DNS-SD bridge, not a general multicast router
  - macOS/iOS: Works when the VPN profile and app use tunnel DNS;
    apps that insist on link-local multicast may not browse remote services
  - Windows: Bonjour-aware application behavior varies
  - Android: .local lookup and service browsing are app-dependent
  - Linux: Behavior depends on the resolver, Avahi config and application

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

main() {
  check_root
  check_os
  check_vpn_modes
  check_ipsec_running
  check_already_configured
  detect_iface
  detect_server_lan_ip
  detect_lan_subnet
  detect_vpn_subnet
  detect_l2tp_subnet
  detect_vpn_ipv6
  check_existing_dns
  parse_upstream_dns
  detect_firewall_backend
  capture_firewall_persistence_ownership
  check_ipv6_firewall_loader
  PREFLIGHT_CONFIG_FINGERPRINT=$(configuration_fingerprint) \
    || exiterr "Could not fingerprint the reviewed preflight configuration."

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
  7. Set modecfgdomains="local, ." to route ALL client DNS queries
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

  acquire_bonjour_lock
  revalidate_after_lock
  capture_service_state
  capture_address_ownership
  save_incomplete_state
  install_packages
  verify_runtime_providers
  configure_avahi
  configure_dnsmasq
  configure_nss
  assign_vpn_server_ip
  install_dnsmasq_config
  update_vpn_dns_config
  update_iptables
  create_cache_warmer
  configure_dnsmasq_resolver_hook
  enable_services
  start_cache_warmer
  verify_setup || exiterr "Bonjour VPN setup verification failed."
  # Promote the recovery marker only after every runtime mutation and
  # verification succeeds. Any earlier failure remains explicitly recoverable
  # by disable_bonjour.sh and blocks a blind second enable attempt.
  save_config_state
  remove_legacy_ipv6_runtime
  release_bonjour_lock
  trap - EXIT HUP INT TERM
  print_summary
}

if [ "${BONJOUR_VPN_LIBRARY_ONLY:-0}" != 1 ]; then
  main "$@"
fi
