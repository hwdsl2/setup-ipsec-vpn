# IPsec VPN 服务器一键安装脚本

[![Build Status](https://img.shields.io/github/workflow/status/hwdsl2/setup-ipsec-vpn/vpn%20test.svg?cacheSeconds=3600)](https://github.com/hwdsl2/setup-ipsec-vpn/actions) [![GitHub Stars](https://img.shields.io/github/stars/hwdsl2/setup-ipsec-vpn.svg?cacheSeconds=86400)](https://github.com/hwdsl2/setup-ipsec-vpn/stargazers) [![Docker Stars](https://img.shields.io/docker/stars/hwdsl2/ipsec-vpn-server.svg?cacheSeconds=86400)](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md) [![Docker Pulls](https://img.shields.io/docker/pulls/hwdsl2/ipsec-vpn-server.svg?cacheSeconds=86400)](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md)

使用 Linux 脚本一键快速搭建自己的 IPsec VPN 服务器。支持 IPsec/L2TP, Cisco IPsec 和 IKEv2 协议，可用于 Ubuntu, Debian 和 CentOS 系统。你只需提供自己的 VPN 登录凭证，然后运行脚本自动完成安装。

IPsec VPN 可以加密你的网络流量，以防止在通过因特网传送时，你和 VPN 服务器之间的任何人对你的数据的未经授权的访问。在使用不安全的网络时，这是特别有用的，例如在咖啡厅，机场或旅馆房间。

我们将使用 <a href="https://libreswan.org/" target="_blank">Libreswan</a> 作为 IPsec 服务器，以及 <a href="https://github.com/xelerance/xl2tpd" target="_blank">xl2tpd</a> 作为 L2TP 提供者。

<a href="https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md" target="_blank">**&raquo; 另见：Docker 上的 IPsec VPN 服务器**</a>

*其他语言版本: [English](README.md), [简体中文](README-zh.md).*

#### 目录

- [快速开始](#快速开始)
- [功能特性](#功能特性)
- [系统要求](#系统要求)
- [安装说明](#安装说明)
- [下一步](#下一步)
- [重要提示](#重要提示)
- [升级Libreswan](#升级libreswan)
- [高级用法](#高级用法)
- [问题和反馈](#问题和反馈)
- [卸载说明](#卸载说明)
- [另见](#另见)
- [授权协议](#授权协议)

## 快速开始

首先，在你的 Linux 服务器\* 上全新安装以下系统之一。

使用以下命令快速搭建 IPsec VPN 服务器：

<details open>
<summary>
Ubuntu & Debian
</summary>

```bash
wget https://git.io/vpnsetup -O vpn.sh && sudo sh vpn.sh && sudo /opt/src/ikev2.sh --auto
```
</details>

<details>
<summary>
CentOS & RHEL
</summary>

```bash
wget https://git.io/vpnsetup-centos -O vpn.sh && sudo sh vpn.sh && sudo /opt/src/ikev2.sh --auto
```
</details>

<details>
<summary>
Amazon Linux 2
</summary>

```bash
wget https://git.io/vpnsetup-amzn -O vpn.sh && sudo sh vpn.sh && sudo /opt/src/ikev2.sh --auto
```
</details>

你的 VPN 登录凭证将会被自动随机生成，并在安装完成后显示在屏幕上。

如需了解其它安装选项，以及如何配置 VPN 客户端，请继续阅读以下部分。

\* 一个专用服务器或者虚拟专用服务器 (VPS)。OpenVZ VPS 不受支持。

## 功能特性

- **新:** 增加支持更高效的 `IPsec/XAuth ("Cisco IPsec")` 和 `IKEv2` 模式
- **新:** 现在可以下载 VPN 服务器的预构建 <a href="https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md" target="_blank">Docker 镜像</a>
- 全自动的 IPsec VPN 服务器配置，无需用户输入
- 封装所有的 VPN 流量在 UDP 协议，不需要 ESP 协议支持
- 可直接作为 Amazon EC2 实例创建时的用户数据使用
- 包含 `sysctl.conf` 优化设置，以达到更佳的传输性能
- 已测试：Ubuntu, Debian, CentOS/RHEL 和 Amazon Linux 2

## 系统要求

一个新创建的 <a href="https://aws.amazon.com/ec2/" target="_blank">Amazon EC2</a> 实例，使用这些映像之一：
- <a href="https://cloud-images.ubuntu.com/locator/" target="_blank">Ubuntu 20.04 (Focal) 或者 18.04 (Bionic)</a>
- <a href="https://wiki.debian.org/Cloud/AmazonEC2Image" target="_blank">Debian 10 (Buster)</a>[\*](#debian-10-note)<a href="https://wiki.debian.org/Cloud/AmazonEC2Image" target="_blank"> 或者 9 (Stretch)</a>
- <a href="https://wiki.centos.org/Cloud/AWS" target="_blank">CentOS 8</a>[\*\*](#centos-8-note)<a href="https://wiki.centos.org/Cloud/AWS" target="_blank"> 或者 7</a>
- <a href="https://aws.amazon.com/partners/redhat/faqs/" target="_blank">Red Hat Enterprise Linux (RHEL) 8 或者 7</a>
- <a href="https://aws.amazon.com/amazon-linux-2/" target="_blank">Amazon Linux 2</a>

请参见 <a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#vpnsetup" target="_blank">详细步骤</a> 以及 <a href="https://aws.amazon.com/cn/ec2/pricing/" target="_blank">EC2 定价细节</a>。另外，你也可以使用 <a href="aws/README-zh.md" target="_blank">CloudFormation</a> 来快速部署。

**-或者-**

一个专用服务器或者虚拟专用服务器 (VPS)，全新安装以上操作系统之一。OpenVZ VPS 不受支持，用户可以另外尝试 <a href="https://github.com/Nyr/openvpn-install" target="_blank">OpenVPN</a>。

这也包括各种公共云服务中的 Linux 虚拟机，比如 <a href="https://blog.ls20.com/digitalocean" target="_blank">DigitalOcean</a>, <a href="https://blog.ls20.com/vultr" target="_blank">Vultr</a>, <a href="https://blog.ls20.com/linode" target="_blank">Linode</a>, <a href="https://cloud.google.com/compute/" target="_blank">Google Compute Engine</a>, <a href="https://aws.amazon.com/lightsail/" target="_blank">Amazon Lightsail</a>, <a href="https://azure.microsoft.com" target="_blank">Microsoft Azure</a>, <a href="https://www.ibm.com/cloud/virtual-servers" target="_blank">IBM Cloud</a>, <a href="https://www.ovh.com/world/vps/" target="_blank">OVH</a> 和 <a href="https://www.rackspace.com" target="_blank">Rackspace</a>。

<a href="aws/README-zh.md" target="_blank"><img src="docs/images/aws-deploy-button.png" alt="Deploy to AWS" /></a> <a href="azure/README-zh.md" target="_blank"><img src="docs/images/azure-deploy-button.png" alt="Deploy to Azure" /></a> <a href="http://dovpn.carlfriess.com/" target="_blank"><img src="docs/images/do-install-button.png" alt="Install on DigitalOcean" /></a> <a href="https://cloud.linode.com/stackscripts/37239" target="_blank"><img src="docs/images/linode-deploy-button.png" alt="Deploy to Linode" /></a>

<a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#gettingavps" target="_blank">**&raquo; 我想建立并使用自己的 VPN ，但是没有可用的服务器**</a>

高级用户可以在一个 $35 的 <a href="https://www.raspberrypi.org" target="_blank">Raspberry Pi</a> 上搭建 VPN 服务器。参见 <a href="https://elasticbyte.net/posts/setting-up-a-native-cisco-ipsec-vpn-server-using-a-raspberry-pi/" target="_blank">[1]</a> <a href="https://www.stewright.me/2018/07/create-a-raspberry-pi-vpn-server-using-l2tpipsec/" target="_blank">[2]</a>。

<a name="debian-10-note"></a>
\* Debian 10 用户需要使用标准的 Linux 内核（而不是 "cloud" 版本）。更多信息请看 <a href="docs/clients-zh.md#debian-10-内核" target="_blank">这里</a>。如果你在 EC2 上使用 Debian 10，你必须首先换用标准的 Linux 内核，然后运行 VPN 安装脚本。   
<a name="centos-8-note"></a>
\*\* CentOS Linux 8 的支持将于2021年12月31日结束。更多信息请看 <a href="https://wiki.centos.org/About/Product" target="_blank">这里</a>。   

:warning: **不要** 在你的 PC 或者 Mac 上运行这些脚本！它们只能用在服务器上！

## 安装说明

首先，更新你的系统：运行 `apt-get update && apt-get dist-upgrade` (Ubuntu/Debian) 或者 `yum update` 并重启。这一步是可选的，但推荐。

要安装 VPN，请从以下选项中选择一个：

**选项 1:** 使用脚本随机生成的 VPN 登录凭证 （完成后会在屏幕上显示）：

<details open>
<summary>
Ubuntu & Debian
</summary>

```bash
wget https://git.io/vpnsetup -O vpn.sh && sudo sh vpn.sh
```
</details>

<details>
<summary>
CentOS & RHEL
</summary>

```bash
yum -y install wget
wget https://git.io/vpnsetup-centos -O vpn.sh && sudo sh vpn.sh
```
</details>

<details>
<summary>
Amazon Linux 2
</summary>

```bash
wget https://git.io/vpnsetup-amzn -O vpn.sh && sudo sh vpn.sh
```
</details>

在安装成功之后，推荐 <a href="docs/ikev2-howto-zh.md" target="_blank">配置 IKEv2</a>：

```bash
sudo bash /opt/src/ikev2.sh --auto
```

**选项 2:** 编辑脚本并提供你自己的 VPN 登录凭证：

<details open>
<summary>
Ubuntu & Debian
</summary>

```bash
wget https://git.io/vpnsetup -O vpn.sh
nano -w vpn.sh
[替换为你自己的值： YOUR_IPSEC_PSK, YOUR_USERNAME 和 YOUR_PASSWORD]
sudo sh vpn.sh
```
</details>

<details>
<summary>
CentOS & RHEL
</summary>

```bash
yum -y install wget nano
wget https://git.io/vpnsetup-centos -O vpn.sh
nano -w vpn.sh
[替换为你自己的值： YOUR_IPSEC_PSK, YOUR_USERNAME 和 YOUR_PASSWORD]
sudo sh vpn.sh
```
</details>

<details>
<summary>
Amazon Linux 2
</summary>

```bash
wget https://git.io/vpnsetup-amzn -O vpn.sh
nano -w vpn.sh
[替换为你自己的值： YOUR_IPSEC_PSK, YOUR_USERNAME 和 YOUR_PASSWORD]
sudo sh vpn.sh
```
</details>

**注：** 一个安全的 IPsec PSK 应该至少包含 20 个随机字符。

在安装成功之后，推荐 <a href="docs/ikev2-howto-zh.md" target="_blank">配置 IKEv2</a>：

```bash
sudo bash /opt/src/ikev2.sh --auto
```

**选项 3:** 将你自己的 VPN 登录凭证定义为环境变量：

<details open>
<summary>
Ubuntu & Debian
</summary>

```bash
# 所有变量值必须用 '单引号' 括起来
# *不要* 在值中使用这些字符：  \ " '
wget https://git.io/vpnsetup -O vpn.sh
sudo VPN_IPSEC_PSK='你的IPsec预共享密钥' \
VPN_USER='你的VPN用户名' \
VPN_PASSWORD='你的VPN密码' \
sh vpn.sh
```
</details>

<details>
<summary>
CentOS & RHEL
</summary>

```bash
# 所有变量值必须用 '单引号' 括起来
# *不要* 在值中使用这些字符：  \ " '
yum -y install wget
wget https://git.io/vpnsetup-centos -O vpn.sh
sudo VPN_IPSEC_PSK='你的IPsec预共享密钥' \
VPN_USER='你的VPN用户名' \
VPN_PASSWORD='你的VPN密码' \
sh vpn.sh
```
</details>

<details>
<summary>
Amazon Linux 2
</summary>

```bash
# 所有变量值必须用 '单引号' 括起来
# *不要* 在值中使用这些字符：  \ " '
wget https://git.io/vpnsetup-amzn -O vpn.sh
sudo VPN_IPSEC_PSK='你的IPsec预共享密钥' \
VPN_USER='你的VPN用户名' \
VPN_PASSWORD='你的VPN密码' \
sh vpn.sh
```
</details>

在安装成功之后，推荐 <a href="docs/ikev2-howto-zh.md" target="_blank">配置 IKEv2</a>：

```bash
sudo bash /opt/src/ikev2.sh --auto
```

**注：** 如果无法通过 `wget` 下载，你也可以打开 <a href="vpnsetup.sh" target="_blank">vpnsetup.sh</a>，<a href="vpnsetup_centos.sh" target="_blank">vpnsetup_centos.sh</a> 或者 <a href="vpnsetup_amzn.sh" target="_blank">vpnsetup_amzn.sh</a>，然后点击右方的 **`Raw`** 按钮。按快捷键 `Ctrl-A` 全选， `Ctrl-C` 复制，然后粘贴到你喜欢的编辑器。

## 下一步

配置你的计算机或其它设备使用 VPN 。请参见：

<a href="docs/clients-zh.md" target="_blank">**配置 IPsec/L2TP VPN 客户端**</a>

<a href="docs/clients-xauth-zh.md" target="_blank">**配置 IPsec/XAuth ("Cisco IPsec") VPN 客户端**</a>

<a href="docs/ikev2-howto-zh.md" target="_blank">**IKEv2 VPN 配置和使用指南**</a>

如果在连接过程中遇到错误，请参见 <a href="docs/clients-zh.md#故障排除" target="_blank">故障排除</a>。

开始使用自己的专属 VPN ! :sparkles::tada::rocket::sparkles:

## 重要提示

*其他语言版本: [English](README.md#important-notes), [简体中文](README-zh.md#重要提示).*

**Windows 用户** 在首次连接之前需要 <a href="docs/clients-zh.md#windows-错误-809" target="_blank">修改注册表</a>，以解决 VPN 服务器或客户端与 NAT（比如家用路由器）的兼容问题。

**Android 用户** 如果遇到连接问题，请尝试 <a href="docs/clients-zh.md#android-mtumss-问题" target="_blank">这些步骤</a>。

同一个 VPN 账户可以在你的多个设备上使用。但是由于 IPsec/L2TP 的局限性，如果需要同时连接在同一个 NAT（比如家用路由器）后面的多个设备到 VPN 服务器，你必须仅使用 <a href="docs/clients-xauth-zh.md" target="_blank">IPsec/XAuth 模式</a>，或者 <a href="docs/ikev2-howto-zh.md" target="_blank">配置 IKEv2</a>。

如果需要查看或更改 VPN 用户账户，请参见 <a href="docs/manage-users-zh.md" target="_blank">管理 VPN 用户</a>。该文档包含辅助脚本，以方便管理 VPN 用户。

对于有外部防火墙的服务器（比如 <a href="https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html" target="_blank">EC2</a>/<a href="https://cloud.google.com/vpc/docs/firewalls" target="_blank">GCE</a>），请为 VPN 打开 UDP 端口 500 和 4500。阿里云用户请参见 <a href="https://github.com/hwdsl2/setup-ipsec-vpn/issues/433" target="_blank">#433</a>。

在 VPN 已连接时，客户端配置为使用 <a href="https://developers.google.com/speed/public-dns/" target="_blank">Google Public DNS</a>。如果偏好其它的域名解析服务，请看 [这里](#使用其他的-dns-服务器)。

使用内核支持有助于提高 IPsec/L2TP 性能。它在所有 [受支持的系统](#系统要求) 上可用。Ubuntu 系统需要安装 `linux-modules-extra-$(uname -r)`（或者 `linux-image-extra`）软件包并运行 `service xl2tpd restart`。

这些脚本在更改现有的配置文件之前会先做备份，使用 `.old-日期-时间` 为文件名后缀。

## 升级Libreswan

在 <a href="extras/" target="_blank">extras/</a> 目录提供额外的脚本，可用于升级 <a href="https://libreswan.org" target="_blank">Libreswan</a>（<a href="https://github.com/libreswan/libreswan/blob/master/CHANGES" target="_blank">更新日志</a> | <a href="https://lists.libreswan.org/mailman/listinfo/swan-announce" target="_blank">通知列表</a>）。请在运行前根据需要修改 `SWAN_VER` 变量。目前支持的最新版本是 `4.4`。查看已安装版本：`ipsec --version`。

<details open>
<summary>
Ubuntu & Debian
</summary>

```bash
wget https://git.io/vpnupgrade -O vpnup.sh && sudo sh vpnup.sh
```
</details>

<details>
<summary>
CentOS & RHEL
</summary>

```bash
wget https://git.io/vpnupgrade-centos -O vpnup.sh && sudo sh vpnup.sh
```
</details>

<details>
<summary>
Amazon Linux 2
</summary>

```bash
wget https://git.io/vpnupgrade-amzn -O vpnup.sh && sudo sh vpnup.sh
```
</details>

## 高级用法

*其他语言版本: [English](README.md#advanced-usage), [简体中文](README-zh.md#高级用法).*

- [使用其他的 DNS 服务器](#使用其他的-dns-服务器)
- [域名和更改服务器 IP](#域名和更改服务器-ip)
- [VPN 内网 IP](#vpn-内网-ip)
- [仅限 IKEv2 的 VPN](#仅限-ikev2-的-vpn)
- [更改 IPTables 规则](#更改-iptables-规则)

### 使用其他的 DNS 服务器

在 VPN 已连接时，客户端配置为使用 <a href="https://developers.google.com/speed/public-dns/" target="_blank">Google Public DNS</a>。如果偏好其它的域名解析服务，你可以编辑以下文件：`/etc/ppp/options.xl2tpd`, `/etc/ipsec.conf` 和 `/etc/ipsec.d/ikev2.conf`（如果存在），并替换 `8.8.8.8` 和 `8.8.4.4`。然后运行 `service ipsec restart` 和 `service xl2tpd restart`。

高级用户可以在运行 VPN 安装脚本和 <a href="docs/ikev2-howto-zh.md#使用辅助脚本" target="_blank">IKEv2 辅助脚本</a> 时定义 `VPN_DNS_SRV1` 和 `VPN_DNS_SRV2`（可选）。比如你想使用 [Cloudflare 的 DNS 服务](https://1.1.1.1)：

```
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 sh vpn.sh
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 bash /opt/src/ikev2.sh --auto
```

### 域名和更改服务器 IP

对于 `IPsec/L2TP` 和 `IPsec/XAuth ("Cisco IPsec")` 模式，你可以在不需要额外配置的情况下使用一个域名（比如 `vpn.example.com`）而不是 IP 地址连接到 VPN 服务器。另外，一般来说，在服务器的 IP 更改后，比如在恢复一个映像到具有不同 IP 的新服务器后，VPN 会继续正常工作，虽然可能需要重启服务器。

对于 `IKEv2` 模式，如果你想要 VPN 在服务器的 IP 更改后继续正常工作，则必须在 <a href="docs/ikev2-howto-zh.md" target="_blank">配置 IKEv2</a> 时指定一个域名作为 VPN 服务器的地址。该域名必须是一个全称域名(FQDN)。示例如下：

```
sudo VPN_DNS_NAME='vpn.example.com' bash /opt/src/ikev2.sh --auto
```

另外，你也可以自定义 IKEv2 安装选项，通过在运行 <a href="docs/ikev2-howto-zh.md#使用辅助脚本" target="_blank">辅助脚本</a> 时去掉 `--auto` 参数来实现。

### VPN 内网 IP

在使用 `IPsec/L2TP` 模式连接时，VPN 服务器在虚拟网络 `192.168.42.0/24` 内具有内网 IP `192.168.42.1`。为客户端分配的内网 IP 在这个范围内：`192.168.42.10` 到 `192.168.42.250`。要找到为特定的客户端分配的 IP，可以查看该 VPN 客户端上的连接状态。

在使用 `IPsec/XAuth ("Cisco IPsec")` 或 `IKEv2` 模式连接时，VPN 服务器在虚拟网络 `192.168.43.0/24` 内 \*没有\* 内网 IP。为客户端分配的内网 IP 在这个范围内：`192.168.43.10` 到 `192.168.43.250`。

你可以使用这些 VPN 内网 IP 进行通信。但是请注意，为 VPN 客户端分配的 IP 是动态的，而且客户端设备上的防火墙可能会阻止这些流量。

在默认配置下，允许客户端之间的流量。如果你想要 \*不允许\* 客户端之间的流量，可以在 VPN 服务器上运行以下命令。将它们添加到 `/etc/rc.local` 以便在重启后继续有效。

```
iptables -I FORWARD 2 -i ppp+ -o ppp+ -s 192.168.42.0/24 -d 192.168.42.0/24 -j DROP
iptables -I FORWARD 3 -s 192.168.43.0/24 -d 192.168.43.0/24 -j DROP
```

### 仅限 IKEv2 的 VPN

Libreswan 4.2 和更新版本支持 `ikev1-policy` 配置选项。使用此选项，高级用户可以设置仅限 IKEv2 的 VPN，即 VPN 服务器仅接受 IKEv2 连接，而 IKEv1 连接（包括 IPsec/L2TP 和 IPsec/XAuth ("Cisco IPsec") 模式）将被丢弃。

要设置仅限 IKEv2 的 VPN，首先按照本自述文件中的说明安装 VPN 服务器并且配置 IKEv2。然后使用 `ipsec --version` 命令检查 Libreswan 版本并 [更新 Libreswan](#升级libreswan)（如果需要）。下一步，编辑 VPN 服务器上的 `/etc/ipsec.conf`。在 `config setup` 小节的末尾添加 `ikev1-policy=drop`，开头必须空两格。保存文件并运行 `service ipsec restart`。在完成后，你可以使用 `ipsec status` 命令来验证仅启用了 `ikev2-cp` 连接。

### 更改 IPTables 规则

如果你想要在安装后更改 IPTables 规则，请编辑 `/etc/iptables.rules` 和/或 `/etc/iptables/rules.v4` (Ubuntu/Debian)，或者 `/etc/sysconfig/iptables` (CentOS/RHEL)。然后重启服务器。

## 问题和反馈

- 有问题需要提问？请先搜索已有的留言，在 <a href="https://gist.github.com/hwdsl2/9030462#comments" target="_blank">这个 Gist</a> 以及 <a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#disqus_thread" target="_blank">我的博客</a>。
- VPN 的相关问题可在 <a href="https://lists.libreswan.org/mailman/listinfo/swan" target="_blank">Libreswan</a> 或 <a href="https://lists.strongswan.org/mailman/listinfo/users" target="_blank">strongSwan</a> 邮件列表提问，或者参考这些网站： <a href="https://libreswan.org/wiki/Main_Page" target="_blank">[1]</a> <a href="https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/sec-securing_virtual_private_networks" target="_blank">[2]</a> <a href="https://wiki.strongswan.org/projects/strongswan/wiki/UserDocumentation" target="_blank">[3]</a> <a href="https://wiki.gentoo.org/wiki/IPsec_L2TP_VPN_server" target="_blank">[4]</a> <a href="https://wiki.archlinux.org/index.php/Openswan_L2TP/IPsec_VPN_client_setup" target="_blank">[5]</a>。
- 如果你发现了一个可重复的程序漏洞，请提交一个 <a href="https://github.com/hwdsl2/setup-ipsec-vpn/issues?q=is%3Aissue" target="_blank">GitHub Issue</a>。

## 卸载说明

请参见 <a href="docs/uninstall-zh.md" target="_blank">卸载 VPN</a>。

## 另见

- <a href="https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md" target="_blank">IPsec VPN Server on Docker</a>

## 授权协议

版权所有 (C) 2014-2021 <a href="https://www.linkedin.com/in/linsongui" target="_blank">Lin Song</a> <a href="https://www.linkedin.com/in/linsongui" target="_blank"><img src="https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png" width="160" height="25" border="0" alt="View my profile on LinkedIn"></a>   
基于 <a href="https://github.com/sarfata/voodooprivacy" target="_blank">Thomas Sarlandie 的工作</a> (版权所有 2012)

<a rel="license" href="http://creativecommons.org/licenses/by-sa/3.0/"><img alt="Creative Commons License" style="border-width:0" src="https://i.creativecommons.org/l/by-sa/3.0/88x31.png" /></a>   
这个项目是以 <a href="http://creativecommons.org/licenses/by-sa/3.0/" target="_blank">知识共享署名-相同方式共享3.0</a> 许可协议授权。   
必须署名： 请包括我的名字在任何衍生产品，并且让我知道你是如何改善它的！
