#!/bin/bash
# shellcheck disable=SC1091,SC2034

set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

make_legacy_fixture() {
  local root="$1" state="$2"
  mkdir -p "$root/etc" "$state"
  cat > "$root/etc/rc.local" <<'EOF'
#!/bin/sh
ip addr add 10.61.0.1/32 dev lo 2>/dev/null || true
ip -6 addr add fd61:61::1/128 dev lo 2>/dev/null || true
exit 0
EOF
  cat > "$state/config" <<'EOF'
VPN_SUBNET_SAVED='10.61.0.0/16'
VPN_POOL_SAVED='10.61.0.10-10.61.255.250'
VPN_SERVER_IP_SAVED='10.61.0.1'
L2TP_SUBNET_SAVED='10.62.0.0/16'
L2TP_POOL_SAVED='10.62.0.10-10.62.255.250'
L2TP_SERVER_IP_SAVED='10.62.0.1'
HAS_IKEV2_SAVED='1'
HAS_XAUTH_SAVED='1'
HAS_L2TP_SAVED='1'
DNSMASQ_WAS_INSTALLED_SAVED='1'
DNSMASQ_WAS_ENABLED_SAVED='0'
DNSMASQ_WAS_ACTIVE_SAVED='0'
AVAHI_WAS_ENABLED_SAVED='1'
AVAHI_WAS_ACTIVE_SAVED='1'
DBUS_WAS_ENABLED_SAVED='1'
DBUS_WAS_ACTIVE_SAVED='1'
AVAHI_SOCKET_WAS_ENABLED_SAVED='0'
AVAHI_SOCKET_WAS_ACTIVE_SAVED='0'
SERVICE_STATE_VERSION_SAVED='2'
EOF
  cat > "$state/ipv6-state" <<'EOF'
HAS_IPV6_SAVED='1'
VPN_POOL_IPV6_SAVED='fd61:61::1000-fd61:61::1fff'
VPN_SUBNET_IPV6_SAVED='fd61:61::/64'
VPN_SERVER_IP_IPV6_SAVED='fd61:61::1'
EOF
  : > "$state/ipv6-enabled"
  chmod 600 "$state/config" "$state/ipv6-state" "$state/ipv6-enabled"
}

enable_upgrade_test() (
  local root="$TEST_DIR/enable-root" state="$TEST_DIR/enable-state"
  make_legacy_fixture "$root" "$state"
  export BONJOUR_VPN_LIBRARY_ONLY=1 BONJOUR_VPN_ROOT="$root"
  # shellcheck source=../../extras/enable_bonjour.sh
  . "$REPO_DIR/extras/enable_bonjour.sh"
  BONJOUR_STATE_DIR="$state"
  BONJOUR_CONFIG_STATE="$state/config"
  BONJOUR_INCOMPLETE_STATE="$state/incomplete"
  BONJOUR_VPN_LEGACY_SYNC_PATH="$TEST_DIR/legacy-sync"
  : > "$BONJOUR_VPN_LEGACY_SYNC_PATH"

  load_saved_config
  [ "$SAVED_VPN_SUBNET" = '10.61.0.0/16' ] \
    || fail "legacy IPv4 state was not loaded"
  [ "$SAVED_L2TP_SUBNET" = '10.62.0.0/16' ] \
    || fail "legacy L2TP state was not loaded"
  [ "$SAVED_HAS_IPV6" = 1 ] \
    && [ "$SAVED_VPN_SUBNET_IPV6" = 'fd61:61::/64' ] \
    || fail "split legacy IPv6 state was not merged"

  normalize_saved_address_ownership
  [ "$SAVED_VPN_SERVER_IP_WAS_PRESENT" = 1 ] \
    || fail "legacy IPv4 address was not preserved conservatively"
  [ "$SAVED_L2TP_SERVER_IP_WAS_PRESENT" = 1 ] \
    || fail "legacy pre-existing L2TP address was not preserved"
  [ "$SAVED_VPN_SERVER_IP_IPV6_WAS_PRESENT" = 1 ] \
    || fail "legacy IPv6 address was not preserved conservatively"
  [ "$SAVED_VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT" = 1 ] \
    || fail "legacy IPv6 route was not preserved conservatively"

  capture_service_state
  [ "$DNSMASQ_WAS_INSTALLED:$DNSMASQ_WAS_ENABLED:$DNSMASQ_WAS_ACTIVE" = '1:0:0' ] \
    || fail "version 2 dnsmasq ownership was not preserved"
  [ "$AVAHI_WAS_ENABLED:$AVAHI_WAS_ACTIVE" = '1:1' ] \
    || fail "version 2 Avahi ownership was not preserved"

  VPN_SUBNET='10.61.0.0/16'
  VPN_POOL='10.61.0.10-10.61.255.250'
  VPN_SERVER_IP='10.61.0.1'
  VPN_SERVER_IP_WAS_PRESENT="$SAVED_VPN_SERVER_IP_WAS_PRESENT"
  L2TP_SUBNET='10.62.0.0/16'
  L2TP_POOL_LINE='10.62.0.10-10.62.255.250'
  L2TP_SERVER_IP='10.62.0.1'
  L2TP_SERVER_IP_WAS_PRESENT="$SAVED_L2TP_SERVER_IP_WAS_PRESENT"
  HAS_IKEV2=1 HAS_XAUTH=1 HAS_L2TP=1 HAS_IPV6=1
  VPN_POOL_IPV6='fd61:61::1000-fd61:61::1fff'
  VPN_SUBNET_IPV6='fd61:61::/64'
  VPN_SERVER_IP_IPV6='fd61:61::1'
  VPN_SERVER_IP_IPV6_WAS_PRESENT="$SAVED_VPN_SERVER_IP_IPV6_WAS_PRESENT"
  VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT="$SAVED_VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT"
  save_incomplete_state
  save_config_state

  grep -Fxq "SERVICE_STATE_VERSION_SAVED='3'" "$BONJOUR_CONFIG_STATE" \
    || fail "legacy state was not promoted to version 3"
  grep -Fxq "VPN_SERVER_IP_WAS_PRESENT_SAVED='1'" "$BONJOUR_CONFIG_STATE" \
    || fail "promoted state lost conservative IPv4 ownership"
  grep -Fxq "L2TP_SERVER_IP_WAS_PRESENT_SAVED='1'" "$BONJOUR_CONFIG_STATE" \
    || fail "promoted state lost pre-existing L2TP ownership"
  grep -Fxq "VPN_SERVER_IP_IPV6_WAS_PRESENT_SAVED='1'" "$BONJOUR_CONFIG_STATE" \
    || fail "promoted state lost conservative IPv6 ownership"
  grep -Fxq "VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT_SAVED='1'" "$BONJOUR_CONFIG_STATE" \
    || fail "promoted state lost conservative IPv6 route ownership"

  remove_legacy_ipv6_runtime
  [ ! -e "$state/ipv6-state" ] && [ ! -e "$state/ipv6-enabled" ] \
    && [ ! -e "$BONJOUR_VPN_LEGACY_SYNC_PATH" ] \
    || fail "legacy IPv6 runtime was not retired after state promotion"
)

disable_upgrade_test() (
  local root="$TEST_DIR/disable-root" state="$TEST_DIR/disable-state"
  make_legacy_fixture "$root" "$state"
  export BONJOUR_VPN_LIBRARY_ONLY=1 BONJOUR_VPN_ROOT="$root"
  # shellcheck source=../../extras/disable_bonjour.sh
  . "$REPO_DIR/extras/disable_bonjour.sh"
  BONJOUR_STATE_DIR="$state"
  BONJOUR_CONFIG_STATE="$state/config"
  BONJOUR_INCOMPLETE_STATE="$state/incomplete"

  load_saved_config || fail "disable path did not load legacy state"
  [ "$VPN_SUBNET_IPV6" = 'fd61:61::/64' ] \
    || fail "disable path did not merge split IPv6 state"
  [ "$VPN_SERVER_IP_WAS_PRESENT" = 1 ] \
    || fail "disable path would remove a legacy IPv4 address without proof"
  [ "$L2TP_SERVER_IP_WAS_PRESENT" = 1 ] \
    || fail "disable path would remove a pre-existing L2TP address"
  [ "$VPN_SERVER_IP_IPV6_WAS_PRESENT" = 1 ] \
    || fail "disable path would remove a legacy IPv6 address without proof"
  [ "$VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT" = 1 ] \
    || fail "disable path would remove a legacy IPv6 route without proof"
)

enable_upgrade_test
disable_upgrade_test

echo "PASS: legacy IPv4/L2TP/IPv6 state upgrade and ownership preservation"
