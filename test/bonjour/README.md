# Bonjour VPN test fixtures

These fixtures validate the Bonjour integration against a fresh installation
of the parent VPN project without touching a production VPN host.

## Fast unit tests

The credential-free shell fixtures exercise detection, firewall transactions,
resolver-hook compatibility, runtime reconciliation, disable behavior, and the
watcher:

```sh
set -e
for test_script in test/bonjour/test_common.sh \
  test/bonjour/test_detection.sh \
  test/bonjour/test_disable.sh \
  test/bonjour/test_firewall.sh \
  test/bonjour/test_legacy_upgrade.sh \
  test/bonjour/test_legacy_disable.sh \
  test/bonjour/test_modes.sh \
  test/bonjour/test_openrc.sh \
  test/bonjour/test_recovery.sh \
  test/bonjour/test_resolver_hook.sh \
  test/bonjour/test_runtime.sh \
  test/bonjour/test_watcher.sh; do
  bash "$test_script"
done
```

## Disposable Podman integration test

`podman_test.sh` creates four uniquely named guests on separate, dynamically
allocated WAN and internal-LAN networks:

- a one-interface VPN server behind a disposable NAT router;
- a WAN-side strongSwan client;
- a LAN-only Avahi device publishing IPP and AirPlay services; and
- the router that provides NAT, IKEv2 forwarding, and LAN DNS.

The default parent source is the exact commit at local `origin/master`. Use
`--parent-live` to test the literal public `get.vpnsetup.net` quick-start.

```sh
podman machine ssh -- sudo modprobe ppp_generic
bash test/bonjour/podman_test.sh
bash test/bonjour/podman_test.sh --ipv4-only
bash test/bonjour/podman_test.sh --ikev2-only
bash test/bonjour/podman_test.sh --parent-live
bash test/bonjour/podman_test.sh --base-image docker.io/library/ubuntu:26.04
```

The test covers the parent's all-protocol and IKEv2-only configurations, a
real guest-to-guest IKEv2 tunnel, UDP and TCP DNS, real IPv4 tunnel multicast
capture, an IPv6 multicast-rule packet probe, DNS-SD PTR/SRV/TXT records,
A/AAAA records, upstream DNS, IPv6 transitions and return routing,
idempotency, disable/re-enable, and reconnect after a container restart.
The base image is content-keyed by both the Containerfile and selected Ubuntu
image, so a stale locally cached fixture is rebuilt automatically. Use
`--base-image` to exercise every Ubuntu release supported by the parent.

Ubuntu 26.04 has passed the server-side disposable installation and Bonjour
checks with `--skip-e2e`. A disposable strongSwan client tunnel did not
establish in the current Ubuntu 26.04 fixture, so that release is not yet
claimed as end-to-end client-path coverage. Ubuntu 24.04 remains the full
client-tunnel and reboot reference fixture while that platform-specific gap is
investigated.

Podman reconstructs a container's packet namespace after early systemd boot
units have run. The harness therefore reports one explicit skip for automatic
firewall-loader ordering, replays the real persisted loader, and validates the
result. The full-VM fixture below tests automatic boot ordering.

### Coverage boundaries

The automated coverage is intentionally split by what the fixture can prove:

| Scenario | Coverage level |
|---|---|
| Ubuntu/systemd, iptables, all-protocol and IKEv2-only installs | Live disposable Podman guests |
| Real IKEv2 client connection, reconnect, DNS and multicast data path | Live disposable Podman guests |
| Ubuntu/systemd boot ordering and persistence | Live disposable Lima VM and real kernel reboot |
| Alpine/OpenRC ownership, lock behavior, services and cron integration | Unit/integration fixture with real kernel `flock` and mocked OpenRC services |
| CentOS/RHEL-family detection and persistence paths | Distro-container unit fixture; no booted RHEL VM |
| Native nftables transactions | Mocked semantic transaction fixture; no live nftables host |
| XAuth and L2TP modes | Installation, configuration and firewall assertions; no real XAuth or L2TP client session |
| Legacy-state upgrades and stateless-disable safety | Synthetic state-transition fixtures, including the zero-rule interlock |
| Interrupted-operation recovery and lock contention | Synthetic fault injection plus live disposable Podman guests |

The GitHub Actions workflow gates the portable unit/integration matrix. The
Podman and Lima fixtures are manual release gates until runners with the
required nested networking, systemd and kernel capabilities are available.
Passing the fast workflow alone must not be described as proof of the live
IKEv2 data path, automatic VM boot recovery, native nftables, or an actual
XAuth/L2TP client session.

Containers, networks, and the transfer volume are removed on every exit. The
encrypted test client bundle moves only through the disposable volume; it is
never copied to the host or printed. Installer and import logs stay inside the
guests. The reusable base image may be removed after testing (use the `amd64`
suffix on an x86-64 host):

```sh
podman image rm localhost/bonjour-test-base:ubuntu24.04-arm64
```

Only unload test kernel modules when no other Podman workload needs PPP:

```sh
podman machine ssh -- sudo modprobe -r pppox ppp_generic slhc
```

## Disposable full-VM reboot test

On macOS with Lima installed, `lima_boot_test.sh` creates a plain Ubuntu 24.04
VM with no host mounts. It installs the pinned parent project and this branch's
Bonjour integration, validates state, performs a real kernel reboot, and then
validates automatic systemd, loopback-address, firewall, and UDP/TCP DNS
recovery. Its trap deletes the VM and disk on success, failure, or interruption.

```sh
bash test/bonjour/lima_boot_test.sh
```

Lima may retain its globally shared Ubuntu image download cache for future VM
runs. This is separate from the deleted test VM and can be managed with Lima's
normal cache-management workflow.

Neither integration fixture contacts an SSH alias or production host. Test-only
credentials and certificates are generated inside disposable guests. Their
contents, public keys, identities, profiles, and raw private logs are not
displayed by the harnesses.
