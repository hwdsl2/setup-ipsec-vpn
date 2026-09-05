#!/bin/bash
# shellcheck disable=SC2030,SC2031,SC2034,SC2329

set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export BONJOUR_VPN_LIBRARY_ONLY=1
# shellcheck source=../../extras/enable_bonjour.sh
. "$REPO_DIR/extras/enable_bonjour.sh"

pass_count=0

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_eq() {
  local actual="$1" expected="$2" name="$3"
  [ "$actual" = "$expected" ] || fail "$name: expected '$expected', got '$actual'"
  pass_count=$((pass_count + 1))
}

assert_fails() {
  local name="$1"
  shift
  if ( "$@" ) >/dev/null 2>&1; then
    fail "$name: command unexpectedly succeeded"
  fi
  pass_count=$((pass_count + 1))
}

IPSEC_CONF="$TEST_DIR/ipsec.conf"
cat > "$IPSEC_CONF" <<'EOF'
config setup
  virtual-private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12,%v4:!10.1.0.0/16,%v4:!10.2.0.0/16
EOF

assert_eq "$(extract_ipv4_pool 'rightaddresspool=10.2.0.10-10.2.254.254')" \
  "10.2.0.10-10.2.254.254" "IPv4-only pool"
assert_eq "$(extract_ipv4_pool 'rightaddresspool=fddd:1:2:3::100-fddd:1:2:3::1ff,10.2.0.10-10.2.254.254')" \
  "10.2.0.10-10.2.254.254" "IPv6-first pool"
assert_eq "$(subnet_for_pool '10.2.0.10-10.2.254.254' '')" \
  "10.2.0.0/16" "custom /16 subnet"
assert_eq "$(subnet_for_pool '10.1.0.10-10.1.254.254' '')" \
  "10.1.0.0/16" "second custom /16 subnet"
assert_eq "$(subnet_for_pool '192.168.43.10-192.168.43.250' '192.168.43.0/24')" \
  "192.168.43.0/24" "documented fallback subnet"
assert_fails "ambiguous custom pool" subnet_for_pool \
  "172.20.0.10-172.20.1.250" "192.168.43.0/24"
assert_eq "$(select_vpn_dns_ip '10.2.0.0/16' '10.2.0.10-10.2.254.254')" \
  "10.2.0.1" "deterministic endpoint"
assert_eq "$(select_vpn_dns_ip '10.2.0.0/16' '10.2.0.1-10.2.0.254')" \
  "10.2.0.255" "endpoint after a pool that starts at the first host"
assert_eq "$(select_vpn_dns_ip '10.2.0.0/16' '10.2.0.10-10.2.254.254' '10.2.0.2')" \
  "10.2.0.2" "persisted endpoint reuse"
assert_fails "pool endpoint rejected" pool_contains_ip \
  "10.2.0.10-10.2.254.254" "10.2.0.2"
assert_fails "reversed pool rejected" select_vpn_dns_ip \
  "10.2.0.0/16" "10.2.0.254-10.2.0.10"
assert_eq "$(canonical_ipv6 'fd12:3456::1')" \
  'fd12:3456:0000:0000:0000:0000:0000:0001' "IPv6 canonical expansion"
assert_eq "$(select_vpn_dns_ipv6 'fd12:3456:789a:bcde::/64' \
  'fd12:3456:789a:bcde::1-fd12:3456:789a:bcde::ff')" \
  'fd12:3456:789a:bcde::100' "IPv6 endpoint outside low client pool"
assert_eq "$(select_vpn_dns_ipv6 'fd12:3456:789a:bcde::/64' \
  'fd12:3456:789a:bcde::1000-fd12:3456:789a:bcde::1fff' \
  'fd12:3456:789a:bcde::2')" \
  'fd12:3456:789a:bcde::2' "persisted IPv6 endpoint reuse"
assert_fails "IPv6 endpoint in client pool rejected" ipv6_in_pool \
  'fd12:3456:789a:bcde::1000-fd12:3456:789a:bcde::1fff' \
  'fd12:3456:789a:bcde::2'
assert_fails "reversed IPv6 pool rejected" select_vpn_dns_ipv6 \
  'fd12:3456:789a:bcde::/64' \
  'fd12:3456:789a:bcde::1fff-fd12:3456:789a:bcde::1000'

RC_LOCAL_TEST="$TEST_DIR/rc.local"
cat > "$RC_LOCAL_TEST" <<'EOF'
#!/bin/sh
if test -f /stop-early; then
  exit 0
fi

exit 0

# trailing administrator comment
EOF
append_before_terminal_exit "$RC_LOCAL_TEST" '# managed marker'
append_before_terminal_exit "$RC_LOCAL_TEST" 'ip addr add 10.2.0.1/32 dev lo'
[ "$(grep -Ec '^[[:space:]]*exit[[:space:]]+0$' "$RC_LOCAL_TEST")" = 2 ] \
  || fail "rc.local helper deleted or duplicated an existing exit"
[ "$(grep -nE '^(ip addr add 10\.2\.0\.1/32 dev lo|exit 0)$' "$RC_LOCAL_TEST" \
    | tail -n 2 | cut -d: -f2-)" = $'ip addr add 10.2.0.1/32 dev lo\nexit 0' ] \
  || fail "rc.local helper did not insert before only the terminal exit"
pass_count=$((pass_count + 1))

RC_OWNERSHIP_TEST="$TEST_DIR/rc-local-ownership"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$RC_OWNERSHIP_TEST"
ensure_rc_local_managed_line "$RC_OWNERSHIP_TEST" \
  'ip addr add 10.1.0.1/32 dev lo 2>/dev/null'
[ -f "$RC_OWNERSHIP_TEST.bak.bonjour-vpn" ] \
  || fail "L2TP-only rc.local ownership did not create a backup"
ensure_rc_local_managed_line "$RC_OWNERSHIP_TEST" \
  'ip addr add 10.2.0.1/32 dev lo 2>/dev/null'
[ "$(grep -Fc '# Added by enable_bonjour.sh' "$RC_OWNERSHIP_TEST")" = 1 ] \
  || fail "rc.local ownership marker was duplicated"
grep -Fxq 'ip addr add 10.2.0.1/32 dev lo 2>/dev/null' "$RC_OWNERSHIP_TEST" \
  || fail "changed VPN endpoint was not persisted beside an existing marker"
pass_count=$((pass_count + 3))

(
  race_root="$TEST_DIR/post-lock-root"
  mkdir -p "$race_root/etc/ipsec.d" "$race_root/etc/xl2tpd" \
    "$race_root/etc/ppp" "$race_root/etc/dnsmasq.d" "$race_root/var/lib/bonjour-vpn"
  BONJOUR_VPN_ROOT="$race_root"
  BONJOUR_STATE_DIR="$race_root/var/lib/bonjour-vpn"
  BONJOUR_CONFIG_STATE="$BONJOUR_STATE_DIR/config"
  BONJOUR_INCOMPLETE_STATE="$BONJOUR_STATE_DIR/incomplete"
  IKEV2_CONF="$race_root/etc/ipsec.d/ikev2.conf"
  IPSEC_CONF="$race_root/etc/ipsec.conf"
  XL2TPD_CONF="$race_root/etc/xl2tpd/xl2tpd.conf"
  PPP_OPTIONS="$race_root/etc/ppp/options.xl2tpd"
  ss() {
    printf '%s\n' 'Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port'
  }
  pgrep() { return 1; }
  printf 'stable\n' > "$IKEV2_CONF"
  RECONFIGURE_CONFIRMED=0
  PREFLIGHT_CONFIG_FINGERPRINT=$(configuration_fingerprint)
  revalidate_after_lock
  : > "$BONJOUR_INCOMPLETE_STATE"
  assert_fails "post-lock incomplete marker rejected" revalidate_after_lock
  rm -f "$BONJOUR_INCOMPLETE_STATE"
  printf 'changed\n' >> "$IKEV2_CONF"
  assert_fails "post-lock configuration race rejected" revalidate_after_lock
)
pass_count=$((pass_count + 3))

HAS_IKEV2=0
HAS_XAUTH=0
HAS_L2TP=1
detect_vpn_subnet
assert_eq "$VPN_POOL" "" "L2TP-only mode does not require an IKEv2/XAuth pool"
assert_eq "$VPN_SUBNET" "" "L2TP-only mode leaves the IKEv2/XAuth subnet unset"

(
  IKEV2_CONF="$TEST_DIR/ikev2-dns.conf"
  HAS_IKEV2=1 HAS_XAUTH=0 HAS_L2TP=0
  VPN_SERVER_IP='10.2.0.1'
  L2TP_SERVER_IP=''
  SAVED_UPSTREAM_DNS1='1.1.1.1'
  SAVED_UPSTREAM_DNS2='9.9.9.9'

  printf '%s\n' '  modecfgdns="10.2.0.1 1.1.1.1"' > "$IKEV2_CONF"
  parse_upstream_dns
  [ "$UPSTREAM_DNS1:$UPSTREAM_DNS2" = '1.1.1.1:9.9.9.9' ] \
    || fail "managed DNS line did not recover the persisted upstream pair"

  printf '%s\n' '  modecfgdns="10.2.0.1 1.1.1.1 8.8.8.8"' > "$IKEV2_CONF"
  parse_upstream_dns
  [ "$UPSTREAM_DNS1:$UPSTREAM_DNS2" = '1.1.1.1:8.8.8.8' ] \
    || fail "complete administrator DNS pair did not override persisted state"

  SAVED_UPSTREAM_DNS1=''
  SAVED_UPSTREAM_DNS2=''
  printf '%s\n' '  modecfgdns="1.1.1.1"' > "$IKEV2_CONF"
  parse_upstream_dns
  [ "$UPSTREAM_DNS1:$UPSTREAM_DNS2" = '1.1.1.1:8.8.4.4' ] \
    || fail "single unmanaged upstream did not receive the documented fallback"

  SAVED_VPN_SERVER_IP='10.9.0.1'
  SAVED_L2TP_SERVER_IP='10.8.0.1'
  printf '%s\n' '  modecfgdns="10.9.0.1 1.1.1.1"' > "$IKEV2_CONF"
  parse_upstream_dns
  [ "$UPSTREAM_DNS1:$UPSTREAM_DNS2" = '1.1.1.1:8.8.4.4' ] \
    || fail "retired managed endpoint was recycled as an upstream DNS server"
)
pass_count=$((pass_count + 4))

(
  drift_root="$TEST_DIR/reconfigure-drift-root"
  mkdir -p "$drift_root/etc"
  printf 'managed\n' > "$drift_root/etc/ipsec.conf"
  printf 'original\n' > "$drift_root/etc/ipsec.conf.bak.bonjour-vpn"
  managed_hash=$(sha256sum "$drift_root/etc/ipsec.conf" | awk '{print $1}')
  BONJOUR_VPN_ROOT="$drift_root"
  BONJOUR_CONFIG_STATE="$TEST_DIR/reconfigure-drift-state"
  printf "_ETC_IPSEC_CONF_MANAGED_HASH='%s'\n" "$managed_hash" \
    > "$BONJOUR_CONFIG_STATE"
  check_reconfigure_drift
  printf 'administrator-change\n' > "$drift_root/etc/ipsec.conf"
  assert_fails "reconfigure drift laundering rejected" check_reconfigure_drift
)
pass_count=$((pass_count + 2))

(
  drift_root="$TEST_DIR/ikev2-pool-drift-root"
  mkdir -p "$drift_root/etc/ipsec.d"
  cat > "$drift_root/etc/ipsec.d/ikev2.conf.bak.bonjour-vpn" <<'EOF'
conn ikev2-cp
  rightaddresspool=10.20.0.10-10.20.0.250,fd20::1000-fd20::1fff
  modecfgdns="1.1.1.1 8.8.8.8"
EOF
  cat > "$drift_root/etc/ipsec.d/ikev2.conf" <<'EOF'
conn ikev2-cp
  rightaddresspool=10.20.0.10-10.20.0.250
  modecfgdns="10.20.0.1 1.1.1.1"
  modecfgdomains="local, ."
EOF
  BONJOUR_VPN_ROOT="$drift_root"
  BONJOUR_CONFIG_STATE="$TEST_DIR/ikev2-pool-drift-state"
  printf "_ETC_IPSEC_D_IKEV2_CONF_MANAGED_HASH='stale-after-pool-change'\n" \
    > "$BONJOUR_CONFIG_STATE"
  check_reconfigure_drift >/dev/null
  grep -Fxq '  rightaddresspool=10.20.0.10-10.20.0.250' \
    "$drift_root/etc/ipsec.d/ikev2.conf.bak.bonjour-vpn" \
    || fail "accepted IKEv2 pool change was not carried into the uninstall baseline"
  grep -Fxq '  modecfgdns="1.1.1.1 8.8.8.8"' \
    "$drift_root/etc/ipsec.d/ikev2.conf.bak.bonjour-vpn" \
    || fail "IKEv2 pool rebase copied a feature-managed DNS value into the baseline"
)
pass_count=$((pass_count + 1))

ss() {
  printf '%s\n' \
    'Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port' \
    "udp UNCONN 0 0 ${MOCK_DNS_LISTENER} 0.0.0.0:*"
}
pgrep() { return 1; }
check_systemd_resolved() { RESOLVED_ACTIVE=0; }
VPN_SERVER_IP='10.2.0.1'
L2TP_SERVER_IP='10.1.0.1'
VPN_SERVER_IP_IPV6=''
MOCK_DNS_LISTENER='192.168.122.1:53'
check_existing_dns
pass_count=$((pass_count + 1))
MOCK_DNS_LISTENER='0.0.0.0:53'
assert_fails "wildcard DNS listener rejected" check_existing_dns
MOCK_DNS_LISTENER='10.2.0.1:53'
assert_fails "selected endpoint listener rejected" check_existing_dns
MOCK_DNS_LISTENER='127.0.0.1:53'
assert_fails "required loopback DNS listener rejected" check_existing_dns
VPN_SERVER_IP_IPV6='FD12:3456:789A:BCDE:0:0:0:1'
MOCK_DNS_LISTENER='[fd12:3456:789a:bcde::1]:53'
assert_fails "equivalent compressed IPv6 DNS listener rejected" check_existing_dns
VPN_SERVER_IP_IPV6=''
unset -f ss pgrep check_systemd_resolved

BONJOUR_STATE_DIR="$TEST_DIR/legacy-state"
BONJOUR_VPN_LEGACY_SYNC_PATH="$TEST_DIR/bonjour-vpn-ipv6-sync"
mkdir -p "$BONJOUR_STATE_DIR"
: > "$BONJOUR_STATE_DIR/config"
: > "$BONJOUR_STATE_DIR/ipv6-state"
: > "$BONJOUR_STATE_DIR/ipv6-enabled"
: > "$BONJOUR_VPN_LEGACY_SYNC_PATH"
remove_legacy_ipv6_runtime
[ -f "$BONJOUR_STATE_DIR/config" ] \
  || fail "consolidated state was removed with legacy IPv6 state"
[ ! -e "$BONJOUR_STATE_DIR/ipv6-state" ] \
  || fail "legacy IPv6 state was not removed"
[ ! -e "$BONJOUR_STATE_DIR/ipv6-enabled" ] \
  || fail "legacy IPv6 marker was not removed"
[ ! -e "$BONJOUR_VPN_LEGACY_SYNC_PATH" ] \
  || fail "legacy IPv6 sync binary was not removed"
pass_count=$((pass_count + 1))

SERVICE_STATE_DIR="$TEST_DIR/service-state"
mkdir -p "$SERVICE_STATE_DIR"
(
  BONJOUR_CONFIG_STATE="$SERVICE_STATE_DIR/config"
  printf "VPN_SUBNET_SAVED='10.2.0.0/16'\n" > "$BONJOUR_CONFIG_STATE"
  dnsmasq() { :; }
  systemctl() {
    case "$1" in
      is-enabled|is-active) return 0 ;;
    esac
    return 1
  }
  capture_service_state >/dev/null
  for captured in DNSMASQ_WAS_INSTALLED DNSMASQ_WAS_ENABLED DNSMASQ_WAS_ACTIVE \
    AVAHI_WAS_ENABLED AVAHI_WAS_ACTIVE DBUS_WAS_ENABLED DBUS_WAS_ACTIVE \
    AVAHI_SOCKET_WAS_ENABLED AVAHI_SOCKET_WAS_ACTIVE; do
    [ "${!captured}" = 1 ] || fail "legacy state did not capture current service ownership: $captured"
  done

  cat > "$BONJOUR_CONFIG_STATE" <<'EOF'
SERVICE_STATE_VERSION_SAVED='2'
DNSMASQ_WAS_INSTALLED_SAVED='0'
DNSMASQ_WAS_ENABLED_SAVED='0'
DNSMASQ_WAS_ACTIVE_SAVED='0'
AVAHI_WAS_ENABLED_SAVED='0'
AVAHI_WAS_ACTIVE_SAVED='0'
DBUS_WAS_ENABLED_SAVED='0'
DBUS_WAS_ACTIVE_SAVED='0'
AVAHI_SOCKET_WAS_ENABLED_SAVED='0'
AVAHI_SOCKET_WAS_ACTIVE_SAVED='0'
EOF
  capture_service_state
  for captured in DNSMASQ_WAS_INSTALLED DNSMASQ_WAS_ENABLED DNSMASQ_WAS_ACTIVE \
    AVAHI_WAS_ENABLED AVAHI_WAS_ACTIVE DBUS_WAS_ENABLED DBUS_WAS_ACTIVE \
    AVAHI_SOCKET_WAS_ENABLED AVAHI_SOCKET_WAS_ACTIVE; do
    [ "${!captured}" = 0 ] || fail "versioned state was not preserved: $captured"
  done
)
pass_count=$((pass_count + 2))

PACKAGE_TEST_DIR="$TEST_DIR/packages"
PACKAGE_MOCK_BIN="$PACKAGE_TEST_DIR/bin"
PACKAGE_CALL_LOG="$PACKAGE_TEST_DIR/calls.log"
mkdir -p "$PACKAGE_MOCK_BIN"
: > "$PACKAGE_CALL_LOG"
cat > "$PACKAGE_MOCK_BIN/dpkg-query" <<'EOF'
#!/bin/sh
if [ "${MOCK_PACKAGES_READY:-0}" = 1 ]; then
  printf 'install ok installed'
  exit 0
fi
exit 1
EOF
cat > "$PACKAGE_MOCK_BIN/apt-get" <<'EOF'
#!/bin/sh
if [ -e /proc/self/fd/9 ]; then
  printf 'FD9_OPEN\n' >> "$PACKAGE_CALL_LOG"
fi
printf '%s\n' "$*" >> "$PACKAGE_CALL_LOG"
exit 0
EOF
chmod +x "$PACKAGE_MOCK_BIN"/*
os_type=ubuntu
(
  export PATH="$PACKAGE_MOCK_BIN:/usr/bin:/bin"
  export PACKAGE_CALL_LOG MOCK_PACKAGES_READY=1
  install_packages >/dev/null
)
[ ! -s "$PACKAGE_CALL_LOG" ] \
  || fail "package manager ran even though all required packages were installed"
pass_count=$((pass_count + 1))

(
  export PATH="$PACKAGE_MOCK_BIN:/usr/bin:/bin"
  export PACKAGE_CALL_LOG MOCK_PACKAGES_READY=0
  exec 9>"$PACKAGE_TEST_DIR/operation.lock"
  install_packages >/dev/null
)
[ "$(wc -l < "$PACKAGE_CALL_LOG" | tr -d ' ')" = 2 ] \
  || fail "incomplete package set did not trigger package update and install"
if grep -Fxq 'FD9_OPEN' "$PACKAGE_CALL_LOG"; then
  fail "package-manager child inherited the Bonjour operation lock"
fi
pass_count=$((pass_count + 1))

# shellcheck disable=SC2015,SC2016
grep -Fq 'cat > "$RESOLVE_SCRIPT_CANDIDATE"' "$REPO_DIR/extras/enable_bonjour.sh" \
  && grep -Fq 'mv -f "$RESOLVE_SCRIPT_CANDIDATE" "$RESOLVE_SCRIPT"' \
    "$REPO_DIR/extras/enable_bonjour.sh" \
  && grep -Fq 'cat > "$WATCHER_SCRIPT_CANDIDATE"' "$REPO_DIR/extras/enable_bonjour.sh" \
  && grep -Fq 'mv -f "$WATCHER_SCRIPT_CANDIDATE" "$WATCHER_SCRIPT"' \
    "$REPO_DIR/extras/enable_bonjour.sh" \
  || fail "runtime helpers are not installed through atomic same-directory candidates"
pass_count=$((pass_count + 1))

echo "PASS: $pass_count common Bonjour configuration tests"
