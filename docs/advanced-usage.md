[English](advanced-usage.md) | [中文](advanced-usage-zh.md)

# Advanced Usage

* [Use alternative DNS servers](#use-alternative-dns-servers)
* [DNS name and server IP changes](#dns-name-and-server-ip-changes)
* [IKEv2-only VPN](#ikev2-only-vpn)
* [Internal VPN IPs and traffic](#internal-vpn-ips-and-traffic)
* [Specify VPN server's public IP](#specify-vpn-servers-public-ip)
* [Customize VPN subnets](#customize-vpn-subnets)
* [Port forwarding to VPN clients](#port-forwarding-to-vpn-clients)
* [Split tunneling](#split-tunneling)
* [Access VPN server's subnet](#access-vpn-servers-subnet)
* [Access VPN clients from server's subnet](#access-vpn-clients-from-servers-subnet)
* [Modify IPTables rules](#modify-iptables-rules)
* [Deploy Google BBR congestion control](#deploy-google-bbr-congestion-control)

## Use alternative DNS servers

By default, clients are set to use [Google Public DNS](https://developers.google.com/speed/public-dns/) when the VPN is active. If another DNS provider is preferred, you may replace `8.8.8.8` and `8.8.4.4` in these files: `/etc/ppp/options.xl2tpd`, `/etc/ipsec.conf` and `/etc/ipsec.d/ikev2.conf` (if exists). Then run `service ipsec restart` and `service xl2tpd restart`.

Below is a list of some popular public DNS providers for your reference.

| Provider | Primary DNS | Secondary DNS | Notes |
| -------- | ----------- | ------------- | ----- |
| [Google Public DNS](https://developers.google.com/speed/public-dns) | 8.8.8.8 | 8.8.4.4 | Default in this project |
| [Cloudflare](https://1.1.1.1/dns/) | 1.1.1.1 | 1.0.0.1 | See also: [Cloudflare for families](https://1.1.1.1/family/) |
| [Quad9](https://www.quad9.net) | 9.9.9.9 | 149.112.112.112 | Blocks malicious domains |
| [OpenDNS](https://www.opendns.com/home-internet-security/) | 208.67.222.222 | 208.67.220.220 | Blocks phishing domains, configurable. |
| [CleanBrowsing](https://cleanbrowsing.org/filters/) | 185.228.168.9 | 185.228.169.9 | [Domain filters](https://cleanbrowsing.org/filters/) available |
| [NextDNS](https://nextdns.io/?from=bg25bwmp) | Varies | Varies | Ad blocking, free tier available. [Learn more](https://nextdns.io/?from=bg25bwmp). |
| [Control D](https://controld.com/free-dns) | Varies | Varies | Ad blocking, configurable. [Learn more](https://controld.com/free-dns). |

Advanced users can define `VPN_DNS_SRV1` and optionally `VPN_DNS_SRV2` when running the VPN setup script. For more details, see [Customize VPN options](../README.md#customize-vpn-options).

It is possible to set different DNS server(s) for specific IKEv2 client(s). For this use case, please refer to [#1562](https://github.com/hwdsl2/setup-ipsec-vpn/issues/1562#issuecomment-2151361658).

If your use case requires redirecting DNS traffic to another server using IPTables rules, see [#1565](https://github.com/hwdsl2/setup-ipsec-vpn/issues/1565).

In certain circumstances, you may want VPN clients to use the specified DNS server(s) only for resolving internal domain name(s), and use their locally configured DNS servers to resolve all other domain names. This can be configured using the `modecfgdomains` option, e.g. `modecfgdomains="internal.example.com, home"`. Add this option to section `conn ikev2-cp` in `/etc/ipsec.d/ikev2.conf` for IKEv2, and to section `conn xauth-psk` in `/etc/ipsec.conf` for IPsec/XAuth ("Cisco IPsec"). Then run `service ipsec restart`. IPsec/L2TP mode does not support this option.

## DNS name and server IP changes

For [IPsec/L2TP](clients.md) and [IPsec/XAuth ("Cisco IPsec")](clients-xauth.md) modes, you may use a DNS name (e.g. `vpn.example.com`) instead of an IP address to connect to the VPN server, without additional configuration. In addition, the VPN should generally continue to work after server IP changes, such as after restoring a snapshot to a new server with a different IP, although a reboot may be required.

For [IKEv2](ikev2-howto.md) mode, if you want the VPN to continue to work after server IP changes, read [this section](ikev2-howto.md#change-ikev2-server-address). Alternatively, you may specify a DNS name for the IKEv2 server address when [setting up IKEv2](ikev2-howto.md#set-up-ikev2-using-helper-script). The DNS name must be a fully qualified domain name (FQDN). Example:

```
sudo VPN_DNS_NAME='vpn.example.com' ikev2.sh --auto
```

Alternatively, you may customize IKEv2 options by running the [helper script](ikev2-howto.md#set-up-ikev2-using-helper-script) without the `--auto` parameter.

## IKEv2-only VPN

Using Libreswan 4.2 or newer, advanced users can enable IKEv2-only mode on the VPN server. With IKEv2-only mode enabled, VPN clients can only connect to the VPN server using IKEv2. All IKEv1 connections (including IPsec/L2TP and IPsec/XAuth ("Cisco IPsec") modes) will be dropped.

To enable IKEv2-only mode, first install the VPN server and set up IKEv2 using instructions in the [README](../README.md). Then run the [helper script](../extras/ikev2onlymode.sh) and follow the prompts.

```bash
wget https://get.vpnsetup.net/ikev2only -O ikev2only.sh
sudo bash ikev2only.sh
```

To disable IKEv2-only mode, run the helper script again and select the appropriate option.

<details>
<summary>
Alternatively, you may manually enable IKEv2-only mode.
</summary>

Alternatively, you may manually enable IKEv2-only mode. First check Libreswan version using `ipsec --version`, and [update Libreswan](../README.md#upgrade-libreswan) if needed. Then edit `/etc/ipsec.conf` on the VPN server. Replace `ikev1-policy=accept` with `ikev1-policy=drop`. If the line does not exist, append `ikev1-policy=drop` to the end of the `config setup` section, indented by two spaces. Save the file and run `service ipsec restart`. When finished, you can run `ipsec status` to verify that only the `ikev2-cp` connection is enabled.
</details>

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

   conn ikev2-shared
     # COPY everything from the ikev2-cp section, EXCEPT FOR:
     # rightid, rightaddresspool, auto=add

   conn client1
     rightid=@client1
     rightaddresspool=192.168.43.4-192.168.43.4
     auto=add
     also=ikev2-shared

   conn client2
     rightid=@client2
     rightaddresspool=192.168.43.5-192.168.43.5
     auto=add
     also=ikev2-shared
   ```

   **Note:** Add a new `conn` section for each client that you want to assign a static IP to. You must add a `@` prefix to the client name for `rightid=`. The client name must exactly match the name you specified when [adding the client certificate](ikev2-howto.md#add-a-client-certificate). The assigned static IP(s) must be from the subnet `192.168.43.0/24`, and must NOT be from the pool of auto-assigned IPs (see `rightaddresspool` above). In the example above, you can only assign static IP(s) from the range `192.168.43.1-192.168.43.99`.

   **Note:** For Windows 7/8/10/11 and [RouterOS](ikev2-howto.md#routeros) clients, you must use a different syntax for `rightid=`. For example, if the client name is `client1`, set `rightid="CN=client1, O=IKEv2 VPN"` in the example above.
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

## Specify VPN server's public IP

On servers with multiple public IP addresses, advanced users can specify a public IP for the VPN server using variable `VPN_PUBLIC_IP`. For example, if the server has IPs `192.0.2.1` and `192.0.2.2`, and you want the VPN server to use `192.0.2.2`:

```
sudo VPN_PUBLIC_IP=192.0.2.2 sh vpn.sh
```

Note that this variable has no effect for IKEv2 mode, if IKEv2 is already set up on the server. In this case, you may remove IKEv2 and set it up again using custom options. Refer to [Set up IKEv2 using helper script](ikev2-howto.md#set-up-ikev2-using-helper-script).

Additional configuration may be required if you want VPN clients to use the specified public IP as their "outgoing IP" when the VPN connection is active, and the specified IP is NOT the main IP (or default route) on the server. In this case, you may need to change IPTables rules on the server. To persist after reboot, you can add these commands to `/etc/rc.local`.

Continuing with the example above, if you want the "outgoing IP" to be `192.0.2.2`:

```
# Get default network interface name
netif=$(ip -4 route list 0/0 | grep -m 1 -Po '(?<=dev )(\S+)')
# Remove MASQUERADE rules
iptables -t nat -D POSTROUTING -s 192.168.43.0/24 -o "$netif" -m policy --dir out --pol none -j MASQUERADE
iptables -t nat -D POSTROUTING -s 192.168.42.0/24 -o "$netif" -j MASQUERADE
# Add SNAT rules
iptables -t nat -I POSTROUTING -s 192.168.43.0/24 -o "$netif" -m policy --dir out --pol none -j SNAT --to 192.0.2.2
iptables -t nat -I POSTROUTING -s 192.168.42.0/24 -o "$netif" -j SNAT --to 192.0.2.2
```

**Note:** The method above only applies if the VPN server's default network interface maps to multiple public IPs. This method may not work if the server has multiple network interfaces, each with a different public IP.

To check the "outgoing IP" for a connected VPN client, you may open a browser on the client and [look up the IP address on Google](https://www.google.com/search?q=my+ip).

## Customize VPN subnets

By default, IPsec/L2TP VPN clients will use internal VPN subnet `192.168.42.0/24`, while IPsec/XAuth ("Cisco IPsec") and IKEv2 VPN clients will use internal VPN subnet `192.168.43.0/24`. For more details, see [Internal VPN IPs and traffic](#internal-vpn-ips-and-traffic).

For most use cases, it is NOT necessary and NOT recommended to customize these subnets. If your use case requires it, however, you may specify custom subnet(s) when installing the VPN.

**Important:** You may only specify custom subnets **during initial VPN install**. If the IPsec VPN is already installed, you **must** first [uninstall the VPN](uninstall.md), then specify custom subnets and re-install. Otherwise, the VPN may stop working.

```
# Example: Specify custom VPN subnet for IPsec/L2TP mode
# Note: All three variables must be specified.
sudo VPN_L2TP_NET=10.1.0.0/16 \
VPN_L2TP_LOCAL=10.1.0.1 \
VPN_L2TP_POOL=10.1.0.10-10.1.254.254 \
sh vpn.sh
```

```
# Example: Specify custom VPN subnet for IPsec/XAuth and IKEv2 modes
# Note: Both variables must be specified.
sudo VPN_XAUTH_NET=10.2.0.0/16 \
VPN_XAUTH_POOL=10.2.0.10-10.2.254.254 \
sh vpn.sh
```

In the examples above, `VPN_L2TP_LOCAL` is the VPN server's internal IP for IPsec/L2TP mode. `VPN_L2TP_POOL` and `VPN_XAUTH_POOL` are the pools of auto-assigned IP addresses for VPN clients.

## Port forwarding to VPN clients

In certain circumstances, you may want to forward port(s) on the VPN server to a connected VPN client. This can be done by adding IPTables rules on the VPN server.

**Warning:** Port forwarding will expose port(s) on the VPN client to the entire Internet, which could be a **security risk**! This is NOT recommended, unless your use case requires it.

**Note:** The internal VPN IPs assigned to VPN clients are dynamic, and firewalls on client devices may block forwarded traffic. To assign static IPs to VPN clients, see [Internal VPN IPs and traffic](#internal-vpn-ips-and-traffic). To check which IP is assigned to a client, view the connection status on the VPN client.

Example 1: Forward TCP port 443 on the VPN server to the IPsec/L2TP client at `192.168.42.10`.
```
# Get default network interface name
netif=$(ip -4 route list 0/0 | grep -m 1 -Po '(?<=dev )(\S+)')
iptables -I FORWARD 2 -i "$netif" -o ppp+ -p tcp --dport 443 -j ACCEPT
iptables -t nat -A PREROUTING -i "$netif" -p tcp --dport 443 -j DNAT --to 192.168.42.10
```

Example 2: Forward UDP port 123 on the VPN server to the IKEv2 (or IPsec/XAuth) client at `192.168.43.10`.
```
# Get default network interface name
netif=$(ip -4 route list 0/0 | grep -m 1 -Po '(?<=dev )(\S+)')
iptables -I FORWARD 2 -i "$netif" -d 192.168.43.0/24 -p udp --dport 123 -j ACCEPT
iptables -t nat -A PREROUTING -i "$netif" ! -s 192.168.43.0/24 -p udp --dport 123 -j DNAT --to 192.168.43.10
```

If you want the rules to persist after reboot, you may add these commands to `/etc/rc.local`. To remove the added IPTables rules, run the commands again, but replace `-I FORWARD 2` with `-D FORWARD`, and replace `-A PREROUTING` with `-D PREROUTING`.

## Split tunneling

With split tunneling, VPN clients will only send traffic for specific destination subnet(s) through the VPN tunnel. Other traffic will NOT go through the VPN tunnel. This allows you to gain secure access to a network through your VPN, without routing all your client's traffic through the VPN. Split tunneling has some limitations, and is not supported by all VPN clients.

Advanced users can optionally enable split tunneling for the [IPsec/XAuth ("Cisco IPsec")](clients-xauth.md) and/or [IKEv2](ikev2-howto.md) modes. Expand for details. IPsec/L2TP mode does not support this feature (except on Windows, see below).

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

**Note:** Advanced users can set a different split tunneling configuration for specific IKEv2 client(s). Refer to section [Internal VPN IPs and traffic](#internal-vpn-ips-and-traffic) and expand "IKEv2 mode: Assign static IPs to VPN clients". Based on the example in that section, you may add the `leftsubnet=...` option to the `conn` section of the specific IKEv2 client, then restart the IPsec service.
</details>

Alternatively, Windows users can enable split tunneling by manually adding routes:

1. Right-click on the wireless/network icon in your system tray.
1. **Windows 11:** Select **Network and Internet settings**, then on the page that opens, click **Advanced network settings**. Click **More network adapter options**.   
   **Windows 10:** Select **Open Network & Internet settings**, then on the page that opens, click **Network and Sharing Center**. On the left, click **Change adapter settings**.   
   **Windows 8/7:** Select **Open Network and Sharing Center**. On the left, click **Change adapter settings**.
1. Right-click on the new VPN connection, and choose **Properties**.
1. Click the **Network** tab. Select **Internet Protocol Version 4 (TCP/IPv4)**, then click **Properties**.
1. Click **Advanced**. Uncheck **Use default gateway on remote network**.
1. Click **OK** to close the **Properties** window.
1. **(Important)** Disconnect the VPN, then re-connect.
1. Assume that the subnet you want VPN clients to send traffic through the VPN tunnel is `10.123.123.0/24`. Open an [elevated command prompt](http://www.winhelponline.com/blog/open-elevated-command-prompt-windows/) and run one of the following commands:   
   For IKEv2 and IPsec/XAuth ("Cisco IPsec") modes:
   ```
   route add -p 10.123.123.0 mask 255.255.255.0 192.168.43.1
   ```
   For IPsec/L2TP mode:
   ```
   route add -p 10.123.123.0 mask 255.255.255.0 192.168.42.1
   ```
1. When finished, VPN clients will send traffic through the VPN tunnel for the specified subnet only. Other traffic will bypass the VPN.

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

## Access VPN clients from server's subnet

In certain circumstances, you may need to access services on VPN clients from other devices that are on the same local subnet as the VPN server. This can be done using the following steps.

Assume that the VPN server IP is `10.1.0.2`, and the IP of the device from which you want to access VPN clients is `10.1.0.3`.

1. Add IPTables rules on the VPN server to allow this traffic. For example:
   ```
   # Get default network interface name
   netif=$(ip -4 route list 0/0 | grep -m 1 -Po '(?<=dev )(\S+)')
   iptables -I FORWARD 2 -i "$netif" -o ppp+ -s 10.1.0.3 -j ACCEPT
   iptables -I FORWARD 2 -i "$netif" -d 192.168.43.0/24 -s 10.1.0.3 -j ACCEPT
   ```
2. Add routing rules on the device you want to access VPN clients. For example:
   ```
   # Replace eth0 with the network interface name of the device's local subnet
   route add -net 192.168.42.0 netmask 255.255.255.0 gw 10.1.0.2 dev eth0
   route add -net 192.168.43.0 netmask 255.255.255.0 gw 10.1.0.2 dev eth0
   ```

Learn more about internal VPN IPs in [Internal VPN IPs and traffic](#internal-vpn-ips-and-traffic).

## Modify IPTables rules

If you want to modify IPTables rules after install, edit `/etc/iptables.rules` and/or `/etc/iptables/rules.v4` (Ubuntu/Debian), or `/etc/sysconfig/iptables` (CentOS/RHEL). Then reboot your server.

**Note:** If your server runs CentOS Linux (or similar), and firewalld was active during VPN setup, nftables may be configured. In this case, edit `/etc/sysconfig/nftables.conf` instead of `/etc/sysconfig/iptables`.

## Deploy Google BBR congestion control

After the VPN server is set up, the performance can be improved by deploying the Google BBR congestion control algorithm.

This is usually done by modifying the configuration file `/etc/sysctl.conf`. However, some Linux distributions may additionally require updates to the Linux kernel.

For detailed deployment methods, please refer to [this document](bbr.md).

## License

Copyright (C) 2021-2024 [Lin Song](https://github.com/hwdsl2) [![View my profile on LinkedIn](https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png)](https://www.linkedin.com/in/linsongui)   

[![Creative Commons License](https://i.creativecommons.org/l/by-sa/3.0/88x31.png)](http://creativecommons.org/licenses/by-sa/3.0/)   
This work is licensed under the [Creative Commons Attribution-ShareAlike 3.0 Unported License](http://creativecommons.org/licenses/by-sa/3.0/)  
Attribution required: please include my name in any derivative and let me know how you have improved it!
