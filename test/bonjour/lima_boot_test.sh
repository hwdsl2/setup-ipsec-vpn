#!/usr/bin/env bash
# Full-VM boot-persistence test for the Bonjour VPN integration.
#
# This complements podman_test.sh. Containers can validate the complete
# IKEv2/DNS/Bonjour path, but Podman recreates packet state after systemd has
# already run early boot units. This fixture uses a real Ubuntu kernel and
# systemd boot, performs no host mounts, and deletes the VM disk on exit.
# No credential, key, certificate, identity, or client-profile content is
# copied to or displayed on the host.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
RUN_ID=${BONJOUR_VM_TEST_RUN_ID:-$(date -u +%Y%m%d%H%M%S)-$$}
VM_NAME="bonjour-vm-test-${RUN_ID}"
PARENT_REF=${BONJOUR_VM_TEST_PARENT_REF:-}
CREATED=0

case "$RUN_ID" in
  *[!A-Za-z0-9_.-]*) echo "Invalid BONJOUR_VM_TEST_RUN_ID." >&2; exit 2 ;;
esac

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$1"; }
die() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }

cleanup() {
  if [ "$CREATED" = 1 ]; then
    log "Deleting disposable Lima VM and its disk..."
    limactl delete --force "$VM_NAME" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

command -v limactl >/dev/null 2>&1 || die "limactl is required"
command -v git >/dev/null 2>&1 || die "git is required"
[ "$(uname -s)" = Darwin ] || die "This full-VM fixture currently targets Lima on macOS"
if limactl list --quiet 2>/dev/null | grep -Fxq "$VM_NAME"; then
  die "Refusing to reuse existing Lima instance $VM_NAME"
fi

if [ -z "$PARENT_REF" ]; then
  PARENT_REF=$(git -C "$REPO_DIR" rev-parse refs/remotes/origin/master 2>/dev/null) \
    || die "Could not resolve refs/remotes/origin/master"
fi
case "$PARENT_REF" in
  *[!0-9a-f]*|'') die "Parent ref must be an exact hexadecimal commit" ;;
esac
[ "${#PARENT_REF}" -eq 40 ] || die "Parent ref must be a full 40-character commit"
git -C "$REPO_DIR" cat-file -e "${PARENT_REF}^{commit}" 2>/dev/null \
  || die "Parent commit is not present locally"

log "Creating plain Ubuntu 24.04 VM (no host mounts)..."
limactl create --yes \
  --name "$VM_NAME" \
  --vm-type vz \
  --plain \
  --cpus 4 \
  --memory 8 \
  --disk 30 \
  template:ubuntu-24.04 >/dev/null \
  || die "Could not create the disposable Lima VM"
CREATED=1
limactl start --timeout 5m "$VM_NAME" >/dev/null \
  || die "Could not start the disposable Lima VM"
limactl shell "$VM_NAME" -- true >/dev/null 2>&1 \
  || die "Disposable Lima VM SSH did not become ready"

log "Staging public project scripts without a host mount..."
git -C "$REPO_DIR" show "${PARENT_REF}:vpnsetup_ubuntu.sh" \
  | limactl shell "$VM_NAME" -- sudo sh -c \
      'umask 077; cat > /tmp/vpnsetup_ubuntu.sh' >/dev/null \
  || die "Could not stage the pinned parent installer"
limactl shell "$VM_NAME" -- sudo sh -c \
  'umask 077; cat > /tmp/enable_bonjour.sh' \
  < "$REPO_DIR/extras/enable_bonjour.sh" >/dev/null \
  || die "Could not stage enable_bonjour.sh"

log "Installing the pinned parent VPN and Bonjour integration inside the VM..."
# shellcheck disable=SC2016 # The single-quoted program expands inside the VM.
limactl shell "$VM_NAME" -- sudo env "TEST_PARENT_REF=$PARENT_REF" bash -c '
  set -e
  umask 077
  exec > /var/log/bonjour-vm-test-install.log 2>&1
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -yqq dnsutils

  iface=$(ip -4 route show default | awk "{print \$5; exit}")
  public_ip=$(ip -4 route get 1.1.1.1 | awk "{for (i=1;i<=NF;i++) if (\$i==\"src\") {print \$(i+1); exit}}")
  test -n "$iface"
  test -n "$public_ip"
  ip -6 addr add 2001:db8:b0:3::20/64 dev "$iface"

  sed -i \
    -e "s#^  base1=.*#  base1=\"https://raw.githubusercontent.com/hwdsl2/setup-ipsec-vpn/${TEST_PARENT_REF}/extras\"#" \
    -e "s#^  base2=.*#  base2=\"https://raw.githubusercontent.com/hwdsl2/setup-ipsec-vpn/${TEST_PARENT_REF}/extras\"#" \
    /tmp/vpnsetup_ubuntu.sh
  grep -Fq "setup-ipsec-vpn/${TEST_PARENT_REF}/extras" /tmp/vpnsetup_ubuntu.sh

  VPN_PUBLIC_IP="$public_ip" \
  VPN_PUBLIC_IP6=2001:db8:b0:3::20 \
  VPN_IPSEC_PSK=bonjour-test-only-psk \
  VPN_USER=bonjour_test \
  VPN_PASSWORD=bonjour-test-only-password \
  VPN_CLIENT_NAME=vpnclient \
  VPN_PROTECT_CONFIG=no \
    bash /tmp/vpnsetup_ubuntu.sh

  bash /tmp/enable_bonjour.sh <<ANSWERS
y
ANSWERS

  rm -f /tmp/vpnsetup_ubuntu.sh /tmp/enable_bonjour.sh
  rm -f /root/vpnclient.p12 /root/vpnclient.sswan /root/vpnclient.mobileconfig
  rm -f /etc/ipsec.d/vpnclient.p12 /etc/ipsec.d/vpnclient.sswan \
    /etc/ipsec.d/vpnclient.mobileconfig
' || die "VM installation failed; its private log was not displayed"

validate_vm() {
  local phase=$1
  # shellcheck disable=SC2016 # The single-quoted program expands inside the VM.
  limactl shell "$VM_NAME" -- sudo bash -c '
    set -e
    . /var/lib/bonjour-vpn/config
    test -n "$VPN_SUBNET_SAVED"
    test -n "$VPN_SERVER_IP_SAVED"
    test "$HAS_IPV6_SAVED" = 1
    test -n "$VPN_SUBNET_IPV6_SAVED"
    test -n "$VPN_SERVER_IP_IPV6_SAVED"
    test "$VPN_SUBNET_IPV6_ROUTE_WAS_PRESENT_SAVED" = 0

    systemctl is-active --quiet ipsec
    systemctl is-active --quiet dnsmasq
    systemctl is-active --quiet avahi-daemon
    systemctl is-active --quiet bonjour-vpn-watch
    systemctl is-enabled --quiet load-iptables-rules.service
    test "$(systemctl show -p Result --value load-iptables-rules.service)" = success

    ip addr show dev lo | grep -Fq "${VPN_SERVER_IP_SAVED}/"
    ip -6 addr show dev lo | grep -Fq "${VPN_SERVER_IP_IPV6_SAVED}/"
    test -n "$(ip -6 route show exact "$VPN_SUBNET_IPV6_SAVED")"
    iptables -C INPUT -s "$VPN_SUBNET_SAVED" -p udp --dport 53 -j ACCEPT
    iptables -C INPUT -s "$VPN_SUBNET_SAVED" -p tcp --dport 53 -j ACCEPT
    iptables -t nat -C PREROUTING -s "$VPN_SUBNET_SAVED" -d 224.0.0.251 \
      -p udp --dport 5353 -j DNAT --to-destination "${VPN_SERVER_IP_SAVED}:53"
    ip6tables -C INPUT -s "$VPN_SUBNET_IPV6_SAVED" -p udp --dport 53 -j ACCEPT
    ip6tables -C INPUT -s "$VPN_SUBNET_IPV6_SAVED" -p tcp --dport 53 -j ACCEPT
    ip6tables -t nat -C PREROUTING -s "$VPN_SUBNET_IPV6_SAVED" -d ff02::fb \
      -p udp --dport 5353 -j DNAT --to-destination "[${VPN_SERVER_IP_IPV6_SAVED}]:53"

    grep -F "$VPN_SUBNET_SAVED" /etc/iptables.rules | grep -q -- "--dport 53"
    grep -F "$VPN_SUBNET_IPV6_SAVED" /etc/ip6tables.rules | grep -q -- "--dport 53"
    ss -lunt | grep -Eq "${VPN_SERVER_IP_SAVED}:53[[:space:]]"
    dig +short +time=5 +tries=1 @"$VPN_SERVER_IP_SAVED" example.com A | grep -Eq "^[0-9]"
    dig +tcp +short +time=5 +tries=1 @"$VPN_SERVER_IP_SAVED" example.com A | grep -Eq "^[0-9]"
  ' >/dev/null 2>&1 || die "$phase VM validation failed"
  printf 'PASS: %s VM validation\n' "$phase"
}

validate_vm pre-reboot
BOOT_ID_BEFORE=$(limactl shell "$VM_NAME" -- cat /proc/sys/kernel/random/boot_id 2>/dev/null) \
  || die "Could not record the initial VM boot identifier"

log "Rebooting the Ubuntu kernel..."
limactl shell "$VM_NAME" -- sudo systemctl reboot >/dev/null 2>&1 || true

ready=0
for _ in $(seq 1 120); do
  if limactl shell "$VM_NAME" -- true >/dev/null 2>&1; then
    boot_id_after=$(limactl shell "$VM_NAME" -- cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)
    if [ -n "$boot_id_after" ] && [ "$boot_id_after" != "$BOOT_ID_BEFORE" ]; then
      ready=1
      break
    fi
  fi
  sleep 2
done
[ "$ready" = 1 ] || die "The disposable VM did not complete a new boot"

validate_vm post-reboot
printf 'PASS: real Ubuntu reboot restored services, loopback addresses, IPv6 return routing, and IPv4/IPv6 firewall state\n'
printf 'sensitive_material_displayed=no host_mounts=none production_contacted=no\n'
