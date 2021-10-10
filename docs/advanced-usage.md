# Advanced Usage

*Read this in other languages: [English](advanced-usage.md), [简体中文](advanced-usage-zh.md).*

* [Use alternative DNS servers](#use-alternative-dns-servers)
* [DNS name and server IP changes](#dns-name-and-server-ip-changes)
* [Internal VPN IPs and traffic](#internal-vpn-ips-and-traffic)
* [Port forwarding to VPN clients](#port-forwarding-to-vpn-clients)
* [Split tunneling](#split-tunneling)
* [Access VPN server's subnet](#access-vpn-servers-subnet)
* [IKEv2 only VPN](#ikev2-only-vpn)
* [Modify IPTables rules](#modify-iptables-rules)

## Use alternative DNS servers

Clients are set to use [Google Public DNS](https://developers.google.com/speed/public-dns/) when the VPN is active. If another DNS provider is preferred, you may replace `8.8.8.8` and `8.8.4.4` in these files: `/etc/ppp/options.xl2tpd`, `/etc/ipsec.conf` and `/etc/ipsec.d/ikev2.conf` (if exists). Then run `service ipsec restart` and `service xl2tpd restart`.

Advanced users can define `VPN_DNS_SRV1` and optionally `VPN_DNS_SRV2` when running the VPN setup script and the [IKEv2 helper script](ikev2-howto.md#set-up-ikev2-using-helper-script). For example, if you want to use [Cloudflare's DNS service](https://1.1.1.1/dns/):

```
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 sh vpn.sh
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 ikev2.sh --auto
```

In certain circumstances, you may want VPN clients to use the specified DNS server(s) only for resolving internal domain name(s), and use their locally configured DNS servers to resolve all other domain names. This can be configured using the `modecfgdomains` option, e.g. `modecfgdomains="internal.example.com, home"`. Add this option to section `conn ikev2-cp` in `/etc/ipsec.d/ikev2.conf` for IKEv2, and to section `conn xauth-psk` in `/etc/ipsec.conf` for IPsec/XAuth ("Cisco IPsec"). Then run `service ipsec restart`. IPsec/L2TP mode does not support this option.

## DNS name and server IP changes

For [IPsec/L2TP](clients.md) and [IPsec/XAuth ("Cisco IPsec")](clients-xauth.md) modes, you may use a DNS name (e.g. `vpn.example.com`) instead of an IP address to connect to the VPN server, without additional configuration. In addition, the VPN should generally continue to work after server IP changes, such as after restoring a snapshot to a new server with a different IP, although a reboot may be required.

For [IKEv2](ikev2-howto.md) mode, if you want the VPN to continue to work after server IP changes, you must specify a DNS name to be used as the VPN server's address when [setting up IKEv2](ikev2-howto.md). The DNS name must be a fully qualified domain name (FQDN). It will be included in the generated server certificate, which is required for VPN clients to connect. Example:

```
sudo VPN_DNS_NAME='vpn.example.com' ikev2.sh --auto
```

Alternatively, you may customize IKEv2 setup options by running the [helper script](ikev2-howto.md#set-up-ikev2-using-helper-script) without the `--auto` parameter.

## Internal VPN IPs and traffic

When connecting using [IPsec/L2TP](clients.md) mode, the VPN server has internal IP `192.168.42.1` within the VPN subnet `192.168.42.0/24`. Clients are assigned internal IPs from `192.168.42.10` to `192.168.42.250`. To check which IP is assigned to a client, view the connection status on the VPN client.

When connecting using [IPsec/XAuth ("Cisco IPsec")](clients-xauth.md) or [IKEv2](ikev2-howto.md) mode, the VPN server does NOT have an internal IP within the VPN subnet `192.168.43.0/24`. Clients are assigned internal IPs from `192.168.43.10` to `192.168.43.250`.

You may use these internal VPN IPs for communication. However, note that the IPs assigned to VPN clients are dynamic, and firewalls on client devices may block such traffic.

Advanced users may optionally assign static IPs to VPN clients. Expand for details.

<details>
<summary>
IPsec/L2TP mode: Assign static IPs to VPN clients
</summary>

The example below **ONLY** applies to IPsec/L2TP mode. Commands must be run as `root`.

1. First, create a new VPN user for each VPN client that you want to assign a static IP to. Refer to [Manage VPN Users](manage-users.md). Helper scripts are included for convenience.
1. Edit `/etc/xl2tpd/xl2tpd.conf` on the VPN server. Replace `ip range = 192.168.42.10-192.168.42.250` with e.g. `ip range = 192.168.42.100-192.168.42.250`. This reduces the pool of auto-assigned IP addresses, so that more IPs are available to assign to clients as static IPs.
1. Edit `/etc/ppp/chap-secrets` on the VPN server. For example, if the file contains:
   ```
   "username1"  l2tpd  "password1"  *
   "username2"  l2tpd  "password2"  *
   "username3"  l2tpd  "password3"  *
   ```

   Let's assume that you want to assign static IP `192.168.42.2` to VPN user `username2`, assign static IP `192.168.42.3` to VPN user `username3`, while keeping `username1` unchanged (auto-assign from the pool). After editing, the file should look like:
   ```
   "username1"  l2tpd  "password1"  *
   "username2"  l2tpd  "password2"  192.168.42.2
   "username3"  l2tpd  "password3"  192.168.42.3
   ```

   **Note:** The assigned static IP(s) must be from the subnet `192.168.42.0/24`, and must NOT be from the pool of auto-assigned IPs (see `ip range` above). In addition, `192.168.42.1` is reserved for the VPN server itself. In the example above, you can only assign static IP(s) from the range `192.168.42.2-192.168.42.99`.
1. **(Important)** Restart the xl2tpd service:
   ```
   service xl2tpd restart
   ```
</details>

<details>
<summary>
IPsec/XAuth ("Cisco IPsec") mode: Assign static IPs to VPN clients
</summary>

The example below **ONLY** applies to IPsec/XAuth ("Cisco IPsec") mode. Commands must be run as `root`.

1. First, create a new VPN user for each VPN client that you want to assign a static IP to. Refer to [Manage VPN Users](manage-users.md). Helper scripts are included for convenience.
1. Edit `/etc/ipsec.conf` on the VPN server. Replace `rightaddresspool=192.168.43.10-192.168.43.250` with e.g. `rightaddresspool=192.168.43.100-192.168.43.250`. This reduces the pool of auto-assigned IP addresses, so that more IPs are available to assign to clients as static IPs.
1. Edit `/etc/ipsec.d/ikev2.conf` on the VPN server (if exists). Replace `rightaddresspool=192.168.43.10-192.168.43.250` with the **same value** as the previous step.
1. Edit `/etc/ipsec.d/passwd` on the VPN server. For example, if the file contains:
   ```
   username1:password1hashed:xauth-psk
   username2:password2hashed:xauth-psk
   username3:password3hashed:xauth-psk
   ```

   Let's assume that you want to assign static IP `192.168.43.2` to VPN user `username2`, assign static IP `192.168.43.3` to VPN user `username3`, while keeping `username1` unchanged (auto-assign from the pool). After editing, the file should look like:
   ```
   username1:password1hashed:xauth-psk
   username2:password2hashed:xauth-psk:192.168.42.2
   username3:password3hashed:xauth-psk:192.168.42.3
   ```

   **Note:** The assigned static IP(s) must be from the subnet `192.168.43.0/24`, and must NOT be from the pool of auto-assigned IPs (see `rightaddresspool` above). In the example above, you can only assign static IP(s) from the range `192.168.43.1-192.168.43.99`.
1. **(Important)** Restart the IPsec service:
   ```
   service ipsec restart
   ```
</details>

<details>
<summary>
IKEv2 mode: Assign static IPs to VPN clients
</summary>

The example below **ONLY** applies to IKEv2 mode. Commands must be run as `root`.

1. First, create a new IKEv2 client certificate for each client that you want to assign a static IP to, and write down the name of each IKEv2 client. Refer to [Add a client certificate](ikev2-howto.md#add-a-client-certificate).
1. Edit `/etc/ipsec.d/ikev2.conf` on the VPN server. Replace `rightaddresspool=192.168.43.10-192.168.43.250` with e.g. `rightaddresspool=192.168.43.100-192.168.43.250`. This reduces the pool of auto-assigned IP addresses, so that more IPs are available to assign to clients as static IPs.
1. Edit `/etc/ipsec.conf` on the VPN server. Replace `rightaddresspool=192.168.43.10-192.168.43.250` with the **same value** as the previous step.
1. Edit `/etc/ipsec.d/ikev2.conf` on the VPN server again. For example, if the file contains:
   ```
   conn ikev2-cp
     left=%defaultroute
     ... ...
   ```

   Let's assume that you want to assign static IP `192.168.43.4` to IKEv2 client `client1`, assign static IP `192.168.43.5` to client `client2`, while keeping other clients unchanged (auto-assign from the pool). After editing, the file should look like:
   ```
   conn ikev2-cp
     left=%defaultroute
     ... ...

   conn client1
     rightid=@client1
     rightaddresspool=192.168.43.4-192.168.43.4
     also=ikev2-cp

   conn client2
     rightid=@client2
     rightaddresspool=192.168.43.5-192.168.43.5
     also=ikev2-cp
   ```

   **Note:** Add a new `conn` section for each client that you want to assign a static IP to. You must add a `@` prefix to the client name for `rightid=`. The client name must exactly match the name you specified when [adding the client certificate](ikev2-howto.md#add-a-client-certificate). The assigned static IP(s) must be from the subnet `192.168.43.0/24`, and must NOT be from the pool of auto-assigned IPs (see `rightaddresspool` above). In the example above, you can only assign static IP(s) from the range `192.168.43.1-192.168.43.99`.
1. **(Important)** Restart the IPsec service:
   ```
   service ipsec restart
   ```
</details>

Client-to-client traffic is allowed by default. If you want to **disallow** client-to-client traffic, run the following commands on the VPN server. Add them to `/etc/rc.local` to persist after reboot.

```
iptables -I FORWARD 2 -i ppp+ -o ppp+ -s 192.168.42.0/24 -d 192.168.42.0/24 -j DROP
iptables -I FORWARD 3 -s 192.168.43.0/24 -d 192.168.43.0/24 -j DROP
iptables -I FORWARD 4 -i ppp+ -d 192.168.43.0/24 -j DROP
iptables -I FORWARD 5 -s 192.168.43.0/24 -o ppp+ -j DROP
```

## Port forwarding to VPN clients

In certain circumstances, you may want to forward port(s) on the VPN server to a connected VPN client. This can be done by adding IPTables rules on the VPN server.

**Warning:** Port forwarding will expose port(s) on the VPN client to the entire Internet, which could be a **security risk**! This is NOT recommended, unless your use case requires it.

**Note:** The internal VPN IPs assigned to VPN clients are dynamic, and firewalls on client devices may block forwarded traffic. To assign static IPs to VPN clients, refer to the previous section. To check which IP is assigned to a client, view the connection status on the VPN client.

Example 1: Forward TCP port 443 on the VPN server to the IPsec/L2TP client at `192.168.42.10`.
```
# Get default network interface name
netif=$(route 2>/dev/null | grep -m 1 '^default' | grep -o '[^ ]*$')
iptables -I FORWARD 2 -i "$netif" -o ppp+ -p tcp --dport 443 -j ACCEPT
iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to 192.168.42.10
```

Example 2: Forward UDP port 123 on the VPN server to the IKEv2 (or IPsec/XAuth) client at `192.168.43.10`.
```
# Get default network interface name
netif=$(route 2>/dev/null | grep -m 1 '^default' | grep -o '[^ ]*$')
iptables -I FORWARD 2 -i "$netif" -d 192.168.43.0/24 -p udp --dport 123 -j ACCEPT
iptables -t nat -A PREROUTING -p udp --dport 123 -j DNAT --to 192.168.43.10
```

If you want the rules to persist after reboot, you may add these commands to `/etc/rc.local`. To remove the added IPTables rules, run the commands again, but replace `-I FORWARD 2` with `-D FORWARD`, and replace `-A PREROUTING` with `-D PREROUTING`.

## Split tunneling

With [split tunneling](https://wiki.strongswan.org/projects/strongswan/wiki/ForwardingAndSplitTunneling#Split-Tunneling), VPN clients will only send traffic for specific destination subnet(s) through the VPN tunnel. Other traffic will NOT go through the VPN tunnel. Split tunneling has [some limitations](https://wiki.strongswan.org/projects/strongswan/wiki/ForwardingAndSplitTunneling#Split-Tunneling), and is not supported by all VPN clients.

Advanced users can optionally enable split tunneling for the [IPsec/XAuth ("Cisco IPsec")](clients-xauth.md) and/or [IKEv2](ikev2-howto.md) modes. Expand for details. IPsec/L2TP mode does NOT support this feature.

<details>
<summary>
IPsec/XAuth ("Cisco IPsec") mode: Enable split tunneling
</summary>

The example below **ONLY** applies to IPsec/XAuth ("Cisco IPsec") mode. Commands must be run as `root`.

1. Edit `/etc/ipsec.conf` on the VPN server. In the section `conn xauth-psk`, replace `leftsubnet=0.0.0.0/0` with the subnet(s) you want VPN clients to send traffic through the VPN tunnel. For example:   
   For a single subnet:
   ```
   leftsubnet=10.123.123.0/24
   ```
   For multiple subnets (use `leftsubnets` instead):
   ```
   leftsubnets="10.123.123.0/24,10.100.0.0/16"
   ```
1. **(Important)** Restart the IPsec service:
   ```
   service ipsec restart
   ```
</details>

<details>
<summary>
IKEv2 mode: Enable split tunneling
</summary>

The example below **ONLY** applies to IKEv2 mode. Commands must be run as `root`.

1. Edit `/etc/ipsec.d/ikev2.conf` on the VPN server. In the section `conn ikev2-cp`, replace `leftsubnet=0.0.0.0/0` with the subnet(s) you want VPN clients to send traffic through the VPN tunnel. For example:   
   For a single subnet:
   ```
   leftsubnet=10.123.123.0/24
   ```
   For multiple subnets (use `leftsubnets` instead):
   ```
   leftsubnets="10.123.123.0/24,10.100.0.0/16"
   ```
1. **(Important)** Restart the IPsec service:
   ```
   service ipsec restart
   ```
</details>

## Access VPN server's subnet

After connecting to the VPN, VPN clients can generally access services running on other devices that are within the same local subnet as the VPN server, without additional configuration. For example, if the VPN server's local subnet is `192.168.0.0/24`, and an Nginx server is running on IP `192.168.0.2`, VPN clients can use IP `192.168.0.2` to access the Nginx server.

Please note, additional configuration is required if the VPN server has multiple network interfaces (e.g. `eth0` and `eth1`), and you want VPN clients to access the local subnet behind the network interface that is NOT for Internet access. In this scenario, you must run the following commands to add IPTables rules. To persist after reboot, you may add these commands to `/etc/rc.local`.

```bash
# Replace eth1 with the name of the network interface
# on the VPN server that you want VPN clients to access
netif=eth1
iptables -I FORWARD 2 -i "$netif" -o ppp+ -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -I FORWARD 2 -i ppp+ -o "$netif" -j ACCEPT
iptables -I FORWARD 2 -i "$netif" -d 192.168.43.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -I FORWARD 2 -s 192.168.43.0/24 -o "$netif" -j ACCEPT
iptables -t nat -I POSTROUTING -s 192.168.43.0/24 -o "$netif" -m policy --dir out --pol none -j MASQUERADE
iptables -t nat -I POSTROUTING -s 192.168.42.0/24 -o "$netif" -j MASQUERADE
```

## IKEv2 only VPN

Libreswan 4.2 and newer versions support the `ikev1-policy` config option. Using this option, advanced users can set up an IKEv2-only VPN, i.e. only IKEv2 connections are accepted by the VPN server, while IKEv1 connections (including the IPsec/L2TP and IPsec/XAuth ("Cisco IPsec") modes) are dropped.

To set up an IKEv2-only VPN, first install the VPN server and set up IKEv2 using instructions in the [README](../README.md). Then check Libreswan version using `ipsec --version`, and [update Libreswan](../README.md#upgrade-libreswan) if needed. After that, edit `/etc/ipsec.conf` on the VPN server. Append `ikev1-policy=drop` to the end of the `config setup` section, indented by two spaces. Save the file and run `service ipsec restart`. When finished, you can run `ipsec status` to verify that only the `ikev2-cp` connection is enabled.

## Modify IPTables rules

If you want to modify the IPTables rules after install, edit `/etc/iptables.rules` and/or `/etc/iptables/rules.v4` (Ubuntu/Debian), or `/etc/sysconfig/iptables` (CentOS/RHEL). Then reboot your server.

**Note:** If using Rocky Linux, AlmaLinux or CentOS/RHEL 8 and firewalld was active during VPN setup, nftables may be configured. In this case, edit `/etc/sysconfig/nftables.conf` instead of `/etc/sysconfig/iptables`.

## License

Copyright (C) 2021 [Lin Song](https://github.com/hwdsl2) [![View my profile on LinkedIn](https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png)](https://www.linkedin.com/in/linsongui)   

[![Creative Commons License](https://i.creativecommons.org/l/by-sa/3.0/88x31.png)](http://creativecommons.org/licenses/by-sa/3.0/)   
This work is licensed under the [Creative Commons Attribution-ShareAlike 3.0 Unported License](http://creativecommons.org/licenses/by-sa/3.0/)  
Attribution required: please include my name in any derivative and let me know how you have improved it!
