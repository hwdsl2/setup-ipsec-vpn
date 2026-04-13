[English](advanced-usage.md) | [中文](advanced-usage-zh.md)

# 高级用法

* [使用其他的 DNS 服务器](#使用其他的-dns-服务器)
* [域名和更改服务器 IP](#域名和更改服务器-ip)
* [仅限 IKEv2 的 VPN](#仅限-ikev2-的-vpn)
* [启用 IKEv2 前向保密](#启用-ikev2-前向保密)
* [VPN 内网 IP 和流量](#vpn-内网-ip-和流量)
* [指定 VPN 服务器的公有 IP](#指定-vpn-服务器的公有-ip)
* [自定义 VPN 子网](#自定义-vpn-子网)
* [IPv6 支持](#ipv6-支持)
* [转发端口到 VPN 客户端](#转发端口到-vpn-客户端)
* [VPN 分流](#vpn-分流)
* [访问 VPN 服务器的网段](#访问-vpn-服务器的网段)
* [VPN 服务器网段访问 VPN 客户端](#vpn-服务器网段访问-vpn-客户端)
* [更改 IPTables 规则](#更改-iptables-规则)
* [部署 Google BBR 拥塞控制](#部署-google-bbr-拥塞控制)

## 使用其他的 DNS 服务器

在 VPN 已连接时，客户端默认配置为使用 [Google Public DNS](https://developers.google.com/speed/public-dns/)。如果偏好其它的域名解析服务，你可以编辑以下文件：`/etc/ppp/options.xl2tpd`, `/etc/ipsec.conf` 和 `/etc/ipsec.d/ikev2.conf`（如果存在），并替换 `8.8.8.8` 和 `8.8.4.4`。然后运行 `service ipsec restart` 和 `service xl2tpd restart`。

以下是一些流行的公共 DNS 提供商的列表，供你参考。

| 提供商 | 主 DNS | 辅助 DNS | 注释 |
| ----- | ------ | ------- | ---- |
| [Google Public DNS](https://developers.google.com/speed/public-dns) | 8.8.8.8 | 8.8.4.4 | 本项目默认 |
| [Cloudflare](https://1.1.1.1/dns/) | 1.1.1.1 | 1.0.0.1 | 另见：[Cloudflare for families](https://1.1.1.1/family/) |
| [Quad9](https://www.quad9.net) | 9.9.9.9 | 149.112.112.112 | 阻止恶意域 |
| [OpenDNS](https://www.opendns.com/home-internet-security/) | 208.67.222.222 | 208.67.220.220 | 阻止网络钓鱼域，可配置。 |
| [CleanBrowsing](https://cleanbrowsing.org/filters/) | 185.228.168.9 | 185.228.169.9 | [域过滤器](https://cleanbrowsing.org/filters/)可用 |
| [NextDNS](https://nextdns.io/?from=bg25bwmp) | 按需选择 | 按需选择 | 广告拦截，免费套餐可用。[了解更多](https://nextdns.io/?from=bg25bwmp)。 |
| [Control D](https://controld.com/free-dns) | 按需选择 | 按需选择 | 广告拦截，可配置。[了解更多](https://controld.com/free-dns)。 |

高级用户可以在运行 VPN 安装脚本时定义 `VPN_DNS_SRV1` 和 `VPN_DNS_SRV2`（可选）。有关更多详细信息，请参见[自定义 VPN 选项](../README-zh.md#自定义-vpn-选项)。

你可以为特定的 IKEv2 客户端设置不同的 DNS 服务器。对于此用例，请参见 [#1562](https://github.com/hwdsl2/setup-ipsec-vpn/issues/1562#issuecomment-2151361658)。

如果你的用例需要使用 IPTables 规则将 DNS 流量重定向到另一台服务器，请参见 [#1565](https://github.com/hwdsl2/setup-ipsec-vpn/issues/1565)。

在某些情况下，你可能希望 VPN 客户端仅使用指定的 DNS 服务器来解析内部域名，并使用其本地配置的 DNS 服务器来解析所有其他域名。这可以使用 `modecfgdomains` 选项进行配置，例如 `modecfgdomains="internal.example.com, home"`。对于 IKEv2，将此选项添加到 `/etc/ipsec.d/ikev2.conf` 中的 `conn ikev2-cp` 小节。对于 IPsec/XAuth ("Cisco IPsec")，将此选项添加到 `/etc/ipsec.conf` 中的 `conn xauth-psk` 小节。然后运行 `service ipsec restart`。IPsec/L2TP 模式不支持此选项。

## 域名和更改服务器 IP

对于 [IPsec/L2TP](clients-zh.md) 和 [IPsec/XAuth ("Cisco IPsec")](clients-xauth-zh.md) 模式，你可以在不需要额外配置的情况下使用一个域名（比如 `vpn.example.com`）而不是 IP 地址连接到 VPN 服务器。另外，一般来说，在服务器的 IP 更改后，比如在恢复一个映像到具有不同 IP 的新服务器后，VPN 会继续正常工作，虽然可能需要重启服务器。

对于 [IKEv2](ikev2-howto-zh.md) 模式，如果你想要 VPN 在服务器的 IP 更改后继续正常工作，参见[这一小节](ikev2-howto-zh.md#更改-ikev2-服务器地址)。或者，你也可以在[配置 IKEv2](ikev2-howto-zh.md#使用辅助脚本配置-ikev2) 时指定一个域名作为 IKEv2 服务器地址。该域名必须是一个全称域名(FQDN)。示例如下：

```
sudo VPN_DNS_NAME='vpn.example.com' ikev2.sh --auto
```

另外，你也可以自定义 IKEv2 选项，通过在运行[辅助脚本](ikev2-howto-zh.md#使用辅助脚本配置-ikev2)时去掉 `--auto` 参数来实现。

## 仅限 IKEv2 的 VPN

使用 Libreswan 4.2 或更新版本，高级用户可以为 VPN 服务器启用仅限 IKEv2 模式。当启用该模式时，VPN 客户端仅能使用 IKEv2 连接到 VPN 服务器。所有的 IKEv1 连接（包括 IPsec/L2TP 和 IPsec/XAuth ("Cisco IPsec") 模式）将被丢弃。

要启用仅限 IKEv2 模式，首先按照[自述文件](../README-zh.md)中的说明安装 VPN 服务器并且配置 IKEv2。然后运行[辅助脚本](../extras/ikev2onlymode.sh)并按提示操作。

```bash
wget https://get.vpnsetup.net/ikev2only -O ikev2only.sh
sudo bash ikev2only.sh
```

要禁用仅限 IKEv2 模式，再次运行辅助脚本并选择适当的选项。

<details>
<summary>
另外，你也可以手动启用仅限 IKEv2 模式。
</summary>

另外，你也可以手动启用仅限 IKEv2 模式。首先使用 `ipsec --version` 命令检查 Libreswan 版本，并[更新 Libreswan](../README-zh.md#升级libreswan)（如果需要）。然后编辑 VPN 服务器上的 `/etc/ipsec.conf`。将 `ikev1-policy=accept` 替换为 `ikev1-policy=drop`。如果该行不存在，则在 `config setup` 小节的末尾添加 `ikev1-policy=drop`，开头必须空两格。保存文件并运行 `service ipsec restart`。在完成后，你可以使用 `ipsec status` 命令来验证仅启用了 `ikev2-cp` 连接。
</details>

## 启用 IKEv2 前向保密

默认情况下，IKEv2 子安全关联（Child SA）从现有 IKE SA 派生密钥材料，不进行新的 Diffie-Hellman 交换（`pfs=no`）。启用前向保密（PFS）后，每次子 SA 重新生成密钥时都会执行新的 DH 交换，从而确保即使服务器私钥在将来遭到泄露，攻击者也无法解密之前录制的会话。

**注：** IKE SA 已将 ECP-256（`aes_gcm_c_256-hmac_sha2_256-ecp_256`）作为首选提案，所有现代客户端均会协商使用，因此这些客户端的会话密钥已与长期密钥材料独立。为子 SA 启用 PFS 是一项渐进式安全加固措施，而非关键漏洞修复。

**客户端兼容性：** 所有现代客户端均支持 PFS。但是，macOS 和 iOS 客户端需要重新导出并导入已将 `EnablePFS` 设为 `1` 的 `.mobileconfig` 配置文件（详见下文）。Windows 客户端需要更新连接配置。RouterOS 用户需将 IKEv2 配置文件中的 `pfs-group=none` 改为 `pfs-group=ecp256`。Android 和 Linux strongSwan 客户端无需更改。Windows 7 IKEv2 客户端不支持 ECP PFS 组，若服务器启用 PFS，将无法连接。

要在服务器上启用 PFS，请编辑 `/etc/ipsec.d/ikev2.conf`，将 `conn ikev2-cp` 部分中的 `pfs=no` 改为 `pfs=yes`，然后重启 IPsec 服务：

```bash
sudo sed -i 's/pfs=no/pfs=yes/' /etc/ipsec.d/ikev2.conf
sudo service ipsec restart
```

**Docker 用户：** 请先[在容器内打开 Bash shell](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/docs/advanced-usage-zh.md#在容器中运行-bash-shell)，运行上述 `sed` 命令，然后 `exit` 并运行 `docker restart ipsec-vpn-server`。

启用 PFS 后，需要更新以下客户端配置：

- **macOS / iOS：** 使用 `sudo ikev2.sh --exportclient <名称>` 重新导出客户端 `.mobileconfig` 文件，然后编辑导出的文件以启用 PFS：
  ```bash
  sed -i '/EnablePFS/{n;s/0/1/;}' <名称>.mobileconfig
  ```
  在设备上重新导入更新后的文件。
- **Windows：** 在提升权限的 PowerShell 窗口中运行 `Set-VpnConnection -Name "你的VPN名称" -PfsGroup ECP256`（替换为实际的 VPN 连接名称），然后重新连接 VPN。
- **RouterOS (MikroTik)：** 在 IKEv2 对等配置文件中，将 `pfs-group=none` 改为 `pfs-group=ecp256`。

Android 和 Linux strongSwan 客户端无需更改，PFS 会自动协商。

要恢复默认设置（禁用 PFS）：

```bash
sudo sed -i 's/pfs=yes/pfs=no/' /etc/ipsec.d/ikev2.conf
sudo service ipsec restart
```

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

1. 首先为要分配静态 IP 的每个 VPN 客户端创建一个新的 VPN 用户。参见[管理 VPN 用户](manage-users-zh.md)。该文档包含辅助脚本，以方便管理 VPN 用户。
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

1. 首先为要分配静态 IP 的每个 VPN 客户端创建一个新的 VPN 用户。参见[管理 VPN 用户](manage-users-zh.md)。该文档包含辅助脚本，以方便管理 VPN 用户。
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

1. 首先为要分配静态 IP 的每个客户端创建一个新的 IKEv2 客户端证书，并且在纸上记下每个客户端的名称。参见[添加客户端证书](ikev2-howto-zh.md#添加客户端证书)。
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

   conn ikev2-shared
     # 复制/粘贴 ikev2-cp 小节中 *除了下面三项之外* 的所有内容
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

   **注：** 为要分配静态 IP 的每个客户端添加一个新的 `conn` 小节。`rightid=` 右边的客户端名称必须添加 `@` 前缀。该客户端名称必须与你在[添加客户端证书](ikev2-howto-zh.md#添加客户端证书)时指定的名称完全一致。分配的静态 IP 必须来自子网 `192.168.43.0/24`，并且必须 **不是** 来自自动分配的 IP 地址池（参见上面的 `rightaddresspool`）。在上面的示例中，你只能分配 `192.168.43.1-192.168.43.99` 范围内的静态 IP。

   **注：** 对于 Windows 7/8/10/11 和 [RouterOS](ikev2-howto-zh.md#routeros) 客户端，你必须对 `rightid=` 使用不同的语法。例如，如果客户端名称为 `client1`，则在上面的示例中设置 `rightid="CN=client1, O=IKEv2 VPN"`。
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

## 指定 VPN 服务器的公有 IP

在具有多个公有 IP 地址的服务器上，高级用户可以使用变量 `VPN_PUBLIC_IP` 为 VPN 服务器指定一个公有 IP。例如，如果服务器的 IP 为 `192.0.2.1` 和 `192.0.2.2`，并且你想要 VPN 服务器使用 `192.0.2.2`：

```
sudo VPN_PUBLIC_IP=192.0.2.2 sh vpn.sh
```

请注意，如果在服务器上已经配置了 IKEv2，则此变量对 IKEv2 模式无效。在这种情况下，你可以移除 IKEv2 并使用自定义选项重新配置它。参见[使用辅助脚本配置 IKEv2](ikev2-howto-zh.md#使用辅助脚本配置-ikev2)。

如果你想要 VPN 客户端在 VPN 连接处于活动状态时使用指定的公有 IP 作为其 "出站 IP"，并且指定的 IP **不是** 服务器上的主 IP（或默认路由），则可能需要额外的配置。在这种情况下，你可能需要更改服务器上的 IPTables 规则。如果要在重启后继续有效，你可以将这些命令添加到 `/etc/rc.local`。

继续上面的例子，如果你希望 "出站 IP" 为 `192.0.2.2`：

```
# 获取默认网络接口名称
netif=$(ip -4 route list 0/0 | grep -m 1 -Po '(?<=dev )(\S+)')
# 移除 MASQUERADE 规则
iptables -t nat -D POSTROUTING -s 192.168.43.0/24 -o "$netif" -m policy --dir out --pol none -j MASQUERADE
iptables -t nat -D POSTROUTING -s 192.168.42.0/24 -o "$netif" -j MASQUERADE
# 添加 SNAT 规则
iptables -t nat -I POSTROUTING -s 192.168.43.0/24 -o "$netif" -m policy --dir out --pol none -j SNAT --to 192.0.2.2
iptables -t nat -I POSTROUTING -s 192.168.42.0/24 -o "$netif" -j SNAT --to 192.0.2.2
```

**注：** 以上方法仅适用于服务器的默认网络接口对应多个公有 IP 的情况。如果服务器有多个网络接口，对应不同的公有 IP，则此方法无效。

要检查一个已连接的 VPN 客户端的 "出站 IP"，你可以在该客户端上打开浏览器并到[这里](https://www.ipchicken.com)检测 IP 地址。

## 自定义 VPN 子网

默认情况下，IPsec/L2TP VPN 客户端将使用内部 VPN 子网 `192.168.42.0/24`，而 IPsec/XAuth ("Cisco IPsec") 和 IKEv2 VPN 客户端将使用内部 VPN 子网 `192.168.43.0/24`。有关更多详细信息，请参见 [VPN 内网 IP 和流量](#vpn-内网-ip-和流量)。

对于大多数用例，没有必要也 **不建议** 自定义这些子网。但是，如果你的用例需要它，你可以在安装 VPN 时指定自定义子网。

**重要：** 你只能在 **初始 VPN 安装时** 指定自定义子网。如果 IPsec VPN 已安装，你 **必须** 首先[卸载 VPN](uninstall-zh.md)，然后指定自定义子网并重新安装。否则，VPN 可能会停止工作。

```
# 示例：为 IPsec/L2TP 模式指定自定义 VPN 子网
# 注：必须指定所有三个变量。
sudo VPN_L2TP_NET=10.1.0.0/16 \
VPN_L2TP_LOCAL=10.1.0.1 \
VPN_L2TP_POOL=10.1.0.10-10.1.254.254 \
sh vpn.sh
```

```
# 示例：为 IPsec/XAuth 和 IKEv2 模式指定自定义 VPN 子网
# 注：必须指定以下两个变量。
sudo VPN_XAUTH_NET=10.2.0.0/16 \
VPN_XAUTH_POOL=10.2.0.10-10.2.254.254 \
sh vpn.sh
```

在上面的例子中，`VPN_L2TP_LOCAL` 是在 IPsec/L2TP 模式下的 VPN 服务器的内网 IP。`VPN_L2TP_POOL` 和 `VPN_XAUTH_POOL` 是为 VPN 客户端自动分配的 IP 地址池。

## IPv6 支持

如果你的 VPN 服务器拥有公共（全局单播）IPv6 地址并且满足以下要求，IKEv2 客户端的 IPv6 支持将在 VPN 安装时自动启用，无需手动配置。

**注：** 在 Android 上使用 strongSwan VPN 客户端时，IPv6 无需额外配置即可正常工作。对于 Windows 和 macOS 客户端，请按照以下平台特定步骤进行配置。iOS 客户端目前不支持通过 IKEv2 VPN 路由 IPv6 流量；你可以改用 [OpenVPN](https://github.com/hwdsl2/openvpn-install/blob/master/README-zh.md) 或 [WireGuard](https://github.com/hwdsl2/wireguard-install/blob/master/README-zh.md)。

<details>
<summary>
Windows：通过 VPN 路由 IPv6 流量
</summary>

如果你使用了 `ikev2_config_import.cmd` 脚本导入 IKEv2 配置，可以在提示时输入 **y** 以自动添加 IPv6 路由。否则，你需要在 PowerShell 窗口中运行以下命令一次，以通过 VPN 路由 IPv6 流量。将 `IKEv2 VPN X.X.X.X` 替换为你的 VPN 连接的实际名称。完成后，重新连接到 IKEv2 VPN。

```powershell
Add-VpnConnectionRoute -ConnectionName "IKEv2 VPN X.X.X.X" -DestinationPrefix ::/1
Add-VpnConnectionRoute -ConnectionName "IKEv2 VPN X.X.X.X" -DestinationPrefix 8000::/1
```
</details>
<details>
<summary>
macOS：通过 VPN 路由 IPv6 流量
</summary>

连接到 IKEv2 VPN 后，需要在终端中运行以下命令以通过 VPN 路由 IPv6 流量。每次连接后都需要运行此命令。断开 VPN 时，该路由将自动删除。接口通常为 `ipsec0`；如果同时有多个 VPN 连接处于活动状态，可能为 `ipsec1` 等，运行 `ifconfig | grep ipsec` 确认。

```
sudo route -n add -inet6 default -interface ipsec0
```
</details>

启用 IPv6 后，IKEv2 VPN 客户端将同时获得来自 `192.168.43.0/24` 地址池的 IPv4 地址和来自 `fddd:500:500:500::/64` 地址池的 IPv6 地址。VPN 服务器通过将客户端地址池的 IPv6 流量伪装（NAT）为服务器自身的 IPv6 地址，从而使 VPN 客户端能够通过该隧道获得完整的 IPv6 互联网访问。

**要求：**
- VPN 服务器必须拥有可路由的全局单播 IPv6 地址（即以 `2` 或 `3` 开头的地址）。链路本地地址 (`fe80::/10`) 和 ULA 地址 (`fc00::/7`) 不满足要求。
- Libreswan 5.0 或更新版本（VPN 安装脚本默认使用 5.x）。
- IPv6 仅支持 **IKEv2 模式**。IPsec/L2TP 和 IPsec/XAuth ("Cisco IPsec") 模式不支持 IPv6。

要验证 IPv6 是否正常工作，请使用 IKEv2 连接到 VPN，然后检查你的 IPv6 地址，例如使用 [test-ipv6.com](https://test-ipv6.com)。

你可以在安装 VPN 时选择指定自定义 IPv6 地址池子网，这是可选的。该子网必须是 `/64` ULA 范围内的子网（推荐使用 `fddd::/16`）。

```
# 示例：为 IKEv2 模式指定自定义 IPv6 地址池子网
sudo VPN_IP6_NET=fddd:1234:5678:9012::/64 \
sh vpn.sh
```

**注：** `VPN_IP6_NET` 变量只能在初始 VPN 安装时指定。

## 转发端口到 VPN 客户端

在某些情况下，你可能想要将 VPN 服务器上的端口转发到一个已连接的 VPN 客户端。这可以通过在 VPN 服务器上添加 IPTables 规则来实现。

**警告：** 端口转发会将 VPN 客户端上的端口暴露给整个因特网，这可能会带来**安全风险**！**不建议**这样做，除非你的用例需要它。

**注：** 为 VPN 客户端分配的内网 IP 是动态的，而且客户端设备上的防火墙可能会阻止转发的流量。如果要将静态 IP 分配给 VPN 客户端，请参见 [VPN 内网 IP 和流量](#vpn-内网-ip-和流量)。要找到为特定的客户端分配的 IP，可以查看该 VPN 客户端上的连接状态。

示例 1：将 VPN 服务器上的 TCP 端口 443 转发到位于 `192.168.42.10` 的 IPsec/L2TP 客户端。
```
# 获取默认网络接口名称
netif=$(ip -4 route list 0/0 | grep -m 1 -Po '(?<=dev )(\S+)')
iptables -I FORWARD 2 -i "$netif" -o ppp+ -p tcp --dport 443 -j ACCEPT
iptables -t nat -A PREROUTING -i "$netif" -p tcp --dport 443 -j DNAT --to 192.168.42.10
```

示例 2：将 VPN 服务器上的 UDP 端口 123 转发到位于 `192.168.43.10` 的 IKEv2（或 IPsec/XAuth）客户端。
```
# 获取默认网络接口名称
netif=$(ip -4 route list 0/0 | grep -m 1 -Po '(?<=dev )(\S+)')
iptables -I FORWARD 2 -i "$netif" -d 192.168.43.0/24 -p udp --dport 123 -j ACCEPT
iptables -t nat -A PREROUTING -i "$netif" ! -s 192.168.43.0/24 -p udp --dport 123 -j DNAT --to 192.168.43.10
```

如果你想要这些规则在重启后仍然有效，可以将这些命令添加到 `/etc/rc.local`。要删除添加的 IPTables 规则，请再次运行这些命令，但是将 `-I FORWARD 2` 替换为 `-D FORWARD`，并且将 `-A PREROUTING` 替换为 `-D PREROUTING`。

## VPN 分流

在启用 VPN 分流 (split tunneling) 时，VPN 客户端将仅通过 VPN 隧道发送特定目标子网的流量。其他流量 **不会** 通过 VPN 隧道。这允许你通过 VPN 安全访问指定的网络，而无需通过 VPN 发送所有客户端的流量。VPN 分流有一些局限性，而且并非所有的 VPN 客户端都支持。

高级用户可以为 [IPsec/XAuth ("Cisco IPsec")](clients-xauth-zh.md) 和/或 [IKEv2](ikev2-howto-zh.md) 模式启用 VPN 分流。这是可选的。展开查看详情。IPsec/L2TP 模式不支持此功能（Windows 除外，见下文）。

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

**注：** 高级用户可以为特定的 IKEv2 客户端设置不同的 VPN 分流配置。请参见 [VPN 内网 IP 和流量](#vpn-内网-ip-和流量)部分并展开 "IKEv2 模式：为 VPN 客户端分配静态 IP"。在该部分中的示例的基础上，你可以将 `leftsubnet=...` 选项添加到特定 IKEv2 客户端的 `conn` 小节，然后重启 IPsec 服务。
</details>

另外，Windows 用户也可以通过手动添加路由的方式启用 VPN 分流：

1. 右键单击系统托盘中的无线/网络图标。
1. **Windows 11:** 选择 **网络和 Internet 设置**，然后在打开的页面中单击 **高级网络设置**。单击 **更多网络适配器选项**。   
   **Windows 10:** 选择 **打开"网络和 Internet"设置**，然后在打开的页面中单击 **网络和共享中心**。单击左侧的 **更改适配器设置**。   
   **Windows 8/7:** 选择 **打开网络和共享中心**。单击左侧的 **更改适配器设置**。
1. 右键单击新的 VPN 连接，并选择 **属性**。
1. 单击 **网络** 选项卡，选择 **Internet Protocol Version 4 (TCP/IPv4)**，然后单击 **属性**。
1. 单击 **高级**，然后取消选中 **在远程网络上使用默认网关**。
1. 单击 **确定** 以关闭 **属性** 对话框。
1. **（重要）** 断开 VPN 连接，然后重新连接。
1. 假设你想要 VPN 客户端通过 VPN 隧道发送流量的子网是 `10.123.123.0/24`。打开[提升权限命令提示符](http://www.cnblogs.com/xxcanghai/p/4610054.html)并运行以下命令之一。   
   对于 IKEv2 和 IPsec/XAuth ("Cisco IPsec") 模式：
   ```
   route add -p 10.123.123.0 mask 255.255.255.0 192.168.43.1
   ```
   对于 IPsec/L2TP 模式：
   ```
   route add -p 10.123.123.0 mask 255.255.255.0 192.168.42.1
   ```
1. 完成后，VPN 客户端将通过 VPN 隧道仅发送指定子网的流量。其他流量将绕过 VPN。

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

## VPN 服务器网段访问 VPN 客户端

在某些情况下，你可能需要从 VPN 服务器位于同一本地子网内的其他设备访问 VPN 客户端上的服务。这可以通过以下几个步骤实现。

假设 VPN 服务器 IP 是 `10.1.0.2`，你想要访问 VPN 客户端的设备的 IP 是 `10.1.0.3`。

1. 在 VPN 服务器上添加 IPTables 规则以允许该流量。例如：
   ```
   # 获取默认网络接口名称
   netif=$(ip -4 route list 0/0 | grep -m 1 -Po '(?<=dev )(\S+)')
   iptables -I FORWARD 2 -i "$netif" -o ppp+ -s 10.1.0.3 -j ACCEPT
   iptables -I FORWARD 2 -i "$netif" -d 192.168.43.0/24 -s 10.1.0.3 -j ACCEPT
   ```
2. 在你想要访问 VPN 客户端的设备上添加路由规则。例如：
   ```
   # 将 eth0 替换为设备的本地子网的网络接口名称
   route add -net 192.168.42.0 netmask 255.255.255.0 gw 10.1.0.2 dev eth0
   route add -net 192.168.43.0 netmask 255.255.255.0 gw 10.1.0.2 dev eth0
   ```

在 [VPN 内网 IP 和流量](#vpn-内网-ip-和流量)小节了解 VPN 内网 IP 的更多信息。

## 更改 IPTables 规则

如果你想要在安装后更改 IPTables 规则，请编辑 `/etc/iptables.rules` 和/或 `/etc/iptables/rules.v4` (Ubuntu/Debian)，或者 `/etc/sysconfig/iptables` (CentOS/RHEL)。然后重启服务器。

如果启用了 [IPv6 支持](#ipv6-支持)，相应的 ip6tables 规则将保存在 `/etc/ip6tables.rules` 和 `/etc/iptables/rules.v6` (Ubuntu/Debian)，或者 `/etc/sysconfig/ip6tables` (CentOS/RHEL)。

**注：** 如果你的服务器运行 CentOS Linux（或类似系统），并且在安装 VPN 时 firewalld 处于活动状态，则可能已配置 nftables。在这种情况下，编辑 `/etc/sysconfig/nftables.conf` 而不是 `/etc/sysconfig/iptables`。

## 部署 Google BBR 拥塞控制

VPN 服务器搭建完成后，可以通过部署 Google BBR 拥塞控制算法提升性能。

这通常只需要在配置文件 `/etc/sysctl.conf` 中插入设定即可完成。但是部分 Linux 发行版可能需要额外更新 Linux 内核。

详细的部署方法，可以参考[这篇文档](bbr-zh.md)。

## 授权协议

版权所有 (C) 2021-2026 [Lin Song](https://github.com/hwdsl2) [![View my profile on LinkedIn](https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png)](https://www.linkedin.com/in/linsongui)   

[![Creative Commons License](https://i.creativecommons.org/l/by-sa/3.0/88x31.png)](http://creativecommons.org/licenses/by-sa/3.0/)   
这个项目是以[知识共享署名-相同方式共享3.0](http://creativecommons.org/licenses/by-sa/3.0/) 许可协议授权。   
必须署名： 请包括我的名字在任何衍生产品，并且让我知道你是如何改善它的！
