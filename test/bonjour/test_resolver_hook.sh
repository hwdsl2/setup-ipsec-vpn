#!/bin/bash

set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)
TEST_DIR=$(mktemp -d)
MOCK_BIN="$TEST_DIR/bin"
ROOT_DIR="$TEST_DIR/root"
CALL_LOG="$TEST_DIR/systemctl.log"
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$MOCK_BIN" "$ROOT_DIR"
: > "$CALL_LOG"

cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/bin/bash
echo "$*" >> "$MOCK_CALL_LOG"
case "$1" in
  is-active) exit "${MOCK_RESOLVED_STATUS:-0}" ;;
  show)
    case "$*" in
      *ExecStartPost*)
        printf '%s\n' "${MOCK_START_HOOKS:-{ path=/usr/share/dnsmasq/systemd-helper ; argv[]=/usr/share/dnsmasq/systemd-helper start-resolvconf ; ignore_errors=no ; }}"
        ;;
      *ExecStop*)
        printf '%s\n' "${MOCK_STOP_HOOKS:-{ path=/usr/share/dnsmasq/systemd-helper ; argv[]=/usr/share/dnsmasq/systemd-helper stop-resolvconf ; ignore_errors=no ; }}"
        ;;
    esac
    exit 0
    ;;
  daemon-reload) exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod 755 "$MOCK_BIN/systemctl"

export BONJOUR_VPN_LIBRARY_ONLY=1
export PATH="$MOCK_BIN:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export BONJOUR_VPN_PATH="$PATH"
export BONJOUR_VPN_ROOT="$ROOT_DIR"
export BONJOUR_VPN_RESOLVCONF_TARGET=/usr/bin/resolvectl
export MOCK_CALL_LOG="$CALL_LOG"
# shellcheck source=../../extras/enable_bonjour.sh
. "$REPO_DIR/extras/enable_bonjour.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

configure_dnsmasq_resolver_hook
DROPIN="$ROOT_DIR/etc/systemd/system/dnsmasq.service.d/bonjour-vpn.conf"
[ -f "$DROPIN" ] || fail "resolvectl compatibility drop-in was not installed"
grep -q '^ExecStartPost=$' "$DROPIN" \
  || fail "dnsmasq start resolver hook was not reset"
grep -q '^ExecStop=$' "$DROPIN" \
  || fail "dnsmasq stop resolver hook was not reset"

BONJOUR_VPN_RESOLVCONF_TARGET=/sbin/resolvconf
configure_dnsmasq_resolver_hook
[ ! -e "$DROPIN" ] || fail "drop-in remained for a native resolvconf provider"

BONJOUR_VPN_RESOLVCONF_TARGET=/usr/bin/resolvectl
MOCK_RESOLVED_STATUS=3
export MOCK_RESOLVED_STATUS
configure_dnsmasq_resolver_hook
[ ! -e "$DROPIN" ] || fail "drop-in remained while systemd-resolved was inactive"

MOCK_RESOLVED_STATUS=0
MOCK_START_HOOKS='{ path=/opt/admin-hook ; argv[]=/opt/admin-hook ; ignore_errors=no ; }'
export MOCK_RESOLVED_STATUS MOCK_START_HOOKS
configure_dnsmasq_resolver_hook 2>/dev/null
[ ! -e "$DROPIN" ] || fail "drop-in replaced an administrator lifecycle hook"

[ "$(grep -c '^daemon-reload$' "$CALL_LOG")" = 3 ] \
  || fail "systemd was not reloaded after each resolver-hook decision"

echo "PASS: dnsmasq resolver-hook compatibility policy and custom-hook guard"
