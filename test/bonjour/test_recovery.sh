#!/bin/bash
# shellcheck disable=SC1091,SC2030,SC2031,SC2034,SC2329

set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'chmod -R u+rwX "$TEST_DIR" 2>/dev/null || true; rm -rf "$TEST_DIR"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_fails() {
  local name="$1"
  shift
  if ( "$@" ) >/dev/null 2>&1; then
    fail "$name: unexpectedly succeeded"
  fi
}

enable_state_test() (
  export BONJOUR_VPN_LIBRARY_ONLY=1
  export BONJOUR_VPN_ROOT="$TEST_DIR/enable-root"
  # shellcheck source=../../extras/enable_bonjour.sh
  . "$REPO_DIR/extras/enable_bonjour.sh"
  BONJOUR_STATE_DIR="$TEST_DIR/enable-state"
  BONJOUR_CONFIG_STATE="$BONJOUR_STATE_DIR/config"
  BONJOUR_INCOMPLETE_STATE="$BONJOUR_STATE_DIR/incomplete"
  VPN_SUBNET='10.20.0.0/16'
  VPN_POOL='10.20.0.10-10.20.255.250'
  VPN_SERVER_IP='10.20.0.1'
  VPN_SERVER_IP_WAS_PRESENT=0
  L2TP_SUBNET='10.30.0.0/16'
  L2TP_POOL_LINE='10.30.0.10-10.30.255.250'
  L2TP_SERVER_IP='10.30.0.1'
  L2TP_SERVER_IP_WAS_PRESENT=1
  HAS_IKEV2=1 HAS_XAUTH=1 HAS_L2TP=1 HAS_IPV6=1
  VPN_POOL_IPV6='fd12:20::1000-fd12:20::1fff'
  VPN_SUBNET_IPV6='fd12:20::/64'
  VPN_SERVER_IP_IPV6='fd12:20::1'
  VPN_SERVER_IP_IPV6_WAS_PRESENT=0
  VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT=0
  UPSTREAM_DNS1='1.1.1.1'
  UPSTREAM_DNS2='9.9.9.9'
  DNSMASQ_WAS_INSTALLED=0 DNSMASQ_WAS_ENABLED=0 DNSMASQ_WAS_ACTIVE=0
  AVAHI_WAS_ENABLED=0 AVAHI_WAS_ACTIVE=0 DBUS_WAS_ENABLED=0 DBUS_WAS_ACTIVE=0
  AVAHI_SOCKET_WAS_ENABLED=0 AVAHI_SOCKET_WAS_ACTIVE=0

  save_incomplete_state
  [ -f "$BONJOUR_INCOMPLETE_STATE" ] || fail "incomplete recovery marker was not created"
  assert_fails "second enable while recovery is required" check_already_configured
  [ "$(stat -c '%a' "$BONJOUR_INCOMPLETE_STATE" 2>/dev/null \
    || stat -f '%Lp' "$BONJOUR_INCOMPLETE_STATE")" = 600 ] \
    || fail "incomplete recovery marker is not mode 0600"
  grep -Fxq "VPN_SERVER_IP_WAS_PRESENT_SAVED='0'" "$BONJOUR_INCOMPLETE_STATE" \
    || fail "IPv4 address ownership was not recorded"
  grep -Fxq "L2TP_SERVER_IP_WAS_PRESENT_SAVED='1'" "$BONJOUR_INCOMPLETE_STATE" \
    || fail "pre-existing L2TP address ownership was not recorded"
  grep -Fxq "VPN_SERVER_IP_IPV6_WAS_PRESENT_SAVED='0'" "$BONJOUR_INCOMPLETE_STATE" \
    || fail "IPv6 address ownership was not recorded"
  grep -Fxq "VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT_SAVED='0'" "$BONJOUR_INCOMPLETE_STATE" \
    || fail "IPv6 route ownership was not recorded"
  grep -Fxq "UPSTREAM_DNS1_SAVED='1.1.1.1'" "$BONJOUR_INCOMPLETE_STATE" \
    && grep -Fxq "UPSTREAM_DNS2_SAVED='9.9.9.9'" "$BONJOUR_INCOMPLETE_STATE" \
    || fail "upstream DNS pair was not recorded"

  mkdir -p "$BONJOUR_VPN_ROOT/etc"
  printf 'pre-feature\n' > "$BONJOUR_VPN_ROOT/etc/ipsec.conf.bak.bonjour-vpn"
  printf 'managed-in-fixture\n' > "$BONJOUR_VPN_ROOT/etc/ipsec.conf"
  save_config_state
  [ -f "$BONJOUR_CONFIG_STATE" ] || fail "completed state was not installed"
  [ ! -e "$BONJOUR_INCOMPLETE_STATE" ] \
    || fail "incomplete marker remained after completed state was committed"
  expected_hash=$(sha256sum "$BONJOUR_VPN_ROOT/etc/ipsec.conf" | awk '{print $1}')
  grep -Fxq "_ETC_IPSEC_CONF_MANAGED_HASH='$expected_hash'" "$BONJOUR_CONFIG_STATE" \
    || fail "completed state did not hash the disposable-root managed file"
)

verify_failure_test() (
  export BONJOUR_VPN_LIBRARY_ONLY=1
  . "$REPO_DIR/extras/enable_bonjour.sh"
  HAS_IKEV2=0 HAS_XAUTH=0 HAS_L2TP=0 HAS_IPV6=0
  VPN_SERVER_IP='' VPN_SUBNET='' L2TP_SERVER_IP='' L2TP_SUBNET=''
  VPN_SERVER_IP_IPV6='' VPN_SUBNET_IPV6=''
  pgrep() { return 1; }
  assert_fails "failed setup verification" verify_setup
)

warmer_failure_test() (
  export BONJOUR_VPN_LIBRARY_ONLY=1
  . "$REPO_DIR/extras/enable_bonjour.sh"
  systemctl() { return 1; }
  assert_fails "failed cache-warmer service" start_cache_warmer
)

backup_failure_test() (
  export BONJOUR_VPN_LIBRARY_ONLY=1
  . "$REPO_DIR/extras/enable_bonjour.sh"
  if [ "$(id -u)" = 0 ] && [ -f /proc/version ]; then
    assert_fails "failed configuration backup" conf_bk_bonjour /proc/version
    [ ! -e /proc/version.bak.bonjour-vpn ] \
      || fail "failed backup left a misleading procfs backup file"
  else
    local_dir="$TEST_DIR/backup-failure"
    mkdir -p "$local_dir"
    printf 'original\n' > "$local_dir/config"
    chmod 500 "$local_dir"
    assert_fails "failed configuration backup" conf_bk_bonjour "$local_dir/config"
    [ ! -e "$local_dir/config.bak.bonjour-vpn" ] \
      || fail "failed backup left a misleading backup file"
  fi
)

restore_failure_test() (
  export BONJOUR_VPN_LIBRARY_ONLY=1
  . "$REPO_DIR/extras/disable_bonjour.sh"
  local_dir="$TEST_DIR/restore-failure"
  mkdir -p "$local_dir"
  printf 'original\n' > "$local_dir/config.bak.bonjour-vpn"
  if [ "$(id -u)" = 0 ] && [ -f /proc/version ]; then
    ln -s /proc/version "$local_dir/config"
  else
    printf 'managed\n' > "$local_dir/config"
    chmod 400 "$local_dir/config"
  fi
  assert_fails "failed configuration restore" restore_config_file "$local_dir/config"
  [ -f "$local_dir/config.bak.bonjour-vpn" ] \
    || fail "failed restore deleted the only backup"
)

incomplete_disable_test() (
  export BONJOUR_VPN_LIBRARY_ONLY=1
  . "$REPO_DIR/extras/disable_bonjour.sh"
  BONJOUR_STATE_DIR="$TEST_DIR/disable-state"
  BONJOUR_CONFIG_STATE="$BONJOUR_STATE_DIR/config"
  BONJOUR_INCOMPLETE_STATE="$BONJOUR_STATE_DIR/incomplete"
  mkdir -p "$BONJOUR_STATE_DIR"
  cat > "$BONJOUR_INCOMPLETE_STATE" <<'EOF'
VPN_SUBNET_SAVED='10.40.0.0/16'
VPN_SERVER_IP_SAVED='10.40.0.1'
VPN_SERVER_IP_WAS_PRESENT_SAVED='0'
L2TP_SUBNET_SAVED='10.50.0.0/16'
L2TP_SERVER_IP_SAVED='10.50.0.1'
L2TP_SERVER_IP_WAS_PRESENT_SAVED='1'
HAS_IPV6_SAVED='1'
VPN_SUBNET_IPV6_SAVED='fd12:40::/64'
VPN_SERVER_IP_IPV6_SAVED='fd12:40::1'
VPN_SERVER_IP_IPV6_WAS_PRESENT_SAVED='0'
VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT_SAVED='0'
SERVICE_STATE_VERSION_SAVED='3'
EOF
  chmod 600 "$BONJOUR_INCOMPLETE_STATE"
  load_saved_config || fail "incomplete recovery state was not loaded"
  [ "$HAVE_INCOMPLETE_STATE" = 1 ] || fail "incomplete state was not identified"
  [ "$VPN_SUBNET" = '10.40.0.0/16' ] || fail "incomplete IPv4 subnet was not loaded"
  [ "$VPN_SUBNET_IPV6" = 'fd12:40::/64' ] || fail "incomplete IPv6 subnet was not loaded"
  [ "$VPN_SERVER_IP_WAS_PRESENT" = 0 ] || fail "incomplete ownership was not loaded"
  [ "$VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT" = 0 ] \
    || fail "incomplete IPv6 route ownership was not loaded"
)

incomplete_drift_recovery_test() (
  export BONJOUR_VPN_LIBRARY_ONLY=1
  . "$REPO_DIR/extras/disable_bonjour.sh"
  drift_root="$TEST_DIR/incomplete-drift-root"
  mkdir -p "$drift_root/etc"
  printf 'partial-reconfigure\n' > "$drift_root/etc/ipsec.conf"
  printf 'original\n' > "$drift_root/etc/ipsec.conf.bak.bonjour-vpn"
  BONJOUR_VPN_ROOT="$drift_root"
  BONJOUR_CONFIG_STATE="$TEST_DIR/incomplete-drift-config"
  BONJOUR_INCOMPLETE_STATE="$TEST_DIR/incomplete-drift-marker"
  printf "_ETC_IPSEC_CONF_MANAGED_HASH='%s'\n" \
    '0000000000000000000000000000000000000000000000000000000000000000' \
    > "$BONJOUR_CONFIG_STATE"
  : > "$BONJOUR_INCOMPLETE_STATE"
  HAVE_INCOMPLETE_STATE=1
  check_restore_drift >/dev/null 2>&1 \
    || fail "incomplete reconfigure could not enter disable recovery"
  rm -f "$BONJOUR_INCOMPLETE_STATE"
  check_bonjour_configured \
    || fail "tail-interrupted disable could not resume from completed state"
)

enable_state_test
verify_failure_test
warmer_failure_test
backup_failure_test
restore_failure_test
incomplete_disable_test
incomplete_drift_recovery_test

echo "PASS: interrupted-enable recovery, address ownership, backup retention, and failure propagation"
