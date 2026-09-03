#!/bin/bash
# shellcheck disable=SC2034

set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)
TEST_DIR=$(mktemp -d)
MOCK_BIN="$TEST_DIR/bin"
CALL_LOG="$TEST_DIR/systemctl.log"
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$MOCK_BIN"
: > "$CALL_LOG"

cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/bin/bash
echo "$*" >> "$MOCK_CALL_LOG"
exit 0
EOF
cat > "$MOCK_BIN/nft" <<'EOF'
#!/bin/bash
if [ "${1:-} ${2:-} ${3:-} ${4:-} ${5:-}" = "list chain inet firewalld filter_INPUT" ]; then
  exit 1
fi
if [ "${1:-} ${2:-} ${3:-} ${4:-} ${5:-}" = "list chain inet nftables_svc INPUT" ]; then
  echo 'table inet nftables_svc { chain INPUT { } }'
  exit 0
fi
if [ "${1:-} ${2:-} ${3:-} ${4:-} ${5:-} ${6:-}" = "-a list chain inet nftables_svc INPUT" ]; then
  if [ -f "$MOCK_NFT_RULE_STATE" ]; then
    echo 'ip saddr 10.2.0.0/16 udp dport 53 accept comment "bonjour-vpn:test" # handle 7'
  fi
  exit 0
fi
if [ "${1:-} ${2:-} ${3:-} ${4:-} ${5:-} ${6:-} ${7:-}" = "delete rule inet nftables_svc INPUT handle 7" ]; then
  rm -f "$MOCK_NFT_RULE_STATE"
  echo delete >> "$MOCK_NFT_CALL_LOG"
  exit 0
fi
exit 1
EOF
chmod +x "$MOCK_BIN/systemctl" "$MOCK_BIN/nft"

export BONJOUR_VPN_LIBRARY_ONLY=1
# shellcheck source=../../extras/disable_bonjour.sh
. "$REPO_DIR/extras/disable_bonjour.sh"
export PATH="$MOCK_BIN:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export MOCK_CALL_LOG="$CALL_LOG"
export MOCK_NFT_RULE_STATE="$TEST_DIR/nft-rule-present"
export MOCK_NFT_CALL_LOG="$TEST_DIR/nft.log"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

os_type=ubuntu
HAVE_SAVED_STATE=0
restore_service_states >/dev/null
[ ! -s "$CALL_LOG" ] \
  || fail "missing state changed a service"

HAVE_SAVED_STATE=1
SERVICE_STATE_VERSION_SAVED=2
DNSMASQ_WAS_ENABLED_SAVED=0
DNSMASQ_WAS_ACTIVE_SAVED=0
AVAHI_WAS_ENABLED_SAVED=0
AVAHI_WAS_ACTIVE_SAVED=0
AVAHI_SOCKET_WAS_ENABLED_SAVED=1
AVAHI_SOCKET_WAS_ACTIVE_SAVED=1
DBUS_WAS_ENABLED_SAVED=1
DBUS_WAS_ACTIVE_SAVED=1
restore_service_states >/dev/null

grep -q '^disable dnsmasq.service$' "$CALL_LOG" \
  || fail "dnsmasq enablement was not restored"
grep -q '^stop dnsmasq.service$' "$CALL_LOG" \
  || fail "dnsmasq activity was not restored"
grep -q '^disable avahi-daemon.service$' "$CALL_LOG" \
  || fail "Avahi service enablement was not restored"
grep -q '^stop avahi-daemon.service$' "$CALL_LOG" \
  || fail "Avahi service activity was not restored"
grep -q '^enable avahi-daemon.socket$' "$CALL_LOG" \
  || fail "Avahi socket enablement was not restored"
grep -q '^start avahi-daemon.socket$' "$CALL_LOG" \
  || fail "Avahi socket activity was not restored"
grep -q '^start dbus.service$' "$CALL_LOG" \
  || fail "D-Bus activity was not restored"
if grep -Eq '^(enable|disable) dbus.service$' "$CALL_LOG"; then
  fail "systemd D-Bus enablement was modified"
fi

: > "$MOCK_NFT_RULE_STATE"
: > "$MOCK_NFT_CALL_LOG"
remove_nft_allow_rules || fail "owned nftables rule removal failed"
[ ! -e "$MOCK_NFT_RULE_STATE" ] \
  || fail "owned nftables rule was not removed"
grep -q '^delete$' "$MOCK_NFT_CALL_LOG" \
  || fail "nftables delete was not issued"

STATE_DIR="$TEST_DIR/state"
mkdir -p "$STATE_DIR"
cat > "$STATE_DIR/config" <<'EOF'
VPN_SUBNET_SAVED='10.2.0.0/16'
VPN_SERVER_IP_SAVED='10.2.0.1'
L2TP_SUBNET_SAVED='10.3.0.0/16'
L2TP_SERVER_IP_SAVED='10.3.0.1'
HAS_IPV6_SAVED='1'
VPN_SUBNET_IPV6_SAVED='fd00:2:3:4::/64'
VPN_SERVER_IP_IPV6_SAVED='fd00:2:3:4::1'
EOF
chmod 600 "$STATE_DIR/config"
BONJOUR_STATE_DIR="$STATE_DIR"
BONJOUR_CONFIG_STATE="$STATE_DIR/config"
load_saved_config || fail "current state was not loaded"
[ "$VPN_SUBNET_IPV6" = 'fd00:2:3:4::/64' ] \
  || fail "IPv6 subnet was not loaded from current state"
[ "$VPN_SERVER_IP_IPV6" = 'fd00:2:3:4::1' ] \
  || fail "IPv6 endpoint was not loaded from current state"

echo "PASS: disable fail-safe, service-state restoration, IPv6 state, and owned nftables cleanup"
