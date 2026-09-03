#!/bin/bash

set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)
TEST_DIR=$(mktemp -d)
MOCK_BIN="$TEST_DIR/bin"
WATCHER="$TEST_DIR/bonjour-vpn-watch"
RESOLVER="$TEST_DIR/resolve"
LAUNCH_LOG="$TEST_DIR/launch.log"
RESOLVE_LOG="$TEST_DIR/resolve.log"
CHILD_PID_FILE="$TEST_DIR/child.pid"
WATCHER_PID=""

cleanup() {
  [ -n "$WATCHER_PID" ] && kill "$WATCHER_PID" 2>/dev/null || true
  wait "$WATCHER_PID" 2>/dev/null || true
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM

mkdir -p "$MOCK_BIN"
awk '/^cat > "\$WATCHER_SCRIPT" <<'\''WATCHER_EOF'\''/{copy=1;next} \
     /^WATCHER_EOF$/{copy=0} copy{print}' \
  "$REPO_DIR/extras/enable_bonjour.sh" > "$WATCHER"
chmod +x "$WATCHER"

cat > "$RESOLVER" <<'EOF'
#!/bin/bash
echo resolve >> "$MOCK_RESOLVE_LOG"
EOF
cat > "$MOCK_BIN/avahi-browse" <<'EOF'
#!/bin/bash
echo launch >> "$MOCK_LAUNCH_LOG"
echo $$ > "$MOCK_CHILD_PID_FILE"
echo '+;eth0;IPv4;Printer;_ipp._tcp;local'
sleep 30 &
sleeper=$!
trap 'kill "$sleeper" 2>/dev/null || true; exit 0' TERM INT
wait "$sleeper"
EOF
chmod +x "$RESOLVER" "$MOCK_BIN/avahi-browse"

export BONJOUR_VPN_PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
export BONJOUR_VPN_RESOLVE_CMD="$RESOLVER"
export BONJOUR_VPN_DEBOUNCE_SEC=1
export BONJOUR_VPN_RECONCILE_SEC=1
export BONJOUR_VPN_MAX_BURST_SEC=2
export BONJOUR_VPN_RUN_DIR="$TEST_DIR"
export MOCK_LAUNCH_LOG="$LAUNCH_LOG"
export MOCK_RESOLVE_LOG="$RESOLVE_LOG"
export MOCK_CHILD_PID_FILE="$CHILD_PID_FILE"
: > "$LAUNCH_LOG"
: > "$RESOLVE_LOG"

"$WATCHER" &
WATCHER_PID=$!
attempt=0
while [ "$attempt" -lt 50 ]; do
  launch_count=$(wc -l < "$LAUNCH_LOG" 2>/dev/null | tr -d ' ' || echo 0)
  resolve_count=$(wc -l < "$RESOLVE_LOG" 2>/dev/null | tr -d ' ' || echo 0)
  [ "${launch_count:-0}" -ge 1 ] 2>/dev/null \
    && [ "${resolve_count:-0}" -ge 3 ] 2>/dev/null && break
  attempt=$((attempt + 1))
  sleep 0.2
done
kill "$WATCHER_PID"
wait "$WATCHER_PID" 2>/dev/null || true
WATCHER_PID=""

[ "$(wc -l < "$LAUNCH_LOG" | tr -d ' ')" = 1 ] \
  || { echo "FAIL: idle reconciliation replaced the persistent browser" >&2; exit 1; }
[ "$(wc -l < "$RESOLVE_LOG" | tr -d ' ')" -ge 3 ] \
  || { echo "FAIL: startup, event, and periodic reconciliation did not run" >&2; exit 1; }
child_pid=$(cat "$CHILD_PID_FILE")
if kill -0 "$child_pid" 2>/dev/null; then
  echo "FAIL: watcher shutdown left its avahi-browse child running" >&2
  exit 1
fi

echo "PASS: persistent watcher, periodic reconcile, and child cleanup"
