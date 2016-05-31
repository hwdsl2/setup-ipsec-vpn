# IPsec VPN 服务器一键安装脚本 <a href="https://travis-ci.org/hwdsl2/setup-ipsec-vpn"><img align="right" src="https://travis-ci.org/hwdsl2/setup-ipsec-vpn.svg?branch=master" alt="Build status" /></a>

*其他语言版本: [English](README.md), [简体中文](README-zh.md).*

使用这些 Linux Shell 脚本一键快速搭建 IPsec VPN 服务器。支持 IPsec/L2TP 和 Cisco IPsec 协议，可用于 Ubuntu，Debian 和 CentOS 系统。你只需提供自己的 VPN 登录凭证，然后运行脚本自动完成安装。

我们将使用 <a href="https://libreswan.org/" target="_blank">Libreswan</a> 作为 IPsec 服务器，以及 <a href="https://github.com/xelerance/xl2tpd" target="_blank">xl2tpd</a> 作为 L2TP 提供者。

<a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/" target="_blank">**&raquo; 相关教程： IPsec VPN Server Auto Setup with Libreswan**</a>

#### 目录

- [功能特性](#功能特性)
- [系统要求](#系统要求)
- [安装说明](#安装说明)
  - [Ubuntu & Debian](#ubuntu--debian)
  - [CentOS & RHEL](#centos--rhel)
- [下一步](#下一步)
- [重要提示](#重要提示)
- [管理 VPN 用户](#管理-vpn-用户)
- [关于升级Libreswan](#关于升级libreswan)
- [问题和反馈](#问题和反馈)
- [另见](#另见)
- [作者](#作者)
- [授权协议](#授权协议)

## 功能特性

- **NEW:** 新增支持更高效的 `IPsec/XAuth ("Cisco IPsec")` 模式
- **NEW:** 现在可以下载 VPN 服务器的预构建 <a href="https://github.com/hwdsl2/docker-ipsec-vpn-server" target="_blank">Docker 映像</a>
- 全自动的 IPsec VPN 服务器配置，无需用户输入
- 封装所有的 VPN 流量在 UDP 协议，不需要 ESP 协议支持
- 可直接作为 Amazon EC2 实例创建时的用户数据使用
- 自动确定服务器的公网 IP 以及私有 IP 地址
- 包括基本的 IPTables 防火墙规则和 `sysctl.conf` 优化设置
- 测试通过： Ubuntu 16.04/14.04/12.04， Debian 8 和 CentOS 6/7

## 系统要求

一个新创建的 <a href="https://aws.amazon.com/ec2/" target="_blank">Amazon EC2</a> 实例，使用这些 AMI: (详细步骤<a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#vpnsetup" target="_blank">点这里</a>)
- <a href="https://cloud-images.ubuntu.com/locator/" target="_blank">Ubuntu 16.04 (Xenial), 14.04 (Trusty) or 12.04 (Precise)</a>
- <a href="https://wiki.debian.org/Cloud/AmazonEC2Image" target="_blank">Debian 8 (Jessie) EC2 Images</a>
- <a href="https://aws.amazon.com/marketplace/pp/B00O7WM7QW" target="_blank">CentOS 7 (x86_64) with Updates</a>
- <a href="https://aws.amazon.com/marketplace/pp/B00NQAYLWO" target="_blank">CentOS 6 (x86_64) with Updates</a>

**-或者-**

一个专用服务器，或者基于 KVM/Xen 的虚拟专用服务器 (VPS)，全新安装以上操作系统之一。另外也可用 Debian 7 (Wheezy)，但是必须首先运行 <a href="extras/vpnsetup-debian-7-workaround.sh" target="_blank">另一个脚本</a>。 OpenVZ VPS 用户请使用其它的 VPN 软件，比如 <a href="https://github.com/Nyr/openvpn-install" target="_blank">OpenVPN</a>。

<a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#gettingavps" target="_blank">**&raquo; 我想建立并使用自己的 VPN ，但是没有可用的服务器**</a>

:warning: **不要** 在你的 PC 或者 Mac 上运行这些脚本！它们只能用在服务器上！

## 安装说明

### Ubuntu & Debian

首先，更新你的系统： 运行 `apt-get update && apt-get dist-upgrade` 并重启。这一步是可选的，但推荐。

**选项 1:** 使用脚本随机生成的 VPN 登录凭证 （会在屏幕上显示）：

```bash
wget https://git.io/vpnsetup -O vpnsetup.sh && sudo sh vpnsetup.sh
```

**选项 2:** 输入你自己的 VPN 登录凭证，或者将它们定义为环境变量：

```bash
wget https://git.io/vpnsetup -O vpnsetup.sh
nano -w vpnsetup.sh
[修改为你自己的值： VPN_IPSEC_PSK, VPN_USER 和 VPN_PASSWORD]
sudo sh vpnsetup.sh
```

### CentOS & RHEL

首先，更新你的系统： 运行 `yum update` 并重启。这一步是可选的，但推荐。

**选项 1:** 使用脚本随机生成的 VPN 登录凭证 （会在屏幕上显示）：

```bash
wget https://git.io/vpnsetup-centos -O vpnsetup_centos.sh && sudo sh vpnsetup_centos.sh
```

**选项 2:** 输入你自己的 VPN 登录凭证，或者将它们定义为环境变量：

```bash
wget https://git.io/vpnsetup-centos -O vpnsetup_centos.sh
nano -w vpnsetup_centos.sh
[修改为你自己的值： VPN_IPSEC_PSK, VPN_USER 和 VPN_PASSWORD]
sudo sh vpnsetup_centos.sh
```

如果无法通过 `wget` 下载，你也可以打开 <a href="vpnsetup.sh" target="_blank">vpnsetup.sh</a> (或者 <a href="vpnsetup_centos.sh" target="_blank">vpnsetup_centos.sh</a>)，然后点击右方的 **`Raw`** 按钮。按快捷键 `Ctrl-A` 全选， `Ctrl-C` 复制，然后粘贴到你喜欢的编辑器。

## 下一步

配置你的计算机或其它设备使用 VPN 。请参见： <a href="docs/clients-zh.md" target="_blank">配置 IPsec/L2TP VPN 客户端</a>。

**NEW：** 新增支持更高效的 `"Cisco IPsec"` 模式： <a href="docs/clients-xauth-zh.md" target="_blank">配置 IPsec/XAuth VPN 客户端</a>。

开始使用自己的专属 VPN ! :sparkles::tada::rocket::sparkles:

## 重要提示

**Windows 用户** 在首次连接之前需要<a href="https://documentation.meraki.com/MX-Z/Client_VPN/Troubleshooting_Client_VPN#Windows_Error_809" target="_blank">修改一次注册表</a>，以解决 VPN 服务器和客户端与 NAT （比如家用路由器）的兼容问题。另外如果遇到 `Error 628` ，请打开 VPN 连接属性的"安全"选项卡，并确保<a href="https://cloud.githubusercontent.com/assets/5704064/14538812/96b4f930-024b-11e6-9d81-fa3d3db1ce33.png" target="_blank">仅选中 "CHAP" 选项</a>。

**Android 6 (Marshmallow) 用户** 请参考此文档中的注释： <a href="docs/clients-zh.md#android" target="_blank">配置 IPsec/L2TP VPN 客户端</a>。

在 VPN 已连接时，客户端配置为使用 <a href="https://developers.google.com/speed/public-dns/" target="_blank">Google Public DNS</a>。如果要使用另外的 DNS 服务商，可以编辑文件 `options.xl2tpd` 和 `ipsec.conf` 并用新的服务器替换 `8.8.8.8` 和 `8.8.4.4`。然后重新启动系统。

如果服务器配置了自定义 SSH 端口（不是 22）或其他服务，请在运行脚本前编辑 <a href="vpnsetup.sh#L336" target="_blank">IPTables 防火墙规则</a>。

这些脚本在更改现有的配置文件之前会先做备份，使用 `.old-日期-时间` 为文件名后缀。

## 管理 VPN 用户

在默认情况下，将只创建一个用于 VPN 登录的用户账户。如果你需要添加，编辑或者删除用户，请阅读本节。

首先，IPsec PSK (预共享密钥) 保存在文件 `/etc/ipsec.secrets`。如果要更换一个新的 PSK，可以编辑此文件。

```bash
<VPN Server IP>  %any  : PSK "<VPN IPsec PSK>"
```

对于 `IPsec/L2TP`，VPN 用户账户信息保存在文件 `/etc/ppp/chap-secrets`。该文件的格式如下：

```bash
"<VPN User 1>"  l2tpd  "<VPN Password 1>"  *
"<VPN User 2>"  l2tpd  "<VPN Password 2>"  *
... ...
```

你可以添加更多用户，每个用户对应文件中的一行。**不要**在用户名，密码或 PSK 中使用这些字符：`\ " '`

对于 `IPsec/XAuth ("Cisco IPsec")`， VPN 用户账户信息保存在文件 `/etc/ipsec.d/passwd`。该文件的格式如下：

```bash
<VPN User 1>:<VPN Password 1 (hashed)>:xauth-psk
<VPN User 2>:<VPN Password 2 (hashed)>:xauth-psk
... ...
```

这个文件中的密码以 salted and hashed 的形式保存。该步骤可以借助比如 `openssl` 工具来完成：

```bash
# The output will be <VPN Password 1 (hashed)>
openssl passwd -1 "<VPN Password 1>"
```

在完成修改之后，需要重启服务器。

## 关于升级Libreswan

提供两个额外的脚本 <a href="extras/vpnupgrade_Libreswan.sh" target="_blank">vpnupgrade_Libreswan.sh</a> 和 <a href="extras/vpnupgrade_Libreswan_centos.sh" target="_blank">vpnupgrade_Libreswan_centos.sh</a> ，可用于升级 Libreswan。请关注<a href="https://libreswan.org" target="_blank">官方网站</a>，并在运行前根据需要更新 `swan_ver` 变量。

## 问题和反馈

- 有问题需要提问？请先搜索其他用户的留言，在<a href="https://gist.github.com/hwdsl2/9030462#comments" target="_blank">这个 GitHub Gist</a> 以及<a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#disqus_thread" target="_blank">我的博客文章</a>。
- Libreswan (IPsec) 的相关问题可在<a href="https://lists.libreswan.org/mailman/listinfo/swan" target="_blank">邮件列表</a>提问。也可以参见这些文章：<a href="https://libreswan.org/wiki/Main_Page" target="_blank">[1]</a> <a href="https://wiki.gentoo.org/wiki/IPsec_L2TP_VPN_server" target="_blank">[2]</a> <a href="https://wiki.archlinux.org/index.php/L2TP/IPsec_VPN_client_setup" target="_blank">[3]</a> <a href="https://help.ubuntu.com/community/L2TPServer" target="_blank">[4]</a> <a href="https://libreswan.org/man/ipsec.conf.5.html" target="_blank">[5]</a>。
- 如果你发现了一个可重复的程序漏洞，请提交一个 <a href="https://github.com/hwdsl2/setup-ipsec-vpn/issues" target="_blank">GitHub Issue</a>。

## 另见

- [Docker 上的 IPsec VPN 服务器](https://github.com/hwdsl2/docker-ipsec-vpn-server)

## 作者

##### 宋琳
- 最后一年的美国在读博士生，专业是电子与计算机工程 (ECE)
- 现在正在积极寻找新的工作机会，比如软件或系统工程师
- 在 LinkedIn 上与我联系： <a href="https://www.linkedin.com/in/linsongui" target="_blank">https://www.linkedin.com/in/linsongui</a>

感谢本项目所有的 [贡献者](https://github.com/hwdsl2/setup-ipsec-vpn/graphs/contributors)！

## 授权协议

版权所有 (C) 2014-2016&nbsp;Lin Song&nbsp;&nbsp;&nbsp;<a href="https://www.linkedin.com/in/linsongui" target="_blank"><img src="https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png" width="160" height="25" border="0" alt="View my profile on LinkedIn"></a>   
基于 <a href="https://github.com/sarfata/voodooprivacy" target="_blank">Thomas Sarlandie 的工作</a> (版权所有 2012)

这个项目是以 <a href="http://creativecommons.org/licenses/by-sa/3.0/" target="_blank">知识共享署名-相同方式共享3.0</a> 许可协议授权。   
必须署名： 请包括我的名字在任何衍生产品，并且让我知道你是如何改善它的！
