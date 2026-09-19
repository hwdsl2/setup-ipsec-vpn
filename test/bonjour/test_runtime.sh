#!/bin/bash

set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)
TEST_DIR=$(mktemp -d)
ROOT_DIR="$TEST_DIR/root"
MOCK_BIN="$TEST_DIR/bin"
LOG_FILE="$TEST_DIR/service.log"
BROWSE_FILE="$TEST_DIR/browse.out"
ACTIVE_FILE="$TEST_DIR/dnsmasq.active"
ROUTE_FILE="$TEST_DIR/ipv6-route.active"
RESOLVER="$TEST_DIR/bonjour-vpn-resolve"
REAL_FLOCK=$(command -v flock 2>/dev/null || true)
cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$ROOT_DIR/etc/dnsmasq.d" "$ROOT_DIR/var/lib/bonjour-vpn" \
  "$ROOT_DIR/run" "$MOCK_BIN"

awk '/^cat > "\$RESOLVE_SCRIPT(_CANDIDATE)?" <<'\''RESOLVE_EOF'\''/{copy=1;next} \
     /^RESOLVE_EOF$/{copy=0} copy{print}' \
  "$REPO_DIR/extras/enable_bonjour.sh" > "$RESOLVER"
chmod +x "$RESOLVER"

cat > "$ROOT_DIR/var/lib/bonjour-vpn/config" <<'EOF'
VPN_SERVER_IP_SAVED='10.2.0.1'
L2TP_SERVER_IP_SAVED='10.1.0.1'
HAS_IPV6_SAVED='1'
VPN_SUBNET_IPV6_SAVED='fd12:3456:789a:bcde::/64'
VPN_SERVER_IP_IPV6_SAVED='FD12:3456:789A:BCDE:0:0:0:1'
EOF
cat > "$ROOT_DIR/etc/dnsmasq.conf" <<EOF
conf-dir=$ROOT_DIR/etc/dnsmasq.d,*.conf
EOF
cat > "$ROOT_DIR/etc/dnsmasq.d/bonjour-vpn.conf" <<EOF
listen-address=10.2.0.1,10.1.0.1
bind-interfaces
addn-hosts=$ROOT_DIR/etc/bonjour-vpn-hosts
EOF
: > "$ROOT_DIR/etc/bonjour-vpn-hosts"
: > "$LOG_FILE"
: > "$ACTIVE_FILE"

cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/bin/bash
case "$1" in
  is-active) [ -f "$MOCK_ACTIVE_FILE" ] ;;
  reload)
    [ "${MOCK_RELOAD_STATUS:-0}" = 0 ] || exit "$MOCK_RELOAD_STATUS"
    echo reload >> "$MOCK_LOG_FILE"
    ;;
  restart) echo restart >> "$MOCK_LOG_FILE"; : > "$MOCK_ACTIVE_FILE" ;;
  start) echo start >> "$MOCK_LOG_FILE"; : > "$MOCK_ACTIVE_FILE" ;;
  reset-failed) : ;;
  *) exit 1 ;;
esac
EOF
cat > "$MOCK_BIN/pgrep" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$MOCK_BIN/ip" <<'EOF'
#!/bin/bash
if [ "$1 $2 $3 $4" = "-4 addr show dev" ]; then
  echo '    inet 10.2.0.1/32 scope host lo'
  echo '    inet 10.1.0.1/32 scope host lo'
  exit 0
fi
if [ "$1 $2 $3 $4" = "-6 -o addr show" ]; then
  echo '1: lo    inet6 fd12:3456:789a:bcde::1/128 scope host'
  exit 0
fi
if [ "$1 $2 $3 $4" = "-6 addr show dev" ]; then
  echo '    inet6 fd12:3456:789a:bcde::1/128 scope host'
  exit 0
fi
if [ "$1 $2 $3" = "-6 route show" ]; then
  [ -f "$MOCK_ROUTE_FILE" ] && echo 'fd12:3456:789a:bcde::/64 dev lo'
  exit 0
fi
if [ "$1 $2 $3" = "-6 route add" ]; then
  : > "$MOCK_ROUTE_FILE"
  echo "ip $*" >> "$MOCK_LOG_FILE"
  exit 0
fi
echo "ip $*" >> "$MOCK_LOG_FILE"
EOF
cat > "$MOCK_BIN/avahi-browse" <<'EOF'
#!/bin/bash
cat "$MOCK_BROWSE_FILE"
exit "${MOCK_BROWSE_STATUS:-0}"
EOF
cat > "$MOCK_BIN/timeout" <<'EOF'
#!/bin/bash
shift
exec "$@"
EOF
cat > "$MOCK_BIN/dnsmasq" <<'EOF'
#!/bin/bash
echo test >> "$MOCK_LOG_FILE"
exit "${MOCK_DNSMASQ_STATUS:-0}"
EOF
cat > "$MOCK_BIN/pkill" <<'EOF'
#!/bin/bash
echo hup >> "$MOCK_LOG_FILE"
EOF
cat > "$MOCK_BIN/flock" <<'EOF'
#!/bin/bash
exit "${MOCK_FLOCK_STATUS:-0}"
EOF
chmod +x "$MOCK_BIN"/*

export BONJOUR_VPN_ROOT="$ROOT_DIR"
export BONJOUR_VPN_PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
export MOCK_LOG_FILE="$LOG_FILE"
export MOCK_BROWSE_FILE="$BROWSE_FILE"
export MOCK_ACTIVE_FILE="$ACTIVE_FILE"
export MOCK_ROUTE_FILE="$ROUTE_FILE"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

count_action() {
  grep -c "^$1$" "$LOG_FILE" 2>/dev/null || true
}

# Initial enablement deliberately has only a recovery state until service
# startup and verification finish. The prepare path must work in that window.
mv "$ROOT_DIR/var/lib/bonjour-vpn/config" \
  "$ROOT_DIR/var/lib/bonjour-vpn/incomplete"
cat > "$ROOT_DIR/var/lib/bonjour-vpn/config" <<'EOF'
VPN_SERVER_IP_SAVED='10.99.0.1'
L2TP_SERVER_IP_SAVED='10.99.0.2'
HAS_IPV6_SAVED='1'
VPN_SUBNET_IPV6_SAVED='fd99::/64'
VPN_SERVER_IP_IPV6_SAVED='fd99::1'
EOF
export MOCK_FLOCK_STATUS=1
"$RESOLVER" --prepare \
  || fail "prepare did not accept recovery state without self-deadlocking"
unset MOCK_FLOCK_STATUS
if grep -q '10.99\|fd99' "$LOG_FILE"; then
  fail "prepare preferred stale completed state over in-progress recovery state"
fi
rm -f "$ROOT_DIR/var/lib/bonjour-vpn/config"
mv "$ROOT_DIR/var/lib/bonjour-vpn/incomplete" \
  "$ROOT_DIR/var/lib/bonjour-vpn/config"

cat > "$BROWSE_FILE" <<'EOF'
=;eth0;IPv4;Office Printer;_ipp._tcp;local;printer.local;10.20.30.40;631;"note=ready"
=;eth0;IPv4;Office Player;_airplay._tcp;local;player.local;10.20.30.41;7000;"model=Device3,1"
EOF

export MOCK_FLOCK_STATUS=1
if [ -n "$REAL_FLOCK" ]; then
  LOCK_READY="$TEST_DIR/lock-ready"
  exec 9>"$ROOT_DIR/run/bonjour-vpn.lock"
  "$REAL_FLOCK" -n 9 || fail "could not establish the real inherited parent-lock fixture"
  : > "$LOCK_READY"
fi
"$RESOLVER" --initial-under-parent-lock \
  || fail "initial OpenRC reconciliation contended with the parent lock"
if [ -n "$REAL_FLOCK" ]; then
  if "$REAL_FLOCK" -n "$ROOT_DIR/run/bonjour-vpn.lock" true; then
    fail "initial OpenRC reconciliation released its inherited parent lock"
  fi
  "$REAL_FLOCK" -u 9
  exec 9>&-
fi
unset MOCK_FLOCK_STATUS
[ "$(count_action restart)" = 1 ] || fail "initial service records did not restart dnsmasq once"
if grep -Fq 'ip -6 addr add' "$LOG_FILE"; then
  fail "non-canonical saved IPv6 endpoint was added a second time"
fi
grep -q '^10.20.30.40 printer.local$' "$ROOT_DIR/etc/bonjour-vpn-hosts" \
  || fail "host record was not published"
[ -e "$ROUTE_FILE" ] || fail "initial preparation did not restore the IPv6 return route"
grep -Fq 'txt-record=Office Player._airplay._tcp.local,"model=Device3,1"' \
  "$ROOT_DIR/etc/dnsmasq.d/bonjour-vpn-services.conf" \
  || fail "literal comma in a TXT value was not quoted for dnsmasq"

"$RESOLVER"
[ "$(count_action restart)" = 1 ] || fail "unchanged snapshot restarted dnsmasq"
[ "$(count_action reload)" = 0 ] || fail "unchanged snapshot reloaded dnsmasq"

cat >> "$BROWSE_FILE" <<'EOF'
=;eth0;IPv6;Office Printer;_ipp._tcp;local;printer.local;fd12:3456:789a:bcde::40;631;"note=ready"
=;eth0;IPv6;Office Printer;_ipp._tcp;local;printer.local;fe80::40%eth0;631;"note=ready"
EOF
"$RESOLVER"
grep -q '^fd12:3456:789a:bcde::40 printer.local$' "$ROOT_DIR/etc/bonjour-vpn-hosts" \
  || fail "global IPv6 host record was not published"
if grep -q '^fe80:' "$ROOT_DIR/etc/bonjour-vpn-hosts"; then
  fail "link-local IPv6 host record was published"
fi
[ "$(count_action restart)" = 1 ] || fail "IPv6 hosts-only change restarted dnsmasq"
[ "$(count_action reload)" = 1 ] || fail "IPv6 hosts-only change did not reload dnsmasq"

sed 's/10.20.30.40/10.20.30.41/' "$BROWSE_FILE" > "$BROWSE_FILE.next"
mv "$BROWSE_FILE.next" "$BROWSE_FILE"
"$RESOLVER"
[ "$(count_action restart)" = 1 ] || fail "hosts-only change restarted dnsmasq"
[ "$(count_action reload)" = 2 ] || fail "hosts-only change did not reload dnsmasq"

export MOCK_RELOAD_STATUS=1
sed 's/10.20.30.41/10.20.30.42/g' "$BROWSE_FILE" > "$BROWSE_FILE.next"
mv "$BROWSE_FILE.next" "$BROWSE_FILE"
"$RESOLVER"
unset MOCK_RELOAD_STATUS
[ "$(count_action restart)" = 2 ] \
  || fail "failed systemd reload did not fall back to a dnsmasq restart"
grep -q '^10.20.30.42 printer.local$' "$ROOT_DIR/etc/bonjour-vpn-hosts" \
  || fail "systemd reload fallback reverted the new hosts snapshot"

: > "$BROWSE_FILE"
"$RESOLVER"
grep -q 'printer.local' "$ROOT_DIR/etc/bonjour-vpn-hosts" \
  || fail "first empty snapshot removed live records"
"$RESOLVER"
[ ! -s "$ROOT_DIR/etc/bonjour-vpn-hosts" ] || fail "second empty snapshot did not clear hosts"
[ "$(count_action restart)" = 3 ] || fail "empty publication did not restart dnsmasq once"

cat > "$BROWSE_FILE" <<'EOF'
=;eth0;IPv4;Scanner;_scanner._tcp;local;scanner.local;10.20.30.50;8080;"note=ready"
EOF
cp "$ROOT_DIR/etc/dnsmasq.d/bonjour-vpn-services.conf" "$TEST_DIR/services.before"
export MOCK_DNSMASQ_STATUS=1
if "$RESOLVER"; then
  fail "invalid effective dnsmasq candidate was accepted"
fi
cmp -s "$ROOT_DIR/etc/dnsmasq.d/bonjour-vpn-services.conf" "$TEST_DIR/services.before" \
  || fail "invalid candidate changed the live services file"
[ ! -e "$ROOT_DIR/etc/.bonjour-vpn-hosts.candidate" ] \
  || fail "invalid reconciliation left a hosts candidate"
[ ! -e "$ROOT_DIR/etc/dnsmasq.d/.bonjour-vpn-services.conf.candidate" ] \
  || fail "invalid reconciliation left a services candidate"
unset MOCK_DNSMASQ_STATUS

rm -f "$ACTIVE_FILE"
: > "$BROWSE_FILE"
"$RESOLVER"
[ "$(count_action start)" = 1 ] || fail "inactive dnsmasq was not recovered on a no-op"

echo "PASS: runtime reconciliation, empty confirmation, validation, and recovery"
