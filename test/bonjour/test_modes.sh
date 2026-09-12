#!/bin/bash
# shellcheck disable=SC1091,SC2030,SC2031

set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

run_mode_case() {
  local name="$1" ikev2="$2" xauth="$3" l2tp="$4" ikev1_policy="$5"
  local root="$TEST_DIR/$name"
  mkdir -p "$root/etc/ipsec.d" "$root/etc/xl2tpd" "$root/etc/ppp"
  printf 'config setup\n  ikev1-policy=%s\n' "$ikev1_policy" > "$root/etc/ipsec.conf"
  [ "$ikev2" = 1 ] && printf 'conn ikev2-cp\n' > "$root/etc/ipsec.d/ikev2.conf"
  [ "$xauth" = 1 ] && printf '\nconn xauth-psk\n' >> "$root/etc/ipsec.conf"
  [ "$l2tp" = 1 ] && printf '[lns default]\n' > "$root/etc/xl2tpd/xl2tpd.conf"

  (
    export BONJOUR_VPN_LIBRARY_ONLY=1 BONJOUR_VPN_ROOT="$root"
    # shellcheck source=../../extras/enable_bonjour.sh
    . "$REPO_DIR/extras/enable_bonjour.sh"
    check_vpn_modes
    [ "$HAS_IKEV2" = "$ikev2" ] || fail "$name IKEv2 detection"
    if [ "$ikev1_policy" = drop ]; then
      [ "$HAS_XAUTH" = 0 ] || fail "$name exposed XAuth in IKEv2-only mode"
      [ "$HAS_L2TP" = 0 ] || fail "$name exposed L2TP in IKEv2-only mode"
    else
      [ "$HAS_XAUTH" = "$xauth" ] || fail "$name XAuth detection"
      [ "$HAS_L2TP" = "$l2tp" ] || fail "$name L2TP detection"
    fi
  )
}

run_mode_case all-protocols 1 1 1 accept
run_mode_case ikev2-only 1 1 1 drop
run_mode_case ikev2-only-no-legacy-files 1 0 0 drop
run_mode_case xauth-only 0 1 0 accept
run_mode_case l2tp-only 0 0 1 accept
run_mode_case ikev2-and-xauth 1 1 0 accept
run_mode_case ikev2-and-l2tp 1 0 1 accept

empty_root="$TEST_DIR/no-modes"
mkdir -p "$empty_root/etc/ipsec.d" "$empty_root/etc/xl2tpd" "$empty_root/etc/ppp"
if (
  export BONJOUR_VPN_LIBRARY_ONLY=1 BONJOUR_VPN_ROOT="$empty_root"
  . "$REPO_DIR/extras/enable_bonjour.sh"
  check_vpn_modes
) >/dev/null 2>&1; then
  fail "empty VPN configuration was accepted"
fi

echo "PASS: all supported VPN mode combinations and IKEv2-only exclusion"
