# 高级用法

*其他语言版本: [English](advanced-usage.md), [简体中文](advanced-usage-zh.md).*

* [使用其他的 DNS 服务器](#使用其他的-dns-服务器)
* [域名和更改服务器 IP](#域名和更改服务器-ip)
* [VPN 内网 IP 和流量](#vpn-内网-ip-和流量)
* [转发端口到 VPN 客户端](#转发端口到-vpn-客户端)
* [VPN 分流](#vpn-分流)
* [访问 VPN 服务器的网段](#访问-vpn-服务器的网段)
* [仅限 IKEv2 的 VPN](#仅限-ikev2-的-vpn)
* [更改 IPTables 规则](#更改-iptables-规则)

## 使用其他的 DNS 服务器

在 VPN 已连接时，客户端配置为使用 [Google Public DNS](https://developers.google.com/speed/public-dns/)。如果偏好其它的域名解析服务，你可以编辑以下文件：`/etc/ppp/options.xl2tpd`, `/etc/ipsec.conf` 和 `/etc/ipsec.d/ikev2.conf`（如果存在），并替换 `8.8.8.8` 和 `8.8.4.4`。然后运行 `service ipsec restart` 和 `service xl2tpd restart`。

高级用户可以在运行 VPN 安装脚本和 [IKEv2 辅助脚本](ikev2-howto-zh.md#使用辅助脚本配置-ikev2) 时定义 `VPN_DNS_SRV1` 和 `VPN_DNS_SRV2`（可选）。比如你想使用 [Cloudflare 的 DNS 服务](https://1.1.1.1/dns/)：

```
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 sh vpn.sh
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 ikev2.sh --auto
```

在某些情况下，你可能希望 VPN 客户端仅使用指定的 DNS 服务器来解析内部域名，并使用其本地配置的 DNS 服务器来解析所有其他域名。这可以使用 `modecfgdomains` 选项进行配置，例如 `modecfgdomains="internal.example.com, home"`。对于 IKEv2，将此选项添加到 `/etc/ipsec.d/ikev2.conf` 中的 `conn ikev2-cp` 小节。对于 IPsec/XAuth ("Cisco IPsec")，将此选项添加到 `/etc/ipsec.conf` 中的 `conn xauth-psk` 小节。然后运行 `service ipsec restart`。IPsec/L2TP 模式不支持此选项。

## 域名和更改服务器 IP

对于 [IPsec/L2TP](clients-zh.md) 和 [IPsec/XAuth ("Cisco IPsec")](clients-xauth-zh.md) 模式，你可以在不需要额外配置的情况下使用一个域名（比如 `vpn.example.com`）而不是 IP 地址连接到 VPN 服务器。另外，一般来说，在服务器的 IP 更改后，比如在恢复一个映像到具有不同 IP 的新服务器后，VPN 会继续正常工作，虽然可能需要重启服务器。

对于 [IKEv2](ikev2-howto-zh.md) 模式，如果你想要 VPN 在服务器的 IP 更改后继续正常工作，则必须在 [配置 IKEv2](ikev2-howto-zh.md) 时指定一个域名作为 VPN 服务器的地址。该域名必须是一个全称域名(FQDN)。它将包含在生成的服务器证书中，这是 VPN 客户端连接所必需的。示例如下：

```
sudo VPN_DNS_NAME='vpn.example.com' ikev2.sh --auto
```

另外，你也可以自定义 IKEv2 安装选项，通过在运行 [辅助脚本](ikev2-howto-zh.md#使用辅助脚本配置-ikev2) 时去掉 `--auto` 参数来实现。

## VPN 内网 IP 和流量

在使用 [IPsec/L2TP](clients-zh.md) 模式连接时，VPN 服务器在虚拟网络 `192.168.42.0/24` 内具有内网 IP `192.168.42.1`。为客户端分配的内网 IP 在这个范围内：`192.168.42.10` 到 `192.168.42.250`。要找到为特定的客户端分配的 IP，可以查看该 VPN 客户端上的连接状态。

在使用 [IPsec/XAuth ("Cisco IPsec")](clients-xauth-zh.md) 或 [IKEv2](ikev2-howto-zh.md) 模式连接时，VPN 服务器在虚拟网络 `192.168.43.0/24` 内 **没有** 内网 IP。为客户端分配的内网 IP 在这个范围内：`192.168.43.10` 到 `192.168.43.250`。

你可以使用这些 VPN 内网 IP 进行通信。但是请注意，为 VPN 客户端分配的 IP 是动态的，而且客户端设备上的防火墙可能会阻止这些流量。

高级用户可以将静态 IP 分配给 VPN 客户端。这是可选的。展开以查看详细信息。

<details>
<summary>
IPsec/L2TP 模式：为 VPN 客户端分配静态 IP
</summary>

下面的示例 **仅适用于** IPsec/L2TP 模式。这些命令必须用 `root` 账户运行。

1. 首先为要分配静态 IP 的每个 VPN 客户端创建一个新的 VPN 用户。参见 [管理 VPN 用户](manage-users-zh.md)。该文档包含辅助脚本，以方便管理 VPN 用户。
1. 编辑 VPN 服务器上的 `/etc/xl2tpd/xl2tpd.conf`。将 `ip range = 192.168.42.10-192.168.42.250` 替换为比如 `ip range = 192.168.42.100-192.168.42.250`。这样可以缩小自动分配的 IP 地址池，从而使更多的 IP 可以作为静态 IP 分配给客户端。
1. 编辑 VPN 服务器上的 `/etc/ppp/chap-secrets`。例如，如果文件内容是：
   ```
   "username1"  l2tpd  "password1"  *
   "username2"  l2tpd  "password2"  *
   "username3"  l2tpd  "password3"  *
   ```

   假设你要为 VPN 用户 `username2` 分配静态 IP `192.168.42.2`，为 VPN 用户 `username3` 分配静态 IP `192.168.42.3`，同时保持 `username1` 不变（从池中自动分配）。在编辑完成后，文件内容应该如下所示：
   ```
   "username1"  l2tpd  "password1"  *
   "username2"  l2tpd  "password2"  192.168.42.2
   "username3"  l2tpd  "password3"  192.168.42.3
   ```

   **注：** 分配的静态 IP 必须来自子网 `192.168.42.0/24`，并且必须 **不是** 来自自动分配的 IP 地址池（参见上面的 `ip range`）。另外，`192.168.42.1` 保留给 VPN 服务器本身使用。在上面的示例中，你只能分配 `192.168.42.2-192.168.42.99` 范围内的静态 IP。
1. **（重要）** 重启 xl2tpd 服务：
   ```
   service xl2tpd restart
   ```
</details>

<details>
<summary>
IPsec/XAuth ("Cisco IPsec") 模式：为 VPN 客户端分配静态 IP
</summary>

下面的示例 **仅适用于** IPsec/XAuth ("Cisco IPsec") 模式。这些命令必须用 `root` 账户运行。

1. 首先为要分配静态 IP 的每个 VPN 客户端创建一个新的 VPN 用户。参见 [管理 VPN 用户](manage-users-zh.md)。该文档包含辅助脚本，以方便管理 VPN 用户。
1. 编辑 VPN 服务器上的 `/etc/ipsec.conf`。将 `rightaddresspool=192.168.43.10-192.168.43.250` 替换为比如 `rightaddresspool=192.168.43.100-192.168.43.250`。这样可以缩小自动分配的 IP 地址池，从而使更多的 IP 可以作为静态 IP 分配给客户端。
1. 编辑 VPN 服务器上的 `/etc/ipsec.d/ikev2.conf`（如果存在）。将 `rightaddresspool=192.168.43.10-192.168.43.250` 替换为与上一步 **相同的值**。
1. 编辑 VPN 服务器上的 `/etc/ipsec.d/passwd`。例如，如果文件内容是：
   ```
   username1:password1hashed:xauth-psk
   username2:password2hashed:xauth-psk
   username3:password3hashed:xauth-psk
   ```

   假设你要为 VPN 用户 `username2` 分配静态 IP `192.168.43.2`，为 VPN 用户 `username3` 分配静态 IP `192.168.43.3`，同时保持 `username1` 不变（从池中自动分配）。在编辑完成后，文件内容应该如下所示：
   ```
   username1:password1hashed:xauth-psk
   username2:password2hashed:xauth-psk:192.168.42.2
   username3:password3hashed:xauth-psk:192.168.42.3
   ```

   **注：** 分配的静态 IP 必须来自子网 `192.168.43.0/24`，并且必须 **不是** 来自自动分配的 IP 地址池（参见上面的 `rightaddresspool`）。在上面的示例中，你只能分配 `192.168.43.1-192.168.43.99` 范围内的静态 IP。
1. **（重要）** 重启 IPsec 服务：
   ```
   service ipsec restart
   ```
</details>

<details>
<summary>
IKEv2 模式：为 VPN 客户端分配静态 IP
</summary>

下面的示例 **仅适用于** IKEv2 模式。这些命令必须用 `root` 账户运行。

1. 首先为要分配静态 IP 的每个客户端创建一个新的 IKEv2 客户端证书，并且在纸上记下每个客户端的名称。参见 [添加客户端证书](ikev2-howto-zh.md#添加客户端证书)。
1. 编辑 VPN 服务器上的 `/etc/ipsec.d/ikev2.conf`。将 `rightaddresspool=192.168.43.10-192.168.43.250` 替换为比如 `rightaddresspool=192.168.43.100-192.168.43.250`。这样可以缩小自动分配的 IP 地址池，从而使更多的 IP 可以作为静态 IP 分配给客户端。
1. 编辑 VPN 服务器上的 `/etc/ipsec.conf`。将 `rightaddresspool=192.168.43.10-192.168.43.250` 替换为与上一步 **相同的值**。
1. 再次编辑 VPN 服务器上的 `/etc/ipsec.d/ikev2.conf`。例如，如果文件内容是：
   ```
   conn ikev2-cp
     left=%defaultroute
     ... ...
   ```

   假设你要为 IKEv2 客户端 `client1` 分配静态 IP `192.168.43.4`，为客户端 `client2` 分配静态 IP `192.168.43.5`，同时保持其它客户端不变（从池中自动分配）。在编辑完成后，文件内容应该如下所示：
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

   **注：** 为要分配静态 IP 的每个客户端添加一个新的 `conn` 小节。`rightid=` 右边的客户端名称必须添加 `@` 前缀。该客户端名称必须与你在[添加客户端证书](ikev2-howto-zh.md#添加客户端证书)时指定的名称完全一致。分配的静态 IP 必须来自子网 `192.168.43.0/24`，并且必须 **不是** 来自自动分配的 IP 地址池（参见上面的 `rightaddresspool`）。在上面的示例中，你只能分配 `192.168.43.1-192.168.43.99` 范围内的静态 IP。
1. **（重要）** 重启 IPsec 服务：
   ```
   service ipsec restart
   ```
</details>

在默认配置下，允许客户端之间的流量。如果你想要 **不允许** 客户端之间的流量，可以在 VPN 服务器上运行以下命令。将它们添加到 `/etc/rc.local` 以便在重启后继续有效。

```
iptables -I FORWARD 2 -i ppp+ -o ppp+ -s 192.168.42.0/24 -d 192.168.42.0/24 -j DROP
iptables -I FORWARD 3 -s 192.168.43.0/24 -d 192.168.43.0/24 -j DROP
iptables -I FORWARD 4 -i ppp+ -d 192.168.43.0/24 -j DROP
iptables -I FORWARD 5 -s 192.168.43.0/24 -o ppp+ -j DROP
```

## 转发端口到 VPN 客户端

在某些情况下，你可能想要将 VPN 服务器上的端口转发到一个已连接的 VPN 客户端。这可以通过在 VPN 服务器上添加 IPTables 规则来实现。

**警告：** 端口转发会将 VPN 客户端上的端口暴露给整个因特网，这可能会带来**安全风险**！**不建议**这样做，除非你的用例需要它。

**注：** 为 VPN 客户端分配的内网 IP 是动态的，而且客户端设备上的防火墙可能会阻止转发的流量。如果要将静态 IP 分配给 VPN 客户端，请参见上一节。要找到为特定的客户端分配的 IP，可以查看该 VPN 客户端上的连接状态。

示例 1：将 VPN 服务器上的 TCP 端口 443 转发到位于 `192.168.42.10` 的 IPsec/L2TP 客户端。
```
# 获取默认网络接口名称
netif=$(route 2>/dev/null | grep -m 1 '^default' | grep -o '[^ ]*$')
iptables -I FORWARD 2 -i "$netif" -o ppp+ -p tcp --dport 443 -j ACCEPT
iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to 192.168.42.10
```

示例 2：将 VPN 服务器上的 UDP 端口 123 转发到位于 `192.168.43.10` 的 IKEv2（或 IPsec/XAuth）客户端。
```
# 获取默认网络接口名称
netif=$(route 2>/dev/null | grep -m 1 '^default' | grep -o '[^ ]*$')
iptables -I FORWARD 2 -i "$netif" -d 192.168.43.0/24 -p udp --dport 123 -j ACCEPT
iptables -t nat -A PREROUTING -p udp --dport 123 -j DNAT --to 192.168.43.10
```

如果你想要这些规则在重启后仍然有效，可以将这些命令添加到 `/etc/rc.local`。要删除添加的 IPTables 规则，请再次运行这些命令，但是将 `-I FORWARD 2` 替换为 `-D FORWARD`，并且将 `-A PREROUTING` 替换为 `-D PREROUTING`。

## VPN 分流

在启用 [VPN 分流 (split tunneling)](https://wiki.strongswan.org/projects/strongswan/wiki/ForwardingAndSplitTunneling#Split-Tunneling) 时，VPN 客户端将仅通过 VPN 隧道发送特定目标子网的流量。其他流量 **不会** 通过 VPN 隧道。VPN 分流 [有一些局限性](https://wiki.strongswan.org/projects/strongswan/wiki/ForwardingAndSplitTunneling#Split-Tunneling)，而且并非所有的 VPN 客户端都支持。

高级用户可以为 [IPsec/XAuth ("Cisco IPsec")](clients-xauth-zh.md) 和/或 [IKEv2](ikev2-howto-zh.md) 模式启用 VPN 分流。这是可选的。IPsec/L2TP 模式 **不支持** 此功能。

<details>
<summary>
IPsec/XAuth ("Cisco IPsec") 模式：启用 VPN 分流 (split tunneling)
</summary>

下面的示例 **仅适用于** IPsec/XAuth ("Cisco IPsec") 模式。这些命令必须用 `root` 账户运行。

1. 编辑 VPN 服务器上的 `/etc/ipsec.conf`。在 `conn xauth-psk` 小节中，将 `leftsubnet=0.0.0.0/0` 替换为你想要 VPN 客户端通过 VPN 隧道发送流量的子网。例如：   
   对于单个子网：
   ```
   leftsubnet=10.123.123.0/24
   ```
   对于多个子网（使用 `leftsubnets`）：
   ```
   leftsubnets="10.123.123.0/24,10.100.0.0/16"
   ```
1. **（重要）** 重启 IPsec 服务：
   ```
   service ipsec restart
   ```
</details>

<details>
<summary>
IKEv2 模式：启用 VPN 分流 (split tunneling)
</summary>

下面的示例 **仅适用于** IKEv2 模式。这些命令必须用 `root` 账户运行。

1. 编辑 VPN 服务器上的 `/etc/ipsec.d/ikev2.conf`。在 `conn ikev2-cp` 小节中，将 `leftsubnet=0.0.0.0/0` 替换为你想要 VPN 客户端通过 VPN 隧道发送流量的子网。例如：   
   对于单个子网：
   ```
   leftsubnet=10.123.123.0/24
   ```
   对于多个子网（使用 `leftsubnets`）：
   ```
   leftsubnets="10.123.123.0/24,10.100.0.0/16"
   ```
1. **（重要）** 重启 IPsec 服务：
   ```
   service ipsec restart
   ```
</details>

## 访问 VPN 服务器的网段

连接到 VPN 后，VPN 客户端通常可以访问与 VPN 服务器位于同一本地子网内的其他设备上运行的服务，而无需进行其他配置。例如，如果 VPN 服务器的本地子网为 `192.168.0.0/24`，并且一个 Nginx 服务器在 IP `192.168.0.2` 上运行，则 VPN 客户端可以使用 IP `192.168.0.2`来访问 Nginx 服务器。

请注意，如果 VPN 服务器具有多个网络接口（例如 `eth0` 和 `eth1`），并且你想要 VPN 客户端访问服务器上 **不用于** Internet 访问的网络接口后面的本地子网，则需要进行额外的配置。在此情形下，你必须运行以下命令来添加 IPTables 规则。为了在重启后仍然有效，你可以将这些命令添加到 `/etc/rc.local`。

```bash
# 将 eth1 替换为 VPN 服务器上你想要客户端访问的网络接口名称
netif=eth1
iptables -I FORWARD 2 -i "$netif" -o ppp+ -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -I FORWARD 2 -i ppp+ -o "$netif" -j ACCEPT
iptables -I FORWARD 2 -i "$netif" -d 192.168.43.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -I FORWARD 2 -s 192.168.43.0/24 -o "$netif" -j ACCEPT
iptables -t nat -I POSTROUTING -s 192.168.43.0/24 -o "$netif" -m policy --dir out --pol none -j MASQUERADE
iptables -t nat -I POSTROUTING -s 192.168.42.0/24 -o "$netif" -j MASQUERADE
```

## 仅限 IKEv2 的 VPN

Libreswan 4.2 和更新版本支持 `ikev1-policy` 配置选项。使用此选项，高级用户可以设置仅限 IKEv2 的 VPN，即 VPN 服务器仅接受 IKEv2 连接，而 IKEv1 连接（包括 IPsec/L2TP 和 IPsec/XAuth ("Cisco IPsec") 模式）将被丢弃。

要设置仅限 IKEv2 的 VPN，首先按照 [自述文件](../README-zh.md) 中的说明安装 VPN 服务器并且配置 IKEv2。然后使用 `ipsec --version` 命令检查 Libreswan 版本并 [更新 Libreswan](../README-zh.md#升级libreswan)（如果需要）。下一步，编辑 VPN 服务器上的 `/etc/ipsec.conf`。在 `config setup` 小节的末尾添加 `ikev1-policy=drop`，开头必须空两格。保存文件并运行 `service ipsec restart`。在完成后，你可以使用 `ipsec status` 命令来验证仅启用了 `ikev2-cp` 连接。

## 更改 IPTables 规则

如果你想要在安装后更改 IPTables 规则，请编辑 `/etc/iptables.rules` 和/或 `/etc/iptables/rules.v4` (Ubuntu/Debian)，或者 `/etc/sysconfig/iptables` (CentOS/RHEL)。然后重启服务器。

**注：** 如果使用 Rocky Linux, AlmaLinux 或者 CentOS/RHEL 8 并且在安装 VPN 时 firewalld 正在运行，则可能已配置 nftables。在这种情况下，编辑 `/etc/sysconfig/nftables.conf` 而不是 `/etc/sysconfig/iptables`。

## 授权协议

版权所有 (C) 2021 [Lin Song](https://github.com/hwdsl2) [![View my profile on LinkedIn](https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png)](https://www.linkedin.com/in/linsongui)   

[![Creative Commons License](https://i.creativecommons.org/l/by-sa/3.0/88x31.png)](http://creativecommons.org/licenses/by-sa/3.0/)   
这个项目是以 [知识共享署名-相同方式共享3.0](http://creativecommons.org/licenses/by-sa/3.0/) 许可协议授权。   
必须署名： 请包括我的名字在任何衍生产品，并且让我知道你是如何改善它的！
