# macOS Finder Network Discovery Over VPN — Research Notes

## Date: 2026-04-15
## Status: Unresolved — macOS Finder click-to-connect for SMB over VPN

---

## The Goal

Make file servers on the VPN server's LAN appear in macOS Finder's Network sidebar with working click-to-connect, purely from the server side (no client software).

## What Works Today

| Feature | Status | How |
|---------|--------|-----|
| iOS printer discovery | Working | `.local` unicast DNS-SD through VPN tunnel |
| iOS AirPlay discovery | Working | `.local` unicast DNS-SD through VPN tunnel |
| macOS hostname resolution | Working | `smb://bam-file-server.local` via Cmd+K connects |
| macOS `smb://hostname.vpn.internal` | Working | Bare hostname address records in dnsmasq |
| macOS Finder sidebar visibility | Working | `vpn.internal` Wide-Area Bonjour browse domain |
| macOS Finder click-to-connect | **BROKEN** | See below |
| All platforms: ping, nc, direct IP | Working | VPN tunnel routing |

## The Core Problem

macOS Finder discovers services under `vpn.internal` via unicast DNS-SD. When you click a server in the sidebar, Finder constructs a connection URL using the **service instance FQDN**:

```
smb://bam-file-server._smb._tcp.vpn.internal
```

This URL fails to connect. The `._smb._tcp.` in the hostname is the problem.

On the local network, the same pattern works (`smb://BAM File Server._smb._tcp.local`) because macOS uses the **mDNS code path** which follows the SRV target hostname instead of using the FQDN directly.

## What We Tested (Chronological)

### Test 1: Wide-Area Bonjour with `vpn.internal`
- **What**: Added `vpn.internal` as a browse domain via `lb._dns-sd._udp.vpn.internal` PTR records. Pushed `vpn.internal` in `modecfgdomains`.
- **Result**: Discovery works — servers appear in Finder sidebar under `vpn.internal`. Click-to-connect fails.
- **Error**: `GetServerInfo failed 65` (EHOSTUNREACH) after 30-second timeout
- **Log**: `URL = smb://bam file server._smb._tcp.vpn.internal` — spaces in URL, `getaddrinfo` rejects spaces

### Test 2: Replace spaces with hyphens in instance names
- **What**: Changed "BAM File Server" to "BAM-File-Server" in `vpn.internal` records
- **Result**: Not tested live (user preferred exploring other options first)

### Test 3: Use hostname as instance name
- **What**: Changed instance name from "BAM File Server" to "bam-file-server" (the actual DNS hostname from avahi's SRV target)
- **Result**: URL becomes `smb://bam-file-server._smb._tcp.vpn.internal` (no spaces). DNS resolves correctly (`dscacheutil` returns IP). Connection still fails.
- **Key finding**: `open "smb://bam-file-server.vpn.internal"` WORKS but `open "smb://bam-file-server._smb._tcp.vpn.internal"` FAILS — same IP, same server, different hostname string

### Test 4: `address=` records for service instance FQDNs
- **What**: Added `address=/bam-file-server._smb._tcp.vpn.internal/192.168.33.213` to dnsmasq
- **Result**: `dig` resolves correctly, `dscacheutil` resolves correctly, SMB connection still fails
- **Key finding**: DNS resolution is NOT the problem — the name resolves, the connection fails at the SMB protocol level

### Test 5: `host-record=` for service instance FQDNs
- **What**: Tried `host-record=BAM File Server._smb._tcp.vpn.internal,192.168.33.213`
- **Result**: dnsmasq can't handle spaces in `host-record=` directive. `dig` returns nothing.
- **Key finding**: `address=` handles spaces (uses `/` delimiter), `host-record=` does not

### Test 6: SRV target under `vpn.internal` instead of `.local`
- **What**: Changed SRV from `bam-file-server.local` to `bam-file-server.vpn.internal`
- **Result**: Connection still fails
- **Tested with**: Both space-containing instance names and hostname-based instance names
- **Hypothesis was**: `.local` SRV target causes mDNS timeout. Disproved — `vpn.internal` SRV target also fails.

### Test 7: `dns-sd -P` local mDNS proxy registration
- **What**: Ran `dns-sd -P "BAM File Server" _smb._tcp local 445 bam-file-server.local 192.168.33.213` on the Mac
- **Result**: SERVER APPEARS IN FINDER SIDEBAR AND CLICK-TO-CONNECT WORKS PERFECTLY
- **Key finding**: The mDNS code path handles everything correctly — spaces in names, SRV following, SMB connection. The unicast DNS-SD code path is what's broken.

### Test 8: mDNS packet injection from server
- **What**: Crafted a raw mDNS response packet on the server, sent via UDP to the Mac's VPN IP (192.168.43.10:5353)
- **Result**: mDNSResponder on the Mac ignored the packet
- **Key finding**: mDNSResponder explicitly excludes point-to-point interfaces (ipsec) from mDNS processing. Packets arriving on ipsec are dropped regardless of format.
- **Source**: Apple's mDNSResponder source code excludes point-to-point links

### Test 9: Browse domain pointers for `.local`
- **What**: Added `lb._dns-sd._udp.local` PTR record to dnsmasq to try enabling unicast browsing for `.local`
- **Result**: macOS did NOT start unicast browsing for `.local`. `dns-sd -B _smb._tcp local.` still only uses multicast.
- **Key finding**: macOS hardcodes `.local` browsing to multicast-only. No server-side config changes this.

### Test 10: `vpn.local` subdomain (hoping `.local` suffix triggers mDNS code path)
- **What**: Created records under `vpn.local` instead of `vpn.internal`, added resolver
- **Result**: `dns-sd -B _smb._tcp vpn.local.` returned nothing — services never discovered
- **Key finding**: Subdomains of `.local` are also treated as mDNS territory. Multicast-only browsing, no unicast fallback.

### Test 11: macOS multicast flag on ipsec interface
- **Not tested**: Would require `sudo ifconfig ipsec1 multicast` on the Mac (client-side change). User requirement is no client modifications.

## Key Technical Findings

### 1. macOS has two distinct service connection paths

| Path | Used for | How it connects | Handles spaces? |
|------|----------|-----------------|-----------------|
| **mDNS** | `.local` domain | Follows SRV target hostname | Yes |
| **Unicast DNS-SD** | Non-`.local` domains | Uses service instance FQDN as URL | No — `getaddrinfo` rejects spaces |

### 2. The SMB URL constructed by Finder

When Finder discovers a service via DNS-SD and the user clicks it, `sharingd` asks `NetAuthSysAgent` to connect. The URL format is always:

```
smb://<instance_name>.<service_type>.<domain>
```

For mDNS services, this URL goes through the mDNS resolution path (which follows SRV). For unicast DNS-SD services, this URL is treated as a literal hostname for connection.

### 3. `open "smb://..."` test results

| URL | Resolves? | Connects? |
|-----|-----------|-----------|
| `smb://192.168.33.213` | N/A (IP) | Yes |
| `smb://bam-file-server.local` | Yes (via VPN DNS) | Yes |
| `smb://bam-file-server.vpn.internal` | Yes | Yes |
| `smb://bam-file-server._smb._tcp.vpn.internal` | Yes (`dscacheutil` works) | **No** |
| `smb://BAM File Server._smb._tcp.vpn.internal` | No (`getaddrinfo` rejects spaces) | **No** |

### 4. mDNSResponder interface exclusion

Apple's mDNSResponder source code explicitly excludes point-to-point interfaces (utun, ipsec) from mDNS processing. This is confirmed by:
- SparkLabs/Viscosity analysis of mDNSResponder source (~line 792)
- Tailscale open issue #1013 (266 upvotes, since 2020, unresolved)
- Our mDNS packet injection test (packets ignored on ipsec interface)

### 5. `GetServerInfo failed 65` = EHOSTUNREACH after 30s timeout

The macOS SMB client attempts to connect, can't resolve/reach the server via the URL-constructed hostname path, and times out after 30 seconds.

### 6. iOS vs macOS behavior

iOS's mDNSResponder is willing to send unicast DNS-SD queries for `.local` over VPN interfaces. macOS's mDNSResponder is not. This is why iOS printer/AirPlay discovery works but macOS Finder browsing does not.

### 7. `dns-sd -P` is the only proven working path

Proxy-registering services via local mDNS is the ONLY approach that achieves Finder sidebar click-to-connect over VPN. It's confirmed working by:
- Our live test on the VPN
- The bogner.sh "Poor Man's Bonjour VPN Server Proxy" (2015, deployed to customers)
- It works because it keeps the entire flow in the mDNS code path

## What Others Have Done

| Solution | Finder Click-to-Connect? | Modern macOS? | Notes |
|----------|--------------------------|---------------|-------|
| **ZeroTier** | Yes | Yes | L2 overlay, mDNS crosses naturally. Not a traditional VPN. |
| **`dns-sd -P` script** | Yes | Yes | Requires client-side script. Only proven VPN solution. |
| **Wide-Area Bonjour DNS** | Partially (domain globe icon) | Inconsistent | afp548 guide (2009), AFP-focused, SMB untested |
| **OpenVPN TAP bridge** | Yes | **Dead** | Apple killed kexts. TAP unavailable on modern macOS. |
| **AutoMounter / Network Share Mounter** | Mounts volumes, not sidebar discovery | Yes | MDM/Jamf compatible. Not Bonjour. |
| **Tailscale** | No | N/A | Open issue since 2020, 266 upvotes, no solution |
| **Any L3 VPN** | No | N/A | Fundamentally blocked by mDNSResponder interface exclusion |

## Possible Paths Forward

### Path A: `dns-sd -P` LaunchAgent (client-side, one-time install)
- A shell script + LaunchAgent plist installed once on the Mac
- launchd detects VPN connect (ipsec interface appears), triggers bridge script
- Bridge script queries dnsmasq for services, runs `dns-sd -P` for each
- Services appear in Finder sidebar via mDNS, click-to-connect works
- Completely invisible after install — no app, no menu bar, no user interaction
- **Status**: Proven working (Test 7). Needs automation/packaging.

### Path B: Ship discovery-only (no click-to-connect)
- Keep `vpn.internal` browse domain for Finder sidebar visibility
- Users see servers exist, connect via Cmd+K with `smb://hostname.vpn.internal`
- Document the limitation
- **Risk**: Users confused by servers they can see but can't click

### Path C: Remove `vpn.internal`, ship `.local` only
- iOS discovery works via `.local` unicast
- macOS users use Cmd+K with `smb://hostname.local`
- No Finder sidebar visibility on macOS
- Simplest, no confusion
- **Risk**: macOS users don't know what servers are available

### Path D: Investigate the `._smb._tcp` URL failure deeper
- We know `smb://hostname.vpn.internal` works and `smb://hostname._smb._tcp.vpn.internal` fails
- Both resolve to the same IP via `dscacheutil`
- The failure is at the SMB protocol/client level, not DNS
- Could use Wireshark to capture the actual SMB negotiation and see exactly where it fails
- Might reveal a fixable issue (e.g., SMB target name, Kerberos SPN, etc.)

### Path E: Wide-Area Bonjour with a real registered domain
- The afp548 guide used BIND with a real domain, not `.internal`
- Maybe macOS handles Wide-Area Bonjour differently with "real" domains vs reserved ones
- Worth testing with the user's actual domain if they have one

## Environment Details

- **VPN Server**: Ubuntu, Libreswan 5.3, IKEv2
- **VPN Client (Mac)**: macOS with native IKEv2 client, ipsec1 interface
- **VPN Client (iOS)**: native IKEv2 client — full service discovery works
- **File Server**: "BAM File Server" at 192.168.33.213, SMB on port 445
- **VPN Subnet**: 192.168.43.0/24, server at 192.168.43.1
- **LAN Subnet**: 192.168.33.0/24
- **DNS**: dnsmasq on 192.168.43.1, serves both `.local` and `vpn.internal` records
- **modecfgdomains**: `"local, vpn.internal, ."`

## Files on the Server

- `/etc/dnsmasq.d/bonjour-vpn.conf` — dnsmasq configuration (listen addresses, upstream DNS)
- `/etc/dnsmasq.d/bonjour-vpn-services.conf` — auto-generated DNS-SD records (both `.local` and `vpn.internal`)
- `/etc/bonjour-vpn-hosts` — hostname → IP mappings for `.local` A records
- `/usr/local/bin/bonjour-vpn-resolve` — cache warmer script (avahi-browse → dnsmasq records)
- `/usr/local/bin/bonjour-vpn-watch` — watcher service (event-driven, triggers resolve)
- `/usr/local/sbin/bonjour-vpn-ipv6-sync` — IPv6 state sync script

## Resolver State on Mac (with VPN connected)

```
resolver #1: search domain[0]: local, search domain[1]: vpn.internal
  nameserver: 192.168.43.1 (ipsec1)

resolver #3: domain: local (Supplemental)
  nameserver: 192.168.43.1 (ipsec1)

resolver #5: domain: vpn.internal (Supplemental)
  nameserver: 192.168.43.1 (ipsec1)

resolver #4: domain: local, options: mdns
  reach: Not Reachable (expected — mDNS on VPN)
```
