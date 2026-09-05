#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2329
#
# Podman-based test harness for enable_bonjour.sh / disable_bonjour.sh
# Runs 4 disposable containers on separate WAN and LAN networks:
# bonjour-device (LAN), bonjour-server (LAN), bonjour-router (WAN + LAN),
# and bonjour-client (WAN). The router provides the server's default route and
# forwards IKEv2, matching a typical one-NIC VPN server behind a NAT router.
# Supports both IPv4-only and dual-stack modes. All object names are unique to
# the run, and IKEv2 material is transferred only through a disposable Podman
# volume. It is never copied to or displayed on the host.
#
# Usage:
#   bash podman_test.sh                 # Default: dual-stack
#   bash podman_test.sh --ipv4-only     # IPv4-only mode
#   bash podman_test.sh --ikev2-only    # Parent IKEv2-only mode
#   bash podman_test.sh --skip-e2e      # Skip IKEv2 client E2E (faster iteration)
#   bash podman_test.sh --parent-live   # Exercise the current public quick-start
#   bash podman_test.sh --parent-ref SHA # Pin the parent source commit (default)
#   bash podman_test.sh --platform linux/amd64
#   bash podman_test.sh --base-image docker.io/library/ubuntu:26.04
#
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed
#   2 = environment setup failed (can't even start tests)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

RUN_ID="${BONJOUR_TEST_RUN_ID:-$(date -u +%Y%m%d%H%M%S)-$$}"
case "$RUN_ID" in
  *[!A-Za-z0-9_.-]*) echo "Invalid BONJOUR_TEST_RUN_ID." >&2; exit 2 ;;
esac
RUN_LABEL="io.github.hwdsl2.bonjour-test.run"
WAN_NETWORK="bonjour-test-${RUN_ID}-wan"
LAN_NETWORK="bonjour-test-${RUN_ID}-lan"
DEVICE_NAME="bonjour-device-${RUN_ID}"
SERVER_NAME="bonjour-server-${RUN_ID}"
CLIENT_NAME="bonjour-client-${RUN_ID}"
ROUTER_NAME="bonjour-router-${RUN_ID}"
TRANSFER_VOLUME="bonjour-test-${RUN_ID}-transfer"

case "$(uname -m)" in
  arm64|aarch64) DEFAULT_PLATFORM=linux/arm64 ;;
  x86_64|amd64) DEFAULT_PLATFORM=linux/amd64 ;;
  *) DEFAULT_PLATFORM=unsupported ;;
esac
PLATFORM="${BONJOUR_TEST_PLATFORM:-$DEFAULT_PLATFORM}"
IMAGE_ARCH=${PLATFORM##*/}
IMAGE="${BONJOUR_TEST_IMAGE:-localhost/bonjour-test-base:ubuntu24.04-${IMAGE_ARCH}}"
PARENT_MODE=pinned
PARENT_REF="${BONJOUR_TEST_PARENT_REF:-}"
BASE_IMAGE="${BONJOUR_TEST_BASE_IMAGE:-docker.io/library/ubuntu:24.04}"
DIAGNOSTIC_HOLD_SECONDS="${BONJOUR_TEST_DIAGNOSTIC_HOLD_SECONDS:-0}"

case "$DIAGNOSTIC_HOLD_SECONDS" in
  ''|*[!0-9]*) echo "BONJOUR_TEST_DIAGNOSTIC_HOLD_SECONDS must be an integer." >&2; exit 2 ;;
esac
[ "$DIAGNOSTIC_HOLD_SECONDS" -le 300 ] \
  || { echo "BONJOUR_TEST_DIAGNOSTIC_HOLD_SECONDS must not exceed 300." >&2; exit 2; }

# Documentation-only IPv6 ranges. They exist solely inside the disposable
# network namespaces and trigger the parent installer's global-IPv6 path.
WAN_ROUTER_IPV6="2001:db8:b0:1::1"
LAN_ROUTER_IPV6="2001:db8:b0:2::1"
LAN_SERVER_IPV6="2001:db8:b0:2::20"
LAN_DEVICE_IPV6="2001:db8:b0:2::10"

# Parse flags
DUAL_STACK=1
SKIP_E2E=0
VPN_MODE=all
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ipv4-only) DUAL_STACK=0 ;;
    --ikev2-only) VPN_MODE=ikev2-only ;;
    --skip-e2e)  SKIP_E2E=1 ;;
    --parent-live) PARENT_MODE=live ;;
    --parent-ref)
      shift
      [ "$#" -gt 0 ] || { echo "--parent-ref requires a commit." >&2; exit 2; }
      PARENT_REF=$1
      ;;
    --platform)
      shift
      [ "$#" -gt 0 ] || { echo "--platform requires a value." >&2; exit 2; }
      PLATFORM=$1
      IMAGE_ARCH=${PLATFORM##*/}
      IMAGE="${BONJOUR_TEST_IMAGE:-localhost/bonjour-test-base:ubuntu24.04-${IMAGE_ARCH}}"
      ;;
    --base-image)
      shift
      [ "$#" -gt 0 ] || { echo "--base-image requires an image reference." >&2; exit 2; }
      BASE_IMAGE=$1
      ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

case "$PLATFORM" in
  linux/arm64|linux/amd64) ;;
  *) echo "Unsupported platform '$PLATFORM'. Use linux/arm64 or linux/amd64." >&2; exit 2 ;;
esac

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
NC='\033[0m'; BOLD='\033[1m'

PASS=0; FAIL=0; SKIP=0
CREATED_WAN=0; CREATED_LAN=0; CREATED_DEVICE=0
CREATED_SERVER=0; CREATED_CLIENT=0; CREATED_ROUTER=0; CREATED_TRANSFER=0
SERVER_WAN_IP=""; SERVER_LAN_IP=""; DEVICE_LAN_IP=""
ROUTER_WAN_IP=""; ROUTER_LAN_IP=""; LAN_SUBNET=""
SERVER_STATIC_LAN_IP=""
VPN_SUBNET=""; VPN_DNS_IP=""; VPN_SUBNET_IPV6=""; VPN_DNS_IP6=""
L2TP_SUBNET_STATE=""; L2TP_DNS_IP=""

log()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
pass() { echo -e "  ${GREEN}PASS${NC}: $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}FAIL${NC}: $1"; FAIL=$((FAIL+1)); }
skip() { echo -e "  ${YELLOW}SKIP${NC}: $1"; SKIP=$((SKIP+1)); }
die()  { echo -e "${RED}FATAL: $1${NC}" >&2; exit 2; }

expect_exact_lines() {
  local actual="$1" name="$2"
  shift 2
  local expected actual_sorted expected_sorted
  actual_sorted=$(printf '%s\n' "$actual" | sed '/^$/d' | LC_ALL=C sort)
  expected_sorted=$(printf '%s\n' "$@" | sed '/^$/d' | LC_ALL=C sort)
  if [ "$actual_sorted" = "$expected_sorted" ]; then
    pass "$name"
  else
    fail "$name returned an unexpected record set"
  fi
}

# Helper: run command in container, filter dig errors that may leak to stdout
run_dig() {
  local ctr="$1"; shift
  podman exec "$ctr" dig +short +time=5 +tries=2 "$@" 2>/dev/null \
    | grep -v '^;;' | grep -v 'no servers' || true
}

run_dig_tcp() {
  local ctr="$1"; shift
  podman exec "$ctr" dig +tcp +short +time=5 +tries=2 "$@" 2>/dev/null \
    | grep -v '^;;' | grep -v 'no servers' || true
}

object_must_not_exist() {
  local kind=$1 name=$2
  case "$kind" in
    container) ! podman container exists "$name" ;;
    network) ! podman network exists "$name" ;;
    volume) ! podman volume exists "$name" ;;
    *) return 1 ;;
  esac || die "Refusing to reuse existing Podman $kind '$name'. Choose a new run ID."
}

# ===== Pre-flight =====
preflight() {
  log "Pre-flight checks..."
  command -v podman >/dev/null 2>&1 || die "podman not installed"
  command -v git >/dev/null 2>&1 || die "git not installed"
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

  # Loading ppp_generic changes only the disposable Podman VM kernel. Do not do
  # that implicitly: fail with a clear prerequisite instead.
  if ! echo "$mods" | grep -q '^ppp_generic$'; then
    die "ppp_generic is not loaded in the Podman VM; load it explicitly before testing"
  fi

  podman machine ssh -- "test -c /dev/ppp && test -c /dev/net/tun" >/dev/null 2>&1 \
    || die "/dev/ppp or /dev/net/tun is absent in the Podman VM"

  object_must_not_exist network "$WAN_NETWORK"
  object_must_not_exist network "$LAN_NETWORK"
  object_must_not_exist container "$DEVICE_NAME"
  object_must_not_exist container "$SERVER_NAME"
  object_must_not_exist container "$CLIENT_NAME"
  object_must_not_exist container "$ROUTER_NAME"
  object_must_not_exist volume "$TRANSFER_VOLUME"

  if [ "$PARENT_MODE" = pinned ]; then
    [ -n "$PARENT_REF" ] || PARENT_REF=$(git -C "$REPO_DIR" rev-parse origin/master)
    case "$PARENT_REF" in
      [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]*) ;;
      *) die "Pinned parent ref must resolve to a hexadecimal Git commit" ;;
    esac
    PARENT_REF=$(git -C "$REPO_DIR" rev-parse --verify "${PARENT_REF}^{commit}" 2>/dev/null) \
      || die "Pinned parent ref is not available in the local repository"
    git -C "$REPO_DIR" cat-file -e "${PARENT_REF}:vpnsetup_ubuntu.sh" 2>/dev/null \
      || die "Pinned parent ref does not contain vpnsetup_ubuntu.sh"
  fi

  log "Pre-flight OK. Mode: $([ "$DUAL_STACK" = 1 ] && echo 'dual-stack' || echo 'IPv4-only')/$VPN_MODE; parent=$PARENT_MODE${PARENT_REF:+:$PARENT_REF}; platform=$PLATFORM"
}

# ===== Network =====
create_networks() {
  log "Creating isolated Podman WAN and LAN networks"
  CREATED_WAN=1
  podman network create --label "$RUN_LABEL=$RUN_ID" "$WAN_NETWORK" >/dev/null \
    || die "Failed to create WAN network"
  CREATED_LAN=1
  podman network create --internal --label "$RUN_LABEL=$RUN_ID" "$LAN_NETWORK" >/dev/null \
    || die "Failed to create LAN network"
  CREATED_TRANSFER=1
  podman volume create --label "$RUN_LABEL=$RUN_ID" "$TRANSFER_VOLUME" >/dev/null \
    || die "Failed to create disposable transfer volume"
}

build_image() {
  local expected_hash image_hash
  if command -v sha256sum >/dev/null 2>&1; then
    expected_hash=$(
      { sha256sum "$SCRIPT_DIR/Containerfile" | awk '{print $1}'; printf '%s\n' "$BASE_IMAGE"; } \
        | sha256sum | awk '{print $1}'
    )
  else
    expected_hash=$(
      { shasum -a 256 "$SCRIPT_DIR/Containerfile" | awk '{print $1}'; printf '%s\n' "$BASE_IMAGE"; } \
        | shasum -a 256 | awk '{print $1}'
    )
  fi
  if podman image exists "$IMAGE"; then
    local image_arch
    image_arch=$(podman image inspect "$IMAGE" --format '{{.Architecture}}' 2>/dev/null)
    image_hash=$(podman image inspect "$IMAGE" \
      --format '{{index .Labels "io.github.hwdsl2.bonjour-test.containerfile-sha256"}}' 2>/dev/null)
    [ "$image_arch" = "$IMAGE_ARCH" ] \
      || die "Existing image '$IMAGE' has architecture '$image_arch', expected '$IMAGE_ARCH'"
    if [ "$image_hash" = "$expected_hash" ]; then
      log "Using current base image: $IMAGE"
      return
    fi
    log "Rebuilding stale base image: $IMAGE"
  fi

  log "Building disposable systemd base image $BASE_IMAGE for $PLATFORM"
  podman build --platform "$PLATFORM" --build-arg "UBUNTU_IMAGE=$BASE_IMAGE" \
    --label "io.github.hwdsl2.bonjour-test.base=$BASE_IMAGE" \
    --label "io.github.hwdsl2.bonjour-test.containerfile-sha256=$expected_hash" \
    -t "$IMAGE" -f "$SCRIPT_DIR/Containerfile" "$SCRIPT_DIR" >/dev/null \
    || die "Failed to build $IMAGE"
}

container_network_ip() {
  local container=$1 network=$2
  podman inspect "$container" \
    --format "{{(index .NetworkSettings.Networks \"$network\").IPAddress}}" 2>/dev/null
}

container_iface_for_ip() {
  local container=$1 address=$2
  podman exec "$container" ip -o -4 addr show 2>/dev/null \
    | awk -v ip="$address" '$4 ~ ("^" ip "/") {print $2; exit}'
}

# ===== Container management =====
run_container() {
  local name="$1"
  local hostname="$2"
  local mem="$3"
  shift 3
  local net_args=()
  local network
  for network in "$@"; do
    net_args+=(--network "$network")
  done
  local volume_args=()
  local ip_args=()
  local dns_server=1.1.1.1
  if [ "$name" = "$SERVER_NAME" ] || [ "$name" = "$CLIENT_NAME" ]; then
    volume_args+=(--volume "$TRANSFER_VOLUME:/run/bonjour-test-transfer:rw,z")
  fi
  # The one-NIC VPN server lives only on the internal LAN, so resolve through
  # the disposable router exactly as a real private-LAN server would. Other
  # guests retain an external resolver while they are attached to the WAN.
  if [ "$name" = "$SERVER_NAME" ]; then
    [ -n "$ROUTER_LAN_IP" ] && [ -n "$SERVER_STATIC_LAN_IP" ] \
      || die "Router DNS or static test-server address is unavailable"
    dns_server=$ROUTER_LAN_IP
    ip_args+=(--ip "$SERVER_STATIC_LAN_IP")
  fi

  # --systemd=always runs the container's CMD (/sbin/init) under systemd
  # The image has systemd pre-installed (see Containerfile)
  podman run -d \
    --name "$name" \
    --hostname "$hostname" \
    --label "$RUN_LABEL=$RUN_ID" \
    --privileged \
    --cap-add=ALL \
    --device=/dev/ppp \
    --device=/dev/net/tun \
    --dns="$dns_server" \
    --memory="$mem" \
    --systemd=always \
    "${net_args[@]}" \
    ${ip_args[@]+"${ip_args[@]}"} \
    ${volume_args[@]+"${volume_args[@]}"} \
    "$IMAGE" >/dev/null 2>&1 \
    || die "Failed to start container $name"

  case "$name" in
    "$DEVICE_NAME") CREATED_DEVICE=1 ;;
    "$SERVER_NAME") CREATED_SERVER=1 ;;
    "$CLIENT_NAME") CREATED_CLIENT=1 ;;
    "$ROUTER_NAME") CREATED_ROUTER=1 ;;
  esac

  # Wait for systemd to be ready (running or degraded are both fine for our use)
  wait_for_systemd "$name"
}

wait_for_systemd() {
  local name=$1 tries=0
  while ! podman exec "$name" bash -c 'systemctl is-system-running 2>&1 | grep -qE "running|degraded"' 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -gt 30 ] && die "systemd not ready in $name after 30 seconds"
    sleep 1
  done
}

cleanup() {
  log "Cleaning up containers..."
  [ "$CREATED_CLIENT" = 0 ] || podman rm -f "$CLIENT_NAME" >/dev/null 2>&1 || true
  [ "$CREATED_SERVER" = 0 ] || podman rm -f "$SERVER_NAME" >/dev/null 2>&1 || true
  [ "$CREATED_DEVICE" = 0 ] || podman rm -f "$DEVICE_NAME" >/dev/null 2>&1 || true
  [ "$CREATED_ROUTER" = 0 ] || podman rm -f "$ROUTER_NAME" >/dev/null 2>&1 || true
  [ "$CREATED_TRANSFER" = 0 ] || podman volume rm -f "$TRANSFER_VOLUME" >/dev/null 2>&1 || true
  [ "$CREATED_LAN" = 0 ] || podman network rm -f "$LAN_NETWORK" >/dev/null 2>&1 || true
  [ "$CREATED_WAN" = 0 ] || podman network rm -f "$WAN_NETWORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ===== Phase: Bonjour device =====
setup_router() {
  log "Setting up disposable NAT router..."
  run_container "$ROUTER_NAME" bonjour-router "512m" "$WAN_NETWORK" "$LAN_NETWORK"
  ROUTER_WAN_IP=$(container_network_ip "$ROUTER_NAME" "$WAN_NETWORK")
  ROUTER_LAN_IP=$(container_network_ip "$ROUTER_NAME" "$LAN_NETWORK")
  LAN_SUBNET=$(podman network inspect "$LAN_NETWORK" \
    --format '{{(index .Subnets 0).Subnet}}' 2>/dev/null)
  [ -n "$ROUTER_WAN_IP" ] && [ -n "$ROUTER_LAN_IP" ] && [ -n "$LAN_SUBNET" ] \
    || die "Could not determine router addresses or the LAN subnet"
  [ "${LAN_SUBNET#*/}" = 24 ] \
    || die "The disposable LAN must be a dynamically allocated IPv4 /24"
  SERVER_STATIC_LAN_IP="${LAN_SUBNET%.*}.20"

  local router_wan_iface router_lan_iface
  router_wan_iface=$(container_iface_for_ip "$ROUTER_NAME" "$ROUTER_WAN_IP")
  router_lan_iface=$(container_iface_for_ip "$ROUTER_NAME" "$ROUTER_LAN_IP")
  [ -n "$router_wan_iface" ] && [ -n "$router_lan_iface" ] \
    || die "Could not determine both router interfaces"

  if [ "$DUAL_STACK" = 1 ]; then
    podman exec "$ROUTER_NAME" ip -6 addr add "${WAN_ROUTER_IPV6}/64" dev "$router_wan_iface" \
      >/dev/null 2>&1 || die "Could not assign the router WAN IPv6 address"
    podman exec "$ROUTER_NAME" ip -6 addr add "${LAN_ROUTER_IPV6}/64" dev "$router_lan_iface" \
      >/dev/null 2>&1 || die "Could not assign the router LAN IPv6 address"
  fi

  podman exec \
    --env "ROUTER_WAN_IFACE=$router_wan_iface" \
    --env "ROUTER_LAN_IFACE=$router_lan_iface" \
    --env "TEST_LAN_SUBNET=$LAN_SUBNET" \
    "$ROUTER_NAME" bash -c '
      set -e
      sysctl -q -w net.ipv4.ip_forward=1
      iptables -P FORWARD DROP
      iptables -A FORWARD -i "$ROUTER_LAN_IFACE" -o "$ROUTER_WAN_IFACE" -j ACCEPT
      iptables -A FORWARD -i "$ROUTER_WAN_IFACE" -o "$ROUTER_LAN_IFACE" \
        -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      iptables -t nat -A POSTROUTING -s "$TEST_LAN_SUBNET" -o "$ROUTER_WAN_IFACE" -j MASQUERADE
    ' >/dev/null 2>&1 || die "Could not configure the disposable IPv4 router"

  # Provide DNS on the isolated LAN. The server remains single-homed and does
  # not depend on Podman's private DNS implementation being reachable across
  # networks. Installation and daemon output stay private to the guest.
  podman exec \
    --env "ROUTER_LAN_IFACE=$router_lan_iface" \
    --env "ROUTER_LAN_IP=$ROUTER_LAN_IP" \
    "$ROUTER_NAME" bash -c '
      set -e
      exec > /var/log/bonjour-test-router-dns.log 2>&1
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -yqq dnsmasq-base
      dnsmasq \
        --conf-file=/dev/null \
        --interface="$ROUTER_LAN_IFACE" \
        --listen-address="$ROUTER_LAN_IP" \
        --bind-interfaces \
        --no-resolv \
        --server=1.1.1.1 \
        --pid-file=/run/bonjour-test-router-dnsmasq.pid
      dig +short +time=3 +tries=1 @"$ROUTER_LAN_IP" raw.githubusercontent.com A \
        | grep -Eq "^[0-9]+(\.[0-9]+){3}$"
    ' || die "Could not start DNS on the disposable router"
}

setup_device() {
  log "Setting up Bonjour device..."
  # The temporary WAN attachment is used only to install test packages. It is
  # removed before the VPN server/client test begins; the LAN itself is an
  # internal Podman network with no default external route.
  run_container "$DEVICE_NAME" testprinter "512m" "$WAN_NETWORK" "$LAN_NETWORK"
  DEVICE_LAN_IP=$(container_network_ip "$DEVICE_NAME" "$LAN_NETWORK")
  [ -n "$DEVICE_LAN_IP" ] || die "Could not determine the Bonjour device LAN address"
  if [ "$DUAL_STACK" = 1 ]; then
    local device_iface
    device_iface=$(container_iface_for_ip "$DEVICE_NAME" "$DEVICE_LAN_IP")
    [ -n "$device_iface" ] || die "Could not determine the Bonjour device LAN interface"
    podman exec "$DEVICE_NAME" ip -6 addr add "${LAN_DEVICE_IPV6}/64" dev "$device_iface" \
      >/dev/null 2>&1 || die "Could not assign the test device IPv6 address"
  fi

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

    systemctl enable avahi-daemon >/dev/null 2>&1
    systemctl restart avahi-daemon >/dev/null 2>&1
    sleep 2
  ' || die "Device setup failed"

  podman network disconnect "$WAN_NETWORK" "$DEVICE_NAME" >/dev/null 2>&1 \
    || die "Could not remove the Bonjour device's temporary WAN attachment"
  podman exec "$DEVICE_NAME" systemctl restart avahi-daemon >/dev/null 2>&1 \
    || die "Could not restart Avahi after isolating the Bonjour device"
}

# ===== Phase: VPN server =====
install_parent_vpn() {
  local install_env=(
    --env "VPN_PUBLIC_IP=$SERVER_WAN_IP"
    --env "VPN_IPSEC_PSK=bonjour-test-only-psk"
    --env "VPN_USER=bonjour_test"
    --env "VPN_PASSWORD=bonjour-test-only-password"
    --env "VPN_CLIENT_NAME=vpnclient"
    --env "VPN_PROTECT_CONFIG=no"
  )
  if [ "$DUAL_STACK" = 1 ]; then
    install_env+=(--env "VPN_PUBLIC_IP6=$WAN_ROUTER_IPV6")
  fi
  [ -z "${BONJOUR_TEST_VPN_XAUTH_NET:-}" ] \
    || install_env+=(--env "VPN_XAUTH_NET=$BONJOUR_TEST_VPN_XAUTH_NET")
  [ -z "${BONJOUR_TEST_VPN_XAUTH_POOL:-}" ] \
    || install_env+=(--env "VPN_XAUTH_POOL=$BONJOUR_TEST_VPN_XAUTH_POOL")
  [ -z "${BONJOUR_TEST_VPN_IP6_NET:-}" ] \
    || install_env+=(--env "VPN_IP6_NET=$BONJOUR_TEST_VPN_IP6_NET")

  if [ "$PARENT_MODE" = pinned ]; then
    git -C "$REPO_DIR" show "${PARENT_REF}:vpnsetup_ubuntu.sh" \
      | podman exec -i "$SERVER_NAME" sh -c \
          'umask 077; cat > /tmp/vpnsetup_ubuntu.sh' \
      || die "Could not stage the pinned parent installer"
    podman exec --env "TEST_PARENT_REF=$PARENT_REF" "$SERVER_NAME" bash -c '
      set -e
      sed -i \
        -e "s#^  base1=.*#  base1=\"https://raw.githubusercontent.com/hwdsl2/setup-ipsec-vpn/${TEST_PARENT_REF}/extras\"#" \
        -e "s#^  base2=.*#  base2=\"https://raw.githubusercontent.com/hwdsl2/setup-ipsec-vpn/${TEST_PARENT_REF}/extras\"#" \
        /tmp/vpnsetup_ubuntu.sh
      grep -Fq "setup-ipsec-vpn/${TEST_PARENT_REF}/extras" /tmp/vpnsetup_ubuntu.sh
    ' >/dev/null 2>&1 || die "Could not pin the parent helper-script downloads"
  fi

  if [ "$PARENT_MODE" = live ]; then
    podman exec "${install_env[@]}" "$SERVER_NAME" bash -c '
      set -e
      umask 077
      exec > /var/log/bonjour-test-parent-install.log 2>&1
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -yqq wget iproute2 iputils-ping dnsutils
      wget -t 3 -T 30 -q -O /tmp/vpn.sh https://get.vpnsetup.net
      bash /tmp/vpn.sh
      rm -f /tmp/vpn.sh
    ' || die "Live parent VPN installation failed; its private guest log was not displayed"
  else
    podman exec "${install_env[@]}" "$SERVER_NAME" bash -c '
      set -e
      umask 077
      exec > /var/log/bonjour-test-parent-install.log 2>&1
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -yqq wget iproute2 iputils-ping dnsutils
      bash /tmp/vpnsetup_ubuntu.sh
      rm -f /tmp/vpnsetup_ubuntu.sh
    ' || die "Pinned parent VPN installation failed; its private guest log was not displayed"
  fi

  podman exec "$SERVER_NAME" bash -c '
    test -s /etc/ipsec.d/ikev2.conf
    systemctl is-active --quiet ipsec
  ' >/dev/null 2>&1 || die "Parent install did not produce an active IKEv2 server"

  if [ "$VPN_MODE" = ikev2-only ]; then
    podman exec "$SERVER_NAME" bash -c '
      set -e
      if grep -q "^[[:space:]]*ikev1-policy=" /etc/ipsec.conf; then
        sed -i "s/^[[:space:]]*ikev1-policy=.*/  ikev1-policy=drop/" /etc/ipsec.conf
      else
        sed -i "/^[[:space:]]*config setup[[:space:]]*$/a\  ikev1-policy=drop" /etc/ipsec.conf
      fi
      service ipsec restart >/dev/null
      grep -q "^[[:space:]]*ikev1-policy=drop" /etc/ipsec.conf
    ' >/dev/null 2>&1 || die "Could not place the disposable parent in IKEv2-only mode"
  fi
}

load_bonjour_state() {
  local state
  state=$(podman exec "$SERVER_NAME" bash -c '
    set -e
    . /var/lib/bonjour-vpn/config
    printf "%s|%s|%s|%s|%s|%s\n" "$VPN_SUBNET_SAVED" "$VPN_SERVER_IP_SAVED" \
      "${VPN_SUBNET_IPV6_SAVED:-}" "${VPN_SERVER_IP_IPV6_SAVED:-}" \
      "${L2TP_SUBNET_SAVED:-}" "${L2TP_SERVER_IP_SAVED:-}"
  ' 2>/dev/null) || die "Could not read the non-sensitive Bonjour network state"
  IFS='|' read -r VPN_SUBNET VPN_DNS_IP VPN_SUBNET_IPV6 VPN_DNS_IP6 \
    L2TP_SUBNET_STATE L2TP_DNS_IP <<< "$state"
  [ -n "$VPN_SUBNET" ] && [ -n "$VPN_DNS_IP" ] \
    || die "Bonjour network state is incomplete"
}

run_interrupted_enable_recovery_test() {
  log "Testing live interrupted-enable rollback and disable recovery..."
  podman exec "$SERVER_NAME" bash -c '
    set -e
    awk '\''
      !injected && $1 == "persist_firewall" {
        print "  : > /run/bonjour-test-firewall-mutated"
        print "  sleep 300"
        injected=1
      }
      { print }
      END { if (!injected) exit 42 }
    '\'' /tmp/enable_bonjour.sh > /tmp/enable_bonjour-interrupt.sh
    chmod 700 /tmp/enable_bonjour-interrupt.sh
    printf "y\n" > /run/bonjour-test-enable-answer
    setsid bash /tmp/enable_bonjour-interrupt.sh \
      </run/bonjour-test-enable-answer \
      >/var/log/bonjour-test-interrupted-enable.log 2>&1 &
    printf "%s\n" "$!" > /run/bonjour-test-enable-pid
  ' >/dev/null 2>&1 || die "Could not start the interrupted-enable fixture"

  local attempt=0
  while [ "$attempt" -lt 120 ]; do
    podman exec "$SERVER_NAME" test -e /run/bonjour-test-firewall-mutated \
      >/dev/null 2>&1 && break
    attempt=$((attempt + 1))
    sleep 0.5
  done
  podman exec "$SERVER_NAME" test -e /run/bonjour-test-firewall-mutated \
    >/dev/null 2>&1 || die "Interrupted-enable fixture did not reach the firewall transaction"

  if podman exec "$SERVER_NAME" bash -c '
    set -e
    pid=$(cat /run/bonjour-test-enable-pid)
    kill -TERM -- "-$pid"
    attempt=0
    while kill -0 "$pid" 2>/dev/null; do
      state=$(ps -o stat= -p "$pid" 2>/dev/null || true)
      case "$state" in Z*) break ;; esac
      attempt=$((attempt + 1))
      [ "$attempt" -lt 50 ] || exit 1
      sleep 0.2
    done
    test -s /var/lib/bonjour-vpn/incomplete
    . /var/lib/bonjour-vpn/incomplete
    ! iptables -C INPUT -s "$VPN_SUBNET_SAVED" -p udp --dport 53 -j ACCEPT 2>/dev/null
    ! iptables -C INPUT -s "$VPN_SUBNET_SAVED" -p tcp --dport 53 -j ACCEPT 2>/dev/null
    ! iptables -C INPUT -s "$VPN_SUBNET_SAVED" -p udp --dport 5353 -j ACCEPT 2>/dev/null
    ! iptables -t nat -C PREROUTING -s "$VPN_SUBNET_SAVED" -d 224.0.0.251 \
      -p udp --dport 5353 -j DNAT --to-destination "$VPN_SERVER_IP_SAVED:53" 2>/dev/null
  ' >/dev/null 2>&1; then
    pass "interrupted enable retained recovery state and rolled back live firewall rules"
  else
    die "Interrupted enable did not retain a safe, rolled-back recovery state"
  fi

  if podman exec "$SERVER_NAME" bash -c '
    bash /tmp/enable_bonjour.sh </dev/null \
      >/var/log/bonjour-test-blocked-reenable.log 2>&1
  ' >/dev/null 2>&1; then
    die "A second enable ignored the incomplete-operation interlock"
  fi
  podman exec "$SERVER_NAME" grep -Fq \
    'A previous Bonjour VPN enable did not complete.' \
    /var/log/bonjour-test-blocked-reenable.log >/dev/null 2>&1 \
    || die "The second-enable refusal did not identify recovery as required"

  if podman exec "$SERVER_NAME" bash -c '
    set -e
    bash /tmp/disable_bonjour.sh >/var/log/bonjour-test-interrupted-disable.log 2>&1 <<ANSWERS
y
ANSWERS
    test ! -e /var/lib/bonjour-vpn/incomplete
    test ! -e /var/lib/bonjour-vpn/config
    test ! -e /etc/dnsmasq.d/bonjour-vpn.conf
    rm -f /tmp/enable_bonjour-interrupt.sh /run/bonjour-test-enable-answer \
      /run/bonjour-test-enable-pid /run/bonjour-test-firewall-mutated
  ' >/dev/null 2>&1; then
    pass "disable recovered a live interrupted enable"
  else
    die "disable_bonjour.sh could not recover the interrupted enable"
  fi
}

run_lock_contention_test() {
  log "Testing the live operation lock timeout..."
  podman exec "$SERVER_NAME" bash -c '
    set -e
    awk '\''
      !changed && index($0, "flock -w 30 9 || exiterr") {
        sub(/flock -w 30 9/, "flock -w 1 9")
        changed=1
      }
      { print }
      END { if (!changed) exit 42 }
    '\'' /tmp/enable_bonjour.sh > /tmp/enable_bonjour-contention.sh
    chmod 700 /tmp/enable_bonjour-contention.sh
    before=$(sha256sum /var/lib/bonjour-vpn/config | cut -d" " -f1)
    printf "%s\n" "$before" > /run/bonjour-test-state-before
    (
      flock 9
      : > /run/bonjour-test-lock-ready
      sleep 4
    ) 9>/run/bonjour-vpn.lock &
    printf "%s\n" "$!" > /run/bonjour-test-lock-holder
  ' >/dev/null 2>&1 || die "Could not stage the lock-contention fixture"

  local attempt=0
  while [ "$attempt" -lt 40 ]; do
    podman exec "$SERVER_NAME" test -e /run/bonjour-test-lock-ready \
      >/dev/null 2>&1 && break
    attempt=$((attempt + 1))
    sleep 0.25
  done
  podman exec "$SERVER_NAME" test -e /run/bonjour-test-lock-ready \
    >/dev/null 2>&1 || die "Lock holder did not acquire the Bonjour operation lock"

  if podman exec "$SERVER_NAME" bash -c '
    bash /tmp/enable_bonjour-contention.sh \
      >/var/log/bonjour-test-lock-contention.log 2>&1 <<ANSWERS
y
y
ANSWERS
  ' >/dev/null 2>&1; then
    die "Concurrent enable unexpectedly acquired the operation lock"
  fi
  if podman exec "$SERVER_NAME" bash -c '
    set -e
    grep -Fq "Timed out waiting for another Bonjour VPN operation." \
      /var/log/bonjour-test-lock-contention.log
    test ! -e /var/lib/bonjour-vpn/incomplete
    before=$(cat /run/bonjour-test-state-before)
    after=$(sha256sum /var/lib/bonjour-vpn/config | cut -d" " -f1)
    test "$before" = "$after"
    wait "$(cat /run/bonjour-test-lock-holder)" 2>/dev/null || true
    rm -f /tmp/enable_bonjour-contention.sh /run/bonjour-test-lock-ready \
      /run/bonjour-test-lock-holder /run/bonjour-test-state-before
  ' >/dev/null 2>&1; then
    pass "lock contention timed out before mutation and preserved completed state"
  else
    die "Lock-contention timeout did not preserve completed state"
  fi
}

setup_server() {
  log "Setting up VPN server (Libreswan compile, ~2-3 min)..."
  run_container "$SERVER_NAME" vpn-server "3g" "$LAN_NETWORK"
  SERVER_WAN_IP=$ROUTER_WAN_IP
  SERVER_LAN_IP=$(container_network_ip "$SERVER_NAME" "$LAN_NETWORK")
  [ -n "$SERVER_WAN_IP" ] && [ -n "$SERVER_LAN_IP" ] \
    || die "Could not determine both VPN server network addresses"

  local lan_iface
  lan_iface=$(container_iface_for_ip "$SERVER_NAME" "$SERVER_LAN_IP")
  [ -n "$lan_iface" ] || die "Could not determine the VPN server LAN interface"
  podman exec "$SERVER_NAME" ip route replace default via "$ROUTER_LAN_IP" dev "$lan_iface" \
    >/dev/null 2>&1 || die "Could not route the VPN server through the disposable router"
  # Podman does not populate a caller-supplied DNS server for a guest attached
  # only to an --internal network. Install the test router as the guest's sole
  # resolver explicitly; this affects only the disposable container.
  podman exec --env "TEST_DNS=$ROUTER_LAN_IP" "$SERVER_NAME" bash -c '
    set -e
    printf "nameserver %s\n" "$TEST_DNS" > /etc/resolv.conf
    test "$(wc -l < /etc/resolv.conf)" -eq 1
    grep -Fxq "nameserver $TEST_DNS" /etc/resolv.conf
  ' >/dev/null 2>&1 || die "Could not configure DNS in the disposable VPN server"

  if [ "$DUAL_STACK" = 1 ]; then
    podman exec "$SERVER_NAME" ip -6 addr add "${LAN_SERVER_IPV6}/64" dev "$lan_iface" \
      >/dev/null 2>&1 || die "Could not assign the VPN server LAN IPv6 address"
  fi

  local router_wan_iface router_lan_iface
  router_wan_iface=$(container_iface_for_ip "$ROUTER_NAME" "$ROUTER_WAN_IP")
  router_lan_iface=$(container_iface_for_ip "$ROUTER_NAME" "$ROUTER_LAN_IP")
  podman exec \
    --env "ROUTER_WAN_IFACE=$router_wan_iface" \
    --env "ROUTER_LAN_IFACE=$router_lan_iface" \
    --env "ROUTER_PUBLIC_IP=$ROUTER_WAN_IP" \
    --env "VPN_SERVER_LAN_IP=$SERVER_LAN_IP" \
    "$ROUTER_NAME" bash -c '
      set -e
      for port in 500 4500; do
        iptables -t nat -A PREROUTING -i "$ROUTER_WAN_IFACE" -d "$ROUTER_PUBLIC_IP" \
          -p udp --dport "$port" -j DNAT --to-destination "$VPN_SERVER_LAN_IP:$port"
        iptables -A FORWARD -i "$ROUTER_WAN_IFACE" -o "$ROUTER_LAN_IFACE" \
          -p udp -d "$VPN_SERVER_LAN_IP" --dport "$port" -j ACCEPT
      done
      iptables -t nat -A PREROUTING -i "$ROUTER_WAN_IFACE" -d "$ROUTER_PUBLIC_IP" \
        -p esp -j DNAT --to-destination "$VPN_SERVER_LAN_IP"
      iptables -A FORWARD -i "$ROUTER_WAN_IFACE" -o "$ROUTER_LAN_IFACE" \
        -p esp -d "$VPN_SERVER_LAN_IP" -j ACCEPT
    ' >/dev/null 2>&1 || die "Could not configure IKEv2 forwarding on the disposable router"

  podman exec "$SERVER_NAME" ip route get 1.1.1.1 >/dev/null 2>&1 \
    || die "VPN server has no route through the disposable router"
  podman exec "$SERVER_NAME" ping -c 1 -W 2 "$ROUTER_LAN_IP" >/dev/null 2>&1 \
    || die "VPN server cannot reach the disposable router's LAN interface"
  podman exec "$ROUTER_NAME" ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 \
    || die "Disposable router cannot reach the Internet"
  podman exec "$SERVER_NAME" ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 \
    || die "VPN server Internet forwarding failed through the disposable router"
  podman exec "$SERVER_NAME" bash -c '
    dig +short +time=3 +tries=1 @"$1" raw.githubusercontent.com A \
      | grep -Eq "^[0-9]+(\.[0-9]+){3}$"
  ' _ "$ROUTER_LAN_IP" >/dev/null 2>&1 \
    || die "VPN server cannot exchange DNS packets with the disposable router"
  podman exec "$SERVER_NAME" timeout 10 getent ahostsv4 raw.githubusercontent.com \
    >/dev/null 2>&1 || die "VPN server DNS failed through the disposable router"
  podman exec "$SERVER_NAME" timeout 15 wget -q --spider \
    "https://raw.githubusercontent.com/hwdsl2/setup-ipsec-vpn/${PARENT_REF:-master}/vpnsetup_ubuntu.sh" \
    >/dev/null 2>&1 || die "VPN server HTTPS failed through the disposable router"

  # Copy bonjour scripts into the container
  podman cp "$REPO_DIR/extras/enable_bonjour.sh"  "$SERVER_NAME:/tmp/enable_bonjour.sh"
  podman cp "$REPO_DIR/extras/disable_bonjour.sh" "$SERVER_NAME:/tmp/disable_bonjour.sh"

  install_parent_vpn

  # Declare a second project-owned VPN subnet before Bonjour is installed.
  # The migration test later moves the IKEv2 pool between these two declared
  # coordinates. subnet_for_pool must continue to reject arbitrary ranges
  # that the parent VPN configuration does not identify.
  podman exec "$SERVER_NAME" bash -c '
    set -e
    grep -q "^[[:space:]]*virtual-private=" /etc/ipsec.conf
    if ! grep -q "%v4:!10.254.77.0/24" /etc/ipsec.conf; then
      sed -i "/^[[:space:]]*virtual-private=/s|$|,%v4:!10.254.77.0/24|" /etc/ipsec.conf
    fi
    grep -q "%v4:!10.254.77.0/24" /etc/ipsec.conf
  ' >/dev/null 2>&1 || die "Could not stage the alternate parent VPN subnet"

  run_interrupted_enable_recovery_test

  log "Running enable_bonjour.sh..."
  if ! podman exec "$SERVER_NAME" bash -c '
    umask 077
    bash /tmp/enable_bonjour.sh > /var/log/bonjour-test-enable.log 2>&1 <<ANSWERS
y
ANSWERS
  '; then
    # Report only the enable script's own generic error/warning classifications.
    # Never expose the full guest log, which shares a filesystem with synthetic
    # client credentials created by the parent installer.
    local safe_enable_reason
    safe_enable_reason=$(podman exec "$SERVER_NAME" awk '
      /^Error: / {last=$0}
      /^  WARNING: / {last=$0}
      END {
        if (last != "") print last
        else print "no classified error was emitted"
      }
    ' /var/log/bonjour-test-enable.log 2>/dev/null || true)
    die "enable_bonjour.sh failed ($safe_enable_reason); the private guest log was not displayed"
  fi

  sleep 5
  load_bonjour_state
  run_lock_contention_test
}

# ===== Phase: IKEv2 client =====
setup_client() {
  log "Setting up IKEv2 client..."
  run_container "$CLIENT_NAME" vpn-client "1g" "$WAN_NETWORK"

  # A valid WAN/LAN fixture must not give the pre-VPN client a direct path to
  # the Bonjour device. Abort before transferring any IKEv2 material if the
  # Podman backend routes between the two test bridges.
  if podman exec "$CLIENT_NAME" ping -c 1 -W 1 "$DEVICE_LAN_IP" >/dev/null 2>&1; then
    die "WAN/LAN isolation failed: the client reached the Bonjour device before VPN setup"
  fi
  podman exec "$CLIENT_NAME" ping -c 1 -W 2 "$SERVER_WAN_IP" >/dev/null 2>&1 \
    || die "The client cannot reach the VPN server on the test WAN"

  podman exec "$CLIENT_NAME" bash -c '
    set -e
    exec > /var/log/bonjour-test-client-install.log 2>&1
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -yqq strongswan strongswan-swanctl dnsutils iproute2 iputils-ping
  ' || die "StrongSwan client installation failed; its private guest log was not displayed"

  # Copy the encrypted client bundle only into the disposable Podman volume.
  # No certificate, key, or bundle crosses the host filesystem or stdout.
  podman exec "$SERVER_NAME" bash -c '
    set -e
    umask 077
    if test -s /root/vpnclient.p12; then
      bundle=/root/vpnclient.p12
    elif test -s /etc/ipsec.d/vpnclient.p12; then
      bundle=/etc/ipsec.d/vpnclient.p12
    else
      exit 1
    fi
    install -m 0600 "$bundle" /run/bonjour-test-transfer/vpnclient.p12
    rm -f /root/vpnclient.p12 /root/vpnclient.sswan /root/vpnclient.mobileconfig
    rm -f /etc/ipsec.d/vpnclient.p12 /etc/ipsec.d/vpnclient.sswan \
      /etc/ipsec.d/vpnclient.mobileconfig
  ' >/dev/null 2>&1 || die "Could not place the client bundle in the disposable transfer volume"

  podman exec "$CLIENT_NAME" bash -c '
    set -e
    exec > /var/log/bonjour-test-client-import.log 2>&1

    mkdir -p /etc/swanctl/x509ca /etc/swanctl/x509 /etc/swanctl/private /etc/swanctl/conf.d

    bundle=/run/bonjour-test-transfer/vpnclient.p12
    openssl pkcs12 -in "$bundle" -cacerts -nokeys -out /etc/swanctl/x509ca/ca.pem -passin pass: -legacy 2>/dev/null || \
      openssl pkcs12 -in "$bundle" -cacerts -nokeys -out /etc/swanctl/x509ca/ca.pem -passin pass:
    openssl pkcs12 -in "$bundle" -clcerts -nokeys -out /etc/swanctl/x509/client.pem -passin pass: -legacy 2>/dev/null || \
      openssl pkcs12 -in "$bundle" -clcerts -nokeys -out /etc/swanctl/x509/client.pem -passin pass:
    openssl pkcs12 -in "$bundle" -nocerts -nodes -out /etc/swanctl/private/client.key -passin pass: -legacy 2>/dev/null || \
      openssl pkcs12 -in "$bundle" -nocerts -nodes -out /etc/swanctl/private/client.key -passin pass:
    chmod 0600 /etc/swanctl/private/client.key
    rm -f "$bundle"
  ' || die "Client bundle import failed; no certificate or key output was displayed"

  # Write only the non-sensitive connection settings directly into the guest.
  # The host never receives a client profile or certificate bundle.
  local client_vips='0.0.0.0' client_remote_ts='0.0.0.0/0'
  if [ "$DUAL_STACK" = 1 ]; then
    client_vips='0.0.0.0, ::'
    client_remote_ts='0.0.0.0/0, ::/0'
  fi
  podman exec -i "$CLIENT_NAME" sh -c 'umask 077; cat > /etc/swanctl/conf.d/myvpn.conf' << EOF
connections {
  myvpn {
    remote_addrs = ${SERVER_WAN_IP}
    vips = ${client_vips}
    local {
      auth = pubkey
      certs = client.pem
      id = vpnclient
    }
    remote {
      auth = pubkey
      id = ${SERVER_WAN_IP}
    }
    children {
      myvpn {
        remote_ts = ${client_remote_ts}
        start_action = none
      }
    }
  }
}
EOF

  if ! podman exec "$CLIENT_NAME" bash -c '
    set -e
    exec > /var/log/bonjour-test-client-connect.log 2>&1
    ipsec restart
    sleep 3
    swanctl --load-all
    timeout 30 swanctl --initiate --child myvpn
    umask 077
    {
      printf "ike_established=%s\n" \
        "$(swanctl --list-sas 2>/dev/null | grep -c "ESTABLISHED" || true)"
      printf "child_installed=%s\n" \
        "$(swanctl --list-sas 2>/dev/null | grep -c "INSTALLED" || true)"
      printf "xfrm_states=%s\n" \
        "$(ip xfrm state 2>/dev/null | grep -c "^src " || true)"
      printf "vpn_v4_addresses=%s\n" \
        "$(ip -o -4 addr show 2>/dev/null | awk "\$4 ~ /^192\\.168\\.43\\./ {n++} END {print n+0}")"
      printf "vpn_v6_addresses=%s\n" \
        "$(ip -o -6 addr show 2>/dev/null | awk "\$4 ~ /^f[dc]/ {n++} END {print n+0}")"
    } > /run/bonjour-test-post-init-counts
    sleep 2
  '; then
    local safe_client_reason
    safe_client_reason=$(podman exec "$CLIENT_NAME" awk '
      BEGIN { reason="unclassified" }
      /AUTHENTICATION_FAILED/ { reason="authentication-failed" }
      /NO_PROPOSAL_CHOSEN/ { reason="no-proposal" }
      /TS_UNACCEPTABLE/ { reason="traffic-selectors" }
      /unable to install IPsec policies/ { reason="policy-install-failed" }
      /no response/ { reason="no-response" }
      /giving up/ { reason="giving-up" }
      /initiate failed/ { reason="initiate-failed" }
      END { print reason }
    ' /var/log/bonjour-test-client-connect.log 2>/dev/null || true)
    die "IKEv2 client connection failed (${safe_client_reason:-unclassified}); its private guest log was not displayed"
  fi

  podman exec "$SERVER_NAME" test ! -e /run/bonjour-test-transfer/vpnclient.p12 \
    >/dev/null 2>&1 || die "Disposable transfer bundle was not removed"
}

# ===== Tests =====
run_server_tests() {
  echo ""
  echo -e "${BOLD}========== Server-Side Tests ==========${NC}"
  echo ""

  if podman exec --env "EXPECTED_MODE=$VPN_MODE" "$SERVER_NAME" bash -c '
      . /var/lib/bonjour-vpn/config
      if [ "$EXPECTED_MODE" = ikev2-only ]; then
        [ "$HAS_IKEV2_SAVED" = 1 ] && [ "$HAS_XAUTH_SAVED" = 0 ] && [ "$HAS_L2TP_SAVED" = 0 ]
      else
        [ "$HAS_IKEV2_SAVED" = 1 ] && [ "$HAS_XAUTH_SAVED" = 1 ] && [ "$HAS_L2TP_SAVED" = 1 ]
      fi
    ' >/dev/null 2>&1; then
    pass "VPN mode detection matched the parent configuration ($VPN_MODE)"
  else
    fail "VPN mode detection did not match the parent configuration ($VPN_MODE)"
  fi

  if [ "$VPN_MODE" = all ]; then
    if podman exec --env "VPN4_DNS=$VPN_DNS_IP" --env "L2TP_DNS=$L2TP_DNS_IP" \
      "$SERVER_NAME" bash -c '
        dns_values=$(sed -n "/conn xauth-psk/,/^conn /{ /modecfgdns=/p; }" /etc/ipsec.conf \
          | head -n 1 | sed "s/.*modecfgdns=//")
        dns_values=${dns_values#\"}
        dns_values=${dns_values%\"}
        printf "%s\n" $dns_values | grep -Fxq "$VPN4_DNS"
        sed -n "/conn xauth-psk/,/^conn /{ /modecfgdomains=/p; }" /etc/ipsec.conf \
          | grep -Fq "local"
        grep -Fxq "ms-dns $L2TP_DNS" /etc/ppp/options.xl2tpd
      ' >/dev/null 2>&1; then
      pass "XAuth and L2TP client DNS settings target the Bonjour proxy"
    else
      fail "XAuth or L2TP client DNS settings do not target the Bonjour proxy"
    fi
    if podman exec --env "L2TP_NET=$L2TP_SUBNET_STATE" --env "L2TP_DNS=$L2TP_DNS_IP" \
      "$SERVER_NAME" bash -c '
        iptables -C INPUT -s "$L2TP_NET" -p udp --dport 53 -j ACCEPT
        iptables -C INPUT -s "$L2TP_NET" -p tcp --dport 53 -j ACCEPT
        iptables -C INPUT -s "$L2TP_NET" -p udp --dport 5353 -j ACCEPT
        iptables -t nat -C PREROUTING -s "$L2TP_NET" -d 224.0.0.251 \
          -p udp --dport 5353 -j DNAT --to-destination "$L2TP_DNS:53"
      ' >/dev/null 2>&1 \
      && [ -n "$(run_dig "$SERVER_NAME" "@${L2TP_DNS_IP}" _ipp._tcp.local PTR)" ]; then
      pass "L2TP DNS endpoint and exact firewall rules are functional"
    else
      fail "L2TP DNS endpoint or firewall rules are incomplete"
    fi
  fi

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
  if podman exec --env "EXPECTED_IP=$VPN_DNS_IP" "$SERVER_NAME" bash -c '
       ip -4 -o addr show dev lo 2>/dev/null \
         | awk -v wanted="$EXPECTED_IP" \
           '\''{ split($4, value, "/"); if (value[1] == wanted) found=1 } END { exit !found }'\''
     '; then
    pass "VPN IP $VPN_DNS_IP on loopback"
  else
    fail "VPN IP $VPN_DNS_IP NOT on loopback"
  fi

  # Test 4: IKEv2 modecfgdns updated
  if podman exec --env "EXPECTED_IP=$VPN_DNS_IP" "$SERVER_NAME" bash -c '
       dns_values=$(sed -n "s/^[[:space:]]*modecfgdns=//p" /etc/ipsec.d/ikev2.conf \
         | head -n 1)
       dns_values=${dns_values#\"}
       dns_values=${dns_values%\"}
       printf "%s\n" $dns_values | grep -Fxq "$EXPECTED_IP"
     ' 2>/dev/null; then
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

  # Test 10: DNS-SD enumeration over both UDP and TCP.
  local sd
  sd=$(run_dig "$SERVER_NAME" "@${VPN_DNS_IP}" _services._dns-sd._udp.local PTR)
  expect_exact_lines "$sd" "DNS-SD UDP returned the fixture service types" \
    '_airplay._tcp.local.' '_ipp._tcp.local.'
  expect_exact_lines \
    "$(run_dig_tcp "$SERVER_NAME" "@${VPN_DNS_IP}" _services._dns-sd._udp.local PTR)" \
    "DNS-SD TCP returned the fixture service types" \
    '_airplay._tcp.local.' '_ipp._tcp.local.'

  # Test 11: IPP PTR/SRV/TXT and host A records.
  local ipp
  ipp=$(run_dig "$SERVER_NAME" "@${VPN_DNS_IP}" _ipp._tcp.local PTR)
  local ipp_instance='test\032printer._ipp._tcp.local.' ipp_txt
  expect_exact_lines "$ipp" "IPP PTR matched the fixture instance" "$ipp_instance"
  expect_exact_lines \
    "$(run_dig "$SERVER_NAME" "@${VPN_DNS_IP}" "$ipp_instance" SRV)" \
    "IPP SRV matched port and target" '0 0 631 testprinter.local.'
  ipp_txt=$(run_dig "$SERVER_NAME" "@${VPN_DNS_IP}" "$ipp_instance" TXT)
  if [ "$(printf '%s\n' "$ipp_txt" | wc -l | tr -d ' ')" = 1 ] \
    && printf '%s\n' "$ipp_txt" | grep -Fq '"txtver=1"' \
    && printf '%s\n' "$ipp_txt" | grep -Fq '"pdl=application/pdf"'; then
    pass "IPP TXT matched both fixture attributes"
  else
    fail "IPP TXT did not match both fixture attributes"
  fi
  expect_exact_lines \
    "$(run_dig "$SERVER_NAME" "@${VPN_DNS_IP}" testprinter.local A)" \
    "fixture hostname A record matched the device" "$DEVICE_LAN_IP"

  # Test 12: AirPlay lookup
  local ap
  ap=$(run_dig "$SERVER_NAME" "@${VPN_DNS_IP}" _airplay._tcp.local PTR)
  local ap_instance='test\032airplay._airplay._tcp.local.' ap_txt
  expect_exact_lines "$ap" "AirPlay PTR matched the fixture instance" "$ap_instance"
  expect_exact_lines \
    "$(run_dig "$SERVER_NAME" "@${VPN_DNS_IP}" "$ap_instance" SRV)" \
    "AirPlay SRV matched port and target" '0 0 7000 testprinter.local.'
  ap_txt=$(run_dig "$SERVER_NAME" "@${VPN_DNS_IP}" "$ap_instance" TXT)
  expect_exact_lines "$ap_txt" "AirPlay TXT matched the fixture model" '"model=AppleTV3,1"'

  # Test 13: Upstream DNS still works
  local up
  up=$(run_dig "$SERVER_NAME" "@${VPN_DNS_IP}" google.com A)
  if [ -n "$up" ]; then
    pass "upstream DNS resolved over UDP"
  else
    fail "upstream DNS over UDP broken"
  fi
  if [ -n "$(run_dig_tcp "$SERVER_NAME" "@${VPN_DNS_IP}" google.com A)" ]; then
    pass "upstream DNS resolved over TCP"
  else
    fail "upstream DNS over TCP broken"
  fi

  # Test 14: iptables DNS rules present for the detected project subnet.
  if podman exec "$SERVER_NAME" iptables -C INPUT -s "$VPN_SUBNET" -p udp --dport 53 -j ACCEPT 2>/dev/null \
     && podman exec "$SERVER_NAME" iptables -C INPUT -s "$VPN_SUBNET" -p tcp --dport 53 -j ACCEPT 2>/dev/null; then
    pass "iptables UDP/TCP DNS rules active for $VPN_SUBNET"
  else
    fail "iptables UDP/TCP DNS rule missing for $VPN_SUBNET"
  fi

  # ===== IPv4-only guard tests =====
  if [ "$DUAL_STACK" = 0 ]; then
    # Test 15: On IPv4-only, the hosts file must NOT contain IPv6 addresses
    # from the LAN. Even though avahi-browse discovers IPv6 addresses for
    # LAN devices, the cache warmer's link-local filter should strip fe80::
    # addresses, and any remaining global IPv6 should appear. This is a
    # behavioral change from the original code — we now include AAAA records
    # even on IPv4-only VPNs. Verify the behavior is consistent.
    local v6_in_hosts
    v6_in_hosts=$(podman exec "$SERVER_NAME" bash -c \
      "grep -cE '^[0-9a-fA-F]*:' /etc/bonjour-vpn-hosts 2>/dev/null || true" \
      2>/dev/null)
    [ -n "$v6_in_hosts" ] || v6_in_hosts=0
    # On IPv4-only test env, the device container has an IPv4 address only
    # (no dual-stack network), so no AAAA entries should appear.
    if [ "$v6_in_hosts" = "0" ]; then
      pass "IPv4-only: no IPv6 entries in hosts file"
    else
      fail "IPv4-only: unexpected IPv6 entries in hosts file ($v6_in_hosts)"
    fi

    # Test 16: Consolidated state records IPv4-only mode and no legacy
    # minute-by-minute firewall mutator remains installed.
    if podman exec "$SERVER_NAME" bash -c \
         "grep -q 'HAS_IPV6_SAVED=.0.' /var/lib/bonjour-vpn/config \
          && test ! -e /var/lib/bonjour-vpn/ipv6-state \
          && test ! -e /var/lib/bonjour-vpn/ipv6-enabled \
          && test ! -e /usr/local/sbin/bonjour-vpn-ipv6-sync"; then
      pass "IPv4-only: consolidated state is IPv4-only and legacy mutator is absent"
    else
      fail "IPv4-only: state or legacy IPv6 cleanup is incorrect"
    fi
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

    if podman exec --env "EXPECTED_V6_SUBNET=$VPN_SUBNET_IPV6" "$SERVER_NAME" \
      bash -c '[ -n "$(ip -6 route show exact "$EXPECTED_V6_SUBNET" 2>/dev/null)" ]'; then
      pass "IPv6 VPN client return route installed"
    else
      fail "IPv6 VPN client return route missing"
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
    expect_exact_lines "$aaaa" "AAAA query matched the fixture device" "$LAN_DEVICE_IPV6"

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

    # ===== Explicit IPv6 reconfiguration =====

    # IPv6.9: no independent background process may mutate VPN firewall or
    # loopback state. All transitions require an explicit script re-run.
    if podman exec "$SERVER_NAME" bash -c \
         "test ! -e /usr/local/sbin/bonjour-vpn-ipv6-sync \
          && test ! -e /var/lib/bonjour-vpn/ipv6-state \
          && test ! -e /var/lib/bonjour-vpn/ipv6-enabled \
          && ! grep -q 'bonjour-vpn-ipv6-sync' /usr/local/bin/bonjour-vpn-watch"; then
      pass "IPv6 state has one owner and no background firewall mutator"
    else
      fail "legacy IPv6 sync runtime is still installed or referenced"
    fi

    # IPv6.10: consolidated state reflects the dual-stack installation.
    if podman exec --env "EXPECTED_V6_SUBNET=$VPN_SUBNET_IPV6" "$SERVER_NAME" bash -c '
         . /var/lib/bonjour-vpn/config
         [ "$HAS_IPV6_SAVED" = 1 ] && [ "$VPN_SUBNET_IPV6_SAVED" = "$EXPECTED_V6_SUBNET" ]
       '; then
      pass "consolidated state records the dual-stack configuration"
    else
      fail "consolidated IPv6 state is missing or incorrect"
    fi

    # IPv6.11: simulate disabling IPv6, then explicitly re-run the setup.
    if podman exec "$SERVER_NAME" bash -c '
      set -e
      /bin/cp -f /etc/ipsec.d/ikev2.conf /etc/ipsec.d/ikev2.conf.explicit-v6-orig
      sed -i -E "/rightaddresspool=/s/,[^,\"]*:[^,\"]*//" /etc/ipsec.d/ikev2.conf
      bash /tmp/enable_bonjour.sh <<ANSWERS >/dev/null 2>&1
y
y
ANSWERS
    '; then
      pass "explicit reconfiguration accepted the IPv6 on-to-off transition"
    else
      fail "explicit IPv6 on-to-off reconfiguration failed"
    fi

    if podman exec --env "OLD_V6_SUBNET=$VPN_SUBNET_IPV6" --env "OLD_V6_DNS=$VPN_DNS_IP6" \
         "$SERVER_NAME" bash -c '
          grep -q "HAS_IPV6_SAVED=.0." /var/lib/bonjour-vpn/config \
          && ! ip -6 addr show dev lo | grep -Fq "${OLD_V6_DNS}/" \
          && [ -z "$(ip -6 route show exact "$OLD_V6_SUBNET" 2>/dev/null)" ] \
          && ! ip6tables -C INPUT -s "$OLD_V6_SUBNET" -p udp --dport 53 -j ACCEPT 2>/dev/null \
          && ! grep -F "$OLD_V6_SUBNET" /etc/ip6tables.rules 2>/dev/null | grep -qE -- "--dport 53|ff02::fb"
         '; then
      pass "explicit IPv6 teardown updated state, loopback, live rules and persistence"
    else
      fail "explicit IPv6 teardown left stale state or firewall configuration"
    fi

    # IPv6.12: restore the pool and explicitly re-run setup to turn IPv6 on.
    if podman exec "$SERVER_NAME" bash -c '
      set -e
      /bin/cp -f /etc/ipsec.d/ikev2.conf.explicit-v6-orig /etc/ipsec.d/ikev2.conf
      bash /tmp/enable_bonjour.sh <<ANSWERS >/dev/null 2>&1
y
y
ANSWERS
      sleep 2
    '; then
      pass "explicit reconfiguration accepted the IPv6 off-to-on transition"
    else
      fail "explicit IPv6 off-to-on reconfiguration failed"
    fi

    if podman exec --env "EXPECTED_V6_SUBNET=$VPN_SUBNET_IPV6" --env "EXPECTED_V6_DNS=$VPN_DNS_IP6" \
         "$SERVER_NAME" bash -c '
          . /var/lib/bonjour-vpn/config
          [ "$HAS_IPV6_SAVED" = 1 ] \
          && [ "$VPN_SUBNET_IPV6_SAVED" = "$EXPECTED_V6_SUBNET" ] \
          && [ "$VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT_SAVED" = 0 ] \
          && ip -6 addr show dev lo | grep -Fq "${EXPECTED_V6_DNS}/" \
          && [ -n "$(ip -6 route show exact "$EXPECTED_V6_SUBNET" 2>/dev/null)" ] \
          && ip6tables -C INPUT -s "$EXPECTED_V6_SUBNET" -p udp --dport 53 -j ACCEPT 2>/dev/null \
          && grep -F "$EXPECTED_V6_SUBNET" /etc/ip6tables.rules 2>/dev/null | grep -q -- "--dport 53" \
          && ss -ulnp 2>/dev/null | grep -E ":53 " | grep -Fq "[${EXPECTED_V6_DNS}]:53"
         '; then
      pass "explicit IPv6 apply updated state, loopback, live rules, persistence and dnsmasq"
    else
      fail "explicit IPv6 apply did not restore the complete runtime state"
    fi

    local post_transition_aaaa
    post_transition_aaaa=$(podman exec "$SERVER_NAME" bash -c \
      "dig +short +time=3 @${VPN_DNS_IP6} testprinter.local AAAA 2>/dev/null | grep -v '^;;'" \
      2>/dev/null || true)
    expect_exact_lines "$post_transition_aaaa" \
      "post-transition IPv6 DNS returned the fixture address" "$LAN_DEVICE_IPV6"
  fi
}

run_ipv4_reconfiguration_test() {
  echo ""
  echo -e "${BOLD}========== IPv4 Subnet Reconfiguration ==========${NC}"
  echo ""

  local original_subnet=$VPN_SUBNET original_dns=$VPN_DNS_IP
  local migration_subnet='10.254.77.0/24'
  local migration_pool='10.254.77.10-10.254.77.250'
  local migration_sentinel='10.254.77.252'

  if podman exec \
    --env "ORIGINAL_NET=$original_subnet" \
    --env "ORIGINAL_DNS=$original_dns" \
    --env "MIGRATION_POOL=$migration_pool" \
    --env "MIGRATION_SENTINEL=$migration_sentinel" \
    "$SERVER_NAME" bash -c '
      set -e
      printf "copy-original\n" > /run/bonjour-test-v4-stage
      /bin/cp -f /etc/ipsec.d/ikev2.conf \
        /etc/ipsec.d/ikev2.conf.explicit-v4-orig
      original_range=$(sed -n "s/.*rightaddresspool=//p" /etc/ipsec.d/ikev2.conf \
        | head -n 1 | tr ",\"" "\n" | grep -E "^[0-9]+(\.[0-9]+){3}-" | head -n 1)
      test -n "$original_range"
      printf "replace-pool\n" > /run/bonjour-test-v4-stage
      escaped=$(printf "%s" "$original_range" | sed "s/[][\\.^$*+?{}|()]/\\\\&/g")
      sed -i "s#${escaped}#${MIGRATION_POOL}#" /etc/ipsec.d/ikev2.conf
      grep -Fq "rightaddresspool=${MIGRATION_POOL}" /etc/ipsec.d/ikev2.conf
      ip -4 addr add "${MIGRATION_SENTINEL}/32" dev lo
      printf "run-enable\n" > /run/bonjour-test-v4-stage
      bash /tmp/enable_bonjour.sh >/var/log/bonjour-test-v4-migrate.log 2>&1 <<ANSWERS
y
y
ANSWERS
      printf "validate-state\n" > /run/bonjour-test-v4-stage
      . /var/lib/bonjour-vpn/config
      test "$VPN_SUBNET_SAVED" = "10.254.77.0/24"
      case "$VPN_SERVER_IP_SAVED" in 10.254.77.*) ;; *) exit 1 ;; esac
      test "$VPN_SERVER_IP_SAVED" != "$MIGRATION_SENTINEL"
      printf "validate-loopback\n" > /run/bonjour-test-v4-stage
      ! ip -4 -o addr show dev lo | grep -Fq " ${ORIGINAL_DNS}/32 "
      ip -4 -o addr show dev lo | grep -Fq " ${MIGRATION_SENTINEL}/32 "
      printf "validate-old-rules-absent\n" > /run/bonjour-test-v4-stage
      ! iptables -S INPUT | grep -F -- "-s ${ORIGINAL_NET}" \
        | grep -Eq -- "--dport (53|5353)"
      ! iptables -t nat -S PREROUTING | grep -F -- "-s ${ORIGINAL_NET}" \
        | grep -Fq -- "--dport 5353"
      printf "validate-new-rules\n" > /run/bonjour-test-v4-stage
      test "$(iptables -S INPUT | grep -F -- "-s ${VPN_SUBNET_SAVED}" \
        | grep -Ec -- "--dport (53|5353)")" -eq 3
      iptables -t nat -C PREROUTING -s "$VPN_SUBNET_SAVED" -d 224.0.0.251 \
        -p udp --dport 5353 -j DNAT --to-destination "$VPN_SERVER_IP_SAVED:53"
    ' >/dev/null 2>&1; then
    pass "live reconfiguration migrated endpoint, loopback and firewall to a changed IPv4 subnet"
  else
    local migration_stage migration_reason
    migration_stage=$(podman exec "$SERVER_NAME" cat /run/bonjour-test-v4-stage 2>/dev/null || true)
    migration_reason=$(podman exec "$SERVER_NAME" awk '
      /^Error: / {last=$0}
      /^  WARNING: / {last=$0}
      END {if (last != "") print last; else print "no classified error"}
    ' /var/log/bonjour-test-v4-migrate.log 2>/dev/null || true)
    die "Live IPv4 subnet migration was incomplete (stage=${migration_stage:-unknown}; ${migration_reason:-no classified error})"
  fi

  if podman exec \
    --env "ORIGINAL_NET=$original_subnet" \
    --env "ORIGINAL_DNS=$original_dns" \
    --env "MIGRATION_NET=$migration_subnet" \
    --env "MIGRATION_SENTINEL=$migration_sentinel" \
    "$SERVER_NAME" bash -c '
      set -e
      printf "capture-migration\n" > /run/bonjour-test-v4-stage
      . /var/lib/bonjour-vpn/config
      migration_dns=$VPN_SERVER_IP_SAVED
      /bin/cp -f /etc/ipsec.d/ikev2.conf.explicit-v4-orig /etc/ipsec.d/ikev2.conf
      printf "run-restore\n" > /run/bonjour-test-v4-stage
      bash /tmp/enable_bonjour.sh >/var/log/bonjour-test-v4-restore.log 2>&1 <<ANSWERS
y
y
ANSWERS
      printf "validate-restored-state\n" > /run/bonjour-test-v4-stage
      . /var/lib/bonjour-vpn/config
      test "$VPN_SUBNET_SAVED" = "$ORIGINAL_NET"
      test "$VPN_SERVER_IP_SAVED" = "$ORIGINAL_DNS"
      printf "validate-restored-loopback\n" > /run/bonjour-test-v4-stage
      ! ip -4 -o addr show dev lo | grep -Fq " ${migration_dns}/32 "
      ip -4 -o addr show dev lo | grep -Fq " ${MIGRATION_SENTINEL}/32 "
      printf "validate-migration-rules-absent\n" > /run/bonjour-test-v4-stage
      ! iptables -S INPUT | grep -F -- "-s ${MIGRATION_NET}" \
        | grep -Eq -- "--dport (53|5353)"
      ! iptables -t nat -S PREROUTING | grep -F -- "-s ${MIGRATION_NET}" \
        | grep -Fq -- "--dport 5353"
      printf "validate-original-rules\n" > /run/bonjour-test-v4-stage
      test "$(iptables -S INPUT | grep -F -- "-s ${ORIGINAL_NET}" \
        | grep -Ec -- "--dport (53|5353)")" -eq 3
      iptables -t nat -C PREROUTING -s "$ORIGINAL_NET" -d 224.0.0.251 \
        -p udp --dport 5353 -j DNAT --to-destination "$ORIGINAL_DNS:53"
      ip -4 addr del "${MIGRATION_SENTINEL}/32" dev lo
      /bin/rm -f /etc/ipsec.d/ikev2.conf.explicit-v4-orig /run/bonjour-test-v4-stage
    ' >/dev/null 2>&1; then
    pass "live reconfiguration removed transitional state and preserved an unrelated loopback address"
  else
    local restoration_stage restoration_reason
    restoration_stage=$(podman exec "$SERVER_NAME" cat /run/bonjour-test-v4-stage 2>/dev/null || true)
    restoration_reason=$(podman exec "$SERVER_NAME" awk '
      /^Error: / {last=$0}
      /^  WARNING: / {last=$0}
      END {if (last != "") print last; else print "no classified error"}
    ' /var/log/bonjour-test-v4-restore.log 2>/dev/null || true)
    die "Live IPv4 subnet restoration was incomplete (stage=${restoration_stage:-unknown}; ${restoration_reason:-no classified error})"
  fi

  load_bonjour_state
}

run_idempotency_test() {
  echo ""
  echo -e "${BOLD}========== Idempotency (double-run) ==========${NC}"
  echo ""

  # Snapshot current state
  local rules_before v6rules_before conf_before listen_before_shape
  rules_before=$(podman exec --env "VPN4_NET=$VPN_SUBNET" --env "VPN4_DNS=$VPN_DNS_IP" \
    "$SERVER_NAME" bash -c '
      iptables -S INPUT | grep -F -- "-s $VPN4_NET" | grep -E -- "--dport (53|5353)"
      iptables -t nat -S PREROUTING | grep -F -- "-s $VPN4_NET" \
        | grep -F -- "-d 224.0.0.251/32" | grep -F -- "--dport 5353" \
        | grep -F -- "--to-destination $VPN4_DNS:53"
    ' 2>/dev/null | LC_ALL=C sort)
  [ "$(printf '%s\n' "$rules_before" | sed '/^$/d' | wc -l | tr -d ' ')" = 4 ] \
    || fail "idempotent: expected four exact IPv4 Bonjour rules before re-run"
  v6rules_before=""
  if [ "$DUAL_STACK" = 1 ]; then
    v6rules_before=$(podman exec --env "VPN6_NET=$VPN_SUBNET_IPV6" --env "VPN6_DNS=$VPN_DNS_IP6" \
      "$SERVER_NAME" bash -c '
        ip6tables -S INPUT | grep -F -- "-s $VPN6_NET" | grep -E -- "--dport (53|5353)"
        ip6tables -t nat -S PREROUTING | grep -F -- "-s $VPN6_NET" \
          | grep -F -- "-d ff02::fb/128" | grep -F -- "--dport 5353" \
          | grep -F -- "--to-destination [$VPN6_DNS]:53"
      ' 2>/dev/null | LC_ALL=C sort)
    [ "$(printf '%s\n' "$v6rules_before" | sed '/^$/d' | wc -l | tr -d ' ')" = 4 ] \
      || fail "idempotent: expected four exact IPv6 Bonjour rules before re-run"
  fi
  conf_before=$(podman exec "$SERVER_NAME" sha256sum \
    /etc/dnsmasq.d/bonjour-vpn.conf 2>/dev/null | awk '{print $1}')
  [ -n "$conf_before" ] || fail "idempotent: dnsmasq config checksum was unavailable"
  podman exec "$SERVER_NAME" /bin/cp -p /etc/dnsmasq.d/bonjour-vpn.conf \
    /run/bonjour-test-dnsmasq-before.conf >/dev/null 2>&1 \
    || fail "idempotent: dnsmasq config diagnostic snapshot was unavailable"
  listen_before_shape=$(podman exec --env "VPN4_DNS=$VPN_DNS_IP" \
    --env "L2TP_DNS=$L2TP_DNS_IP" "$SERVER_NAME" bash -c '
      line=$(sed -n "s/^listen-address=//p" /etc/dnsmasq.d/bonjour-vpn.conf)
      count=$(printf "%s" "$line" | awk -F, "{print NF}")
      case ",$line," in *,127.0.0.1,*) loopback=yes ;; *) loopback=no ;; esac
      case ",$line," in *,"$VPN4_DNS",*) vpn=yes ;; *) vpn=no ;; esac
      case ",$line," in *,"$L2TP_DNS",*) l2tp=yes ;; *) l2tp=no ;; esac
      printf "count=%s/loopback=%s/vpn=%s/l2tp=%s" "$count" "$loopback" "$vpn" "$l2tp"
    ' 2>/dev/null || true)

  # Re-run enable_bonjour.sh
  podman exec "$SERVER_NAME" bash -c 'bash /tmp/enable_bonjour.sh <<ANSWERS >/dev/null 2>&1
y
y
ANSWERS
' || fail "idempotent: enable_bonjour.sh re-run failed"

  # Compare: no duplicate iptables rules
  local rules_after
  rules_after=$(podman exec --env "VPN4_NET=$VPN_SUBNET" --env "VPN4_DNS=$VPN_DNS_IP" \
    "$SERVER_NAME" bash -c '
      iptables -S INPUT | grep -F -- "-s $VPN4_NET" | grep -E -- "--dport (53|5353)"
      iptables -t nat -S PREROUTING | grep -F -- "-s $VPN4_NET" \
        | grep -F -- "-d 224.0.0.251/32" | grep -F -- "--dport 5353" \
        | grep -F -- "--to-destination $VPN4_DNS:53"
    ' 2>/dev/null | LC_ALL=C sort)
  if [ "$rules_before" = "$rules_after" ]; then
    pass "idempotent: exact IPv4 Bonjour rules unchanged after re-run"
  else
    fail "idempotent: exact IPv4 Bonjour rules changed after re-run"
  fi

  # Compare: no duplicate ip6tables rules
  if [ "$DUAL_STACK" = 1 ]; then
    local v6rules_after
    v6rules_after=$(podman exec --env "VPN6_NET=$VPN_SUBNET_IPV6" --env "VPN6_DNS=$VPN_DNS_IP6" \
      "$SERVER_NAME" bash -c '
        ip6tables -S INPUT | grep -F -- "-s $VPN6_NET" | grep -E -- "--dport (53|5353)"
        ip6tables -t nat -S PREROUTING | grep -F -- "-s $VPN6_NET" \
          | grep -F -- "-d ff02::fb/128" | grep -F -- "--dport 5353" \
          | grep -F -- "--to-destination [$VPN6_DNS]:53"
      ' 2>/dev/null | LC_ALL=C sort)
    if [ "$v6rules_before" = "$v6rules_after" ]; then
      pass "idempotent: exact IPv6 Bonjour rules unchanged after re-run"
    else
      fail "idempotent: exact IPv6 Bonjour rules changed after re-run"
    fi
  fi

  # Compare: dnsmasq config unchanged
  local conf_after
  conf_after=$(podman exec "$SERVER_NAME" sha256sum \
    /etc/dnsmasq.d/bonjour-vpn.conf 2>/dev/null | awk '{print $1}')
  if [ "$conf_before" = "$conf_after" ]; then
    pass "idempotent: dnsmasq config unchanged after re-run"
  else
    local changed_directives listen_after_shape
    changed_directives=$(podman exec "$SERVER_NAME" diff -u \
      /run/bonjour-test-dnsmasq-before.conf /etc/dnsmasq.d/bonjour-vpn.conf \
      2>/dev/null | awk '
        /^[+-][^+-#[:space:]]/ {
          line=substr($0, 2)
          sub(/=.*/, "", line)
          if (line != "") seen[line]=1
        }
        END {for (line in seen) print line}
      ' | LC_ALL=C sort | paste -sd, - || true)
    listen_after_shape=$(podman exec --env "VPN4_DNS=$VPN_DNS_IP" \
      --env "L2TP_DNS=$L2TP_DNS_IP" "$SERVER_NAME" bash -c '
        line=$(sed -n "s/^listen-address=//p" /etc/dnsmasq.d/bonjour-vpn.conf)
        count=$(printf "%s" "$line" | awk -F, "{print NF}")
        case ",$line," in *,127.0.0.1,*) loopback=yes ;; *) loopback=no ;; esac
        case ",$line," in *,"$VPN4_DNS",*) vpn=yes ;; *) vpn=no ;; esac
        case ",$line," in *,"$L2TP_DNS",*) l2tp=yes ;; *) l2tp=no ;; esac
        printf "count=%s/loopback=%s/vpn=%s/l2tp=%s" "$count" "$loopback" "$vpn" "$l2tp"
      ' 2>/dev/null || true)
    fail "idempotent: dnsmasq config changed after re-run (directives: ${changed_directives:-unknown}; listen before ${listen_before_shape:-unknown}, after ${listen_after_shape:-unknown})"
  fi
  podman exec "$SERVER_NAME" rm -f /run/bonjour-test-dnsmasq-before.conf \
    >/dev/null 2>&1 || true

  # Services still running
  if podman exec "$SERVER_NAME" pgrep -x dnsmasq >/dev/null 2>&1; then
    pass "idempotent: dnsmasq still running after re-run"
  else
    fail "idempotent: dnsmasq NOT running after re-run"
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

  local vpn_ip vpn_prefix
  vpn_prefix=${VPN_DNS_IP%.*}.
  vpn_ip=$(podman exec "$CLIENT_NAME" ip -o -4 addr show 2>/dev/null \
    | awk -v p="$vpn_prefix" '$4 ~ ("^" p) {sub(/\/.*/, "", $4); print $4; exit}' \
    || true)

  if [ -n "$vpn_ip" ]; then
    pass "Client got VPN IP: $vpn_ip"
  else
    fail "No VPN IP - tunnel not established"
    echo "       credential-safe tunnel counters:"
    if podman exec "$CLIENT_NAME" test -f /run/bonjour-test-post-init-counts \
         >/dev/null 2>&1; then
      podman exec "$CLIENT_NAME" cat /run/bonjour-test-post-init-counts 2>/dev/null \
        | sed 's/^/         immediately_after_initiate: /'
    fi
    local diag_label
    for diag_ctr in "$CLIENT_NAME" "$SERVER_NAME"; do
      diag_label=${diag_ctr%-"$RUN_ID"}
      podman exec "$diag_ctr" bash -c '
        sas=$(swanctl --list-sas 2>/dev/null | grep -c "ESTABLISHED" || true)
        children=$(swanctl --list-sas 2>/dev/null | grep -c "INSTALLED" || true)
        xfrm=$(ip xfrm state 2>/dev/null | grep -c "^src " || true)
        printf "ike_established=%s child_installed=%s xfrm_states=%s\n" \
          "$sas" "$children" "$xfrm"
      ' 2>/dev/null | sed "s/^/         ${diag_label}: /"
    done
    podman exec "$ROUTER_NAME" bash -c '
      iptables -t nat -nvxL PREROUTING 2>/dev/null \
        | awk "/dpt:(500|4500)/ { packets += \$1 } END { print packets + 0 }"
    ' 2>/dev/null | sed 's/^/         router_ike_packets=/'
    podman exec "$CLIENT_NAME" bash -c '
      log=/var/log/bonjour-test-client-connect.log
      for item in \
        "ike-sa-mentioned:IKE_SA myvpn" \
        "child-sa-mentioned:CHILD_SA myvpn" \
        "initiate-success:initiate completed successfully" \
        "child-establish-attempt:establishing CHILD_SA" \
        "child-install-attempt:installing CHILD_SA" \
        "policy-install-failed:unable to install IPsec policies" \
        "vip-install-attempt:installing new virtual IP" \
        "authentication-failed:AUTHENTICATION_FAILED" \
        "no-proposal:NO_PROPOSAL_CHOSEN" \
        "traffic-selectors:TS_UNACCEPTABLE" \
        "peer-delete:DELETE for IKE_SA" \
        "no-response:no response" \
        "giving-up:giving up" \
        "generic-failure:failed"; do
        label=${item%%:*}; pattern=${item#*:}
        grep -Fqi "$pattern" "$log" 2>/dev/null && printf "%s=yes " "$label"
      done
      printf "\n"
    ' 2>/dev/null | sed 's/^/         client_log_classes: /'
    echo "       No raw log, identity, certificate, key, or profile data was displayed."
    return
  fi

  if [ "$DUAL_STACK" = 1 ]; then
    local vpn_ip6
    vpn_ip6=$(podman exec "$CLIENT_NAME" ip -o -6 addr show 2>/dev/null \
      | awk '$4 ~ /^f[dc]/ { sub(/\/.*/, "", $4); print $4; exit }' || true)
    if [ -n "$vpn_ip6" ]; then
      pass "Client received an IPv6 VPN virtual address"
    else
      fail "Client did not receive an IPv6 VPN virtual address"
    fi
  fi

  # E2E Test 1: service type enumeration through tunnel
  local r
  r=$(run_dig "$CLIENT_NAME" "@${VPN_DNS_IP}" _services._dns-sd._udp.local PTR)
  expect_exact_lines "$r" "E2E DNS-SD UDP returned both fixture types" \
    '_airplay._tcp.local.' '_ipp._tcp.local.'
  expect_exact_lines \
    "$(run_dig_tcp "$CLIENT_NAME" "@${VPN_DNS_IP}" _services._dns-sd._udp.local PTR)" \
    "E2E DNS-SD TCP returned both fixture types" \
    '_airplay._tcp.local.' '_ipp._tcp.local.'

  # E2E Test 2: printer through tunnel
  r=$(run_dig "$CLIENT_NAME" "@${VPN_DNS_IP}" _ipp._tcp.local PTR)
  local e2e_ipp_instance='test\032printer._ipp._tcp.local.' e2e_ipp_txt
  expect_exact_lines "$r" "E2E IPP PTR matched the fixture" "$e2e_ipp_instance"
  expect_exact_lines \
    "$(run_dig "$CLIENT_NAME" "@${VPN_DNS_IP}" "$e2e_ipp_instance" SRV)" \
    "E2E IPP SRV matched port and target" '0 0 631 testprinter.local.'
  e2e_ipp_txt=$(run_dig "$CLIENT_NAME" "@${VPN_DNS_IP}" "$e2e_ipp_instance" TXT)
  if [ "$(printf '%s\n' "$e2e_ipp_txt" | wc -l | tr -d ' ')" = 1 ] \
    && printf '%s\n' "$e2e_ipp_txt" | grep -Fq '"txtver=1"' \
    && printf '%s\n' "$e2e_ipp_txt" | grep -Fq '"pdl=application/pdf"'; then
    pass "E2E IPP TXT matched both fixture attributes"
  else
    fail "E2E IPP TXT did not match both fixture attributes"
  fi
  expect_exact_lines \
    "$(run_dig "$CLIENT_NAME" "@${VPN_DNS_IP}" testprinter.local A)" \
    "E2E fixture hostname matched the device" "$DEVICE_LAN_IP"

  # E2E Test 3: AirPlay through tunnel
  r=$(run_dig "$CLIENT_NAME" "@${VPN_DNS_IP}" _airplay._tcp.local PTR)
  local e2e_ap_instance='test\032airplay._airplay._tcp.local.'
  expect_exact_lines "$r" "E2E AirPlay PTR matched the fixture" "$e2e_ap_instance"
  expect_exact_lines \
    "$(run_dig "$CLIENT_NAME" "@${VPN_DNS_IP}" "$e2e_ap_instance" SRV)" \
    "E2E AirPlay SRV matched port and target" '0 0 7000 testprinter.local.'
  expect_exact_lines \
    "$(run_dig "$CLIENT_NAME" "@${VPN_DNS_IP}" "$e2e_ap_instance" TXT)" \
    "E2E AirPlay TXT matched the fixture" '"model=AppleTV3,1"'

  # E2E Test 3b: send a genuine IPv4 mDNS multicast query from the VPN
  # address and prove that the server's PREROUTING rule captured it. The
  # records are served over the VPN-provided unicast DNS endpoint (asserted
  # above); multicast is not reflected onto the LAN.
  local mdns4_before mdns4_after
  mdns4_before=$(podman exec "$SERVER_NAME" iptables -t nat -nvxL PREROUTING 2>/dev/null \
    | awk -v n="$VPN_SUBNET" '
      index($0,n) && /224\.0\.0\.251/ && /dpt:5353/ {print $1; found=1; exit}
      END {if (!found) print 0}
    ')
  podman exec "$CLIENT_NAME" dig +short +time=2 +tries=1 \
    -b "$vpn_ip" @224.0.0.251 -p 5353 _ipp._tcp.local PTR \
    >/dev/null 2>&1 || true
  mdns4_after=$(podman exec "$SERVER_NAME" iptables -t nat -nvxL PREROUTING 2>/dev/null \
    | awk -v n="$VPN_SUBNET" '
      index($0,n) && /224\.0\.0\.251/ && /dpt:5353/ {print $1; found=1; exit}
      END {if (!found) print 0}
    ')
  if [ "$mdns4_after" -gt "$mdns4_before" ]; then
    pass "E2E IPv4 multicast mDNS packet was captured through the tunnel"
  else
    fail "E2E IPv4 multicast mDNS packet did not reach the capture rule"
  fi

  # E2E Test 4: upstream DNS through tunnel
  r=$(run_dig "$CLIENT_NAME" "@${VPN_DNS_IP}" google.com A)
  if [ -n "$r" ]; then
    pass "E2E upstream DNS over UDP"
  else
    fail "E2E upstream DNS over UDP broken"
  fi
  if [ -n "$(run_dig_tcp "$CLIENT_NAME" "@${VPN_DNS_IP}" google.com A)" ]; then
    pass "E2E upstream DNS over TCP"
  else
    fail "E2E upstream DNS over TCP broken"
  fi

  # E2E Test 5 (dual-stack only): AAAA query over the IPv4 tunnel returns the
  # IPv6 address from the cache warmer's hosts file. This proves the dnsmasq
  # IPv6 listen+hosts pipeline works end-to-end from a VPN client's shell,
  # even though the client itself negotiated an IPv4-only virtual IP.
  if [ "$DUAL_STACK" = 1 ]; then
    local e2e_aaaa
    e2e_aaaa=$(podman exec "$CLIENT_NAME" bash -c \
      "dig +short +time=3 @${VPN_DNS_IP} testprinter.local AAAA 2>/dev/null | grep -v '^;;'" \
      2>/dev/null || true)
    expect_exact_lines "$e2e_aaaa" "E2E AAAA lookup matched the fixture" "$LAN_DEVICE_IPV6"

    expect_exact_lines \
      "$(podman exec "$CLIENT_NAME" dig +short +time=3 +tries=1 \
        -b "$vpn_ip6" "@${VPN_DNS_IP6}" _ipp._tcp.local PTR 2>/dev/null \
        | grep -v '^;;' || true)" \
      "E2E DNS over the IPv6 VPN path matched the fixture" "$e2e_ipp_instance"

    # Linux policy-based IPsec clients do not route ff02::/16 link-local
    # multicast through an XFRM tunnel. Inject a real IPv6 multicast packet
    # from the disposable router with a synthetic VPN-pool source and assert
    # the server rule itself, while the preceding query proves the actual
    # IPv6 IPsec request/response path.
    local mdns6_before mdns6_after router_lan_iface probe_v6 v6_base
    mdns6_before=$(podman exec "$SERVER_NAME" ip6tables -t nat -nvxL PREROUTING 2>/dev/null \
      | awk -v n="$VPN_SUBNET_IPV6" '
        index($0,n) && /ff02::fb/ && /dpt:5353/ {print $1; found=1; exit}
        END {if (!found) print 0}
      ')
    router_lan_iface=$(container_iface_for_ip "$ROUTER_NAME" "$ROUTER_LAN_IP")
    v6_base=${VPN_SUBNET_IPV6%/*}
    probe_v6="${v6_base%::*}::2ffe"
    if [ -n "$router_lan_iface" ] && podman exec \
      --env "PROBE_IFACE=$router_lan_iface" --env "PROBE_V6=$probe_v6" \
      "$ROUTER_NAME" bash -c '
        set -e
        cleanup_probe() {
          ip -6 addr del "${PROBE_V6}/128" dev "$PROBE_IFACE" 2>/dev/null || true
        }
        trap cleanup_probe EXIT
        ip -6 addr add "${PROBE_V6}/128" dev "$PROBE_IFACE" nodad
        python3 - <<"PY"
import os
import socket
import struct

iface = os.environ["PROBE_IFACE"]
source = os.environ["PROBE_V6"]
ifindex = socket.if_nametoindex(iface)
query = bytes.fromhex(
    "000000000001000000000000"
    "045f697070045f746370056c6f63616c00"
    "000c0001"
)

with socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as sock:
    sock.setsockopt(
        socket.IPPROTO_IPV6,
        socket.IPV6_MULTICAST_IF,
        struct.pack("@I", ifindex),
    )
    sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_MULTICAST_HOPS, 1)
    sock.bind((source, 0))
    sock.sendto(query, ("ff02::fb", 5353, 0, ifindex))
PY
      '; then
      mdns6_after=$(podman exec "$SERVER_NAME" ip6tables -t nat -nvxL PREROUTING 2>/dev/null \
        | awk -v n="$VPN_SUBNET_IPV6" '
          index($0,n) && /ff02::fb/ && /dpt:5353/ {print $1; found=1; exit}
          END {if (!found) print 0}
        ')
      if [ "$mdns6_after" -gt "$mdns6_before" ]; then
        pass "IPv6 multicast mDNS packet matched the server capture rule"
      else
        fail "IPv6 multicast mDNS packet did not reach the server capture rule"
      fi
    else
      fail "IPv6 multicast capture probe could not be injected"
    fi
  fi
}

run_disable_tests() {
  echo ""
  echo -e "${BOLD}========== Disable / Re-enable ==========${NC}"
  echo ""

  if podman exec "$SERVER_NAME" bash -c 'bash /tmp/disable_bonjour.sh <<ANSWERS >/dev/null 2>&1
y
ANSWERS
'; then
    pass "disable: script completed successfully"
  else
    fail "disable: script returned failure"
    return
  fi

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

  # ===== Phase 8: IPv6 cleanup on disable (dual-stack only) =====
  if [ "$DUAL_STACK" = 1 ]; then
    # Disable: IPv6 sync script must be removed
    if ! podman exec "$SERVER_NAME" test -f /usr/local/sbin/bonjour-vpn-ipv6-sync; then
      pass "disable: bonjour-vpn-ipv6-sync removed"
    else
      fail "disable: bonjour-vpn-ipv6-sync still present"
    fi

    # Disable: state directory must be removed
    if ! podman exec "$SERVER_NAME" test -d /var/lib/bonjour-vpn; then
      pass "disable: /var/lib/bonjour-vpn directory removed"
    else
      fail "disable: /var/lib/bonjour-vpn still present"
    fi

    # Disable: IPv6 server address removed from loopback
    if ! podman exec "$SERVER_NAME" bash -c \
         "ip -6 addr show dev lo 2>/dev/null | grep -Fq '${VPN_DNS_IP6}/'"; then
      pass "disable: IPv6 VPN server IP removed from loopback"
    else
      fail "disable: IPv6 VPN server IP still on loopback"
    fi

    if podman exec "$SERVER_NAME" bash -c \
         "[ -z \"\$(ip -6 route show exact '$VPN_SUBNET_IPV6' 2>/dev/null)\" ]"; then
      pass "disable: IPv6 VPN client route removed"
    else
      fail "disable: IPv6 VPN client route still present"
    fi

    # Disable: ip6tables INPUT rule removed
    if ! podman exec "$SERVER_NAME" bash -c \
         "ip6tables -C INPUT -s '$VPN_SUBNET_IPV6' -p udp --dport 53 -j ACCEPT 2>/dev/null"; then
      pass "disable: ip6tables INPUT rule removed"
    else
      fail "disable: ip6tables INPUT rule still active"
    fi

    # Disable: ip6tables PREROUTING DNAT removed
    if ! podman exec "$SERVER_NAME" bash -c \
         "ip6tables -t nat -C PREROUTING -s '$VPN_SUBNET_IPV6' -d ff02::fb -p udp --dport 5353 -j DNAT --to-destination '[$VPN_DNS_IP6]:53' 2>/dev/null"; then
      pass "disable: ip6tables mDNS DNAT removed"
    else
      fail "disable: ip6tables mDNS DNAT still active"
    fi

    # Disable: rc.local IPv6 line removed (if present)
    if ! podman exec "$SERVER_NAME" bash -c \
         "grep -Eq 'ip -6 (addr add $VPN_DNS_IP6/128|route add $VPN_SUBNET_IPV6) dev lo' /etc/rc.local 2>/dev/null"; then
      pass "disable: IPv6 rc.local entries removed"
    else
      fail "disable: IPv6 rc.local address or route entry still present"
    fi
  fi

  # Re-enable
  if podman exec "$SERVER_NAME" bash -c 'bash /tmp/enable_bonjour.sh <<ANSWERS >/dev/null 2>&1
y
ANSWERS
'; then
    pass "re-enable: script completed successfully"
  else
    fail "re-enable: script returned failure"
    return
  fi

  if podman exec "$SERVER_NAME" pgrep -x dnsmasq >/dev/null 2>&1; then
    pass "re-enable: dnsmasq running again"
  else
    fail "re-enable: dnsmasq NOT running"
  fi

  load_bonjour_state

  # Dual-stack only: re-enable must restore consolidated IPv6 state without
  # reinstalling the retired background firewall mutator.
  if [ "$DUAL_STACK" = 1 ]; then
    if podman exec "$SERVER_NAME" bash -c \
         "grep -q 'HAS_IPV6_SAVED=.1.' /var/lib/bonjour-vpn/config \
          && grep -q 'VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT_SAVED=.0.' /var/lib/bonjour-vpn/config \
          && [ -n \"\$(ip -6 route show exact '$VPN_SUBNET_IPV6' 2>/dev/null)\" ] \
          && test ! -e /usr/local/sbin/bonjour-vpn-ipv6-sync \
          && test ! -e /var/lib/bonjour-vpn/ipv6-state"; then
      pass "re-enable: consolidated IPv6 state restored without legacy mutator"
    else
      fail "re-enable: IPv6 state or legacy cleanup is incorrect"
    fi
  fi
}

reconnect_client() {
  podman exec "$CLIENT_NAME" bash -c '
    set -e
    exec > /var/log/bonjour-test-client-reconnect.log 2>&1
    timeout 10 swanctl --terminate --ike myvpn || true
    swanctl --load-all
    timeout 30 swanctl --initiate --child myvpn
    sleep 2
  '
}

run_restart_tests() {
  [ "$SKIP_E2E" = 0 ] || return
  echo ""
  echo -e "${BOLD}========== Server Restart Persistence ==========${NC}"
  echo ""

  podman restart "$SERVER_NAME" >/dev/null 2>&1 \
    || { fail "server container restart failed"; return; }
  wait_for_systemd "$SERVER_NAME"
  # The internal Podman network has no gateway by design, and Podman discards
  # the route we added to model the server's persistent one-NIC netplan when
  # it recreates the network namespace. Restore only this fixture route and
  # resolver before evaluating application-level restart recovery.
  local restarted_lan_iface
  restarted_lan_iface=$(container_iface_for_ip "$SERVER_NAME" "$SERVER_LAN_IP")
  if [ -n "$restarted_lan_iface" ]; then
    podman exec "$SERVER_NAME" ip route replace default via "$ROUTER_LAN_IP" \
      dev "$restarted_lan_iface" >/dev/null 2>&1 \
      || fail "could not restore the disposable server route after restart"
    podman exec --env "TEST_DNS=$ROUTER_LAN_IP" "$SERVER_NAME" bash -c '
      printf "nameserver %s\n" "$TEST_DNS" > /etc/resolv.conf
    ' >/dev/null 2>&1 \
      || fail "could not restore the disposable server resolver after restart"
  else
    fail "could not identify the disposable server interface after restart"
  fi
  sleep 5

  if podman exec "$SERVER_NAME" bash -c '
      systemctl is-active --quiet ipsec
      systemctl is-active --quiet dnsmasq
      systemctl is-active --quiet avahi-daemon
      systemctl is-active --quiet bonjour-vpn-watch
    ' >/dev/null 2>&1; then
    pass "VPN and Bonjour services survived server restart"
  else
    fail "one or more VPN/Bonjour services failed after server restart"
  fi

  local persistence_replay=0
  if ! podman exec --env "VPN4_NET=$VPN_SUBNET" "$SERVER_NAME" bash -c '
      iptables -C INPUT -s "$VPN4_NET" -p udp --dport 53 -j ACCEPT
      iptables -C INPUT -s "$VPN4_NET" -p tcp --dport 53 -j ACCEPT
      iptables -C INPUT -s "$VPN4_NET" -p udp --dport 5353 -j ACCEPT
    ' >/dev/null 2>&1; then
    if podman exec "$SERVER_NAME" bash -c '
        systemctl is-enabled --quiet load-iptables-rules.service
        [ "$(systemctl show -p Result --value load-iptables-rules.service)" = success ]
        test -x /etc/network/if-pre-up.d/iptablesload
      ' >/dev/null 2>&1; then
      skip "Podman recreated packet state after the boot loader ran; automatic boot ordering requires a full VM"
      podman exec "$SERVER_NAME" /etc/network/if-pre-up.d/iptablesload >/dev/null 2>&1 \
        || fail "explicit persistence-loader replay failed"
      persistence_replay=1
    fi
  fi

  if podman exec --env "VPN4_NET=$VPN_SUBNET" --env "VPN4_DNS=$VPN_DNS_IP" \
    "$SERVER_NAME" bash -c '
      iptables -C INPUT -s "$VPN4_NET" -p udp --dport 53 -j ACCEPT
      iptables -C INPUT -s "$VPN4_NET" -p tcp --dport 53 -j ACCEPT
      iptables -C INPUT -s "$VPN4_NET" -p udp --dport 5353 -j ACCEPT
      iptables -t nat -C PREROUTING -s "$VPN4_NET" -d 224.0.0.251 \
        -p udp --dport 5353 -j DNAT --to-destination "$VPN4_DNS:53"
    ' >/dev/null 2>&1; then
    pass "IPv4 Bonjour firewall state restored from persisted rules"
  else
    fail "IPv4 Bonjour firewall state was not restored from persisted rules"
  fi

  if [ "$DUAL_STACK" = 1 ]; then
    if [ "$persistence_replay" = 1 ]; then
      podman exec "$SERVER_NAME" /etc/rc.local >/dev/null 2>&1 \
        || fail "explicit rc.local replay failed"
    fi
    if podman exec --env "VPN6_NET=$VPN_SUBNET_IPV6" --env "VPN6_DNS=$VPN_DNS_IP6" \
         "$SERVER_NAME" bash -c '
          ip -6 addr show dev lo | grep -Fq "${VPN6_DNS}/"
          [ -n "$(ip -6 route show exact "$VPN6_NET" 2>/dev/null)" ]
          ip6tables -C INPUT -s "$VPN6_NET" -p udp --dport 53 -j ACCEPT
          ip6tables -C INPUT -s "$VPN6_NET" -p tcp --dport 53 -j ACCEPT
          ip6tables -C INPUT -s "$VPN6_NET" -p udp --dport 5353 -j ACCEPT
          ip6tables -t nat -C PREROUTING -s "$VPN6_NET" -d ff02::fb \
            -p udp --dport 5353 -j DNAT --to-destination "[$VPN6_DNS]:53"
        ' >/dev/null 2>&1; then
      pass "IPv6 Bonjour address and firewall state restored from persisted configuration"
    else
      fail "IPv6 Bonjour address or firewall state failed after server restart"
    fi
  fi

  if reconnect_client >/dev/null 2>&1 \
     && [ -n "$(run_dig "$CLIENT_NAME" "@${VPN_DNS_IP}" _ipp._tcp.local PTR)" ] \
     && [ -n "$(run_dig_tcp "$CLIENT_NAME" "@${VPN_DNS_IP}" testprinter.local A)" ]; then
    pass "IKEv2 and UDP/TCP Bonjour DNS recovered after server restart"
  else
    fail "IKEv2 or Bonjour DNS failed after server restart"
  fi
}

print_results() {
  echo ""
  echo -e "${BOLD}========================================${NC}"
  echo -e "  ${GREEN}Passed${NC}:  $PASS"
  echo -e "  ${RED}Failed${NC}:  $FAIL"
  echo -e "  ${YELLOW}Skipped${NC}: $SKIP"
  echo -e "  Mode:    $([ "$DUAL_STACK" = 1 ] && echo 'dual-stack' || echo 'IPv4-only')"
  echo -e "  VPN mode: $VPN_MODE"
  echo -e "  Parent:  $PARENT_MODE${PARENT_REF:+:$PARENT_REF}"
  echo -e "  Platform: $PLATFORM"
  echo -e "${BOLD}========================================${NC}"
}

# ===== Main =====
START_TIME=$(date +%s)
preflight
build_image
create_networks
setup_router
setup_device
setup_server
run_server_tests
run_ipv4_reconfiguration_test
run_idempotency_test
run_disable_tests
if [ "$SKIP_E2E" = 0 ]; then
  setup_client
  run_e2e_tests
  if [ "$DIAGNOSTIC_HOLD_SECONDS" -gt 0 ]; then
    log "Holding disposable guests for ${DIAGNOSTIC_HOLD_SECONDS}s for credential-safe diagnostics..."
    sleep "$DIAGNOSTIC_HOLD_SECONDS"
  fi
  run_restart_tests
else
  skip "IKEv2 client import and tunnel path (--skip-e2e)"
  log "Skipping E2E tests (--skip-e2e)"
fi
print_results
END_TIME=$(date +%s)
echo ""
echo "Elapsed: $((END_TIME - START_TIME))s"
echo ""

exit "$FAIL"
