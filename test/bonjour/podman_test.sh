#!/usr/bin/env bash
#
# Podman-based test harness for enable_bonjour.sh / disable_bonjour.sh
# Runs 3 containers: bonjour-device, bonjour-server, bonjour-client
# Supports both IPv4-only and dual-stack modes
#
# Usage:
#   bash podman_test.sh                 # Default: dual-stack
#   bash podman_test.sh --ipv4-only     # IPv4-only mode
#   bash podman_test.sh --keep          # Don't tear down on completion
#   bash podman_test.sh --skip-e2e      # Skip IKEv2 client E2E (faster iteration)
#
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed
#   2 = environment setup failed (can't even start tests)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Use a working dir inside the repo to avoid /tmp symlink issues on macOS
WORKDIR="$SCRIPT_DIR/.work"
mkdir -p "$WORKDIR"

NETWORK_NAME="bonjour-test"
DEVICE_NAME="bonjour-device"
SERVER_NAME="bonjour-server"
CLIENT_NAME="bonjour-client"

IMAGE="localhost/bonjour-test-base:latest"

# IPv4 subnet (always used)
V4_SUBNET="10.89.0.0/24"
V4_GATEWAY="10.89.0.1"

# IPv6 subnet (used in dual-stack mode).
# Uses 2001:db8::/32 documentation prefix (RFC 3849). Starts with "2" so it
# matches the project's detect_ipv6() pattern `inet6 [23]` and triggers
# actual IPv6 enablement in the VPN install.
V6_SUBNET="2001:db8:aaaa::/64"
V6_GATEWAY="2001:db8:aaaa::1"

# Parse flags
DUAL_STACK=1
KEEP_CONTAINERS=0
SKIP_E2E=0
for arg in "$@"; do
  case "$arg" in
    --ipv4-only) DUAL_STACK=0 ;;
    --keep)      KEEP_CONTAINERS=1 ;;
    --skip-e2e)  SKIP_E2E=1 ;;
    *)           echo "Unknown flag: $arg" >&2; exit 2 ;;
  esac
done

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
NC='\033[0m'; BOLD='\033[1m'

PASS=0; FAIL=0; SKIP=0

log()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
pass() { echo -e "  ${GREEN}PASS${NC}: $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}FAIL${NC}: $1"; FAIL=$((FAIL+1)); }
skip() { echo -e "  ${YELLOW}SKIP${NC}: $1"; SKIP=$((SKIP+1)); }
die()  { echo -e "${RED}FATAL: $1${NC}" >&2; exit 2; }

# Helper: run command in container, filter dig errors that may leak to stdout
run_dig() {
  local ctr="$1"; shift
  podman exec "$ctr" bash -c "dig +short +time=5 +tries=2 $* 2>/dev/null" 2>/dev/null \
    | grep -v '^;;' | grep -v 'no servers' || true
}

# ===== Pre-flight =====
preflight() {
  log "Pre-flight checks..."
  command -v podman >/dev/null 2>&1 || die "podman not installed"
  podman machine list 2>/dev/null | grep -q 'Currently running' || die "podman machine not running"
  [ -f "$REPO_DIR/extras/enable_bonjour.sh" ] || die "enable_bonjour.sh not found at $REPO_DIR/extras/"
  [ -f "$REPO_DIR/extras/disable_bonjour.sh" ] || die "disable_bonjour.sh not found at $REPO_DIR/extras/"

  # Verify required kernel modules in podman VM
  local mods
  mods=$(podman machine ssh -- "sudo lsmod 2>/dev/null | awk '{print \$1}'" 2>/dev/null || true)
  echo "$mods" | grep -q '^tun$'         || die "tun module not loaded in podman machine"
  echo "$mods" | grep -q '^ip_tables$'   || die "ip_tables module not loaded"
  echo "$mods" | grep -q '^ip6_tables$'  || die "ip6_tables module not loaded (needed for IPv6 tests)"
  echo "$mods" | grep -q '^nf_nat$'      || die "nf_nat module not loaded"

  # Load ppp_generic if not already (needed for L2TP)
  if ! echo "$mods" | grep -q '^ppp_generic$'; then
    log "Loading ppp_generic module in podman machine..."
    podman machine ssh -- "sudo modprobe ppp_generic" 2>&1 \
      || die "Failed to load ppp_generic module"
  fi

  # Ensure /dev/ppp exists in podman machine
  podman machine ssh -- "sudo test -c /dev/ppp || sudo mknod /dev/ppp c 108 0" 2>&1 \
    | grep -v '^$' || true

  log "Pre-flight OK. Mode: $([ "$DUAL_STACK" = 1 ] && echo 'dual-stack' || echo 'IPv4-only')"
}

# ===== Network =====
create_network() {
  log "Creating podman network: $NETWORK_NAME"
  podman network rm -f "$NETWORK_NAME" >/dev/null 2>&1 || true

  if [ "$DUAL_STACK" = 1 ]; then
    podman network create \
      --subnet "$V4_SUBNET" --gateway "$V4_GATEWAY" \
      --ipv6 --subnet "$V6_SUBNET" --gateway "$V6_GATEWAY" \
      "$NETWORK_NAME" >/dev/null \
      || die "Failed to create dual-stack network"
  else
    podman network create \
      --subnet "$V4_SUBNET" --gateway "$V4_GATEWAY" \
      "$NETWORK_NAME" >/dev/null \
      || die "Failed to create IPv4 network"
  fi
}

remove_network() {
  podman network rm -f "$NETWORK_NAME" >/dev/null 2>&1 || true
}

# ===== Container management =====
run_container() {
  local name="$1"
  local hostname="$2"
  local ip4="$3"
  local ip6="$4"
  local mem="${5:-1g}"

  podman rm -f "$name" >/dev/null 2>&1 || true

  local net_args=(--network "$NETWORK_NAME:ip=$ip4")
  if [ "$DUAL_STACK" = 1 ] && [ -n "$ip6" ]; then
    net_args=(--network "$NETWORK_NAME:ip=$ip4,ip6=$ip6")
  fi

  # --systemd=always runs the container's CMD (/sbin/init) under systemd
  # The image has systemd pre-installed (see Containerfile)
  podman run -d \
    --name "$name" \
    --hostname "$hostname" \
    --privileged \
    --cap-add=ALL \
    --device=/dev/ppp \
    --device=/dev/net/tun \
    --memory="$mem" \
    --systemd=always \
    "${net_args[@]}" \
    "$IMAGE" >/dev/null 2>&1 \
    || die "Failed to start container $name"

  # Wait for systemd to be ready (running or degraded are both fine for our use)
  local tries=0
  while ! podman exec "$name" bash -c 'systemctl is-system-running 2>&1 | grep -qE "running|degraded"' 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -gt 30 ] && die "systemd not ready in $name after 30 seconds"
    sleep 1
  done
}

cleanup() {
  if [ "$KEEP_CONTAINERS" = 1 ] && [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Containers kept for debugging:"
    echo "  podman exec -it $DEVICE_NAME bash"
    echo "  podman exec -it $SERVER_NAME bash"
    echo "  podman exec -it $CLIENT_NAME bash"
    echo "  Cleanup: podman rm -f $DEVICE_NAME $SERVER_NAME $CLIENT_NAME && podman network rm $NETWORK_NAME"
    return
  fi
  log "Cleaning up containers..."
  podman rm -f "$DEVICE_NAME" "$SERVER_NAME" "$CLIENT_NAME" >/dev/null 2>&1 || true
  remove_network
}
trap cleanup EXIT

# ===== Phase: Bonjour device =====
setup_device() {
  log "Setting up Bonjour device..."
  run_container "$DEVICE_NAME" testprinter "10.89.0.10" "2001:db8:aaaa::10" "512m"

  podman exec "$DEVICE_NAME" bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -yqq avahi-daemon avahi-utils dbus iproute2 iputils-ping >/dev/null 2>&1
    mkdir -p /run/dbus /etc/avahi/services

    cat > /etc/avahi/services/printer.service << EOF
<?xml version="1.0" standalone="no"?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>Test Printer</name>
  <service>
    <type>_ipp._tcp</type>
    <port>631</port>
    <txt-record>txtver=1</txt-record>
    <txt-record>pdl=application/pdf</txt-record>
  </service>
</service-group>
EOF

    cat > /etc/avahi/services/airplay.service << EOF
<?xml version="1.0" standalone="no"?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>Test AirPlay</name>
  <service>
    <type>_airplay._tcp</type>
    <port>7000</port>
    <txt-record>model=AppleTV3,1</txt-record>
  </service>
</service-group>
EOF

    # Configure avahi for this container
    cat > /etc/avahi/avahi-daemon.conf << EOF
[server]
use-ipv4=yes
use-ipv6=yes
enable-dbus=yes

[publish]
publish-addresses=yes
publish-hinfo=yes
publish-workstation=no
publish-domain=yes
publish-aaaa-on-ipv4=yes

[rlimits]
rlimit-core=0
rlimit-data=4194304
rlimit-fsize=0
rlimit-nofile=768
rlimit-stack=4194304
rlimit-nproc=100
EOF

    dbus-daemon --system >/dev/null 2>&1 || true
    sleep 1
    avahi-daemon --daemonize --no-drop-root >/dev/null 2>&1 || true
    sleep 2
  ' || die "Device setup failed"
}

# ===== Phase: VPN server =====
setup_server() {
  log "Setting up VPN server (Libreswan compile, ~2-3 min)..."
  run_container "$SERVER_NAME" vpn-server "10.89.0.20" "2001:db8:aaaa::20" "3g"

  # Copy bonjour scripts into the container
  podman cp "$REPO_DIR/extras/enable_bonjour.sh"  "$SERVER_NAME:/tmp/enable_bonjour.sh"
  podman cp "$REPO_DIR/extras/disable_bonjour.sh" "$SERVER_NAME:/tmp/disable_bonjour.sh"

  podman exec "$SERVER_NAME" bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -yqq wget iproute2 iputils-ping dnsutils >/dev/null 2>&1
    VPN_IPSEC_PSK=testpsk123456789 VPN_USER=testuser VPN_PASSWORD=testpass1234 \
      wget -t 3 -T 30 -nv -O vpn.sh https://get.vpnsetup.net 2>&1 | tail -1
    VPN_IPSEC_PSK=testpsk123456789 VPN_USER=testuser VPN_PASSWORD=testpass1234 \
      bash vpn.sh 2>&1 | tail -5
    [ -f /etc/ipsec.d/ikev2.conf ] || { echo "FATAL: ikev2.conf not generated"; exit 1; }
    echo "VPN install OK"
  ' || die "VPN server install failed"

  log "Running enable_bonjour.sh..."
  podman exec "$SERVER_NAME" bash -c 'bash /tmp/enable_bonjour.sh <<ANSWERS 2>&1 | tail -20
y
ANSWERS
' || die "enable_bonjour.sh failed"

  sleep 5
}

# ===== Phase: IKEv2 client =====
setup_client() {
  log "Setting up IKEv2 client..."
  run_container "$CLIENT_NAME" vpn-client "10.89.0.30" "2001:db8:aaaa::30" "1g"

  # Export client cert from server
  podman exec "$SERVER_NAME" ikev2.sh --exportclient vpnclient 2>&1 | tail -3
  podman cp "$SERVER_NAME:/root/vpnclient.p12" "$WORKDIR/vpnclient.p12"
  podman cp "$WORKDIR/vpnclient.p12" "$CLIENT_NAME:/tmp/vpnclient.p12"

  # Server identity for strongSwan config — run the full pipeline inside the container
  # so we don't depend on GNU grep being present on the host (macOS has BSD grep)
  local server_id
  server_id=$(podman exec "$SERVER_NAME" bash -c \
    "grep -oP '(?<=leftid=).*' /etc/ipsec.d/ikev2.conf | head -1 | tr -d '[:space:]'" \
    2>/dev/null)

  podman exec "$CLIENT_NAME" bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -yqq strongswan strongswan-swanctl dnsutils iproute2 iputils-ping >/dev/null 2>&1

    mkdir -p /etc/swanctl/x509ca /etc/swanctl/x509 /etc/swanctl/private /etc/swanctl/conf.d

    openssl pkcs12 -in /tmp/vpnclient.p12 -cacerts -nokeys -out /etc/swanctl/x509ca/ca.pem -passin pass: -legacy 2>/dev/null || \
      openssl pkcs12 -in /tmp/vpnclient.p12 -cacerts -nokeys -out /etc/swanctl/x509ca/ca.pem -passin pass:
    openssl pkcs12 -in /tmp/vpnclient.p12 -clcerts -nokeys -out /etc/swanctl/x509/client.pem -passin pass: -legacy 2>/dev/null || \
      openssl pkcs12 -in /tmp/vpnclient.p12 -clcerts -nokeys -out /etc/swanctl/x509/client.pem -passin pass:
    openssl pkcs12 -in /tmp/vpnclient.p12 -nocerts -nodes -out /etc/swanctl/private/client.key -passin pass: -legacy 2>/dev/null || \
      openssl pkcs12 -in /tmp/vpnclient.p12 -nocerts -nodes -out /etc/swanctl/private/client.key -passin pass:
  '

  # Write swanctl config on host, copy in. We only request an IPv4 vip — the
  # server-side IPv6 paths (dnsmasq listen, ip6tables, loopback, cache warmer)
  # are validated through server-side assertions and the E2E AAAA lookup
  # below (which works cross-family over the IPv4 tunnel).
  local tmp_conf="$WORKDIR/client-swanctl.conf"
  cat > "$tmp_conf" << EOF
connections {
  myvpn {
    remote_addrs = 10.89.0.20
    vips = 0.0.0.0
    local {
      auth = pubkey
      certs = client.pem
      id = vpnclient
    }
    remote {
      auth = pubkey
      id = ${server_id}
    }
    children {
      myvpn {
        remote_ts = 0.0.0.0/0
        start_action = none
      }
    }
  }
}
EOF
  podman cp "$tmp_conf" "$CLIENT_NAME:/etc/swanctl/conf.d/myvpn.conf"
  rm -f "$tmp_conf" "$WORKDIR/vpnclient.p12"

  podman exec "$CLIENT_NAME" bash -c '
    ipsec restart
    sleep 3
    swanctl --load-all 2>&1 | tail -3
    swanctl --initiate --child myvpn 2>&1 | tail -3 || true
    sleep 1
  '
}

# ===== Tests =====
VPN_DNS_IP=""

run_server_tests() {
  echo ""
  echo -e "${BOLD}========== Server-Side Tests ==========${NC}"
  echo ""

  VPN_DNS_IP=$(podman exec "$SERVER_NAME" bash -c \
    'grep "listen-address=" /etc/dnsmasq.d/bonjour-vpn.conf 2>/dev/null \
       | grep -oP "\d+\.\d+\.\d+\.\d+" | grep -v 127.0.0.1 | head -1' 2>/dev/null || true)
  [ -z "$VPN_DNS_IP" ] && VPN_DNS_IP="192.168.43.1"

  # Test 1: avahi-daemon running
  if podman exec "$SERVER_NAME" pgrep -x avahi-daemon >/dev/null 2>&1; then
    pass "avahi-daemon running"
  else
    fail "avahi-daemon NOT running"
  fi

  # Test 2: dnsmasq running
  if podman exec "$SERVER_NAME" pgrep -x dnsmasq >/dev/null 2>&1; then
    pass "dnsmasq running"
  else
    fail "dnsmasq NOT running"
  fi

  # Test 3: VPN server IP assigned to loopback
  if podman exec "$SERVER_NAME" ip addr show dev lo 2>/dev/null | grep -q "$VPN_DNS_IP"; then
    pass "VPN IP $VPN_DNS_IP on loopback"
  else
    fail "VPN IP $VPN_DNS_IP NOT on loopback"
  fi

  # Test 4: IKEv2 modecfgdns updated
  if podman exec "$SERVER_NAME" grep -q "modecfgdns=.*${VPN_DNS_IP}" /etc/ipsec.d/ikev2.conf 2>/dev/null; then
    pass "IKEv2 modecfgdns includes $VPN_DNS_IP"
  else
    fail "IKEv2 modecfgdns does NOT include $VPN_DNS_IP"
  fi

  # Test 5: IKEv2 modecfgdomains set
  if podman exec "$SERVER_NAME" grep -q 'modecfgdomains=.*local' /etc/ipsec.d/ikev2.conf 2>/dev/null; then
    pass "IKEv2 modecfgdomains set"
  else
    fail "IKEv2 modecfgdomains NOT set"
  fi

  # Test 6: Cache warmer script exists
  if podman exec "$SERVER_NAME" test -x /usr/local/bin/bonjour-vpn-resolve 2>/dev/null; then
    pass "bonjour-vpn-resolve installed"
  else
    fail "bonjour-vpn-resolve NOT installed"
  fi

  # Test 7: Watcher service running
  if podman exec "$SERVER_NAME" systemctl is-active bonjour-vpn-watch >/dev/null 2>&1 \
     || podman exec "$SERVER_NAME" pgrep -f bonjour-vpn-watch >/dev/null 2>&1; then
    pass "watcher service active"
  else
    fail "watcher service NOT active"
  fi

  # Test 8: Hosts file exists
  if podman exec "$SERVER_NAME" test -f /etc/bonjour-vpn-hosts 2>/dev/null; then
    pass "bonjour-vpn-hosts file exists"
  else
    fail "bonjour-vpn-hosts NOT generated"
  fi

  # Test 9: Services config generated
  if podman exec "$SERVER_NAME" test -s /etc/dnsmasq.d/bonjour-vpn-services.conf 2>/dev/null; then
    pass "DNS-SD services config generated"
  else
    fail "DNS-SD services config NOT generated"
  fi

  # Test 10: DNS-SD enumeration query
  local sd
  sd=$(run_dig "$SERVER_NAME" "@${VPN_DNS_IP} _services._dns-sd._udp.local PTR")
  if [ -n "$sd" ]; then
    local n; n=$(echo "$sd" | wc -l | tr -d ' ')
    pass "DNS-SD query returned $n service types"
  else
    fail "DNS-SD query returned nothing"
  fi

  # Test 11: IPP printer lookup
  local ipp
  ipp=$(run_dig "$SERVER_NAME" "@${VPN_DNS_IP} _ipp._tcp.local PTR")
  if [ -n "$ipp" ]; then
    pass "found printer via _ipp._tcp.local"
  else
    fail "no printers via _ipp._tcp.local"
  fi

  # Test 12: AirPlay lookup
  local ap
  ap=$(run_dig "$SERVER_NAME" "@${VPN_DNS_IP} _airplay._tcp.local PTR")
  if [ -n "$ap" ]; then
    pass "found AirPlay device"
  else
    fail "no AirPlay device found"
  fi

  # Test 13: Upstream DNS still works
  local up
  up=$(run_dig "$SERVER_NAME" "@${VPN_DNS_IP} google.com A")
  if [ -n "$up" ]; then
    pass "upstream DNS (google.com -> $(echo "$up" | head -1))"
  else
    fail "upstream DNS broken"
  fi

  # Test 14: iptables DNS rule present
  if podman exec "$SERVER_NAME" iptables -C INPUT -s 192.168.43.0/24 -p udp --dport 53 -j ACCEPT 2>/dev/null; then
    pass "iptables DNS rule active"
  else
    fail "iptables DNS rule missing"
  fi

  # ===== IPv6 tests — only run in dual-stack mode =====
  if [ "$DUAL_STACK" = 1 ]; then
    echo ""
    echo -e "${BOLD}---- IPv6 tests ----${NC}"

    # IPv6.1: VPN server has IPv6 enabled (rightaddresspool contains IPv6 range)
    if podman exec "$SERVER_NAME" grep -q 'rightaddresspool=.*:.*-.*:' /etc/ipsec.d/ikev2.conf 2>/dev/null; then
      pass "VPN install enabled IPv6 (rightaddresspool has IPv6 range)"
    else
      fail "VPN install did NOT enable IPv6 — detect_ipv6 probably failed"
      echo "       Server container IPv6 addrs:"
      podman exec "$SERVER_NAME" ip -6 addr show 2>/dev/null | grep 'inet6 [23]' | sed 's/^/         /'
    fi

    # IPv6.2: enable_bonjour.sh detected IPv6 and assigned the IPv6 server IP to lo
    if podman exec "$SERVER_NAME" bash -c "ip -6 addr show dev lo | grep -qE 'inet6 f[dc]'"; then
      pass "IPv6 VPN server IP assigned to loopback"
    else
      fail "IPv6 VPN server IP NOT assigned to loopback"
    fi

    # IPv6.3: dnsmasq is listening on an IPv6 address (expected after Phase 2)
    if podman exec "$SERVER_NAME" bash -c "ss -ulnp 2>/dev/null | grep -E ':53 ' | grep -qE '\[f[dc]'"; then
      pass "dnsmasq listening on IPv6"
    else
      fail "dnsmasq NOT listening on IPv6"
      echo "       ss -ulnp :53 output:"
      podman exec "$SERVER_NAME" bash -c "ss -ulnp 2>/dev/null | grep ':53 '" | sed 's/^/         /'
    fi

    # IPv6.4: ip6tables INPUT rule for DNS from IPv6 VPN subnet
    if podman exec "$SERVER_NAME" bash -c '
      vpn6=$(grep rightaddresspool /etc/ipsec.d/ikev2.conf | head -1 \
        | sed "s/.*rightaddresspool=//; s/\"//g" \
        | awk -F, "{print \$2}" | cut -d- -f1)
      [ -z "$vpn6" ] && exit 1
      prefix=$(printf "%s" "$vpn6" | sed -E "s/:[0-9a-fA-F]*\$/::/; s/::+/::/")
      prefix="${prefix%::*}::/64"
      ip6tables -C INPUT -s "$prefix" -p udp --dport 53 -j ACCEPT 2>/dev/null
    '; then
      pass "ip6tables INPUT rule for IPv6 VPN subnet active"
    else
      fail "ip6tables INPUT rule for IPv6 VPN subnet missing"
    fi

    # IPv6.5: ip6tables NAT PREROUTING DNAT for mDNS multicast (ff02::fb)
    if podman exec "$SERVER_NAME" bash -c "ip6tables -t nat -L PREROUTING -n 2>/dev/null | grep -qi 'ff02::fb.*dpt:5353'"; then
      pass "ip6tables DNAT for IPv6 mDNS multicast active"
    else
      fail "ip6tables DNAT for IPv6 mDNS multicast missing"
      echo "       PREROUTING chain:"
      podman exec "$SERVER_NAME" ip6tables -t nat -L PREROUTING -n 2>/dev/null | sed 's/^/         /'
    fi

    # IPv6.6: /etc/bonjour-vpn-hosts contains IPv6 entries for the test device
    if podman exec "$SERVER_NAME" bash -c "grep -qE '^2001:db8' /etc/bonjour-vpn-hosts 2>/dev/null"; then
      pass "hosts file contains IPv6 entries from cache warmer"
    else
      fail "hosts file has NO IPv6 entries"
      echo "       bonjour-vpn-hosts content:"
      podman exec "$SERVER_NAME" head -20 /etc/bonjour-vpn-hosts 2>/dev/null | sed 's/^/         /'
    fi

    # IPv6.7: cross-family AAAA query over IPv4 returns the IPv6 address
    local aaaa
    aaaa=$(podman exec "$SERVER_NAME" bash -c \
      "dig +short +time=3 @${VPN_DNS_IP} testprinter.local AAAA 2>/dev/null" \
      2>/dev/null | grep -v '^;;' || true)
    if [ -n "$aaaa" ]; then
      pass "AAAA query returns IPv6 for testprinter.local ($aaaa)"
    else
      fail "AAAA query for testprinter.local returned nothing"
    fi

    # IPv6.8: Regression guard — modecfgdns MUST be IPv4-only. Libreswan <=5.3
    # serializes INTERNAL_IP6_DNS with 17 bytes instead of the 16 bytes that
    # RFC 5996 requires, and strongSwan clients reject the IKE_AUTH response
    # with "invalid attribute length 17 for INTERNAL_IP6_DNS", breaking the
    # tunnel entirely. If this test starts failing, it means someone added
    # IPv6 DNS back into modecfgdns — which will silently brick strongSwan
    # clients on dual-stack VPN servers.
    if podman exec "$SERVER_NAME" bash -c \
         "grep -E '^[[:space:]]*modecfgdns=' /etc/ipsec.d/ikev2.conf | grep -qE ':[0-9a-fA-F]*:'"; then
      fail "modecfgdns contains IPv6 DNS — will break strongSwan clients (Libreswan bug)"
      echo "       modecfgdns line:"
      podman exec "$SERVER_NAME" grep -E '^[[:space:]]*modecfgdns=' /etc/ipsec.d/ikev2.conf 2>/dev/null \
        | sed 's/^/         /'
    else
      pass "modecfgdns is IPv4-only (regression guard for Libreswan INTERNAL_IP6_DNS bug)"
    fi

    # ===== Phase 7: Adaptive IPv6 sync =====

    # IPv6.9: sync script is installed and executable
    if podman exec "$SERVER_NAME" test -x /usr/local/sbin/bonjour-vpn-ipv6-sync; then
      pass "bonjour-vpn-ipv6-sync installed and executable"
    else
      fail "bonjour-vpn-ipv6-sync missing or not executable"
    fi

    # IPv6.10: watcher invokes the sync script
    if podman exec "$SERVER_NAME" bash -c \
         "grep -q 'bonjour-vpn-ipv6-sync' /usr/local/bin/bonjour-vpn-watch 2>/dev/null"; then
      pass "watcher references the IPv6 sync script"
    else
      fail "watcher does not reference the IPv6 sync script"
    fi

    # IPv6.11: initial state file created at install time and reflects dual-stack
    if podman exec "$SERVER_NAME" bash -c \
         "grep -q 'HAS_IPV6_SAVED=1' /var/lib/bonjour-vpn/ipv6-state 2>/dev/null"; then
      pass "initial IPv6 sync state file reflects dual-stack install"
    else
      fail "initial IPv6 sync state file missing or wrong"
      echo "       state file content:"
      podman exec "$SERVER_NAME" cat /var/lib/bonjour-vpn/ipv6-state 2>/dev/null | sed 's/^/         /'
    fi

    # IPv6.12: running sync again is a no-op (idempotent) — state file unchanged
    local state_before state_after
    state_before=$(podman exec "$SERVER_NAME" sha256sum /var/lib/bonjour-vpn/ipv6-state 2>/dev/null | awk '{print $1}')
    podman exec "$SERVER_NAME" /usr/local/sbin/bonjour-vpn-ipv6-sync 2>/dev/null || true
    state_after=$(podman exec "$SERVER_NAME" sha256sum /var/lib/bonjour-vpn/ipv6-state 2>/dev/null | awk '{print $1}')
    if [ -n "$state_before" ] && [ "$state_before" = "$state_after" ]; then
      pass "sync script is idempotent (state file unchanged on re-run)"
    else
      fail "sync script is not idempotent"
    fi

    # IPv6.13: simulate a user DISABLING IPv6 after install (transition on->off).
    # Remove the IPv6 range from rightaddresspool, run sync, verify teardown.
    podman exec "$SERVER_NAME" bash -c '
      /bin/cp -f /etc/ipsec.d/ikev2.conf /etc/ipsec.d/ikev2.conf.phase7-orig
      sed -i "s|rightaddresspool=192.168.43.10-192.168.43.250,fddd:500:500:500::1000-fddd:500:500:500::1fff|rightaddresspool=192.168.43.10-192.168.43.250|" /etc/ipsec.d/ikev2.conf
      /usr/local/sbin/bonjour-vpn-ipv6-sync
      sleep 1
    ' >/dev/null 2>&1

    # After transition: state file should now say HAS_IPV6_SAVED=0
    if podman exec "$SERVER_NAME" bash -c \
         "grep -q 'HAS_IPV6_SAVED=0' /var/lib/bonjour-vpn/ipv6-state 2>/dev/null"; then
      pass "sync: user-removed IPv6 pool triggers state transition to off"
    else
      fail "sync: state file still shows HAS_IPV6_SAVED=1 after removal"
    fi

    # After transition: IPv6 address should be gone from loopback
    if ! podman exec "$SERVER_NAME" bash -c \
         "ip -6 addr show dev lo 2>/dev/null | grep -q 'fddd:500:500:500::1/'"; then
      pass "sync: IPv6 loopback address removed on teardown"
    else
      fail "sync: IPv6 loopback address still present after teardown"
    fi

    # After transition: ip6tables INPUT rule should be gone
    if ! podman exec "$SERVER_NAME" bash -c \
         "ip6tables -C INPUT -s fddd:500:500:500::/64 -p udp --dport 53 -j ACCEPT 2>/dev/null"; then
      pass "sync: ip6tables INPUT rule removed on teardown"
    else
      fail "sync: ip6tables INPUT rule still present after teardown"
    fi

    # IPv6.14: now RESTORE the IPv6 pool and verify sync re-applies (off->on)
    podman exec "$SERVER_NAME" bash -c '
      /bin/cp -f /etc/ipsec.d/ikev2.conf.phase7-orig /etc/ipsec.d/ikev2.conf
      /usr/local/sbin/bonjour-vpn-ipv6-sync
      sleep 1
    ' >/dev/null 2>&1

    if podman exec "$SERVER_NAME" bash -c \
         "grep -q 'HAS_IPV6_SAVED=1' /var/lib/bonjour-vpn/ipv6-state 2>/dev/null"; then
      pass "sync: restoring IPv6 pool triggers state transition to on"
    else
      fail "sync: state file still shows HAS_IPV6_SAVED=0 after restore"
    fi

    if podman exec "$SERVER_NAME" bash -c \
         "ip -6 addr show dev lo 2>/dev/null | grep -q 'fddd:500:500:500::1/'"; then
      pass "sync: IPv6 loopback address re-added on apply"
    else
      fail "sync: IPv6 loopback address not re-added after apply"
    fi

    if podman exec "$SERVER_NAME" bash -c \
         "ip6tables -C INPUT -s fddd:500:500:500::/64 -p udp --dport 53 -j ACCEPT 2>/dev/null"; then
      pass "sync: ip6tables INPUT rule re-added on apply"
    else
      fail "sync: ip6tables INPUT rule not re-added after apply"
    fi
  fi
}

run_e2e_tests() {
  if [ "$SKIP_E2E" = 1 ]; then
    log "Skipping E2E tests (--skip-e2e)"
    return
  fi

  echo ""
  echo -e "${BOLD}========== E2E Through IKEv2 Tunnel ==========${NC}"
  echo ""

  local vpn_ip
  vpn_ip=$(podman exec "$CLIENT_NAME" bash -c \
    "ip addr show 2>/dev/null | grep -oP '192\.168\.43\.\d+' | head -1" \
    2>/dev/null || true)

  if [ -n "$vpn_ip" ]; then
    pass "Client got VPN IP: $vpn_ip"
  else
    fail "No VPN IP - tunnel not established"
    podman exec "$CLIENT_NAME" swanctl --list-sas 2>&1 | head -10
    return
  fi

  # E2E Test 1: service type enumeration through tunnel
  local r
  r=$(run_dig "$CLIENT_NAME" "@192.168.43.1 _services._dns-sd._udp.local PTR")
  if [ -n "$r" ]; then
    local n; n=$(echo "$r" | wc -l | tr -d ' ')
    pass "E2E DNS-SD ($n types through tunnel)"
  else
    fail "E2E DNS-SD returned nothing"
  fi

  # E2E Test 2: printer through tunnel
  r=$(run_dig "$CLIENT_NAME" "@192.168.43.1 _ipp._tcp.local PTR")
  if [ -n "$r" ]; then
    pass "E2E printer lookup through tunnel"
  else
    fail "E2E printer lookup failed"
  fi

  # E2E Test 3: AirPlay through tunnel
  r=$(run_dig "$CLIENT_NAME" "@192.168.43.1 _airplay._tcp.local PTR")
  if [ -n "$r" ]; then
    pass "E2E AirPlay lookup through tunnel"
  else
    fail "E2E AirPlay lookup failed"
  fi

  # E2E Test 4: upstream DNS through tunnel
  r=$(run_dig "$CLIENT_NAME" "@192.168.43.1 google.com A")
  if [ -n "$r" ]; then
    pass "E2E upstream DNS (google.com -> $(echo "$r" | head -1))"
  else
    fail "E2E upstream DNS broken"
  fi

  # E2E Test 5 (dual-stack only): AAAA query over the IPv4 tunnel returns the
  # IPv6 address from the cache warmer's hosts file. This proves the dnsmasq
  # IPv6 listen+hosts pipeline works end-to-end from a VPN client's shell,
  # even though the client itself negotiated an IPv4-only virtual IP.
  if [ "$DUAL_STACK" = 1 ]; then
    local e2e_aaaa
    e2e_aaaa=$(podman exec "$CLIENT_NAME" bash -c \
      "dig +short +time=3 @192.168.43.1 testprinter.local AAAA 2>/dev/null | grep -v '^;;'" \
      2>/dev/null || true)
    if [ -n "$e2e_aaaa" ]; then
      pass "E2E AAAA lookup over tunnel (testprinter.local -> $e2e_aaaa)"
    else
      fail "E2E AAAA lookup over tunnel returned nothing"
    fi
  fi
}

run_disable_tests() {
  echo ""
  echo -e "${BOLD}========== Disable / Re-enable ==========${NC}"
  echo ""

  podman exec "$SERVER_NAME" bash -c 'bash /tmp/disable_bonjour.sh <<ANSWERS >/dev/null 2>&1
y
ANSWERS
' || true

  if ! podman exec "$SERVER_NAME" test -f /etc/dnsmasq.d/bonjour-vpn.conf 2>/dev/null; then
    pass "disable: bonjour-vpn.conf removed"
  else
    fail "disable: bonjour-vpn.conf still present"
  fi

  if ! podman exec "$SERVER_NAME" test -f /etc/dnsmasq.d/bonjour-vpn-services.conf 2>/dev/null; then
    pass "disable: services config removed"
  else
    fail "disable: services config still present"
  fi

  if ! podman exec "$SERVER_NAME" grep -q 'modecfgdomains=.*local' /etc/ipsec.d/ikev2.conf 2>/dev/null; then
    pass "disable: ikev2.conf restored"
  else
    fail "disable: ikev2.conf NOT restored"
  fi

  # Re-enable
  podman exec "$SERVER_NAME" bash -c 'bash /tmp/enable_bonjour.sh <<ANSWERS >/dev/null 2>&1
y
ANSWERS
' || true

  if podman exec "$SERVER_NAME" pgrep -x dnsmasq >/dev/null 2>&1; then
    pass "re-enable: dnsmasq running again"
  else
    fail "re-enable: dnsmasq NOT running"
  fi
}

print_results() {
  echo ""
  echo -e "${BOLD}========================================${NC}"
  echo -e "  ${GREEN}Passed${NC}:  $PASS"
  echo -e "  ${RED}Failed${NC}:  $FAIL"
  echo -e "  ${YELLOW}Skipped${NC}: $SKIP"
  echo -e "  Mode:    $([ "$DUAL_STACK" = 1 ] && echo 'dual-stack' || echo 'IPv4-only')"
  echo -e "${BOLD}========================================${NC}"
}

# ===== Main =====
START_TIME=$(date +%s)
preflight
create_network
setup_device
setup_server
setup_client
run_server_tests
run_e2e_tests
run_disable_tests
print_results
END_TIME=$(date +%s)
echo ""
echo "Elapsed: $((END_TIME - START_TIME))s"
echo ""

exit "$FAIL"
