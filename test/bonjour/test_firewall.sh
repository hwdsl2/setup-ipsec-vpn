#!/bin/bash
# shellcheck disable=SC2034

set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)
TEST_DIR=$(mktemp -d)
MOCK_BIN="$TEST_DIR/bin"
CALL_LOG="$TEST_DIR/calls.log"
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$MOCK_BIN"
: > "$CALL_LOG"

cat > "$MOCK_BIN/iptables-save" <<'EOF'
#!/bin/bash
cat <<'RULES'
*filter
:INPUT ACCEPT [0:0]
-A INPUT -s 10.2.0.0/16 -p udp --dport 53 -j ACCEPT
COMMIT
RULES
EOF
cat > "$MOCK_BIN/iptables-restore" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "--help" ]; then
  echo '--test'
  exit 0
fi
cat > /dev/null
echo "iptables-restore ${1:-live}" >> "$MOCK_CALL_LOG"
EOF
cat > "$MOCK_BIN/ip6tables-save" <<'EOF'
#!/bin/bash
cat <<'RULES'
*filter
:INPUT ACCEPT [0:0]
-A INPUT -s fd12:3456:789a:bcde::/64 -p udp --dport 53 -j ACCEPT
COMMIT
RULES
EOF
cat > "$MOCK_BIN/ip6tables-restore" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "--help" ]; then
  echo '--test'
  exit 0
fi
cat > /dev/null
echo "ip6tables-restore ${1:-live}" >> "$MOCK_CALL_LOG"
EOF
cat > "$MOCK_BIN/nft" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "-c" ]; then
  exit "${MOCK_NFT_CHECK_STATUS:-0}"
fi
if [ "${1:-} ${2:-}" = "list ruleset" ]; then
  cat <<'RULES'
table inet nftables_svc {
  chain INPUT {
    type filter hook input priority filter; policy accept;
  }
}
RULES
  exit 0
fi
if [ "${1:-} ${2:-} ${3:-} ${4:-} ${5:-}" = "list chain inet nftables_svc INPUT" ]; then
  echo 'table inet nftables_svc { chain INPUT { } }'
  exit 0
fi
if [ "${1:-} ${2:-} ${3:-} ${4:-} ${5:-}" = "list chain inet firewalld filter_INPUT" ]; then
  exit 1
fi
echo "nft $*" >> "$MOCK_CALL_LOG"
EOF
chmod +x "$MOCK_BIN"/*

export BONJOUR_VPN_LIBRARY_ONLY=1
export PATH="$MOCK_BIN:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export BONJOUR_VPN_PATH="$PATH"
export MOCK_CALL_LOG="$CALL_LOG"
# shellcheck source=../../extras/enable_bonjour.sh
. "$REPO_DIR/extras/enable_bonjour.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

FIREWALL_BACKEND=iptables
FIREWALL_PERSIST_FILE="$TEST_DIR/iptables.rules"
FIREWALL_PERSIST_FILE2="$TEST_DIR/rules.v4"
FIREWALL_PERSIST6_FILE="$TEST_DIR/ip6tables.rules"
FIREWALL_PERSIST6_FILE2="$TEST_DIR/rules.v6"
HAS_IPV6=1
SAVED_HAS_IPV6=0
persist_firewall || fail "valid iptables snapshot was not persisted"
grep -q '^# Modified by hwdsl2 VPN script$' "$FIREWALL_PERSIST_FILE" \
  || fail "iptables persistence marker missing"
cmp -s "$FIREWALL_PERSIST_FILE" "$FIREWALL_PERSIST_FILE2" \
  || fail "secondary iptables file differs"
grep -q '^iptables-restore --test$' "$CALL_LOG" \
  || fail "iptables candidate was not validated"
grep -q 'fd12:3456:789a:bcde::/64' "$FIREWALL_PERSIST6_FILE" \
  || fail "IPv6 rules were not persisted"
cmp -s "$FIREWALL_PERSIST6_FILE" "$FIREWALL_PERSIST6_FILE2" \
  || fail "secondary ip6tables file differs"
grep -q '^ip6tables-restore --test$' "$CALL_LOG" \
  || fail "ip6tables candidate was not validated"

FIREWALL_BACKEND=nftables
FIREWALL_PERSIST_FILE="$TEST_DIR/nftables.conf"
FIREWALL_PERSIST_FILE2=""
HAS_IPV6=0
persist_firewall || fail "valid nftables snapshot was not persisted"
grep -q '^flush ruleset$' "$FIREWALL_PERSIST_FILE" \
  || fail "nftables persistence is missing flush ruleset"
grep -q '^table inet nftables_svc' "$FIREWALL_PERSIST_FILE" \
  || fail "nftables ruleset was not persisted"
add_nft_allow_rules '10.2.0.0/16' \
  || fail "native nftables allow rules were not added"
[ "$(grep -c '^nft insert rule inet nftables_svc INPUT ' "$CALL_LOG")" = 3 ] \
  || fail "native nftables rules did not cover TCP DNS, UDP DNS and mDNS"
add_nft_allow_rules 'fd12:3456:789a:bcde::/64' ip6 \
  || fail "native IPv6 nftables allow rules were not added"
grep -q 'nft insert rule inet nftables_svc INPUT ip6 saddr fd12:3456:789a:bcde::/64' "$CALL_LOG" \
  || fail "native nftables IPv6 rules did not use ip6 source matching"

FIREWALL_BACKEND=iptables
FIREWALL_PERSIST_FILE="$TEST_DIR/rollback.rules"
FIREWALL_PERSIST_FILE2=""
FIREWALL_PERSIST6_FILE="$TEST_DIR/rollback6.rules"
FIREWALL_PERSIST6_FILE2=""
HAS_IPV6=1
FIREWALL_TX_DIR="$TEST_DIR/transaction"
mkdir -p "$FIREWALL_TX_DIR"
printf 'old firewall\n' > "$FIREWALL_TX_DIR/persist.before"
printf '1\n' > "$FIREWALL_TX_DIR/persist.had"
printf '0\n' > "$FIREWALL_TX_DIR/persist2.had"
printf 'old IPv6 firewall\n' > "$FIREWALL_TX_DIR/persist6.before"
printf '1\n' > "$FIREWALL_TX_DIR/persist6.had"
printf '0\n' > "$FIREWALL_TX_DIR/persist62.had"
printf '*filter\nCOMMIT\n' > "$FIREWALL_TX_DIR/live.v4"
printf '*filter\nCOMMIT\n' > "$FIREWALL_TX_DIR/live.v6"
printf 'new firewall\n' > "$FIREWALL_PERSIST_FILE"
printf 'new IPv6 firewall\n' > "$FIREWALL_PERSIST6_FILE"
rollback_firewall_transaction
grep -q '^old firewall$' "$FIREWALL_PERSIST_FILE" \
  || fail "rollback did not restore the persistent firewall"
[ -z "$FIREWALL_TX_DIR" ] || fail "rollback left a transaction active"
grep -q '^iptables-restore live$' "$CALL_LOG" \
  || fail "rollback did not restore the live firewall"
grep -q '^old IPv6 firewall$' "$FIREWALL_PERSIST6_FILE" \
  || fail "rollback did not restore the persistent IPv6 firewall"
grep -q '^ip6tables-restore live$' "$CALL_LOG" \
  || fail "rollback did not restore the live IPv6 firewall"

LOADER="$TEST_DIR/iptablesload"
cat > "$LOADER" <<'EOF'
#!/bin/sh
iptables-restore < /etc/iptables.rules
exit 0
EOF
chmod 755 "$LOADER"
os_type=ubuntu
FIREWALL_BACKEND=iptables
FIREWALL_PERSIST6_FILE2=""
HAS_IPV6=1
SAVED_HAS_IPV6=0
BONJOUR_VPN_IPTABLES_LOADER="$LOADER"
BONJOUR_VPN_NETFILTER_IP6_PLUGIN="$TEST_DIR/no-netfilter-plugin"
check_ipv6_firewall_loader
[ "$IPV6_FIREWALL_LOADER_NEEDS_UPDATE" = 1 ] \
  || fail "legacy hwdsl2 loader was not marked for IPv6 persistence update"
configure_ipv6_firewall_loader \
  || fail "legacy hwdsl2 loader could not be updated"
grep -Fxq '[ -f /etc/ip6tables.rules ] && ip6tables-restore < /etc/ip6tables.rules' "$LOADER" \
  || fail "IPv6 restore command was not installed in the hwdsl2 loader"
[ -f "$LOADER.bak.bonjour-vpn" ] \
  || fail "hwdsl2 loader backup was not created"
check_ipv6_firewall_loader
[ "$IPV6_FIREWALL_LOADER_NEEDS_UPDATE" = 0 ] \
  || fail "IPv6-capable hwdsl2 loader was not idempotent"

NETFILTER_PLUGIN="$TEST_DIR/25-ip6tables"
: > "$NETFILTER_PLUGIN"
chmod 755 "$NETFILTER_PLUGIN"
FIREWALL_PERSIST6_FILE2=/etc/iptables/rules.v6
BONJOUR_VPN_NETFILTER_IP6_PLUGIN="$NETFILTER_PLUGIN"
BONJOUR_VPN_IPTABLES_LOADER="$TEST_DIR/no-custom-loader"
check_ipv6_firewall_loader
[ -z "$IPV6_FIREWALL_LOADER" ] && [ "$IPV6_FIREWALL_LOADER_NEEDS_UPDATE" = 0 ] \
  || fail "netfilter-persistent IPv6 ownership was not preserved"

cat > "$LOADER" <<'EOF'
#!/bin/sh
iptables-restore < /etc/iptables.rules
custom-firewall-command
exit 0
EOF
chmod 755 "$LOADER"
FIREWALL_PERSIST6_FILE2=""
BONJOUR_VPN_NETFILTER_IP6_PLUGIN="$TEST_DIR/no-netfilter-plugin"
BONJOUR_VPN_IPTABLES_LOADER="$LOADER"
if ( check_ipv6_firewall_loader ) >/dev/null 2>&1; then
  fail "custom hwdsl2 loader was accepted for modification"
fi

echo "PASS: validated firewall persistence and rollback"
