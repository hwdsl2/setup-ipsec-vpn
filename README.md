# IPsec VPN Server Auto Setup Scripts

[![Build Status](https://img.shields.io/travis/hwdsl2/setup-ipsec-vpn.svg?maxAge=1200)](https://travis-ci.org/hwdsl2/setup-ipsec-vpn) [![GitHub Stars](https://img.shields.io/github/stars/hwdsl2/setup-ipsec-vpn.svg?maxAge=86400)](https://github.com/hwdsl2/setup-ipsec-vpn/stargazers) [![Docker Stars](https://img.shields.io/docker/stars/hwdsl2/ipsec-vpn-server.svg?maxAge=86400)](https://github.com/hwdsl2/docker-ipsec-vpn-server) [![Docker Pulls](https://img.shields.io/docker/pulls/hwdsl2/ipsec-vpn-server.svg?maxAge=86400)](https://github.com/hwdsl2/docker-ipsec-vpn-server)

Set up your own IPsec VPN server in just a few minutes, with both IPsec/L2TP and Cisco IPsec on Ubuntu, Debian and CentOS. All you need to do is provide your own VPN credentials, and let the scripts handle the rest.

An IPsec VPN encrypts your network traffic, so that nobody between you and the VPN server can eavesdrop on your data as it travels via the Internet. This is especially useful when using unsecured networks, e.g. at coffee shops, airports or hotel rooms.

We will use <a href="https://libreswan.org/" target="_blank">Libreswan</a> as the IPsec server, and <a href="https://github.com/xelerance/xl2tpd" target="_blank">xl2tpd</a> as the L2TP provider.

<a href="https://github.com/hwdsl2/docker-ipsec-vpn-server" target="_blank">**&raquo; See also: IPsec VPN Server on Docker**</a>

*Read this in other languages: [English](README.md), [简体中文](README-zh.md).*

#### Table of Contents

- [Quick start](#quick-start)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Next steps](#next-steps)
- [Important notes](#important-notes)
- [Upgrade Libreswan](#upgrade-libreswan)
- [Bugs & Questions](#bugs--questions)
- [Uninstallation](#uninstallation)
- [See also](#see-also)
- [License](#license)

## Quick start

First, prepare your Linux server[\*](#quick-start-note) with a fresh install of Ubuntu LTS, Debian or CentOS.

Use this one-liner to set up an IPsec VPN server:

```bash
wget https://git.io/vpnsetup -O vpnsetup.sh && sudo sh vpnsetup.sh
```

If using CentOS, replace the link above with `https://git.io/vpnsetup-centos`.

Your VPN login details will be randomly generated, and displayed on the screen when finished.

For other installation options and how to set up VPN clients, read the sections below.

<a name="quick-start-note"></a>
\* A dedicated server or virtual private server (VPS). OpenVZ VPS is not supported.

## Features

- **New:** The faster `IPsec/XAuth ("Cisco IPsec")` mode is supported
- **New:** A pre-built <a href="https://github.com/hwdsl2/docker-ipsec-vpn-server" target="_blank">Docker image</a> of the VPN server is now available
- Fully automated IPsec VPN server setup, no user input needed
- Encapsulates all VPN traffic in UDP - does not need ESP protocol
- Can be directly used as "user-data" for a new Amazon EC2 instance
- Includes `sysctl.conf` optimizations for improved performance
- Tested with Ubuntu 18.04/16.04, Debian 10/9/8 and CentOS 8/7/6

## Requirements

A newly created <a href="https://aws.amazon.com/ec2/" target="_blank">Amazon EC2</a> instance, from one of these images:
- <a href="https://cloud-images.ubuntu.com/locator/" target="_blank">Ubuntu 18.04 (Bionic) or 16.04 (Xenial)</a>
- <a href="https://wiki.debian.org/Cloud/AmazonEC2Image" target="_blank">Debian 10 (Buster)</a>[\*](#debian-10-note)<a href="https://wiki.debian.org/Cloud/AmazonEC2Image" target="_blank">, 9 (Stretch) or 8 (Jessie)</a>
- <a href="https://wiki.centos.org/Cloud/AWS" target="_blank">CentOS 8 (x86_64) with Updates</a> [\*\*](#centos-8-note)
- <a href="https://aws.amazon.com/marketplace/pp/B00O7WM7QW" target="_blank">CentOS 7 (x86_64) with Updates</a>
- <a href="https://aws.amazon.com/marketplace/pp/B00NQAYLWO" target="_blank">CentOS 6 (x86_64) with Updates</a>
- <a href="https://aws.amazon.com/partners/redhat/faqs/" target="_blank">Red Hat Enterprise Linux (RHEL) 8, 7 or 6</a>

Please see <a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#vpnsetup" target="_blank">detailed instructions</a> and <a href="https://aws.amazon.com/ec2/pricing/" target="_blank">EC2 pricing</a>.

**-OR-**

A dedicated server or KVM/Xen-based virtual private server (VPS), freshly installed with one of the above OS. OpenVZ VPS is not supported, users could instead try <a href="https://github.com/Nyr/openvpn-install" target="_blank">OpenVPN</a>.

This also includes Linux VMs in public clouds, such as <a href="https://blog.ls20.com/digitalocean" target="_blank">DigitalOcean</a>, <a href="https://blog.ls20.com/vultr" target="_blank">Vultr</a>, <a href="https://blog.ls20.com/linode" target="_blank">Linode</a>, <a href="https://cloud.google.com/compute/" target="_blank">Google Compute Engine</a>, <a href="https://aws.amazon.com/lightsail/" target="_blank">Amazon Lightsail</a>, <a href="https://azure.microsoft.com" target="_blank">Microsoft Azure</a>, <a href="https://www.ibm.com/cloud/virtual-servers" target="_blank">IBM Cloud</a>, <a href="https://www.ovh.com/world/vps/" target="_blank">OVH</a> and <a href="https://www.rackspace.com" target="_blank">Rackspace</a>.

<a href="azure/README.md" target="_blank"><img src="docs/images/azure-deploy-button.png" alt="Deploy to Azure" /></a> <a href="http://dovpn.carlfriess.com/" target="_blank"><img src="docs/images/do-install-button.png" alt="Install on DigitalOcean" /></a> <a href="https://cloud.linode.com/stackscripts/37239" target="_blank"><img src="docs/images/linode-deploy-button.png" alt="Deploy to Linode" /></a>

<a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#gettingavps" target="_blank">**&raquo; I want to run my own VPN but don't have a server for that**</a>

Advanced users can set up the VPN server on a $35 <a href="https://www.raspberrypi.org" target="_blank">Raspberry Pi</a>. See <a href="https://blog.elasticbyte.net/setting-up-a-native-cisco-ipsec-vpn-server-using-a-raspberry-pi/" target="_blank">[1]</a> <a href="https://www.stewright.me/create-a-raspberry-pi-vpn-server-using-l2tpipsec/" target="_blank">[2]</a>.

<a name="debian-10-note"></a>
\* Debian 10 users should use the standard Linux kernel (not the "cloud" version). Read more <a href="docs/clients.md#debian-10-kernel" target="_blank">here</a>.   
<a name="centos-8-note"></a>
\*\* CentOS 8 does not yet have an official EC2 image.

:warning: **DO NOT** run these scripts on your PC or Mac! They should only be used on a server!

## Installation

### Ubuntu & Debian

First, update your system with `apt-get update && apt-get dist-upgrade` and reboot. This is optional, but recommended.

To install the VPN, please choose one of the following options:

**Option 1:** Have the script generate random VPN credentials for you (will be displayed when finished):

```bash
wget https://git.io/vpnsetup -O vpnsetup.sh && sudo sh vpnsetup.sh
```

**Option 2:** Edit the script and provide your own VPN credentials:

```bash
wget https://git.io/vpnsetup -O vpnsetup.sh
nano -w vpnsetup.sh
[Replace with your own values: YOUR_IPSEC_PSK, YOUR_USERNAME and YOUR_PASSWORD]
sudo sh vpnsetup.sh
```

**Note:** A secure IPsec PSK should consist of at least 20 random characters.

**Option 3:** Define your VPN credentials as environment variables:

```bash
# All values MUST be placed inside 'single quotes'
# DO NOT use these special characters within values: \ " '
wget https://git.io/vpnsetup -O vpnsetup.sh && sudo \
VPN_IPSEC_PSK='your_ipsec_pre_shared_key' \
VPN_USER='your_vpn_username' \
VPN_PASSWORD='your_vpn_password' \
sh vpnsetup.sh
```

**Note:** If unable to download via `wget`, you may also open <a href="vpnsetup.sh" target="_blank">vpnsetup.sh</a> (or <a href="vpnsetup_centos.sh" target="_blank">vpnsetup_centos.sh</a>) and click the **`Raw`** button. Press `Ctrl-A` to select all, `Ctrl-C` to copy, then paste into your favorite editor.

### CentOS & RHEL

First, update your system with `yum update` and reboot. This is optional, but recommended.

Follow the same steps as above, but replace `https://git.io/vpnsetup` with `https://git.io/vpnsetup-centos`.

## Next steps

Get your computer or device to use the VPN. Please refer to:

<a href="docs/clients.md" target="_blank">**Configure IPsec/L2TP VPN Clients**</a>

<a href="docs/clients-xauth.md" target="_blank">**Configure IPsec/XAuth ("Cisco IPsec") VPN Clients**</a>

<a href="docs/ikev2-howto.md" target="_blank">**Step-by-Step Guide: How to Set Up IKEv2 VPN**</a>

If you get an error when trying to connect, see <a href="docs/clients.md#troubleshooting" target="_blank">Troubleshooting</a>.

Enjoy your very own VPN! :sparkles::tada::rocket::sparkles:

## Important notes

*Read this in other languages: [English](README.md#important-notes), [简体中文](README-zh.md#重要提示).*

**Windows users**: This <a href="docs/clients.md#windows-error-809" target="_blank">one-time registry change</a> is required if the VPN server and/or client is behind NAT (e.g. home router).

**Android 6 and 7 users**: If you encounter connection issues, try <a href="docs/clients.md#android-6-and-7" target="_blank">these steps</a>.

The same VPN account can be used by your multiple devices. However, due to an IPsec/L2TP limitation, if you wish to connect multiple devices simultaneously from behind the same NAT (e.g. home router), you must use only <a href="docs/clients-xauth.md" target="_blank">IPsec/XAuth mode</a>.

For servers with an external firewall (e.g. <a href="https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-network-security.html" target="_blank">EC2</a>/<a href="https://cloud.google.com/vpc/docs/firewalls" target="_blank">GCE</a>), open UDP ports 500 and 4500 for the VPN. Aliyun users, see [#433](https://github.com/hwdsl2/setup-ipsec-vpn/issues/433).

If you wish to add, edit or remove VPN user accounts, see <a href="docs/manage-users.md" target="_blank">Manage VPN Users</a>. Helper scripts are included for convenience.

Clients are set to use <a href="https://developers.google.com/speed/public-dns/" target="_blank">Google Public DNS</a> when the VPN is active. If another DNS provider is preferred, replace `8.8.8.8` and `8.8.4.4` in both `/etc/ppp/options.xl2tpd` and `/etc/ipsec.conf`, then reboot your server. Advanced users can define `VPN_DNS_SRV1` and optionally `VPN_DNS_SRV2` when running the VPN setup script.

Using kernel support could improve IPsec/L2TP performance. It is available on Ubuntu 18.04/16.04, Debian 10/9 and CentOS 8/7/6. Ubuntu users: Install `linux-modules-extra-$(uname -r)` (or `linux-image-extra`), then run `service xl2tpd restart`.

To modify the IPTables rules after install, edit `/etc/iptables.rules` and/or `/etc/iptables/rules.v4` (Ubuntu/Debian), or `/etc/sysconfig/iptables` (CentOS/RHEL). Then reboot your server.

When connecting via `IPsec/L2TP`, the VPN server has IP `192.168.42.1` within the VPN subnet `192.168.42.0/24`.

The scripts will backup existing config files before making changes, with `.old-date-time` suffix.

## Upgrade Libreswan

The additional scripts <a href="extras/vpnupgrade.sh" target="_blank">vpnupgrade.sh</a> and <a href="extras/vpnupgrade_centos.sh" target="_blank">vpnupgrade_centos.sh</a> can be used to upgrade <a href="https://libreswan.org" target="_blank">Libreswan</a> (<a href="https://github.com/libreswan/libreswan/blob/master/CHANGES" target="_blank">changelog</a> | <a href="https://lists.libreswan.org/mailman/listinfo/swan-announce" target="_blank">announce</a>). Edit the `SWAN_VER` variable as necessary. Check which version is installed: `ipsec --version`.

```bash
# Ubuntu & Debian
wget https://git.io/vpnupgrade -O vpnupgrade.sh
# CentOS & RHEL
wget https://git.io/vpnupgrade-centos -O vpnupgrade.sh
```

## Bugs & Questions

- Got a question? Please first search other people's comments <a href="https://gist.github.com/hwdsl2/9030462#comments" target="_blank">in this Gist</a> and <a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#disqus_thread" target="_blank">on my blog</a>.
- Ask VPN related questions on the <a href="https://lists.libreswan.org/mailman/listinfo/swan" target="_blank">Libreswan</a> or <a href="https://lists.strongswan.org/mailman/listinfo/users" target="_blank">strongSwan</a> mailing list, or read these wikis: <a href="https://libreswan.org/wiki/Main_Page" target="_blank">[1]</a> <a href="https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/sec-securing_virtual_private_networks" target="_blank">[2]</a> <a href="https://wiki.strongswan.org/projects/strongswan/wiki/UserDocumentation" target="_blank">[3]</a> <a href="https://wiki.gentoo.org/wiki/IPsec_L2TP_VPN_server" target="_blank">[4]</a> <a href="https://wiki.archlinux.org/index.php/Openswan_L2TP/IPsec_VPN_client_setup" target="_blank">[5]</a>.
- If you found a reproducible bug, open a <a href="https://github.com/hwdsl2/setup-ipsec-vpn/issues?q=is%3Aissue" target="_blank">GitHub Issue</a> to submit a bug report.

## Uninstallation

Please refer to <a href="docs/uninstall.md" target="_blank">Uninstall the VPN</a>.

## See also

- <a href="https://github.com/hwdsl2/docker-ipsec-vpn-server" target="_blank">IPsec VPN Server on Docker</a>
- <a href="https://github.com/trailofbits/algo" target="_blank">Algo VPN</a>
- <a href="https://github.com/StreisandEffect/streisand" target="_blank">Streisand</a>
- <a href="https://github.com/Nyr/openvpn-install" target="_blank">OpenVPN Install</a>

## License

Copyright (C) 2014-2020 <a href="https://www.linkedin.com/in/linsongui" target="_blank">Lin Song</a> <a href="https://www.linkedin.com/in/linsongui" target="_blank"><img src="https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png" width="160" height="25" border="0" alt="View my profile on LinkedIn"></a>   
Based on <a href="https://github.com/sarfata/voodooprivacy" target="_blank">the work of Thomas Sarlandie</a> (Copyright 2012)

This work is licensed under the <a href="http://creativecommons.org/licenses/by-sa/3.0/" target="_blank">Creative Commons Attribution-ShareAlike 3.0 Unported License</a>  
Attribution required: please include my name in any derivative and let me know how you have improved it!
