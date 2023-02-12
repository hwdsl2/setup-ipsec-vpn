[English](README.md) | [中文](README-zh.md)

# IPsec VPN 服务器一键安装脚本

[![Build Status](https://github.com/hwdsl2/setup-ipsec-vpn/actions/workflows/main.yml/badge.svg)](https://github.com/hwdsl2/setup-ipsec-vpn/actions/workflows/main.yml) [![GitHub Stars](docs/images/badges/github-stars.svg)](https://github.com/hwdsl2/setup-ipsec-vpn/stargazers) [![Docker Stars](docs/images/badges/docker-stars.svg)](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md) [![Docker Pulls](docs/images/badges/docker-pulls.svg)](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md)

使用 Linux 脚本一键快速搭建自己的 IPsec VPN 服务器。支持 IPsec/L2TP, Cisco IPsec 和 IKEv2 协议。

IPsec VPN 可以加密你的网络流量，以防止在通过因特网传送时，你和 VPN 服务器之间的任何人对你的数据的未经授权的访问。在使用不安全的网络时，这是特别有用的，例如在咖啡厅，机场或旅馆房间。

我们将使用 [Libreswan](https://libreswan.org/) 作为 IPsec 服务器，以及 [xl2tpd](https://github.com/xelerance/xl2tpd) 作为 L2TP 提供者。

**[&raquo; :book: 电子书：搭建自己的 IPsec VPN, OpenVPN 和 WireGuard 服务器](https://mybook.to/vpnzhs)**

## 快速开始

首先，在你的 Linux 服务器\* 上安装 Ubuntu, Debian 或者 CentOS。

使用以下命令快速搭建 IPsec VPN 服务器：

```bash
wget https://get.vpnsetup.net -O vpn.sh && sudo sh vpn.sh
```

你的 VPN 登录凭证将会被自动随机生成，并在安装完成后显示。

**可选：** 在同一台服务器上安装 [WireGuard](https://github.com/hwdsl2/wireguard-install/blob/master/README-zh.md) 和/或 [OpenVPN](https://github.com/hwdsl2/openvpn-install/blob/master/README-zh.md)。

<details>
<summary>
查看脚本的示例输出（终端记录）。
</summary>

**注：** 此终端记录仅用于演示目的。该记录中的 VPN 凭据 **无效**。

<p align="center"><img src="docs/images/script-demo.svg"></p>
</details>
<details>
<summary>
如果无法下载，请点这里。
</summary>

你也可以使用 `curl` 下载：

```bash
curl -fsSL https://get.vpnsetup.net -o vpn.sh && sudo sh vpn.sh
```

或者，你也可以使用这些链接：

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/vpnsetup.sh
```

如果无法下载，打开 [vpnsetup.sh](vpnsetup.sh)，然后点击右边的 `Raw` 按钮。按快捷键 `Ctrl/Cmd+A` 全选，`Ctrl/Cmd+C` 复制，然后粘贴到你喜欢的编辑器。
</details>

另外，你也可以使用预构建的 [Docker 镜像](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md)。如需了解其它选项以及客户端配置，请继续阅读以下部分。

\* 一个云服务器，虚拟专用服务器 (VPS) 或者专用服务器。

## 功能特性

- 全自动的 IPsec VPN 服务器配置，无需用户输入
- 支持具有强大和快速加密算法（例如 AES-GCM）的 IKEv2 模式
- 生成 VPN 配置文件以自动配置 iOS, macOS 和 Android 设备
- 支持 Windows, macOS, iOS, Android, Chrome OS 和 Linux 客户端
- 包括辅助脚本以管理 VPN 用户和证书

## 系统要求

一个云服务器，虚拟专用服务器 (VPS) 或者专用服务器，安装以下操作系统之一：

- Ubuntu 22.04, 20.04 或者 18.04
- Debian 11 或者 10
- CentOS 7 或者 CentOS Stream 9/8
- Rocky Linux 或者 AlmaLinux 9/8
- Oracle Linux 9, 8 或者 7
- Amazon Linux 2

<details>
<summary>
其他受支持的 Linux 发行版。
</summary>

- Raspberry Pi OS (Raspbian) 11 或者 10
- Kali Linux
- Alpine Linux 3.17 或者 3.16
- Red Hat Enterprise Linux (RHEL) 9, 8 或者 7
</details>

这也包括公共云服务中的 Linux 虚拟机，例如 [DigitalOcean](https://blog.ls20.com/digitalocean), [Vultr](https://blog.ls20.com/vultr), [Linode](https://blog.ls20.com/linode), [OVH](https://www.ovhcloud.com/en/vps/) 和 [Microsoft Azure](https://azure.microsoft.com)。公共云用户也可以使用[用户数据](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#vpnsetup)部署。

[![Deploy to DigitalOcean](docs/images/do-install-button.png)](http://dovpn.carlfriess.com) &nbsp;[![Deploy to Linode](docs/images/linode-deploy-button.png)](https://cloud.linode.com/stackscripts/37239) &nbsp;[![Deploy to Azure](docs/images/azure-deploy-button.png)](azure/README-zh.md)

[**&raquo; 我想建立并使用自己的 VPN，但是没有可用的服务器**](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#gettingavps)

对于有外部防火墙的服务器（比如 [EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html)/[GCE](https://cloud.google.com/vpc/docs/firewalls)），请为 VPN 打开 UDP 端口 500 和 4500。

另外，你也可以使用预构建的 [Docker 镜像](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md)。高级用户可以在 [Raspberry Pi](https://www.raspberrypi.org) 上安装。[[1]](https://elasticbyte.net/posts/setting-up-a-native-cisco-ipsec-vpn-server-using-a-raspberry-pi/) [[2]](https://www.stewright.me/2018/07/create-a-raspberry-pi-vpn-server-using-l2tpipsec/)

:warning: **不要** 在你的 PC 或者 Mac 上运行这些脚本！它们只能用在服务器上！

## 安装说明

首先，更新你的服务器：运行 `sudo apt-get update && sudo apt-get dist-upgrade` (Ubuntu/Debian) 或者 `sudo yum update` 并重启。这一步是可选的，但推荐。

要安装 VPN，请从以下选项中选择一个：

**选项 1:** 使用脚本随机生成的 VPN 登录凭证（完成后会显示）。

```bash
wget https://get.vpnsetup.net -O vpn.sh && sudo sh vpn.sh
```

**选项 2:** 编辑脚本并提供你自己的 VPN 登录凭证。

```bash
wget https://get.vpnsetup.net -O vpn.sh
nano -w vpn.sh
[替换为你自己的值： YOUR_IPSEC_PSK, YOUR_USERNAME 和 YOUR_PASSWORD]
sudo sh vpn.sh
```

**注：** 一个安全的 IPsec PSK 应该至少包含 20 个随机字符。

**选项 3:** 将你自己的 VPN 登录凭证定义为环境变量。

```bash
# 所有变量值必须用 '单引号' 括起来
# *不要* 在值中使用这些字符：  \ " '
wget https://get.vpnsetup.net -O vpn.sh
sudo VPN_IPSEC_PSK='你的IPsec预共享密钥' \
VPN_USER='你的VPN用户名' \
VPN_PASSWORD='你的VPN密码' \
sh vpn.sh
```

你可以选择在同一台服务器上安装 [WireGuard](https://github.com/hwdsl2/wireguard-install/blob/master/README-zh.md) 和/或 [OpenVPN](https://github.com/hwdsl2/openvpn-install/blob/master/README-zh.md)。如果你的服务器运行 CentOS Stream, Rocky Linux 或 AlmaLinux，请先安装 OpenVPN/WireGuard，然后安装 IPsec VPN。

<details>
<summary>
如果无法下载，请点这里。
</summary>

你也可以使用 `curl` 下载。例如：

```bash
curl -fL https://get.vpnsetup.net -o vpn.sh
sudo sh vpn.sh
```

或者，你也可以使用这些链接：

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/vpnsetup.sh
```

如果无法下载，打开 [vpnsetup.sh](vpnsetup.sh)，然后点击右边的 `Raw` 按钮。按快捷键 `Ctrl/Cmd+A` 全选，`Ctrl/Cmd+C` 复制，然后粘贴到你喜欢的编辑器。
</details>

#### 可选：在安装 VPN 时自定义 IKEv2 选项。

在安装 VPN 时，你可以自定义 IKEv2 选项。这是可选的。

<details>
<summary>
选项 1: 使用环境变量自定义 IKEv2 选项。
</summary>

在安装 VPN 时，你可以指定一个域名作为 IKEv2 服务器地址。这是可选的。该域名必须是一个全称域名(FQDN)。示例如下：

```bash
sudo VPN_DNS_NAME='vpn.example.com' sh vpn.sh
```

类似地，你可以指定第一个 IKEv2 客户端的名称。如果未指定，则使用默认值 `vpnclient`。

```bash
sudo VPN_CLIENT_NAME='your_client_name' sh vpn.sh
```

在 VPN 已连接时，客户端默认配置为使用 [Google Public DNS](https://developers.google.com/speed/public-dns/)。你可以为所有的 VPN 模式指定另外的 DNS 服务器。示例如下：

```bash
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 sh vpn.sh
```

默认情况下，导入 IKEv2 客户端配置时不需要密码。你可以选择使用随机密码保护客户端配置文件。

```bash
sudo VPN_PROTECT_CONFIG=yes sh vpn.sh
```
</details>
<details>
<summary>
选项 2: 在安装 VPN 时跳过 IKEv2，然后使用自定义选项配置 IKEv2。
</summary>

在安装 VPN 时，你可以跳过 IKEv2，仅安装 IPsec/L2TP 和 IPsec/XAuth ("Cisco IPsec") 模式：

```bash
sudo VPN_SKIP_IKEV2=yes sh vpn.sh
```

（可选）如需为 VPN 客户端指定另外的 DNS 服务器，你可以定义 `VPN_DNS_SRV1` 和 `VPN_DNS_SRV2`（可选）。有关详细信息，参见上面的选项 1。

然后运行 IKEv2 [辅助脚本](docs/ikev2-howto-zh.md#使用辅助脚本配置-ikev2) 使用自定义选项以交互方式配置 IKEv2:

```bash
sudo ikev2.sh
```

**注：** 如果服务器上已经配置了 IKEv2，则 `VPN_SKIP_IKEV2` 变量无效。在这种情况下，如需自定义 IKEv2 选项，你可以首先 [移除 IKEv2](docs/ikev2-howto-zh.md#移除-ikev2)，然后运行 `sudo ikev2.sh` 重新配置。
</details>
<details>
<summary>
供参考：IKEv1 和 IKEv2 参数列表。
</summary>

| IKEv1 参数\* |默认值 |自定义（环境变量）\*\* |
| ------------ | ---- | ----------------- |
|服务器地址（DNS域名）| - |不能，但你可以使用 DNS 域名进行连接 |
|服务器地址（公网IP）|自动检测 | VPN_PUBLIC_IP |
| IPsec 预共享密钥 |自动生成 | VPN_IPSEC_PSK |
| VPN 用户名 | vpnuser | VPN_USER |
| VPN 密码 |自动生成 | VPN_PASSWORD |
|客户端的 DNS 服务器 |Google Public DNS | VPN_DNS_SRV1, VPN_DNS_SRV2 |
|跳过 IKEv2 安装 |no | VPN_SKIP_IKEV2=yes |

\* 这些 IKEv1 参数适用于 IPsec/L2TP 和 IPsec/XAuth ("Cisco IPsec") 模式。   
\*\* 在运行 vpn(setup).sh 时将这些定义为环境变量。

| IKEv2 参数\* |默认值 |自定义（环境变量）\*\* |自定义（交互式）\*\*\* |
| ----------- | ---- | ------------------ | ----------------- |
|服务器地址（DNS域名）| - | VPN_DNS_NAME | ✅ |
|服务器地址（公网IP）|自动检测 | VPN_PUBLIC_IP | ✅ |
|第一个客户端的名称 | vpnclient | VPN_CLIENT_NAME | ✅ |
|客户端的 DNS 服务器 |Google Public DNS | VPN_DNS_SRV1, VPN_DNS_SRV2 | ✅ |
|保护客户端配置文件 |no | VPN_PROTECT_CONFIG=yes | ✅ |
|启用/禁用 MOBIKE |如果系统支持则启用 | ❌ | ✅ |
|客户端证书有效期 | 10 年（120 个月）| VPN_CLIENT_VALIDITY\*\*\*\* | ✅ |
| CA 和服务器证书有效期 | 10 年（120 个月）| ❌ | ❌ |
| CA 证书名称 | IKEv2 VPN CA | ❌ | ❌ |
|证书密钥长度 | 3072 bits | ❌ | ❌ |

\* 这些 IKEv2 参数适用于 IKEv2 模式。   
\*\* 在运行 vpn(setup).sh 时，或者在自动模式下配置 IKEv2 时 (`sudo ikev2.sh --auto`) 将这些定义为环境变量。   
\*\*\* 可以在交互式配置 IKEv2 期间自定义 (`sudo ikev2.sh`)。参见上面的选项 2。   
\*\*\*\* 使用 `VPN_CLIENT_VALIDITY` 定义客户端证书的有效期（单位：月）。它必须是 1 到 120 之间的整数。

除了这些参数，高级用户还可以在安装时 [自定义 VPN 子网](docs/advanced-usage-zh.md#自定义-vpn-子网)。
</details>

## 下一步

*其他语言版本: [English](README.md#next-steps), [中文](README-zh.md#下一步)。*

配置你的计算机或其它设备使用 VPN。请参见：

**[配置 IKEv2 VPN 客户端（推荐）](docs/ikev2-howto-zh.md)**

**[配置 IPsec/L2TP VPN 客户端](docs/clients-zh.md)**

**[配置 IPsec/XAuth ("Cisco IPsec") VPN 客户端](docs/clients-xauth-zh.md)**

**[:book: 电子书：搭建自己的 IPsec VPN, OpenVPN 和 WireGuard 服务器](https://mybook.to/vpnzhs)**

开始使用自己的专属 VPN! :sparkles::tada::rocket::sparkles:

喜欢这个项目？[:heart: 赞助](https://github.com/sponsors/hwdsl2?metadata_o=iz) 或 [:coffee: 支持](https://ko-fi.com/hwdsl2) 并访问 [额外内容](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-X8X5FVFZC)。

## 重要提示

**Windows 用户** 对于 IPsec/L2TP 模式，在首次连接之前需要 [修改注册表](docs/clients-zh.md#windows-错误-809)，以解决 VPN 服务器或客户端与 NAT（比如家用路由器）的兼容问题。

同一个 VPN 账户可以在你的多个设备上使用。但是由于 IPsec/L2TP 的局限性，如果需要连接在同一个 NAT（比如家用路由器）后面的多个设备，你必须使用 [IKEv2](docs/ikev2-howto-zh.md) 或者 [IPsec/XAuth](docs/clients-xauth-zh.md) 模式。要查看或更改 VPN 用户账户，请参见 [管理 VPN 用户](docs/manage-users-zh.md)。

对于有外部防火墙的服务器（比如 [EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html)/[GCE](https://cloud.google.com/vpc/docs/firewalls)），请为 VPN 打开 UDP 端口 500 和 4500。阿里云用户请参见 [#433](https://github.com/hwdsl2/setup-ipsec-vpn/issues/433)。

在 VPN 已连接时，客户端配置为使用 [Google Public DNS](https://developers.google.com/speed/public-dns/)。如果偏好其它的域名解析服务，请参见 [高级用法](docs/advanced-usage-zh.md)。

使用内核支持有助于提高 IPsec/L2TP 性能。它在所有 [受支持的系统](#系统要求) 上可用。Ubuntu 系统需要安装 `linux-modules-extra-$(uname -r)` 软件包并运行 `service xl2tpd restart`。

这些脚本在更改现有的配置文件之前会先做备份，使用 `.old-日期-时间` 为文件名后缀。

## 升级Libreswan

使用以下命令更新你的 VPN 服务器上的 [Libreswan](https://libreswan.org)（[更新日志](https://github.com/libreswan/libreswan/blob/main/CHANGES) | [通知列表](https://lists.libreswan.org/mailman/listinfo/swan-announce)）。

```bash
wget https://get.vpnsetup.net/upg -O vpnup.sh && sudo sh vpnup.sh
```

<details>
<summary>
如果无法下载，请点这里。
</summary>

你也可以使用 `curl` 下载：

```bash
curl -fsSL https://get.vpnsetup.net/upg -o vpnup.sh && sudo sh vpnup.sh
```

或者，你也可以使用这些链接：

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/extras/vpnupgrade.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/extras/vpnupgrade.sh
```

如果无法下载，打开 [vpnupgrade.sh](extras/vpnupgrade.sh)，然后点击右边的 `Raw` 按钮。按快捷键 `Ctrl/Cmd+A` 全选，`Ctrl/Cmd+C` 复制，然后粘贴到你喜欢的编辑器。
</details>

当前支持的 Libreswan 最新版本是 `4.9`。查看已安装版本：`ipsec --version`。

**注：** `xl2tpd` 可以使用系统的软件包管理器进行更新，例如 Ubuntu/Debian 上的 `apt-get`。

## 管理 VPN 用户

请参见 [管理 VPN 用户](docs/manage-users-zh.md)。

- [使用辅助脚本管理 VPN 用户](docs/manage-users-zh.md#使用辅助脚本管理-vpn-用户)
- [查看 VPN 用户](docs/manage-users-zh.md#查看-vpn-用户)
- [查看或更改 IPsec PSK](docs/manage-users-zh.md#查看或更改-ipsec-psk)
- [手动管理 VPN 用户](docs/manage-users-zh.md#手动管理-vpn-用户)

## 高级用法

请参见 [高级用法](docs/advanced-usage-zh.md)。

- [使用其他的 DNS 服务器](docs/advanced-usage-zh.md#使用其他的-dns-服务器)
- [域名和更改服务器 IP](docs/advanced-usage-zh.md#域名和更改服务器-ip)
- [仅限 IKEv2 的 VPN](docs/advanced-usage-zh.md#仅限-ikev2-的-vpn)
- [VPN 内网 IP 和流量](docs/advanced-usage-zh.md#vpn-内网-ip-和流量)
- [自定义 VPN 子网](docs/advanced-usage-zh.md#自定义-vpn-子网)
- [转发端口到 VPN 客户端](docs/advanced-usage-zh.md#转发端口到-vpn-客户端)
- [VPN 分流](docs/advanced-usage-zh.md#vpn-分流)
- [访问 VPN 服务器的网段](docs/advanced-usage-zh.md#访问-vpn-服务器的网段)
- [VPN 服务器网段访问 VPN 客户端](docs/advanced-usage-zh.md#vpn-服务器网段访问-vpn-客户端)
- [更改 IPTables 规则](docs/advanced-usage-zh.md#更改-iptables-规则)
- [部署 Google BBR 拥塞控制](docs/advanced-usage-zh.md#部署-google-bbr-拥塞控制)

## 卸载 VPN

要卸载 IPsec VPN，运行[辅助脚本](extras/vpnuninstall.sh)：

**警告：** 此辅助脚本将从你的服务器中删除 IPsec VPN。所有的 VPN 配置将被**永久删除**，并且 Libreswan 和 xl2tpd 将被移除。此操作**不可撤销**！

```bash
wget https://get.vpnsetup.net/unst -O unst.sh && sudo bash unst.sh
```

<details>
<summary>
如果无法下载，请点这里。
</summary>

你也可以使用 `curl` 下载：

```bash
curl -fsSL https://get.vpnsetup.net/unst -o unst.sh && sudo bash unst.sh
```

或者，你也可以使用这些链接：

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/extras/vpnuninstall.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/extras/vpnuninstall.sh
```
</details>

更多信息请参见 [卸载 VPN](docs/uninstall-zh.md)。

## 问题和反馈

- 如果你有对本项目的建议，请提交一个 [改进建议](https://github.com/hwdsl2/setup-ipsec-vpn/issues/new/choose)，或者欢迎提交 [Pull request](https://github.com/hwdsl2/setup-ipsec-vpn/pulls)。
- 如果你发现了一个可重复的程序漏洞，请为 [IPsec VPN](https://github.com/libreswan/libreswan/issues?q=is%3Aissue) 或者 [VPN 脚本](https://github.com/hwdsl2/setup-ipsec-vpn/issues/new/choose) 提交一个错误报告。
- 有问题需要提问？请先搜索 [已有的 issues](https://github.com/hwdsl2/setup-ipsec-vpn/issues?q=is%3Aissue) 以及在 [这个 Gist](https://gist.github.com/hwdsl2/9030462#comments) 和 [我的博客](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#disqus_thread) 上已有的留言。
- VPN 的相关问题可在 [Libreswan](https://lists.libreswan.org/mailman/listinfo/swan) 或 [strongSwan](https://lists.strongswan.org/mailman/listinfo/users) 邮件列表提问，或者参考这些网站：[[1]](https://libreswan.org/wiki/Main_Page) [[2]](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/sec-securing_virtual_private_networks) [[3]](https://wiki.strongswan.org/projects/strongswan/wiki/UserDocumentation) [[4]](https://wiki.gentoo.org/wiki/IPsec_L2TP_VPN_server) [[5]](https://wiki.archlinux.org/index.php/Openswan_L2TP/IPsec_VPN_client_setup)。

## 授权协议

版权所有 (C) 2014-2023 [Lin Song](https://github.com/hwdsl2) [![View my profile on LinkedIn](https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png)](https://www.linkedin.com/in/linsongui)   
基于 [Thomas Sarlandie 的工作](https://github.com/sarfata/voodooprivacy) (版权所有 2012)

[![Creative Commons License](https://i.creativecommons.org/l/by-sa/3.0/88x31.png)](http://creativecommons.org/licenses/by-sa/3.0/)   
这个项目是以 [知识共享署名-相同方式共享3.0](http://creativecommons.org/licenses/by-sa/3.0/) 许可协议授权。   
必须署名： 请包括我的名字在任何衍生产品，并且让我知道你是如何改善它的！
