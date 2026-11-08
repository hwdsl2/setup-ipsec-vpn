#!/bin/bash
# shellcheck disable=SC2034

set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)
TEST_DIR=$(mktemp -d)
MOCK_BIN="$TEST_DIR/bin"
CALL_LOG="$TEST_DIR/calls.log"
NFT_STATE="$TEST_DIR/nft.state"
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$MOCK_BIN"
: > "$CALL_LOG"
: > "$NFT_STATE"

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
if [ "${1:-}" = "--test" ]; then
  exit "${MOCK_IPTABLES_RESTORE_TEST_STATUS:-0}"
fi
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
if [ "${1:-}" = "--test" ]; then
  exit "${MOCK_IP6TABLES_RESTORE_TEST_STATUS:-0}"
fi
EOF
cat > "$MOCK_BIN/nft" <<'EOF'
#!/bin/bash
set -e
if [ "${1:-}" = "-c" ]; then
  if [ "${MOCK_NFT_CHECK_STATUS:-0}" = masquerade ]; then
    grep -q 'xt target "MASQUERADE"' "${3:-}" && exit 1
    exit 0
  fi
  exit "${MOCK_NFT_CHECK_STATUS:-0}"
fi
if [ "${1:-} ${2:-}" = "list ruleset" ]; then
  if [ "${MOCK_NFT_RULESET_MASQUERADE:-0}" = 1 ]; then
    printf '%s\n' 'table ip nat {' '  chain POSTROUTING {' \
      '    xt target "MASQUERADE"' '  }' '}'
    exit 0
  fi
  cat <<'RULES'
table inet nftables_svc {
  chain INPUT {
    type filter hook input priority filter; policy accept;
  }
}
RULES
  exit 0
fi
if [ "${1:-} ${2:-} ${3:-} ${4:-} ${5:-}" = "list chain inet nftables_svc INPUT" ] \
  || [ "${1:-} ${2:-} ${3:-} ${4:-} ${5:-} ${6:-}" = "-a list chain inet nftables_svc INPUT" ]; then
  echo 'table inet nftables_svc {'
  echo '  chain INPUT {'
  sed 's/^/    /' "$MOCK_NFT_STATE"
  echo '  }'
  echo '}'
  exit 0
fi
if [ "${1:-} ${2:-} ${3:-} ${4:-} ${5:-}" = "list chain inet firewalld filter_INPUT" ]; then
  exit 1
fi
if [ "${1:-} ${2:-} ${3:-} ${4:-} ${5:-}" = "insert rule inet nftables_svc INPUT" ]; then
  shift 5
  next=$(( $(wc -l < "$MOCK_NFT_STATE") + 1 ))
  printf '%s # handle %s\n' "$*" "$next" >> "$MOCK_NFT_STATE"
  echo "nft insert rule inet nftables_svc INPUT $*" >> "$MOCK_CALL_LOG"
  exit 0
fi
if [ "${1:-} ${2:-} ${3:-} ${4:-} ${5:-} ${6:-}" = "delete rule inet nftables_svc INPUT handle" ]; then
  handle=${7:-}
  awk -v h="$handle" '$0 !~ ("# handle " h "$")' "$MOCK_NFT_STATE" > "$MOCK_NFT_STATE.tmp"
  mv "$MOCK_NFT_STATE.tmp" "$MOCK_NFT_STATE"
  echo "nft delete rule inet nftables_svc INPUT handle $handle" >> "$MOCK_CALL_LOG"
  exit 0
fi
echo "nft $*" >> "$MOCK_CALL_LOG"
EOF
chmod +x "$MOCK_BIN"/*

export BONJOUR_VPN_LIBRARY_ONLY=1
export PATH="$MOCK_BIN:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export BONJOUR_VPN_PATH="$PATH"
export MOCK_CALL_LOG="$CALL_LOG"
export MOCK_NFT_STATE="$NFT_STATE"
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

FAILURE_RULES="$TEST_DIR/failure.rules"
printf 'administrator IPv4 baseline\n' > "$FAILURE_RULES"
FIREWALL_PERSIST_FILE="$FAILURE_RULES"
FIREWALL_PERSIST_FILE2=""
HAS_IPV6=0
export MOCK_IPTABLES_RESTORE_TEST_STATUS=1
if persist_firewall; then
  fail "invalid IPv4 firewall candidate passed validation"
fi
unset MOCK_IPTABLES_RESTORE_TEST_STATUS
grep -Fxq 'administrator IPv4 baseline' "$FAILURE_RULES" \
  || fail "failed IPv4 validation changed persistent firewall state"
[ ! -e "${FAILURE_RULES}.bonjour-vpn.candidate" ] \
  || fail "failed IPv4 validation left a candidate file"

FIREWALL_PERSIST_FILE="$TEST_DIR/failure-v4.rules"
FIREWALL_PERSIST6_FILE="$TEST_DIR/failure-v6.rules"
printf 'administrator IPv6 baseline\n' > "$FIREWALL_PERSIST6_FILE"
HAS_IPV6=1
export MOCK_IP6TABLES_RESTORE_TEST_STATUS=1
if persist_firewall; then
  fail "invalid IPv6 firewall candidate passed validation"
fi
unset MOCK_IP6TABLES_RESTORE_TEST_STATUS
grep -Fxq 'administrator IPv6 baseline' "$FIREWALL_PERSIST6_FILE" \
  || fail "failed IPv6 validation changed persistent IPv6 firewall state"
[ ! -e "${FIREWALL_PERSIST6_FILE}.bonjour-vpn.candidate" ] \
  || fail "failed IPv6 validation left a candidate file"

cat > "$FIREWALL_PERSIST6_FILE" <<'EOF'
# Modified by hwdsl2 VPN script
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
COMMIT
EOF
FIREWALL_PERSIST6_FILE2=""
FIREWALL_PERSIST6_FILE_WAS_PRESENT=0
remove_empty_owned_ipv6_persistence \
  || fail "empty Bonjour-owned IPv6 persistence cleanup failed"
[ ! -e "$FIREWALL_PERSIST6_FILE" ] \
  || fail "empty Bonjour-owned IPv6 persistence file was retained"
cat > "$FIREWALL_PERSIST6_FILE" <<'EOF'
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -s fd12::/64 -j ACCEPT
COMMIT
EOF
remove_empty_owned_ipv6_persistence \
  || fail "administrator IPv6 persistence preservation failed"
[ -f "$FIREWALL_PERSIST6_FILE" ] \
  || fail "IPv6 persistence containing an administrator rule was removed"

FIREWALL_BACKEND=nftables
FIREWALL_PERSIST_FILE="$TEST_DIR/nftables.conf"
FIREWALL_PERSIST_FILE2=""
HAS_IPV6=0
persist_firewall || fail "valid nftables snapshot was not persisted"
grep -q '^flush ruleset$' "$FIREWALL_PERSIST_FILE" \
  || fail "nftables persistence is missing flush ruleset"
grep -q '^table inet nftables_svc' "$FIREWALL_PERSIST_FILE" \
  || fail "nftables ruleset was not persisted"
export MOCK_NFT_RULESET_MASQUERADE=1 MOCK_NFT_CHECK_STATUS=masquerade
persist_firewall || fail "nftables MASQUERADE compatibility fallback failed"
unset MOCK_NFT_RULESET_MASQUERADE MOCK_NFT_CHECK_STATUS
grep -q 'masquerade' "$FIREWALL_PERSIST_FILE" \
  && ! grep -q 'xt target "MASQUERADE"' "$FIREWALL_PERSIST_FILE" \
  || fail "nftables MASQUERADE compatibility fallback did not rewrite the candidate"
printf 'administrator nftables baseline\n' > "$FIREWALL_PERSIST_FILE"
export MOCK_NFT_CHECK_STATUS=1
if persist_firewall; then
  fail "invalid nftables candidate passed validation"
fi
unset MOCK_NFT_CHECK_STATUS
grep -Fxq 'administrator nftables baseline' "$FIREWALL_PERSIST_FILE" \
  || fail "failed nftables validation changed persistent firewall state"
[ ! -e "${FIREWALL_PERSIST_FILE}.bonjour-vpn.candidate" ] \
  || fail "failed nftables validation left a candidate file"
add_nft_allow_rules '10.2.0.0/16' \
  || fail "native nftables allow rules were not added"
[ "$(grep -c '^nft insert rule inet nftables_svc INPUT ' "$CALL_LOG")" = 3 ] \
  || fail "native nftables rules did not cover TCP DNS, UDP DNS and mDNS"
grep -Fq 'comment "bonjour-vpn:10.2.0.0/16:udp:53"' "$NFT_STATE" \
  || fail "stateful nftables mock did not retain the inserted rule"
nft list chain inet nftables_svc INPUT \
  | grep -F 'comment "bonjour-vpn:10.2.0.0/16:udp:53"' >/dev/null \
  || fail "stateful nftables mock did not expose the inserted rule"
add_nft_allow_rules '10.2.0.0/16' \
  || fail "native nftables allow rules were not idempotent"
[ "$(grep -c '^nft insert rule inet nftables_svc INPUT ' "$CALL_LOG")" = 3 ] \
  || fail "native nftables idempotency inserted duplicate rules"
add_nft_allow_rules 'fd12:3456:789a:bcde::/64' ip6 \
  || fail "native IPv6 nftables allow rules were not added"
grep -q 'nft insert rule inet nftables_svc INPUT ip6 saddr fd12:3456:789a:bcde::/64' "$CALL_LOG" \
  || fail "native nftables IPv6 rules did not use ip6 source matching"
remove_nft_allow_rules_for_subnet '10.2.0.0/16' \
  || fail "native nftables rules could not be removed"
! grep -Fq 'bonjour-vpn:10.2.0.0/16:' "$NFT_STATE" \
  || fail "native nftables removal left managed IPv4 rules"
grep -Fq 'bonjour-vpn:fd12:3456:789a:bcde::/64:' "$NFT_STATE" \
  || fail "native nftables removal deleted an unrelated IPv6 rule"

cat > "$NFT_STATE" <<'EOF'
ip saddr 10.99.0.0/16 tcp dport 22 accept comment "administrator:ssh" # handle 1
ip saddr 10.2.0.0/16 udp dport 53 accept comment "bonjour-vpn:10.2.0.0/16:udp:53" # handle 2
EOF
(
  export BONJOUR_VPN_LIBRARY_ONLY=1
  # shellcheck source=../../extras/disable_bonjour.sh
  . "$REPO_DIR/extras/disable_bonjour.sh"
  export PATH="$MOCK_BIN:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  remove_nft_allow_rules
) || fail "disable-side nftables cleanup failed"
grep -Fq 'comment "administrator:ssh"' "$NFT_STATE" \
  || fail "disable-side nftables cleanup removed an administrator rule"
! grep -Fq 'bonjour-vpn:' "$NFT_STATE" \
  || fail "disable-side nftables cleanup retained a managed rule"

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

ROLLBACK_TRIGGER_LOG="$TEST_DIR/rollback-triggered"
export ROLLBACK_TRIGGER_LOG
if (
  HAS_IKEV2=0 HAS_XAUTH=0 HAS_L2TP=0 HAS_IPV6=0 SAVED_HAS_IPV6=0
  SAVED_VPN_SUBNET='' SAVED_VPN_SERVER_IP='' VPN_SUBNET='' VPN_SERVER_IP=''
  SAVED_L2TP_SUBNET='' SAVED_L2TP_SERVER_IP='' L2TP_SUBNET='' L2TP_SERVER_IP=''
  SAVED_VPN_SUBNET_IPV6='' SAVED_VPN_SERVER_IP_IPV6=''
  VPN_SUBNET_IPV6='' VPN_SERVER_IP_IPV6=''
  FIREWALL_BACKEND=iptables
  start_firewall_transaction() { FIREWALL_TX_DIR="$TEST_DIR/update-transaction"; }
  persist_firewall() { return 1; }
  rollback_firewall_transaction() {
    printf 'rollback\n' > "$ROLLBACK_TRIGGER_LOG"
    FIREWALL_TX_DIR=""
  }
  update_iptables
) >/dev/null 2>&1; then
  fail "update_iptables ignored persistent firewall validation failure"
fi
grep -Fxq rollback "$ROLLBACK_TRIGGER_LOG" \
  || fail "persistent firewall failure did not trigger transaction rollback"

MIGRATION_LOG="$TEST_DIR/migration.log"
export MIGRATION_LOG
(
  HAS_IKEV2=1 HAS_XAUTH=0 HAS_L2TP=0 HAS_IPV6=0 SAVED_HAS_IPV6=0
  SAVED_VPN_SUBNET='10.10.0.0/24' SAVED_VPN_SERVER_IP='10.10.0.1'
  VPN_SUBNET='10.20.0.0/24' VPN_SERVER_IP='10.20.0.1'
  SAVED_L2TP_SUBNET='' SAVED_L2TP_SERVER_IP='' L2TP_SUBNET='' L2TP_SERVER_IP=''
  SAVED_VPN_SUBNET_IPV6='' SAVED_VPN_SERVER_IP_IPV6=''
  VPN_SUBNET_IPV6='' VPN_SERVER_IP_IPV6=''
  FIREWALL_BACKEND=iptables
  start_firewall_transaction() { FIREWALL_TX_DIR="$TEST_DIR/migration-transaction"; }
  remove_ipv4_bonjour_rules() { printf 'remove %s %s\n' "$1" "$2" >> "$MIGRATION_LOG"; }
  iptables() {
    case " $* " in
      *' -C '*) return 1 ;;
      *' -I '*) printf 'insert %s\n' "$*" >> "$MIGRATION_LOG"; return 0 ;;
      *) return 1 ;;
    esac
  }
  persist_firewall() { return 0; }
  configure_ipv6_firewall_loader() { return 0; }
  finish_firewall_transaction() { FIREWALL_TX_DIR=''; }
  rollback_firewall_transaction() { return 1; }
  update_iptables
) >/dev/null 2>&1 || fail "changed-subnet firewall migration failed"
grep -Fxq 'remove 10.10.0.0/24 10.10.0.1' "$MIGRATION_LOG" \
  || fail "changed-subnet migration did not remove the old rules"
[ "$(grep -c '^insert .*10.20.0.0/24' "$MIGRATION_LOG")" = 4 ] \
  || fail "changed-subnet migration did not install four rules for the new subnet"
grep -Fq -- '--to-destination 10.20.0.1:53' "$MIGRATION_LOG" \
  || fail "changed-subnet migration retained the old DNS endpoint"

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
