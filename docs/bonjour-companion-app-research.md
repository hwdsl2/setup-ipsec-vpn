# Bonjour over IKEv2 VPN via macOS Network Extensions -- Technical Investigation

## Date: 2026-04-11
## Status: Complete investigation -- viable path identified

---

## Executive Summary

**Can we embed Bonjour service registration into a macOS IKEv2 VPN profile or Network Extension so that Bonjour services from the remote LAN automatically appear in Finder with zero additional setup?**

**Answer: Yes, but not via a configuration profile alone.** The viable architecture is a lightweight macOS app containing:
1. A companion app (or Login Item agent) that monitors the native IKEv2 VPN connection via `NEVPNStatusDidChange` notifications
2. On VPN connect, the agent queries the server for available services and calls `DNSServiceRegister` to proxy-register them into local mDNS
3. On VPN disconnect, registrations are torn down automatically (the `DNSServiceRef` is deallocated)

This is the programmatic equivalent of `dns-sd -P` (already proven working in Test 7 of the existing research) but automated and invisible. No custom VPN tunnel implementation is needed -- the native IKEv2 stack is used as-is.

**What is NOT possible:**
- A `.mobileconfig` profile alone cannot do this (no code execution capability)
- NEPacketTunnelProvider wrapping native IKEv2 is explicitly prohibited by Apple
- No Network Extension type can make mDNSResponder use mDNS on a point-to-point interface
- No interface flag manipulation can bypass the mDNSResponder exclusion

---

## 1. NEPacketTunnelProvider -- Can It Wrap Native IKEv2?

### Verdict: NO

`NEPacketTunnelProvider` is for implementing **custom** VPN protocols at the packet level. Apple's Quinn (DTS engineer) has stated explicitly and repeatedly on the Developer Forums:

> "If you develop your own VPN transport, you can't layer it on top of a built-in VPN transport. If you decide you need your own IKEv2 implementation, you have to write it from scratch."

This means:
- You cannot create a Network Extension that "wraps" the native IKEv2 connection
- You cannot intercept or augment the native IKEv2 tunnel's lifecycle from within a packet tunnel provider
- Implementing IKEv2 from scratch inside `NEPacketTunnelProvider` is technically possible but is described by Apple as "a horrendous amount of work" -- IKEv2 is thousands of pages of RFCs (RFC 7296, RFC 7427, RFC 3748, etc.)

### Could a custom packet tunnel add Bonjour on connect?

Hypothetically, if you wrote an entire IKEv2 implementation inside `NEPacketTunnelProvider`, you could call `DNSServiceRegister` from within the extension's `startTunnel()` method. But:
- Writing IKEv2 from scratch is a multi-year engineering effort
- You'd need to maintain compatibility with Libreswan's server-side implementation
- The existing native IKEv2 client works perfectly and is battle-tested
- This is absurdly disproportionate to the problem

**Conclusion:** Not viable. The correct approach is to use the native IKEv2 alongside a companion process.

### Sources
- [Network Extension Framework & IKEv2 -- Apple Developer Forums](https://developer.apple.com/forums/thread/41665)
- [NEPacketTunnelProvider -- Apple Developer Documentation](https://developer.apple.com/documentation/networkextension/nepackettunnelprovider)
- [VPN Part 2: Packet Tunnel Provider -- kean.blog](https://kean.blog/post/packet-tunnel-provider)

---

## 2. NEAppProxyProvider -- Can It Intercept mDNS Traffic?

### Verdict: NO (wrong layer entirely)

`NEAppProxyProvider` operates at the **flow level** (TCP connections, UDP sessions), not the packet level. It intercepts traffic from specific apps based on `NEAppRule` matching.

Problems:
- mDNS uses **multicast UDP** to 224.0.0.251:5353 -- this is not a flow initiated by an app; it's initiated by `mDNSResponder`, a system daemon
- `mDNSResponder` is a system process that is explicitly excluded from Network Extension interception on macOS (Apple exempts certain system processes from content filters and proxies)
- Even if you could intercept the traffic, the problem is that mDNSResponder **never sends** mDNS queries on point-to-point interfaces in the first place -- there is nothing to intercept
- `NEAppProxyProvider` requires per-app VPN configuration, which must be deployed via MDM configuration profile on macOS

**Conclusion:** Fundamentally incompatible with the problem. mDNS is a system-level multicast protocol, not an app-level flow.

### Sources
- [NEAppProxyProvider -- Apple Developer Documentation](https://developer.apple.com/documentation/networkextension/neappproxyprovider)
- [Apple Apps Exempt From Network Filters and VPNs](https://mjtsai.com/blog/2020/10/22/apple-apps-exempt-from-network-filters-and-vpns/)

---

## 3. NEDNSProxyProvider -- Can It Handle .local Queries?

### Verdict: NO (mDNS bypasses DNS proxy entirely)

`NEDNSProxyProvider` creates a system-wide DNS proxy that intercepts DNS queries. However:

1. **`.local` queries use mDNS, not DNS.** macOS hardcodes `.local` resolution to multicast DNS. These queries never go through the normal DNS resolution path and therefore never reach `NEDNSProxyProvider`.

2. **mDNSResponder bypasses DNS proxy.** Starting with macOS Ventura, `mDNSResponder` communicates directly with DNS servers over a persistent connection. Even for unicast DNS queries, `mDNSResponder` can bypass the DNS proxy if it discovers the upstream server supports DoH/DoT.

3. **The problem is not DNS resolution.** As proven in the existing research (Test 6c), the macOS SMB client successfully resolves service names via Wide-Area Bonjour DNS. The failure is that the **SMB connection pipeline after PTR browse is not implemented for non-`.local` domains**. A DNS proxy cannot fix an SMB client bug.

4. **The real solution needs mDNS registration, not DNS interception.** The proven path (`dns-sd -P`) works by registering services in the local mDNS domain, which triggers the mDNS code path in Finder/SMB. A DNS proxy intercepts queries; it cannot inject service registrations.

**Conclusion:** Wrong tool. The problem is not about intercepting DNS queries -- it's about registering services into the local mDNS domain.

### Sources
- [NEDNSProxyProvider -- Apple Developer Documentation](https://developer.apple.com/documentation/networkextension/nednsproxyprovider)
- [DNSProxy Network Extension on macOS Ventura -- Apple Developer Forums](https://developer.apple.com/forums/thread/716624)

---

## 4. Per-App VPN with DNS -- Can a .mobileconfig Enable Bonjour?

### Verdict: NO

A `.mobileconfig` configuration profile can contain:
- **VPN payloads** (IKEv2, IPSec, etc.) -- configures the VPN connection
- **DNS Settings payloads** -- configures DNS servers and search domains
- **OnDemand rules** -- controls when VPN connects/disconnects automatically

It **cannot** contain:
- Scripts or executable code of any kind
- Bonjour service registrations
- mDNSResponder configuration
- Interface flag modifications
- Lifecycle hooks that execute on VPN connect/disconnect

The OnDemand rules system provides `Connect`, `Disconnect`, `Ignore`, and `EvaluateConnection` actions -- these control whether the VPN connects, not what happens after it connects.

There is no payload type in the entire `.mobileconfig` specification that can:
- Run code on VPN connect/disconnect
- Register Bonjour services
- Modify mDNSResponder behavior
- Set interface flags

**Conclusion:** Configuration profiles are pure declarative configuration. They have zero code execution capability.

### Sources
- [Apple IKEv2 Configuration Profile -- strongSwan Documentation](https://docs.strongswan.org/docs/5.9/interop/appleIkev2Profile.html)
- [Configuration Profile Reference -- Apple Developer](https://developer.apple.com/business/documentation/Configuration-Profile-Reference.pdf)

---

## 5. NEVPNManager Programmatic VPN -- Can We Attach Lifecycle Hooks?

### Verdict: YES -- This is the core of the viable architecture

`NEVPNManager` allows a macOS app to programmatically configure and control the **built-in** IKEv2 VPN transport. Critically, it provides the `NEVPNStatusDidChange` notification, which fires whenever the VPN connection state changes.

### How it works

```swift
// Observe VPN status changes
NotificationCenter.default.addObserver(
    forName: .NEVPNStatusDidChange,
    object: nil,
    queue: .main
) { notification in
    guard let connection = notification.object as? NEVPNConnection else { return }
    switch connection.status {
    case .connected:
        // VPN is up -- register Bonjour services
        registerRemoteServices()
    case .disconnected, .invalid:
        // VPN is down -- deregister
        deregisterRemoteServices()
    default:
        break
    }
}
```

The `registerRemoteServices()` function would:
1. Query the VPN server's DNS for available services (DNS-SD browse via `DNSServiceBrowse` on `vpn.internal` or a custom API endpoint)
2. For each discovered service, call `DNSServiceRegister` with the service's details, registering it into the local `.local` mDNS domain
3. This is the programmatic equivalent of `dns-sd -P`

### Important notes

- `NEVPNManager` requires the `com.apple.developer.networking.vpn.api` entitlement, which is available to **all** apps (no special approval needed)
- The app does NOT need to implement its own VPN protocol -- it uses the system's native IKEv2
- The app can configure the VPN OR just observe an existing VPN configured by a profile
- `NEVPNStatusDidChange` works for VPN connections configured by `.mobileconfig` profiles too, not just ones created by the app
- The notification includes the `NEVPNConnection` object, which provides the server address and other connection details

### The even simpler alternative: NWPathMonitor

If the app does not need to configure the VPN (it's already configured via profile), it can skip `NEVPNManager` entirely and use `NWPathMonitor` to detect when a VPN interface (ipsec/utun) appears:

```swift
let monitor = NWPathMonitor()
monitor.pathUpdateHandler = { path in
    // Check for VPN interface
    let hasVPN = path.availableInterfaces.contains {
        $0.type == .other // utun/ipsec interfaces report as .other
    }
}
monitor.start(queue: DispatchQueue.global())
```

**Conclusion:** This is the foundation of the viable approach. A companion app/agent observes the native IKEv2 VPN lifecycle and triggers Bonjour registrations.

### Sources
- [NEVPNManager -- Apple Developer Documentation](https://developer.apple.com/documentation/networkextension/nevpnmanager)
- [NEVPNStatusDidChange -- Apple Developer Documentation](https://developer.apple.com/documentation/foundation/nsnotification/name/1406683-nevpnstatusdidchange)
- [NWPathMonitor -- Apple Developer Documentation](https://developer.apple.com/documentation/network/nwpathmonitor)

---

## 6. System Extension vs App Extension -- Distribution Requirements

### The Matrix (macOS only)

| Distribution Channel | Extension Type Required | Requirements |
|----------------------|------------------------|-------------|
| **Mac App Store** | App Extension (`.appex`) | Apple Developer Program ($99/yr), App Store review |
| **Developer ID (direct)** | System Extension (`.systemextension`) | Apple Developer Program ($99/yr), notarization required, `-systemextension` entitlement values |
| **MDM-managed** | Either | Requires MDM infrastructure |
| **TestFlight** | App Extension (`.appex`) | Apple Developer Program ($99/yr) |

### For our use case: NO System Extension needed

The companion app architecture does **not** require a Network Extension at all:
- It does not create a VPN tunnel (uses native IKEv2)
- It does not filter content
- It does not proxy DNS
- It only observes VPN status via `NEVPNManager` and calls `DNSServiceRegister`

This means:
- **No System Extension required** -- it's a regular macOS app
- **No special entitlements beyond `com.apple.developer.networking.vpn.api`** (for `NEVPNManager` observation)
- Can be distributed via **App Store, Developer ID, or even ad-hoc** for testing
- The `com.apple.developer.networking.vpn.api` entitlement is automatically available to all apps (no special request needed)
- Notarization is required for Developer ID distribution (standard since macOS 10.15)

### If a System Extension were needed

For reference, if we did need a Network Extension (e.g., packet tunnel, DNS proxy):
- Must use `com.apple.developer.networking.networkextension` entitlement with `-systemextension` suffix values
- Must be contained within a regular macOS app bundle
- User must approve the System Extension in System Settings > General > Login Items & Extensions (macOS Sequoia) or System Settings > Privacy & Security (macOS Sonoma)
- The approval prompt is a standard macOS dialog -- not especially intrusive
- Distribution via `.pkg` installer containing the app bundle is the standard pattern

### Sources
- [TN3134: Network Extension Provider Deployment -- Apple Developer Documentation](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment)
- [Network Extensions Entitlement -- Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension)
- [Notarizing macOS Software -- Apple Developer Documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

---

## 7. Configuration Profile Payloads -- Can ANY Payload Do This?

### Verdict: NO payload type can execute code or register Bonjour services

Complete audit of relevant payload types:

| Payload Type | What It Does | Can It Help? |
|-------------|-------------|-------------|
| `com.apple.vpn.managed` | Configures VPN connection | No -- declarative config only |
| `com.apple.dnsSettings.managed` | Configures DNS servers/domains | No -- sets resolver config, cannot register services |
| `com.apple.wifi.managed` | Configures WiFi | No |
| `com.apple.MCX` | Legacy managed preferences | No -- sets plist values, no code execution |
| `com.apple.servicemanagement` | Manages Login Items and LaunchAgents | **Interesting but requires MDM** -- see below |
| `com.apple.system-extension-policy` | Allows/blocks System Extensions | No -- policy only |
| `com.apple.TCC.configuration-profile-policy` | Manages privacy permissions (PPPC) | No |

### The `com.apple.servicemanagement` angle

This payload can "auto-enable and auto-allow" LaunchAgents and Login Items. In theory, you could:
1. Install the companion app with its embedded LaunchAgent
2. Deploy a `com.apple.servicemanagement` profile to auto-allow the LaunchAgent

**However:**
- This payload **requires MDM enrollment** -- it cannot be installed via a manually-installed `.mobileconfig`
- It only manages items that are already installed -- it does not install them
- It does not execute code itself

### The PKG installer alternative

A standard macOS `.pkg` installer can:
- Install the companion app to `/Applications`
- Register a LaunchAgent via the app's `SMAppService` registration
- The LaunchAgent runs the Bonjour bridge automatically

This is the correct distribution mechanism, not a configuration profile.

### Sources
- [Managed Login Items Payload Settings -- Apple Support](https://support.apple.com/guide/deployment/managed-login-items-payload-settings-dep07b92494/web)
- [Profile-Specific Payload Keys -- Apple Developer Documentation](https://developer.apple.com/documentation/devicemanagement/profile-specific-payload-keys)

---

## 8. What Do Cisco AnyConnect / GlobalProtect / Tunnelblick Do?

### Cisco AnyConnect / Cisco Secure Client

- Creates a `utun` interface via System Extension (modern versions) or kernel extension (legacy)
- Does **NOT** enable mDNS/Bonjour on the tunnel interface
- Uses its own DNS configuration to handle split-DNS
- No Bonjour integration whatsoever
- Users must use explicit hostnames/IPs for file sharing

### Palo Alto GlobalProtect

- Creates a `utun` interface via System Extension
- Does **NOT** enable mDNS/Bonjour on the tunnel interface
- Has HIP (Host Information Profile) checks but no service discovery
- No Bonjour integration

### Tunnelblick (OpenVPN)

- Historically used `tap` interfaces (Layer 2) which DID support mDNS natively because they appeared as ethernet-like broadcast domains
- Since macOS killed kernel extensions (kexts), `tap` is no longer available on modern macOS
- Switched to `utun` (Layer 3, point-to-point) -- mDNS stopped working
- SparkLabs (Viscosity) confirmed: "Apple specifically excludes point-to-point links from mDNSResponder"
- Workaround recommended by SparkLabs: run a Bonjour/mDNS proxy

### Viscosity (OpenVPN client by SparkLabs)

- Most relevant analysis found in the research
- SparkLabs explored three approaches:
  1. **Packet re-injection** into loopback -- abandoned due to performance penalties and kext requirements
  2. **Bonjour/mDNS proxy** -- recommended approach (equivalent to `dns-sd -P`)
  3. **Hybrid TAP+TUN** -- dead on modern macOS
- Their final recommendation is the same as ours: proxy registration via `dns-sd -P` or equivalent API

### Key takeaway

**No commercial VPN client has solved Bonjour over L3 VPN tunnels on modern macOS.** Every solution that works uses either L2 bridging (dead on modern macOS) or explicit proxy registration (what we're proposing).

### Sources
- [Viscosity, OpenVPN, utun Interfaces and Bonjour/mDNS Fun -- SparkLabs Forum](https://www.sparklabs.com/forum/viewtopic.php?t=2162)
- [Bonjour, Multicast -- SparkLabs Forum](https://www.sparklabs.com/forum/viewtopic.php?t=1836)

---

## 9. Can a Network Extension Create a Multicast-Capable Interface?

### Verdict: NO (the interface is already multicast-flagged; that's not the problem)

This is a common misconception. The `utun` interfaces created by `NEPacketTunnelProvider` **already have** the `IFF_MULTICAST` flag set:

```
utun4: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST>
```

Similarly, `ipsec` interfaces from the native IKEv2 client have both flags:

```
ipsec1: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST>
```

The problem is that mDNSResponder's `MulticastInterface` macro checks for **both** conditions:

```c
#define MulticastInterface(i) (((i)->ifa_flags & IFF_MULTICAST) && !((i)->ifa_flags & IFF_POINTOPOINT))
```

The interface must have `IFF_MULTICAST` **AND must NOT have** `IFF_POINTOPOINT`. VPN interfaces inherently have `IFF_POINTOPOINT` because they are point-to-point tunnels. This is a fundamental characteristic, not a configurable flag.

### Can we remove IFF_POINTOPOINT?

- `sudo ifconfig ipsec1 -pointopoint` -- this would require root access on the client Mac
- Even if it worked, it would likely break the tunnel's routing (the kernel uses this flag for routing decisions)
- mDNSResponder caches interface state; changing flags on a live interface may not be picked up
- This is a client-side modification, defeating the "zero additional setup" goal
- Network Extensions cannot modify interface flags of interfaces they don't own
- `NEPacketTunnelProvider` creates `utun` interfaces through the kernel API -- the `IFF_POINTOPOINT` flag is set by the kernel, not by the extension

### Could Apple change this?

Apple would need to modify mDNSResponder to treat certain point-to-point interfaces as multicast-capable. Tailscale has had an open issue (#1013) requesting exactly this since December 2020 with 266+ upvotes. Apple has not changed this behavior. The comment in Apple's source code explains the design rationale:

> "We don't want to run up the user's bill sending multicast traffic over a link where there's only a single device at the other end, and that device (e.g. a modem) is probably not answering Multicast DNS queries anyway."

### Sources
- [mDNSResponder source -- mDNSMacOSX.c (MulticastInterface macro)](https://github.com/obiltschnig/mDNSResponder/blob/master/mDNSMacOSX/mDNSMacOSX.c)
- [Support mDNS for name and service resolution -- Tailscale Issue #1013](https://github.com/tailscale/tailscale/issues/1013)
- [apple-oss-distributions/mDNSResponder](https://github.com/apple-oss-distributions/mDNSResponder)

---

## 10. Login Items vs App Extensions -- Modern macOS (Ventura+)

### Background

macOS Ventura (13+) introduced `SMAppService` as the replacement for `SMJobBless` and `SMLoginItemSetEnabled`. All new background helpers should use this API.

### How this applies to our architecture

The companion app would use `SMAppService` to register a **Login Item** (background agent):

```swift
import ServiceManagement

// Register the agent to run at login
let service = SMAppService.agent(plistName: "com.example.bonjour-vpn-bridge.plist")
try service.register()
```

The agent's LaunchAgent plist lives **inside the app bundle** at:
```
BonjourVPNBridge.app/Contents/Library/LaunchAgents/com.example.bonjour-vpn-bridge.plist
```

### User experience on modern macOS

1. User installs the app (drag to Applications or via `.pkg`)
2. App registers its Login Item via `SMAppService`
3. macOS shows a **single notification**: "BonjourVPNBridge added items that can run in the background"
4. User can see/manage it in System Settings > General > Login Items & Extensions
5. The agent runs in the background -- no Dock icon, no menu bar item (unless desired)
6. Agent monitors VPN status and manages Bonjour registrations

### Can a Login Item be bundled with a VPN configuration profile?

Not directly. They are separate things:
- The `.mobileconfig` profile configures the VPN connection
- The `.pkg` installer installs the companion app with its Login Item agent

However, a single `.pkg` installer can:
1. Install the companion app
2. Install the `.mobileconfig` profile (via `profiles` command in postinstall script)
3. This gives the user a single installation step

### MDM deployment

For enterprise/MDM deployment:
- The `com.apple.servicemanagement` profile payload can auto-allow the Login Item without user interaction
- The app can be deployed via MDM alongside the VPN profile
- Users see zero prompts

### Sources
- [SMAppService -- Apple Developer Documentation](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [macOS Service Management -- theevilbit blog](https://theevilbit.github.io/posts/smappservice/)
- [How Ventura is Changing Login and Background Items -- Eclectic Light Company](https://eclecticlight.co/2023/02/16/how-ventura-is-changing-login-and-background-items/)

---

## 11. User Experience Comparison for Each Approach

### Approach A: Companion App with Login Item Agent (RECOMMENDED)

| Aspect | Details |
|--------|---------|
| **Installation** | Download `.pkg` installer (~2 MB). Double-click to install. One "Allow" prompt for Login Item. |
| **Permissions** | Standard app permissions. No System Extension approval. No TCC/privacy prompts. |
| **What user sees** | Nothing in normal use. No Dock icon. No menu bar. Services appear in Finder when VPN connects. |
| **App Store distributable?** | Yes -- no special entitlements beyond `com.apple.developer.networking.vpn.api` |
| **Developer ID distributable?** | Yes -- standard notarization |
| **Apple Developer account?** | Yes -- $99/year Apple Developer Program |
| **Works with existing Libreswan?** | Yes -- does not touch the VPN tunnel at all |
| **macOS version support** | macOS 13+ (Ventura) for SMAppService. macOS 11+ possible with legacy LaunchAgent. |
| **Ongoing maintenance** | Minimal -- no VPN protocol implementation to maintain |

### Approach B: NEPacketTunnelProvider with Custom IKEv2 (NOT RECOMMENDED)

| Aspect | Details |
|--------|---------|
| **Installation** | Download app, approve System Extension, configure VPN in the app |
| **Permissions** | System Extension approval required (Settings > Privacy & Security) |
| **What user sees** | App in Dock/menu bar. VPN connects through the app, not system VPN settings. |
| **App Store distributable?** | Yes, as App Extension |
| **Developer ID distributable?** | Yes, as System Extension |
| **Apple Developer account?** | Yes -- $99/year + Network Extension entitlement |
| **Works with existing Libreswan?** | Only if IKEv2 implementation is compatible |
| **macOS version support** | macOS 10.15+ |
| **Ongoing maintenance** | Enormous -- full IKEv2 protocol implementation |

### Approach C: NEDNSProxyProvider for .local Interception (NOT VIABLE)

| Aspect | Details |
|--------|---------|
| **Installation** | Download app, approve System Extension |
| **Permissions** | System Extension approval required |
| **Would it work?** | **No** -- mDNS queries for `.local` bypass DNS proxy entirely |
| **Apple Developer account?** | Yes -- $99/year + Network Extension entitlement |

### Approach D: Configuration Profile Only (NOT POSSIBLE)

| Aspect | Details |
|--------|---------|
| **Installation** | Double-click `.mobileconfig`, approve in System Settings |
| **Would it work?** | **No** -- profiles cannot execute code or register Bonjour services |

---

## 12. How Tailscale and WireGuard Handle This

### Tailscale

**Architecture:**
- **App Store version**: Uses `NEPacketTunnelProvider` (App Extension) inside sandbox
- **Standalone version**: Uses System Extension with `NEPacketTunnelProvider`
- **Open source version**: Uses kernel `utun` interface directly via `tailscaled`
- All variants implement WireGuard under the hood

**Bonjour/mDNS status:**
- **Not supported.** Issue #1013 has been open since December 2020 with 266+ upvotes.
- Issue #8884 (multicast across tailnet) and #14739 (local peer discovery) are also unresolved.
- Tailscale's `MagicDNS` provides name resolution but NOT service discovery.
- Their architecture is fundamentally peer-to-peer, making multicast broadcast impractical.

**Why they haven't solved it:**
- Tailscale would need to reflect mDNS across potentially hundreds of peers
- The `utun` interface they create has the same `IFF_POINTOPOINT` exclusion from mDNSResponder
- They could theoretically use `DNSServiceRegister` to proxy-register services, but the scope is different (their mesh network vs. a single LAN)

### WireGuard (official macOS app)

**Architecture:**
- App Store version uses Network Extension (App Extension)
- Creates `utun` interface via `NEPacketTunnelProvider`

**Bonjour/mDNS status:**
- **Not supported.** Same fundamental limitation -- `utun` is point-to-point, mDNSResponder ignores it.
- WireGuard is purely a tunnel; it has no service discovery layer.

### Could their architecture be adapted?

**Yes, and it's simpler than their approach.** Both Tailscale and WireGuard implement custom tunneling protocols, which forces them to use `NEPacketTunnelProvider` and therefore own the tunnel interface. We don't need to own the tunnel -- we just need to react to the native IKEv2 tunnel connecting/disconnecting.

Our architecture is dramatically simpler:
- They build: custom protocol + packet tunnel + interface management + DNS + ...
- We build: VPN status observer + DNS-SD query + `DNSServiceRegister` calls

---

## Technical Architecture for the Recommended Approach

### Components

```
+----------------------------------------------------------+
|  macOS Client                                             |
|                                                           |
|  +-------------------+    +---------------------------+   |
|  | Native IKEv2 VPN  |    | BonjourVPNBridge.app      |   |
|  | (System Settings  |    |                           |   |
|  |  or .mobileconfig)|    |  Background Agent:        |   |
|  |                    |    |  1. NEVPNStatusDidChange   |   |
|  |  ipsec1 interface  |    |  2. DNS-SD Browse on      |   |
|  |                    |    |     vpn.internal           |   |
|  +--------+-----------+    |  3. DNSServiceRegister    |   |
|           |                |     into .local            |   |
|           |                +---------------------------+   |
|           |                            |                   |
|           v                            v                   |
|  +--------+-----------+    +----------+----------------+   |
|  | VPN Tunnel Traffic  |    | mDNSResponder             |   |
|  | (normal IP packets) |    | (local mDNS registrations)|   |
|  +---------------------+    +---------------------------+   |
|                                        |                   |
|                                        v                   |
|                              +---------+----------+        |
|                              | Finder Network     |        |
|                              | Sidebar (services  |        |
|                              | appear via mDNS)   |        |
|                              +--------------------+        |
+----------------------------------------------------------+

+----------------------------------------------------------+
|  VPN Server (Libreswan + dnsmasq)                         |
|                                                           |
|  Existing infrastructure -- NO CHANGES NEEDED             |
|  - IKEv2 VPN (as configured)                              |
|  - dnsmasq with DNS-SD records for vpn.internal           |
|  - avahi-daemon discovering LAN services                  |
+----------------------------------------------------------+
```

### Sequence on VPN Connect

1. User connects VPN (System Settings, menu bar, or On-Demand)
2. Native IKEv2 tunnel establishes, `ipsec1` interface comes up
3. `NEVPNStatusDidChange` notification fires with `.connected` status
4. Background agent receives notification
5. Agent performs DNS-SD browse: `DNSServiceBrowse` for `_smb._tcp` (and other types) on `vpn.internal` domain, using the VPN's DNS server
6. For each discovered service, agent performs `DNSServiceResolve` to get SRV target, port, TXT record
7. Agent calls `DNSServiceRegister` for each service in the `local.` domain (equivalent to `dns-sd -P`)
8. mDNSResponder advertises these services on the local mDNS domain
9. Finder picks them up and shows them in the Network sidebar
10. User clicks a service -- Finder uses the mDNS code path (which works correctly)

### Sequence on VPN Disconnect

1. VPN disconnects
2. `NEVPNStatusDidChange` notification fires with `.disconnected` status
3. Agent receives notification
4. Agent calls `DNSServiceRefDeallocate` for each active registration
5. Services disappear from Finder sidebar
6. Clean state -- no stale registrations

### The `DNSServiceRegister` Call (equivalent to `dns-sd -P`)

The `dns-sd -P` command does two things internally:
1. Creates a shared connection via `DNSServiceCreateConnection`
2. Registers an address record via `DNSServiceRegisterRecord` (the proxy A record)
3. Registers the service via `DNSServiceRegister` with a non-nil `host` parameter

In Swift/C, the equivalent is:

```c
// Register proxy address record
DNSServiceRegisterRecord(
    sharedConnection,
    &recordRef,
    kDNSServiceFlagsShared,
    kDNSServiceInterfaceIndexAny,
    "bam-file-server.local.",
    kDNSServiceType_A,
    kDNSServiceClass_IN,
    4,                      // rdlen
    &ipv4Address,           // rdata (192.168.33.213)
    0,                      // ttl
    callback,
    context
);

// Register the service with explicit host
DNSServiceRegister(
    &serviceRef,
    0,                          // flags
    kDNSServiceInterfaceIndexAny,
    "BAM File Server",          // instance name
    "_smb._tcp",                // service type
    "local",                    // domain
    "bam-file-server.local.",   // host (non-nil = proxy)
    htons(445),                 // port
    txtLen,                     // TXT record length
    txtRecord,                  // TXT record data
    callback,
    context
);
```

The key is the non-nil `host` parameter to `DNSServiceRegister` -- this is what makes it a proxy registration. The service is registered on behalf of a remote host, not the local machine.

---

## Development and Distribution Requirements Summary

### Minimum Requirements

| Requirement | Details |
|-------------|---------|
| **Apple Developer Account** | Yes -- $99/year Apple Developer Program |
| **Xcode** | Yes -- for building the macOS app |
| **Languages** | Swift (recommended) or Objective-C |
| **Frameworks** | NetworkExtension (for NEVPNManager), dnssd (for DNSServiceRegister), ServiceManagement (for SMAppService) |
| **Code Signing** | Developer ID certificate for direct distribution, or App Store distribution certificate |
| **Notarization** | Required for Developer ID distribution |
| **System Extension** | NOT required -- this is a regular app |
| **Entitlements** | `com.apple.developer.networking.vpn.api` (auto-granted), `com.apple.security.app-sandbox` (for App Store) |

### Distribution Options

| Channel | Feasibility | Notes |
|---------|------------|-------|
| **Direct (.pkg)** | Best for this project | Standard installer, notarized, no App Store overhead |
| **App Store** | Possible | Subject to App Store review. Sandboxing may complicate DNS-SD calls. |
| **GitHub Releases** | Possible with notarization | Notarized `.dmg` or `.pkg` on GitHub Releases |
| **Homebrew Cask** | Possible | Community can add a cask formula |

### Server-Side Changes

**None required.** The existing Libreswan + dnsmasq setup already provides:
- IKEv2 VPN tunnel (works with native macOS client)
- DNS-SD records for `vpn.internal` (used by the agent to discover services)
- A records for `.local` hostnames (used as SRV targets in proxy registrations)

---

## Risk Assessment

### Low Risk
- **API stability**: `DNSServiceRegister`, `NEVPNManager`, and `SMAppService` are stable, mature Apple APIs
- **Server compatibility**: Zero server changes needed
- **User experience**: Invisible after installation
- **Maintenance burden**: Small codebase (~500-1000 lines of Swift)

### Medium Risk
- **App Store sandboxing**: `DNSServiceRegister` works from sandboxed apps, but proxy registration (with explicit host parameter) may need testing. Direct distribution avoids this concern entirely.
- **macOS updates**: Apple could change mDNSResponder behavior (unlikely given stability of dns_sd.h API, but possible)
- **Multiple VPN configurations**: Agent needs to correctly identify which VPN to monitor if multiple are configured

### Low Probability but High Impact
- **Apple deprecates dns_sd.h API**: Extremely unlikely -- it's the foundation of Bonjour and has been stable since 2004
- **Apple fixes the Wide-Area Bonjour SMB connection bug**: If Apple fixes the SMB client to properly follow SRV records for non-`.local` domains, the server-side solution would work without any client software. This would make the companion app unnecessary (but harmless if still installed).
