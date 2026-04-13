#!/usr/bin/env bash
#
# Unit tests for the IPv6 detection logic in enable_bonjour.sh
#
# These tests don't need containers — they source the detection functions
# and run them against sample ikev2.conf fixtures.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'; BOLD='\033[1m'
PASS=0; FAIL=0

pass() { echo -e "  ${GREEN}PASS${NC}: $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}FAIL${NC}: $1 — $2"; FAIL=$((FAIL+1)); }

# Create a temp working directory
WORKDIR=$(mktemp -d -t bonjour-detect.XXXXXX) || { echo "mktemp failed"; exit 2; }
trap 'rm -rf "$WORKDIR"' EXIT

# Extract just the helper functions we need (check_ip, check_ip6, detect_vpn_ipv6)
# by sourcing the enable_bonjour.sh up to the point where main execution begins.
# Use a subshell with a stub main() and intercept before it runs.
#
# We source into a fresh shell that sets up the minimal state and only calls
# detect_vpn_ipv6 after setting HAS_IKEV2 and IKEV2_CONF.

run_detection() {
  local fixture="$1"
  local ikev2_conf_path="$fixture"

  # Extract just the functions we need from enable_bonjour.sh.
  # The "Main" section is marked by "# Main" between two "# ====" lines.
  # We copy everything up to the first "# Main" marker — that gives us all
  # the function definitions without any main-execution code.
  local script_body
  script_body=$(awk '/^# Main$/ {exit} 1' "$REPO_DIR/extras/enable_bonjour.sh")

  # Source the functions in a clean subshell and run detect_vpn_ipv6 against
  # the given fixture. Print results as key=value so we can parse them.
  bash -c '
    '"$script_body"'
    HAS_IKEV2=1
    IKEV2_CONF="'"$ikev2_conf_path"'"
    detect_vpn_ipv6
    printf "HAS_IPV6=%s\n" "${HAS_IPV6}"
    printf "VPN_POOL_IPV6=%s\n" "${VPN_POOL_IPV6}"
    printf "VPN_POOL_IPV6_START=%s\n" "${VPN_POOL_IPV6_START}"
    printf "VPN_SUBNET_IPV6=%s\n" "${VPN_SUBNET_IPV6}"
    printf "VPN_SERVER_IP_IPV6=%s\n" "${VPN_SERVER_IP_IPV6}"
  '
}

assert_var() {
  local output="$1"
  local key="$2"
  local expected="$3"
  local testname="$4"
  local actual
  actual=$(printf '%s\n' "$output" | grep "^${key}=" | cut -d= -f2-)
  if [ "$actual" = "$expected" ]; then
    pass "$testname ($key)"
  else
    fail "$testname ($key)" "expected '$expected', got '$actual'"
  fi
}

echo ""
echo -e "${BOLD}==== IPv6 Detection Unit Tests ====${NC}"
echo ""

# --- Fixture 1: IPv4-only ikev2.conf ---
cat > "$WORKDIR/fixture-ipv4-only.conf" << 'EOF'
conn ikev2-cp
  left=%defaultroute
  leftcert=example.com
  leftsendcert=always
  leftsubnet=0.0.0.0/0
  leftrsasigkey=%cert
  right=%any
  rightid=%fromcert
  rightaddresspool=192.168.43.10-192.168.43.250
  rightca=%same
  rightrsasigkey=%cert
  narrowing=yes
  dpddelay=30
  auto=add
  ikev2=insist
  rekey=no
  pfs=no
  ikelifetime=24h
  salifetime=24h
  encapsulation=yes
  leftid=@vpn.example.com
  modecfgdns="8.8.8.8 8.8.4.4"
  mobike=no
EOF

echo "Fixture 1: IPv4-only"
out=$(run_detection "$WORKDIR/fixture-ipv4-only.conf")
assert_var "$out" "HAS_IPV6" "0" "IPv4-only"
assert_var "$out" "VPN_SERVER_IP_IPV6" "" "IPv4-only"
echo ""

# --- Fixture 2: Dual-stack with default IPv6 pool ---
cat > "$WORKDIR/fixture-dual-default.conf" << 'EOF'
conn ikev2-cp
  left=%defaultroute
  leftsubnet=0.0.0.0/0,::/0
  right=%any
  rightaddresspool=192.168.43.10-192.168.43.250,fddd:500:500:500::1000-fddd:500:500:500::1fff
  ikev2=insist
  pfs=no
EOF

echo "Fixture 2: Dual-stack default pool"
out=$(run_detection "$WORKDIR/fixture-dual-default.conf")
assert_var "$out" "HAS_IPV6" "1" "dual-stack default"
assert_var "$out" "VPN_POOL_IPV6" "fddd:500:500:500::1000-fddd:500:500:500::1fff" "dual-stack default"
assert_var "$out" "VPN_POOL_IPV6_START" "fddd:500:500:500::1000" "dual-stack default"
assert_var "$out" "VPN_SUBNET_IPV6" "fddd:500:500:500::/64" "dual-stack default"
assert_var "$out" "VPN_SERVER_IP_IPV6" "fddd:500:500:500::1" "dual-stack default"
echo ""

# --- Fixture 3: Dual-stack with custom IPv6 prefix ---
cat > "$WORKDIR/fixture-dual-custom.conf" << 'EOF'
conn ikev2-cp
  leftsubnet=0.0.0.0/0,::/0
  rightaddresspool=10.200.0.10-10.200.0.250,fd12:3456:789a:bcde::1000-fd12:3456:789a:bcde::1fff
  ikev2=insist
EOF

echo "Fixture 3: Dual-stack custom prefix"
out=$(run_detection "$WORKDIR/fixture-dual-custom.conf")
assert_var "$out" "HAS_IPV6" "1" "custom IPv6 prefix"
assert_var "$out" "VPN_SERVER_IP_IPV6" "fd12:3456:789a:bcde::1" "custom IPv6 prefix"
assert_var "$out" "VPN_SUBNET_IPV6" "fd12:3456:789a:bcde::/64" "custom IPv6 prefix"
echo ""

# --- Fixture 4: IPv6 pool with quoted values ---
cat > "$WORKDIR/fixture-dual-quoted.conf" << 'EOF'
conn ikev2-cp
  rightaddresspool="192.168.43.10-192.168.43.250,fddd:500:500:500::1000-fddd:500:500:500::1fff"
  ikev2=insist
EOF

echo "Fixture 4: Quoted rightaddresspool"
out=$(run_detection "$WORKDIR/fixture-dual-quoted.conf")
assert_var "$out" "HAS_IPV6" "1" "quoted pool"
assert_var "$out" "VPN_SERVER_IP_IPV6" "fddd:500:500:500::1" "quoted pool"
echo ""

# --- Fixture 5: No ikev2-cp section at all ---
cat > "$WORKDIR/fixture-empty.conf" << 'EOF'
# empty config
EOF

echo "Fixture 5: Empty config"
out=$(run_detection "$WORKDIR/fixture-empty.conf")
assert_var "$out" "HAS_IPV6" "0" "empty config"
assert_var "$out" "VPN_SERVER_IP_IPV6" "" "empty config"
echo ""

# --- Fixture 6: Reversed order — IPv6 first, IPv4 second ---
cat > "$WORKDIR/fixture-reversed.conf" << 'EOF'
conn ikev2-cp
  rightaddresspool=fddd:500:500:500::1000-fddd:500:500:500::1fff,192.168.43.10-192.168.43.250
  ikev2=insist
EOF

echo "Fixture 6: Reversed pool order (IPv6 first)"
out=$(run_detection "$WORKDIR/fixture-reversed.conf")
# The parser takes fields after the first comma and greps for ":".
# With IPv6 first, the second field is IPv4 (no ":"), so HAS_IPV6=0.
# This is a known limitation — hwdsl2 scripts always put IPv4 first.
assert_var "$out" "HAS_IPV6" "0" "reversed pool"
echo ""

# --- Fixture 7: Expanded (non-compressed) IPv6 address ---
cat > "$WORKDIR/fixture-expanded.conf" << 'EOF'
conn ikev2-cp
  rightaddresspool=192.168.43.10-192.168.43.250,fddd:0500:0500:0500:0000:0000:0000:1000-fddd:0500:0500:0500:0000:0000:0000:1fff
  ikev2=insist
EOF

echo "Fixture 7: Expanded (non-compressed) IPv6 address"
out=$(run_detection "$WORKDIR/fixture-expanded.conf")
assert_var "$out" "HAS_IPV6" "1" "expanded IPv6"
assert_var "$out" "VPN_SUBNET_IPV6" "fddd:0500:0500:0500::/64" "expanded IPv6"
assert_var "$out" "VPN_SERVER_IP_IPV6" "fddd:0500:0500:0500:0000:0000:0000:1" "expanded IPv6"
echo ""

# --- Fixture 8: Multiple comma-separated pools (IPv4, IPv4, IPv6) ---
cat > "$WORKDIR/fixture-multi.conf" << 'EOF'
conn ikev2-cp
  rightaddresspool=192.168.43.10-192.168.43.250,10.0.0.10-10.0.0.250,fddd:500:500:500::1000-fddd:500:500:500::1fff
  ikev2=insist
EOF

echo "Fixture 8: Three pools (IPv4, IPv4, IPv6)"
out=$(run_detection "$WORKDIR/fixture-multi.conf")
assert_var "$out" "HAS_IPV6" "1" "multi pool"
assert_var "$out" "VPN_SERVER_IP_IPV6" "fddd:500:500:500::1" "multi pool"
echo ""

# ===== Summary =====
echo -e "${BOLD}========================================${NC}"
echo -e "  ${GREEN}Passed${NC}: $PASS"
echo -e "  ${RED}Failed${NC}: $FAIL"
echo -e "${BOLD}========================================${NC}"
echo ""

exit "$FAIL"
