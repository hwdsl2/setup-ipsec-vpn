[English](README.md) | [中文](README-zh.md)

# IPsec VPN Server Auto Setup Scripts

[![Build Status](https://github.com/hwdsl2/setup-ipsec-vpn/actions/workflows/main.yml/badge.svg)](https://github.com/hwdsl2/setup-ipsec-vpn/actions/workflows/main.yml) [![GitHub Stars](docs/images/badges/github-stars.svg)](https://github.com/hwdsl2/setup-ipsec-vpn/stargazers) [![Docker Stars](docs/images/badges/docker-stars.svg)](https://github.com/hwdsl2/docker-ipsec-vpn-server) [![Docker Pulls](docs/images/badges/docker-pulls.svg)](https://github.com/hwdsl2/docker-ipsec-vpn-server)

Set up your own IPsec VPN server in just a few minutes, with IPsec/L2TP, Cisco IPsec and IKEv2.

An IPsec VPN encrypts your network traffic, so that nobody between you and the VPN server can eavesdrop on your data as it travels via the Internet. This is especially useful when using unsecured networks, e.g. at coffee shops, airports or hotel rooms.

We will use [Libreswan](https://libreswan.org/) as the IPsec server, and [xl2tpd](https://github.com/xelerance/xl2tpd) as the L2TP provider.

## Quick start

First, prepare your Linux server\* with a fresh install of Ubuntu, Debian or CentOS.

Use this one-liner to set up an IPsec VPN server:

```bash
wget https://get.vpnsetup.net -O vpn.sh && sudo sh vpn.sh
```

Your VPN login details will be randomly generated, and displayed when finished.

**Optional:** Install [WireGuard](https://github.com/hwdsl2/wireguard-install) and/or [OpenVPN](https://github.com/hwdsl2/openvpn-install) on the same server.

<details>
<summary>
Alternative one-liner.
</summary>

You may also use `curl` to download:

```bash
curl -fsSL https://get.vpnsetup.net -o vpn.sh && sudo sh vpn.sh
```

Alternative setup URLs:

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/vpnsetup.sh
```

If you are unable to download, open [vpnsetup.sh](vpnsetup.sh), then click the `Raw` button on the right. Press `Ctrl/Cmd+A` to select all, `Ctrl/Cmd+C` to copy, then paste into your favorite editor.
</details>
<details>
<summary>
See the VPN script in action (terminal recording).
</summary>

**Note:** This recording is for demo purposes only. VPN credentials in this recording are **NOT** valid.

<p align="center"><img src="docs/images/script-demo.svg"></p>
</details>

A pre-built [Docker image](https://github.com/hwdsl2/docker-ipsec-vpn-server) is also available. For other options and client setup, read the sections below.

\* A cloud server, virtual private server (VPS) or dedicated server.

## Features

- Fully automated IPsec VPN server setup, no user input needed
- Supports IKEv2 with strong and fast ciphers (e.g. AES-GCM)
- Generates VPN profiles to auto-configure iOS, macOS and Android devices
- Supports Windows, macOS, iOS, Android and Linux as VPN clients
- Includes helper scripts to manage VPN users and certificates

## Requirements

A cloud server, virtual private server (VPS) or dedicated server, freshly installed with:

- Ubuntu 22.04, 20.04 or 18.04
- Debian 11[\*](#debian-10-note), 10[\*](#debian-10-note) or 9
- CentOS 7 or CentOS Stream 8[\*\*](#centos-8-note)
- Rocky Linux or AlmaLinux 8
- Oracle Linux 8 or 7
- Red Hat Enterprise Linux (RHEL) 8 or 7
- Amazon Linux 2
- Alpine Linux 3.16 or 3.15

This also includes Linux VMs in public clouds, such as [DigitalOcean](https://blog.ls20.com/digitalocean), [Vultr](https://blog.ls20.com/vultr), [Linode](https://blog.ls20.com/linode), [OVH](https://www.ovhcloud.com/en/vps/) and [Microsoft Azure](https://azure.microsoft.com). Public cloud users can also deploy using [user data](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#vpnsetup).

[![Deploy to DigitalOcean](docs/images/do-install-button.png)](http://dovpn.carlfriess.com) &nbsp;[![Deploy to Linode](docs/images/linode-deploy-button.png)](https://cloud.linode.com/stackscripts/37239) &nbsp;[![Deploy to Azure](docs/images/azure-deploy-button.png)](azure/README.md)

[**&raquo; I want to run my own VPN but don't have a server for that**](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#gettingavps)

A pre-built [Docker image](https://github.com/hwdsl2/docker-ipsec-vpn-server) is also available. Advanced users can install on a [Raspberry Pi](https://www.raspberrypi.org). [[1]](https://elasticbyte.net/posts/setting-up-a-native-cisco-ipsec-vpn-server-using-a-raspberry-pi/) [[2]](https://www.stewright.me/2018/07/create-a-raspberry-pi-vpn-server-using-l2tpipsec/)

<a name="debian-10-note"></a>
\* Debian 11/10 users should [use the standard Linux kernel](docs/clients.md#debian-10-kernel).   
<a name="centos-8-note"></a>
\*\* CentOS Linux 8 [is no longer supported](https://www.centos.org/centos-linux-eol/).

:warning: **DO NOT** run these scripts on your PC or Mac! They should only be used on a server!

## Installation

First, update your server with `sudo apt-get update && sudo apt-get dist-upgrade` (Ubuntu/Debian) or `sudo yum update` and reboot. This is optional, but recommended.

To install the VPN, please choose one of the following options:

**Option 1:** Have the script generate random VPN credentials for you (will be displayed when finished).

```bash
wget https://get.vpnsetup.net -O vpn.sh && sudo sh vpn.sh
```

**Option 2:** Edit the script and provide your own VPN credentials.

```bash
wget https://get.vpnsetup.net -O vpn.sh
nano -w vpn.sh
[Replace with your own values: YOUR_IPSEC_PSK, YOUR_USERNAME and YOUR_PASSWORD]
sudo sh vpn.sh
```

**Note:** A secure IPsec PSK should consist of at least 20 random characters.

**Option 3:** Define your VPN credentials as environment variables.

```bash
# All values MUST be placed inside 'single quotes'
# DO NOT use these special characters within values: \ " '
wget https://get.vpnsetup.net -O vpn.sh
sudo VPN_IPSEC_PSK='your_ipsec_pre_shared_key' \
VPN_USER='your_vpn_username' \
VPN_PASSWORD='your_vpn_password' \
sh vpn.sh
```

After setup, you may optionally install [WireGuard](https://github.com/hwdsl2/wireguard-install) and/or [OpenVPN](https://github.com/hwdsl2/openvpn-install) on the same server.

<details>
<summary>
Advanced users can optionally customize IKEv2 options.
</summary>

Advanced users can optionally specify a DNS name for the IKEv2 server address. The DNS name must be a fully qualified domain name (FQDN). Example:

```bash
sudo VPN_DNS_NAME='vpn.example.com' sh vpn.sh
```

Similarly, you may specify a name for the first IKEv2 client. The default is `vpnclient` if not specified.

```bash
sudo VPN_CLIENT_NAME='your_client_name' sh vpn.sh
```

By default, clients are set to use [Google Public DNS](https://developers.google.com/speed/public-dns/) when the VPN is active. You may specify custom DNS server(s) for all VPN modes. Example:

```bash
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 sh vpn.sh
```

By default, no password is required when importing IKEv2 client configuration. You can choose to protect client config files using a random password.

```bash
sudo VPN_PROTECT_CONFIG=yes sh vpn.sh
```
</details>
<details>
<summary>
Click here if you are unable to download.
</summary>

You may also use `curl` to download. For example:

```bash
curl -fL https://get.vpnsetup.net -o vpn.sh
sudo sh vpn.sh
```

Alternative setup URLs:

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/vpnsetup.sh
```

If you are unable to download, open [vpnsetup.sh](vpnsetup.sh), then click the `Raw` button on the right. Press `Ctrl/Cmd+A` to select all, `Ctrl/Cmd+C` to copy, then paste into your favorite editor.
</details>

## Next steps

*Read this in other languages: [English](README.md#next-steps), [中文](README-zh.md#下一步).*

Get your computer or device to use the VPN. Please refer to:

**[Configure IKEv2 VPN Clients (recommended)](docs/ikev2-howto.md)**

**[Configure IPsec/L2TP VPN Clients](docs/clients.md)**

**[Configure IPsec/XAuth ("Cisco IPsec") VPN Clients](docs/clients-xauth.md)**

Enjoy your very own VPN! :sparkles::tada::rocket::sparkles:

Like this project? You can show your support or appreciation.

<a href="https://ko-fi.com/hwdsl2" target="_blank"><img height="36" src="docs/images/kofi2.png" border="0" alt="Buy Me a Coffee at ko-fi.com" /></a> &nbsp;<a href="https://coindrop.to/hwdsl2" target="_blank"><img src="docs/images/embed-button.png" height="36" width="145" border="0" alt="Coindrop.to me" /></a>

## Important notes

**Windows users**: For IPsec/L2TP mode, a [one-time registry change](docs/clients.md#windows-error-809) is required if the VPN server or client is behind NAT (e.g. home router).

The same VPN account can be used by your multiple devices. However, due to an IPsec/L2TP limitation, if you wish to connect multiple devices from behind the same NAT (e.g. home router), you must use [IKEv2](docs/ikev2-howto.md) or [IPsec/XAuth](docs/clients-xauth.md) mode. To view or update VPN user accounts, see [Manage VPN users](docs/manage-users.md).

For servers with an external firewall (e.g. [EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html)/[GCE](https://cloud.google.com/vpc/docs/firewalls)), open UDP ports 500 and 4500 for the VPN. Aliyun users, see [#433](https://github.com/hwdsl2/setup-ipsec-vpn/issues/433).

Clients are set to use [Google Public DNS](https://developers.google.com/speed/public-dns/) when the VPN is active. If another DNS provider is preferred, see [Advanced usage](docs/advanced-usage.md).

Using kernel support could improve IPsec/L2TP performance. It is available on [all supported OS](#requirements). Ubuntu users should install the `linux-modules-extra-$(uname -r)` package and run `service xl2tpd restart`.

The scripts will backup existing config files before making changes, with `.old-date-time` suffix.

## Upgrade Libreswan

Use this one-liner to update [Libreswan](https://libreswan.org) ([changelog](https://github.com/libreswan/libreswan/blob/main/CHANGES) | [announce](https://lists.libreswan.org/mailman/listinfo/swan-announce)) on your VPN server.

```bash
wget https://get.vpnsetup.net/upg -O vpnup.sh && sudo sh vpnup.sh
```

<details>
<summary>
Alternative one-liner.
</summary>

You may also use `curl` to download:

```bash
curl -fsSL https://get.vpnsetup.net/upg -o vpnup.sh && sudo sh vpnup.sh
```

Alternative update URLs:

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/extras/vpnupgrade.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/extras/vpnupgrade.sh
```

If you are unable to download, open [vpnupgrade.sh](extras/vpnupgrade.sh), then click the `Raw` button on the right. Press `Ctrl/Cmd+A` to select all, `Ctrl/Cmd+C` to copy, then paste into your favorite editor.
</details>

The latest supported Libreswan version is `4.7`. Check installed version: `ipsec --version`.

**Note:** `xl2tpd` can be updated using your system's package manager, such as `apt-get` on Ubuntu/Debian.

## Manage VPN users

See [Manage VPN users](docs/manage-users.md).

- [Manage VPN users using helper scripts](docs/manage-users.md#manage-vpn-users-using-helper-scripts)
- [View VPN users](docs/manage-users.md#view-vpn-users)
- [View or update the IPsec PSK](docs/manage-users.md#view-or-update-the-ipsec-psk)
- [Manually manage VPN users](docs/manage-users.md#manually-manage-vpn-users)

## Advanced usage

See [Advanced usage](docs/advanced-usage.md).

- [Use alternative DNS servers](docs/advanced-usage.md#use-alternative-dns-servers)
- [DNS name and server IP changes](docs/advanced-usage.md#dns-name-and-server-ip-changes)
- [IKEv2-only VPN](docs/advanced-usage.md#ikev2-only-vpn)
- [Internal VPN IPs and traffic](docs/advanced-usage.md#internal-vpn-ips-and-traffic)
- [Customize VPN subnets](docs/advanced-usage.md#customize-vpn-subnets)
- [Port forwarding to VPN clients](docs/advanced-usage.md#port-forwarding-to-vpn-clients)
- [Split tunneling](docs/advanced-usage.md#split-tunneling)
- [Access VPN server's subnet](docs/advanced-usage.md#access-vpn-servers-subnet)
- [Modify IPTables rules](docs/advanced-usage.md#modify-iptables-rules)
- [Deploy Google BBR congestion control](docs/advanced-usage.md#deploy-google-bbr-congestion-control)

## Uninstall the VPN

To uninstall IPsec VPN, run the [helper script](extras/vpnuninstall.sh):

**Warning:** This helper script will remove IPsec VPN from your server. All VPN configuration will be **permanently deleted**, and Libreswan and xl2tpd will be removed. This **cannot be undone**!

```bash
wget https://get.vpnsetup.net/unst -O vpnunst.sh && sudo bash vpnunst.sh
```

<details>
<summary>
Alternative commands.
</summary>

You may also use `curl` to download:

```bash
curl -fsSL https://get.vpnsetup.net/unst -o vpnunst.sh && sudo bash vpnunst.sh
```

Alternative script URLs:

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/extras/vpnuninstall.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/extras/vpnuninstall.sh
```
</details>

For more information, see [Uninstall the VPN](docs/uninstall.md).

## Feedback & Questions

- Have a suggestion for this project? Open an [Enhancement request](https://github.com/hwdsl2/setup-ipsec-vpn/issues/new/choose). [Pull requests](https://github.com/hwdsl2/setup-ipsec-vpn/pulls) are also welcome.
- If you found a reproducible bug, open a bug report for the [IPsec VPN](https://github.com/libreswan/libreswan/issues?q=is%3Aissue) or for the [VPN scripts](https://github.com/hwdsl2/setup-ipsec-vpn/issues/new/choose).
- Got a question? Please first search [existing issues](https://github.com/hwdsl2/setup-ipsec-vpn/issues?q=is%3Aissue) and comments [in this Gist](https://gist.github.com/hwdsl2/9030462#comments) and [on my blog](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#disqus_thread).
- Ask VPN related questions on the [Libreswan](https://lists.libreswan.org/mailman/listinfo/swan) or [strongSwan](https://lists.strongswan.org/mailman/listinfo/users) mailing list, or read these wikis: [[1]](https://libreswan.org/wiki/Main_Page) [[2]](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/sec-securing_virtual_private_networks) [[3]](https://wiki.strongswan.org/projects/strongswan/wiki/UserDocumentation) [[4]](https://wiki.gentoo.org/wiki/IPsec_L2TP_VPN_server) [[5]](https://wiki.archlinux.org/index.php/Openswan_L2TP/IPsec_VPN_client_setup).

## License

Copyright (C) 2014-2022 [Lin Song](https://github.com/hwdsl2) [![View my profile on LinkedIn](https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png)](https://www.linkedin.com/in/linsongui)   
Based on [the work of Thomas Sarlandie](https://github.com/sarfata/voodooprivacy) (Copyright 2012)

[![Creative Commons License](https://i.creativecommons.org/l/by-sa/3.0/88x31.png)](http://creativecommons.org/licenses/by-sa/3.0/)   
This work is licensed under the [Creative Commons Attribution-ShareAlike 3.0 Unported License](http://creativecommons.org/licenses/by-sa/3.0/)  
Attribution required: please include my name in any derivative and let me know how you have improved it!
