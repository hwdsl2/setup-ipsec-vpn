#!/bin/bash
# shellcheck disable=SC2034,SC2329

set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

ROOT="$TEST_DIR/root"
STATE_DIR="$ROOT/var/lib/bonjour-vpn"
mkdir -p "$ROOT/etc/dnsmasq.d" "$ROOT/etc/xl2tpd" "$STATE_DIR"
cat > "$ROOT/etc/dnsmasq.d/bonjour-vpn.conf" <<'EOF'
listen-address=127.0.0.1,10.77.0.1,10.78.0.1,fd77:88:99:aa::1
EOF

export BONJOUR_VPN_LIBRARY_ONLY=1
export BONJOUR_VPN_ROOT="$ROOT"
# shellcheck source=../../extras/disable_bonjour.sh
. "$REPO_DIR/extras/disable_bonjour.sh"
BONJOUR_STATE_DIR="$STATE_DIR"
BONJOUR_CONFIG_STATE="$STATE_DIR/config"
BONJOUR_INCOMPLETE_STATE="$STATE_DIR/incomplete"

detect_vpn_server_ip
[ "$HAVE_SAVED_STATE" = 0 ] || fail "stateless fixture unexpectedly loaded saved state"
[ "$VPN_SERVER_IP" = '10.77.0.1' ] || fail "legacy primary IPv4 endpoint was not detected"
[ "$VPN_SUBNET" = '10.77.0.0/24' ] || fail "legacy primary IPv4 subnet was not inferred"
[ "$L2TP_SERVER_IP" = '10.78.0.1' ] || fail "legacy L2TP endpoint was not detected"
[ "$L2TP_SUBNET" = '10.78.0.0/24' ] || fail "legacy L2TP subnet was not inferred"
[ "$VPN_SERVER_IP_IPV6" = 'fd77:88:99:aa::1' ] || fail "legacy IPv6 endpoint was not detected"
[ "$VPN_SUBNET_IPV6" = 'fd77:88:99:aa::/64' ] || fail "legacy IPv6 subnet was not inferred"

run_zero_match_interlock() (
  FIREWALL_TX_DIR='fixture-transaction'
  FIREWALL_BACKEND=iptables
  FIREWALL_PERSIST_FILE="$TEST_DIR/iptables.rules"
  FIREWALL_PERSIST_FILE2=''
  FIREWALL_PERSIST6_FILE=''
  FIREWALL_PERSIST6_FILE2=''
  HAVE_SAVED_STATE=0 HAVE_INCOMPLETE_STATE=0
  VPN_SUBNET='10.77.0.0/24' VPN_SERVER_IP='10.77.0.1'
  L2TP_SUBNET='10.78.0.0/24' L2TP_SERVER_IP='10.78.0.1'
  VPN_SUBNET_IPV6='' VPN_SERVER_IP_IPV6=''
  start_firewall_transaction() { :; }
  remove_ipv4_bonjour_rules() { :; }
  rollback_firewall_transaction() {
    : > "$TEST_DIR/rollback-called"
    FIREWALL_TX_DIR=''
  }
  persist_firewall() { : > "$TEST_DIR/persist-called"; }
  remove_iptables_rules
)

if run_zero_match_interlock >/dev/null 2>&1; then
  fail "stateless disable accepted an inferred subnet without matching rules"
fi
[ -e "$TEST_DIR/rollback-called" ] || fail "zero-match interlock did not roll back"
[ ! -e "$TEST_DIR/persist-called" ] || fail "zero-match interlock persisted a firewall change"

run_positive_match_path() (
  FIREWALL_TX_DIR='fixture-transaction'
  FIREWALL_BACKEND=iptables
  FIREWALL_PERSIST_FILE="$TEST_DIR/iptables.rules"
  FIREWALL_PERSIST_FILE2=''
  FIREWALL_PERSIST6_FILE=''
  FIREWALL_PERSIST6_FILE2=''
  HAVE_SAVED_STATE=0 HAVE_INCOMPLETE_STATE=0
  VPN_SUBNET='10.77.0.0/24' VPN_SERVER_IP='10.77.0.1'
  L2TP_SUBNET='' L2TP_SERVER_IP=''
  VPN_SUBNET_IPV6='' VPN_SERVER_IP_IPV6=''
  start_firewall_transaction() { :; }
  remove_ipv4_bonjour_rules() { FIREWALL_RULES_REMOVED=$((FIREWALL_RULES_REMOVED + 1)); }
  rollback_firewall_transaction() { return 1; }
  persist_firewall() { : > "$TEST_DIR/persist-called"; }
  remove_empty_owned_ipv6_persistence() { :; }
  finish_firewall_transaction() {
    : > "$TEST_DIR/finish-called"
    FIREWALL_TX_DIR=''
  }
  remove_iptables_rules
)

run_positive_match_path >/dev/null 2>&1 \
  || fail "stateless disable rejected a proven matching legacy rule"
[ -e "$TEST_DIR/persist-called" ] || fail "positive legacy path did not persist"
[ -e "$TEST_DIR/finish-called" ] || fail "positive legacy path did not commit"

echo "PASS: stateless legacy detection and zero-match disable safety interlock"
