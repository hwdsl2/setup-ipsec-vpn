#!/bin/bash
# shellcheck disable=SC1091,SC2030,SC2031,SC2034

set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)
TEST_DIR=$(mktemp -d)
MOCK_BIN="$TEST_DIR/bin"
CALL_LOG="$TEST_DIR/calls.log"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$MOCK_BIN"
: > "$CALL_LOG"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

cat > "$MOCK_BIN/dnsmasq" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$MOCK_BIN/rc-update" <<'EOF'
#!/bin/sh
if [ "$1 $2" = "show default" ]; then
  printf '%s\n' 'dnsmasq | default' 'avahi-daemon | default' 'dbus | default'
  exit 0
fi
printf 'rc-update %s\n' "$*" >> "$MOCK_CALL_LOG"
exit "${MOCK_OPENRC_STATUS:-0}"
EOF
cat > "$MOCK_BIN/rc-service" <<'EOF'
#!/bin/sh
printf 'rc-service %s\n' "$*" >> "$MOCK_CALL_LOG"
exit "${MOCK_OPENRC_STATUS:-0}"
EOF
cat > "$MOCK_BIN/crontab" <<'EOF'
#!/bin/sh
case "${1:-}" in
  -l)
    [ -f "$MOCK_CRONTAB_STATE" ] && cat "$MOCK_CRONTAB_STATE"
    ;;
  -)
    cat > "$MOCK_CRONTAB_STATE"
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$MOCK_BIN"/*

capture_openrc_state() (
  export BONJOUR_VPN_LIBRARY_ONLY=1
  export BONJOUR_VPN_PATH="$MOCK_BIN:/usr/bin:/bin"
  export MOCK_CALL_LOG="$CALL_LOG"
  # shellcheck source=../../extras/enable_bonjour.sh
  . "$REPO_DIR/extras/enable_bonjour.sh"
  os_type=alpine
  BONJOUR_CONFIG_STATE="$TEST_DIR/no-completed-state"
  capture_service_state
  [ "$DNSMASQ_WAS_INSTALLED" = 1 ] || fail "OpenRC dnsmasq installation was not detected"
  [ "$DNSMASQ_WAS_ENABLED" = 1 ] || fail "OpenRC dnsmasq enablement was not detected"
  [ "$DNSMASQ_WAS_ACTIVE" = 1 ] || fail "OpenRC dnsmasq activity was not detected"
  [ "$AVAHI_WAS_ENABLED" = 1 ] || fail "OpenRC Avahi enablement was not detected"
  [ "$AVAHI_WAS_ACTIVE" = 1 ] || fail "OpenRC Avahi activity was not detected"
  [ "$DBUS_WAS_ENABLED" = 1 ] || fail "OpenRC D-Bus enablement was not detected"
  [ "$DBUS_WAS_ACTIVE" = 1 ] || fail "OpenRC D-Bus activity was not detected"
)

restore_openrc_state() (
  export BONJOUR_VPN_LIBRARY_ONLY=1
  export PATH="$MOCK_BIN:/usr/bin:/bin"
  export MOCK_CALL_LOG="$CALL_LOG"
  export BONJOUR_VPN_ROOT="$TEST_DIR/openrc-root"
  mkdir -p "$BONJOUR_VPN_ROOT/etc/init.d"
  : > "$BONJOUR_VPN_ROOT/etc/init.d/dnsmasq"
  : > "$BONJOUR_VPN_ROOT/etc/init.d/avahi-daemon"
  chmod +x "$BONJOUR_VPN_ROOT/etc/init.d/dnsmasq" \
    "$BONJOUR_VPN_ROOT/etc/init.d/avahi-daemon"
  # shellcheck source=../../extras/disable_bonjour.sh
  . "$REPO_DIR/extras/disable_bonjour.sh"
  export PATH="$MOCK_BIN:/usr/bin:/bin"
  os_type=alpine
  HAVE_SAVED_STATE=1
  SERVICE_STATE_VERSION_SAVED=3
  DNSMASQ_WAS_ENABLED_SAVED=0 DNSMASQ_WAS_ACTIVE_SAVED=0
  AVAHI_WAS_ENABLED_SAVED=1 AVAHI_WAS_ACTIVE_SAVED=1
  DBUS_WAS_ENABLED_SAVED=1 DBUS_WAS_ACTIVE_SAVED=1
  restore_service_states
  grep -Fxq 'rc-update del dnsmasq default' "$CALL_LOG" \
    || fail "OpenRC dnsmasq enablement was not restored"
  grep -Fxq 'rc-service dnsmasq stop' "$CALL_LOG" \
    || fail "OpenRC dnsmasq activity was not restored"
  grep -Fxq 'rc-update add avahi-daemon default' "$CALL_LOG" \
    || fail "OpenRC Avahi enablement was not restored"
  grep -Fxq 'rc-service avahi-daemon restart' "$CALL_LOG" \
    || fail "OpenRC Avahi activity was not restored"
  if grep -Eq '^(rc-update (add|del) dbus|rc-service dbus (start|stop|restart))' "$CALL_LOG"; then
    fail "shared OpenRC D-Bus state was modified"
  fi

  export MOCK_OPENRC_STATUS=1
  if ( restore_service_states ) >/dev/null 2>&1; then
    fail "OpenRC restoration failure was ignored"
  fi

  : > "$CALL_LOG"
  rm -f "$BONJOUR_VPN_ROOT/etc/init.d/dnsmasq" \
    "$BONJOUR_VPN_ROOT/etc/init.d/avahi-daemon"
  unset MOCK_OPENRC_STATUS
  restore_service_states
  [ ! -s "$CALL_LOG" ] \
    || fail "OpenRC recovery tried to restore absent pre-install services"
)

capture_openrc_state
restore_openrc_state

cron_ownership() (
  export BONJOUR_VPN_LIBRARY_ONLY=1
  export BONJOUR_VPN_PATH="$MOCK_BIN:/usr/bin:/bin"
  export PATH="$MOCK_BIN:/usr/bin:/bin"
  export MOCK_CRONTAB_STATE="$TEST_DIR/crontab"
  exact_line='* * * * * /usr/local/bin/bonjour-vpn-resolve >/dev/null 2>&1'
  legacy_line='* * * * * /usr/local/bin/bonjour-vpn-resolve'
  printf '%s\n' \
    '5 * * * * /usr/local/bin/bonjour-vpn-report' \
    "$legacy_line" \
    '10 * * * * /opt/example/bonjour-vpn-custom' > "$MOCK_CRONTAB_STATE"
  # shellcheck source=../../extras/enable_bonjour.sh
  . "$REPO_DIR/extras/enable_bonjour.sh"
  install_cache_warmer_cron "$exact_line"
  [ "$(grep -Fxc "$exact_line" "$MOCK_CRONTAB_STATE")" = 1 ] \
    || fail "OpenRC cache-warmer cron entry was not installed exactly once"
  ! grep -Fxq "$legacy_line" "$MOCK_CRONTAB_STATE" \
    || fail "OpenRC upgrade retained the legacy cache-warmer cron entry"
  grep -Fxq '10 * * * * /opt/example/bonjour-vpn-custom' "$MOCK_CRONTAB_STATE" \
    || fail "install removed a similarly named administrator cron entry"
  install_cache_warmer_cron "$exact_line"
  [ "$(grep -Fxc "$exact_line" "$MOCK_CRONTAB_STATE")" = 1 ] \
    || fail "OpenRC cache-warmer cron installation was not idempotent"

  # shellcheck source=../../extras/disable_bonjour.sh
  . "$REPO_DIR/extras/disable_bonjour.sh"
  export PATH="$MOCK_BIN:/usr/bin:/bin"
  remove_cache_warmer_cron
  ! grep -Fxq "$exact_line" "$MOCK_CRONTAB_STATE" \
    || fail "OpenRC cache-warmer cron entry was not removed"
  ! grep -Fxq "$legacy_line" "$MOCK_CRONTAB_STATE" \
    || fail "disable retained the legacy cache-warmer cron entry"
  grep -Fxq '10 * * * * /opt/example/bonjour-vpn-custom' "$MOCK_CRONTAB_STATE" \
    || fail "disable removed a similarly named administrator cron entry"
)

cron_ownership

local_d_ownership() (
  export BONJOUR_VPN_LIBRARY_ONLY=1
  export BONJOUR_VPN_ROOT="$TEST_DIR/local-d-root"
  # shellcheck source=../../extras/enable_bonjour.sh
  . "$REPO_DIR/extras/enable_bonjour.sh"
  os_type=alpine
  HAS_IKEV2=1 HAS_XAUTH=0 HAS_L2TP=1 HAS_IPV6=1
  VPN_SERVER_IP='10.60.0.1' VPN_SUBNET='10.60.0.0/24'
  L2TP_SERVER_IP='10.61.0.1' L2TP_SUBNET='10.61.0.0/24'
  VPN_SERVER_IP_IPV6='fd60:1::1' VPN_SUBNET_IPV6='fd60:1::/64'
  VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT=0
  SAVED_VPN_SERVER_IP='' SAVED_L2TP_SERVER_IP=''
  SAVED_VPN_SERVER_IP_IPV6='' SAVED_VPN_SUBNET_IPV6=''
  remove_stale_owned_loopback_addresses() { :; }
  loopback_has_ipv4() { return 1; }
  loopback_has_ipv6() { return 1; }
  ipv6_subnet_route_exists() { return 1; }
  ip() { printf 'ip %s\n' "$*" >> "$CALL_LOG"; }
  rc-update() { printf 'rc-update %s\n' "$*" >> "$CALL_LOG"; }

  assign_vpn_server_ip >/dev/null
  local_script="$BONJOUR_VPN_ROOT/etc/local.d/bonjour-vpn.start"
  [ -x "$local_script" ] || fail "Alpine local.d boot script was not installed under the fixture root"
  grep -Fxq 'ip addr add 10.60.0.1/32 dev lo 2>/dev/null' "$local_script" \
    || fail "Alpine local.d omitted the IKEv2/XAuth endpoint"
  grep -Fxq 'ip addr add 10.61.0.1/32 dev lo 2>/dev/null' "$local_script" \
    || fail "Alpine local.d omitted the L2TP endpoint"
  grep -Fxq 'ip -6 addr add fd60:1::1/128 dev lo 2>/dev/null' "$local_script" \
    || fail "Alpine local.d omitted the IPv6 endpoint"
  grep -Fxq 'ip -6 route add fd60:1::/64 dev lo 2>/dev/null' "$local_script" \
    || fail "Alpine local.d omitted the IPv6 return route"

  # shellcheck source=../../extras/disable_bonjour.sh
  . "$REPO_DIR/extras/disable_bonjour.sh"
  os_type=alpine
  VPN_SERVER_IP='10.60.0.1' L2TP_SERVER_IP='10.61.0.1'
  VPN_SERVER_IP_IPV6='fd60:1::1' VPN_SUBNET_IPV6='fd60:1::/64'
  VPN_SERVER_IP_WAS_PRESENT=0 L2TP_SERVER_IP_WAS_PRESENT=0
  VPN_SERVER_IP_IPV6_WAS_PRESENT=0 VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT=0
  HAVE_INCOMPLETE_STATE=0
  remove_owned_loopback_address() { :; }
  remove_owned_ipv6_route() { :; }
  remove_vpn_server_ip >/dev/null
  [ ! -e "$local_script" ] || fail "disable retained the owned Alpine local.d boot script"
)

local_d_ownership

echo "PASS: OpenRC service, local.d, exact cron ownership, restoration, and failure propagation"
