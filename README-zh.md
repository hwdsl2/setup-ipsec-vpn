# IPsec/L2TP VPN 服务器一键安装脚本

*其他语言版本: [English](README.md), [简体中文](README-zh.md).*

使用 Linux Shell 脚本一键搭建 IPsec/L2TP VPN 服务器。适用于 Ubuntu 16.04/14.04/12.04，Debian 8 和 CentOS 6/7 系统。   
你只需提供以下的信息： `IPSEC_PSK` ， `VPN_USER` 和 `VPN_PASSWORD` ，然后运行脚本自动完成安装。

我们将使用 <a href="https://libreswan.org/" target="_blank">Libreswan</a> 作为 IPsec 服务器，以及 <a href="https://www.xelerance.com/services/software/xl2tpd/" target="_blank">xl2tpd</a> 作为 L2TP 提供者。

#### <a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/" target="_blank">详细的 VPN 教程请参见我的博客文章</a>

## 特性

- 全自动的 IPsec/L2TP VPN 服务器配置，无需用户输入
- 封装所有的 VPN 流量在 UDP 协议，不需要 ESP 协议支持
- 可直接作为 Amazon EC2 实例创建时的用户数据使用
- 自动确定服务器的公网 IP 以及私有 IP 地址
- 包括基本的 IPTables 防火墙规则和 `sysctl.conf` 优化设置
- 测试通过： Ubuntu 16.04/14.04/12.04，Debian 8 和 CentOS 6/7

## 系统要求

一个新创建的 <a href="https://aws.amazon.com/ec2/" target="_blank">Amazon EC2</a> 实例，使用这些 AMI: (详细步骤<a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#vpnsetup" target="_blank">点这里</a>)
- <a href="https://cloud-images.ubuntu.com/locator/" target="_blank">Ubuntu 16.04 (Xenial), 14.04 (Trusty) or 12.04 (Precise)</a>
- <a href="https://wiki.debian.org/Cloud/AmazonEC2Image" target="_blank">Debian 8 (Jessie) EC2 Images</a>
- <a href="https://aws.amazon.com/marketplace/pp/B00O7WM7QW" target="_blank">CentOS 7 (x86_64) with Updates HVM</a>
- <a href="https://aws.amazon.com/marketplace/pp/B00NQAYLWO" target="_blank">CentOS 6 (x86_64) with Updates HVM</a>

**- 或者 -**

一个专用服务器，或者基于 KVM/Xen 的虚拟专用服务器 (VPS)，使用以下操作系统:   
&nbsp;（注: 推荐在一个全新安装的系统上运行这些脚本）
- Ubuntu 16.04 (Xenial), 14.04 (Trusty) or 12.04 (Precise)
- Debian 8 (Jessie)
- Debian 7 (Wheezy) &raquo; 不推荐。必须先运行<a href="https://gist.github.com/hwdsl2/5a769b2c4436cdf02a90" target="_blank">另一个脚本</a>。
- CentOS / Red Hat Enterprise Linux (RHEL) 6 or 7

OpenVZ VPS 用户请使用其它的 VPN 软件，比如 <a href="https://github.com/Nyr/openvpn-install" target="_blank">Nyr 的 OpenVPN 脚本</a>。

<a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#gettingavps" target="_blank">**&raquo; 我想建立并使用自己的 VPN ，但是没有可用的服务器**</a>

:warning: **不要** 在你的 PC 或者 Mac 上运行这些脚本！它们只能用在服务器上！

## 安装说明

### 用于 Ubuntu 和 Debian:

首先，更新你的系统： 运行 `apt-get update && apt-get dist-upgrade` 并重启。这一步是可选的，但推荐。

```bash
wget https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup.sh -O vpnsetup.sh
nano -w vpnsetup.sh
[编辑并替换这些参数为你自己的值： IPSEC_PSK, VPN_USER 和 VPN_PASSWORD]
sudo sh vpnsetup.sh
```

### 用于 CentOS 和 RHEL:

首先，更新你的系统： 运行 `yum update` 并重启。这一步是可选的，但推荐。

```bash
yum -y install wget nano
wget https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup_centos.sh -O vpnsetup_centos.sh
nano -w vpnsetup_centos.sh
[编辑并替换这些参数为你自己的值： IPSEC_PSK, VPN_USER 和 VPN_PASSWORD]
sudo sh vpnsetup_centos.sh
```

如果无法通过 `wget` 下载，你也可以打开 <a href="vpnsetup.sh" target="_blank">vpnsetup.sh</a> (或者 <a href="vpnsetup_centos.sh" target="_blank">vpnsetup_centos.sh</a>)，然后点击右方的 **`Raw`** 按钮。按快捷键 `Ctrl-A` 全选， `Ctrl-C` 复制，然后粘贴到你喜欢的编辑器。

## 下一步

配置你的计算机或其它设备使用 VPN 。在网络上根据关键词搜索教程，比如 <a href="https://www.bing.com/search?q=setup+L2TP+client" target="_blank">bing.com/search?q=setup+L2TP+client</a> 。


开始使用自己的专属 VPN ! :sparkles::tada::rocket::sparkles:

## 重要提示

**Windows 用户** 在首次连接之前可能需要<a href="https://documentation.meraki.com/MX-Z/Client_VPN/Troubleshooting_Client_VPN#Windows_Error_809" target="_blank">更改注册表</a>，以解决 VPN 服务器和客户端与 NAT （比如家用路由器）的兼容问题。另外请打开 VPN 连接属性的<a href="https://github.com/hwdsl2/setup-ipsec-vpn/issues/7#issuecomment-210084875" target="_blank">"安全"选项卡</a>，启用 `CHAP` 选项并且禁用 `MS-CHAP v2`。

**Android 6 (Marshmallow) 用户**: 安装完成之后，请编辑文件 `/etc/ipsec.conf` 并在 `ike=` 和 `phase2alg=` 两行的结尾添加 `,aes256-sha2_256` 。另外<a href="https://libreswan.org/wiki/FAQ#Android_6.0_connection_comes_up_but_no_packet_flow" target="_blank">增加一行</a> `sha2-truncbug=yes` 。每行开头必须空两格。保存修改并运行 `service ipsec restart` 。

**iPhone/iPad 用户**: 在 iOS 的设置菜单请选择 `L2TP` (而不是 `IPSec`) 作为 VPN 类型。如果无法连接，可编辑 `ipsec.conf` 并尝试用 `rightprotoport=17/0` 替换 `rightprotoport=17/%any` 。保存修改并重启 `ipsec` 服务。

如果你想创建具有不同凭据的多个 VPN 用户，只需要<a href="https://gist.github.com/hwdsl2/123b886f29f4c689f531" target="_blank">修改这几行的脚本</a>。

在 VPN 处于活动状态时，客户端已配置为使用<a href="https://developers.google.com/speed/public-dns/" target="_blank">Google Public DNS</a>。此设置可在 `options.xl2tpd` 文件的 `ms-dns` 项更改。

仅适用于 Amazon EC2 实例：在<a href="https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-network-security.html" target="_blank">安全组</a>设置中，请打开 UDP 端口 500 和 4500，以及 TCP 端口 22 （可选，用于 SSH ）。

如果你为服务器配置了自定义 SSH 端口（不是 22）或希望允许其他服务，请在运行脚本之前编辑 <a href="vpnsetup.sh#L278" target="_blank">IPTables 防火墙规则</a>。

这些脚本每次在更改你的配置文件之前，会在同一目录下以 `.old-日期-时间` 为后缀备份现有的配置文件。

## 关于升级Libreswan

提供两个额外的脚本 <a href="vpnupgrade_Libreswan.sh" target="_blank">vpnupgrade_Libreswan.sh</a> 和 <a href="vpnupgrade_Libreswan_centos.sh" target="_blank">vpnupgrade_Libreswan_centos.sh</a> ，可用于将已安装的 Libreswan 不定期升级至最新版本。请关注<a href="https://libreswan.org" target="_blank">官方网站</a>，并在运行前根据需要更新 `SWAN_VER` 变量。

## 问题和反馈

- 有问题需要提问？请先搜索其他用户的留言，在<a href="https://gist.github.com/hwdsl2/9030462#comments" target="_blank">这个 GitHub Gist</a> 以及<a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#disqus_thread" target="_blank">我的博客文章</a>。
- Libreswan (IPsec) 的相关问题可在<a href="https://lists.libreswan.org/mailman/listinfo/swan" target="_blank">邮件列表</a>提问。也可以参见这些 wiki 文章：<a href="https://libreswan.org/wiki/Main_Page" target="_blank">[1]</a> <a href="https://wiki.gentoo.org/wiki/IPsec_L2TP_VPN_server" target="_blank">[2]</a> <a href="https://wiki.archlinux.org/index.php/L2TP/IPsec_VPN_client_setup" target="_blank">[3]</a> <a href="https://help.ubuntu.com/community/L2TPServer" target="_blank">[4]</a> <a href="https://wiki.strongswan.org/projects/strongswan/wiki/UserDocumentation" target="_blank">[5]</a>。
- 如果你发现了一个可重复的程序漏洞，请提交一个 <a href="https://github.com/hwdsl2/setup-ipsec-vpn/issues" target="_blank">GitHub Issue</a>。

## 版权与许可

版权所有 (C) 2014-2016&nbsp;Lin Song&nbsp;&nbsp;&nbsp;<a href="https://www.linkedin.com/in/linsongui" target="_blank"><img src="https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png" width="160" height="25" border="0" alt="View my profile on LinkedIn"></a>   
基于 <a href="https://github.com/sarfata/voodooprivacy" target="_blank">Thomas Sarlandie 的工作</a> (版权所有 2012)

这个项目是以 <a href="http://creativecommons.org/licenses/by-sa/3.0/" target="_blank">知识共享署名-相同方式共享3.0</a> 许可协议授权。   
必须署名： 请包括我的名字在任何衍生产品，并且让我知道你是如何改善它的！
