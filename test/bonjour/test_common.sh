#!/bin/bash
# shellcheck disable=SC2034,SC2329

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

HAS_IKEV2=0
HAS_XAUTH=0
HAS_L2TP=1
detect_vpn_subnet
assert_eq "$VPN_POOL" "" "L2TP-only mode does not require an IKEv2/XAuth pool"
assert_eq "$VPN_SUBNET" "" "L2TP-only mode leaves the IKEv2/XAuth subnet unset"

ss() {
  printf '%s\n' \
    'Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port' \
    "udp UNCONN 0 0 ${MOCK_DNS_LISTENER} 0.0.0.0:*"
}
pgrep() { return 1; }
VPN_SERVER_IP='10.2.0.1'
L2TP_SERVER_IP='10.1.0.1'
MOCK_DNS_LISTENER='192.168.122.1:53'
check_existing_dns
pass_count=$((pass_count + 1))
MOCK_DNS_LISTENER='0.0.0.0:53'
assert_fails "wildcard DNS listener rejected" check_existing_dns
MOCK_DNS_LISTENER='10.2.0.1:53'
assert_fails "selected endpoint listener rejected" check_existing_dns
MOCK_DNS_LISTENER='127.0.0.1:53'
assert_fails "required loopback DNS listener rejected" check_existing_dns
unset -f ss pgrep

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

echo "PASS: $pass_count common Bonjour configuration tests"
