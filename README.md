# IPsec VPN Server Auto Setup Scripts

[![Build Status](https://img.shields.io/github/workflow/status/hwdsl2/setup-ipsec-vpn/vpn%20test.svg?cacheSeconds=3600)](https://github.com/hwdsl2/setup-ipsec-vpn/actions) [![GitHub Stars](https://img.shields.io/github/stars/hwdsl2/setup-ipsec-vpn.svg?cacheSeconds=86400)](https://github.com/hwdsl2/setup-ipsec-vpn/stargazers) [![Docker Stars](https://img.shields.io/docker/stars/hwdsl2/ipsec-vpn-server.svg?cacheSeconds=86400)](https://github.com/hwdsl2/docker-ipsec-vpn-server) [![Docker Pulls](https://img.shields.io/docker/pulls/hwdsl2/ipsec-vpn-server.svg?cacheSeconds=86400)](https://github.com/hwdsl2/docker-ipsec-vpn-server)

Set up your own IPsec VPN server in just a few minutes, with IPsec/L2TP, Cisco IPsec and IKEv2 on Ubuntu, Debian and CentOS. All you need to do is provide your own VPN credentials, and let the scripts handle the rest.

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
- [Advanced usage](#advanced-usage)
- [Bugs & Questions](#bugs--questions)
- [Uninstallation](#uninstallation)
- [See also](#see-also)
- [License](#license)

## Quick start

First, prepare your Linux server\* with a fresh install of one of the following OS.

Use this one-liner to set up an IPsec VPN server:

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

Your VPN login details will be randomly generated, and displayed on the screen when finished.

For other installation options and how to set up VPN clients, read the sections below.

\* A dedicated server or virtual private server (VPS). OpenVZ VPS is not supported.

## Features

- **New:** The faster `IPsec/XAuth ("Cisco IPsec")` and `IKEv2` modes are supported
- **New:** A pre-built <a href="https://github.com/hwdsl2/docker-ipsec-vpn-server" target="_blank">Docker image</a> of the VPN server is now available
- Fully automated IPsec VPN server setup, no user input needed
- Encapsulates all VPN traffic in UDP - does not need ESP protocol
- Can be directly used as "user-data" for a new Amazon EC2 instance
- Includes `sysctl.conf` optimizations for improved performance
- Tested with Ubuntu, Debian, CentOS/RHEL and Amazon Linux 2

## Requirements

A newly created <a href="https://aws.amazon.com/ec2/" target="_blank">Amazon EC2</a> instance, from one of these images:
- <a href="https://cloud-images.ubuntu.com/locator/" target="_blank">Ubuntu 20.04 (Focal) or 18.04 (Bionic)</a>
- <a href="https://wiki.debian.org/Cloud/AmazonEC2Image" target="_blank">Debian 10 (Buster)</a>[\*](#debian-10-note)<a href="https://wiki.debian.org/Cloud/AmazonEC2Image" target="_blank"> or 9 (Stretch)</a>
- <a href="https://wiki.centos.org/Cloud/AWS" target="_blank">CentOS 8</a>[\*\*](#centos-8-note)<a href="https://wiki.centos.org/Cloud/AWS" target="_blank"> or 7</a>
- <a href="https://aws.amazon.com/partners/redhat/faqs/" target="_blank">Red Hat Enterprise Linux (RHEL) 8 or 7</a>
- <a href="https://aws.amazon.com/amazon-linux-2/" target="_blank">Amazon Linux 2</a>

See <a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#vpnsetup" target="_blank">detailed instructions</a> and <a href="https://aws.amazon.com/ec2/pricing/" target="_blank">EC2 pricing</a>. Alternatively, you may also deploy rapidly using <a href="aws/README.md" target="_blank">CloudFormation</a>.

**-OR-**

A dedicated server or virtual private server (VPS), freshly installed with one of the above OS. OpenVZ VPS is not supported, users could instead try <a href="https://github.com/Nyr/openvpn-install" target="_blank">OpenVPN</a>.

This also includes Linux VMs in public clouds, such as <a href="https://blog.ls20.com/digitalocean" target="_blank">DigitalOcean</a>, <a href="https://blog.ls20.com/vultr" target="_blank">Vultr</a>, <a href="https://blog.ls20.com/linode" target="_blank">Linode</a>, <a href="https://cloud.google.com/compute/" target="_blank">Google Compute Engine</a>, <a href="https://aws.amazon.com/lightsail/" target="_blank">Amazon Lightsail</a>, <a href="https://azure.microsoft.com" target="_blank">Microsoft Azure</a>, <a href="https://www.ibm.com/cloud/virtual-servers" target="_blank">IBM Cloud</a>, <a href="https://www.ovh.com/world/vps/" target="_blank">OVH</a> and <a href="https://www.rackspace.com" target="_blank">Rackspace</a>.

<a href="aws/README.md" target="_blank"><img src="docs/images/aws-deploy-button.png" alt="Deploy to AWS" /></a> <a href="azure/README.md" target="_blank"><img src="docs/images/azure-deploy-button.png" alt="Deploy to Azure" /></a> <a href="http://dovpn.carlfriess.com/" target="_blank"><img src="docs/images/do-install-button.png" alt="Install on DigitalOcean" /></a> <a href="https://cloud.linode.com/stackscripts/37239" target="_blank"><img src="docs/images/linode-deploy-button.png" alt="Deploy to Linode" /></a>

<a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#gettingavps" target="_blank">**&raquo; I want to run my own VPN but don't have a server for that**</a>

Advanced users can set up the VPN server on a $35 <a href="https://www.raspberrypi.org" target="_blank">Raspberry Pi</a>. See <a href="https://elasticbyte.net/posts/setting-up-a-native-cisco-ipsec-vpn-server-using-a-raspberry-pi/" target="_blank">[1]</a> <a href="https://www.stewright.me/2018/07/create-a-raspberry-pi-vpn-server-using-l2tpipsec/" target="_blank">[2]</a>.

<a name="debian-10-note"></a>
\* Debian 10 users should use the standard Linux kernel (not the "cloud" version). Read more <a href="docs/clients.md#debian-10-kernel" target="_blank">here</a>. If using Debian 10 on EC2, you must first switch to the standard Linux kernel before running the VPN setup script.   
<a name="centos-8-note"></a>
\*\* Support for CentOS Linux 8 will end on December 31, 2021. Read more <a href="https://wiki.centos.org/About/Product" target="_blank">here</a>.   

:warning: **DO NOT** run these scripts on your PC or Mac! They should only be used on a server!

## Installation

First, update your system with `apt-get update && apt-get dist-upgrade` (Ubuntu/Debian) or `yum update` and reboot. This is optional, but recommended.

To install the VPN, please choose one of the following options:

**Option 1:** Have the script generate random VPN credentials for you (will be displayed when finished):

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

After successful installation, it is recommended to <a href="docs/ikev2-howto.md" target="_blank">set up IKEv2</a>:

```bash
sudo bash /opt/src/ikev2.sh --auto
```

**Option 2:** Edit the script and provide your own VPN credentials:

<details open>
<summary>
Ubuntu & Debian
</summary>

```bash
wget https://git.io/vpnsetup -O vpn.sh
nano -w vpn.sh
[Replace with your own values: YOUR_IPSEC_PSK, YOUR_USERNAME and YOUR_PASSWORD]
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
[Replace with your own values: YOUR_IPSEC_PSK, YOUR_USERNAME and YOUR_PASSWORD]
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
[Replace with your own values: YOUR_IPSEC_PSK, YOUR_USERNAME and YOUR_PASSWORD]
sudo sh vpn.sh
```
</details>

**Note:** A secure IPsec PSK should consist of at least 20 random characters.

After successful installation, it is recommended to <a href="docs/ikev2-howto.md" target="_blank">set up IKEv2</a>:

```bash
sudo bash /opt/src/ikev2.sh --auto
```

**Option 3:** Define your VPN credentials as environment variables:

<details open>
<summary>
Ubuntu & Debian
</summary>

```bash
# All values MUST be placed inside 'single quotes'
# DO NOT use these special characters within values: \ " '
wget https://git.io/vpnsetup -O vpn.sh
sudo VPN_IPSEC_PSK='your_ipsec_pre_shared_key' \
VPN_USER='your_vpn_username' \
VPN_PASSWORD='your_vpn_password' \
sh vpn.sh
```
</details>

<details>
<summary>
CentOS & RHEL
</summary>

```bash
# All values MUST be placed inside 'single quotes'
# DO NOT use these special characters within values: \ " '
yum -y install wget
wget https://git.io/vpnsetup-centos -O vpn.sh
sudo VPN_IPSEC_PSK='your_ipsec_pre_shared_key' \
VPN_USER='your_vpn_username' \
VPN_PASSWORD='your_vpn_password' \
sh vpn.sh
```
</details>

<details>
<summary>
Amazon Linux 2
</summary>

```bash
# All values MUST be placed inside 'single quotes'
# DO NOT use these special characters within values: \ " '
wget https://git.io/vpnsetup-amzn -O vpn.sh
sudo VPN_IPSEC_PSK='your_ipsec_pre_shared_key' \
VPN_USER='your_vpn_username' \
VPN_PASSWORD='your_vpn_password' \
sh vpn.sh
```
</details>

After successful installation, it is recommended to <a href="docs/ikev2-howto.md" target="_blank">set up IKEv2</a>:

```bash
sudo bash /opt/src/ikev2.sh --auto
```

**Note:** If unable to download via `wget`, you may also open <a href="vpnsetup.sh" target="_blank">vpnsetup.sh</a>, <a href="vpnsetup_centos.sh" target="_blank">vpnsetup_centos.sh</a> or <a href="vpnsetup_amzn.sh" target="_blank">vpnsetup_amzn.sh</a>, and click the **`Raw`** button on the right. Press `Ctrl-A` to select all, `Ctrl-C` to copy, then paste into your favorite editor.

## Next steps

Get your computer or device to use the VPN. Please refer to:

<a href="docs/clients.md" target="_blank">**Configure IPsec/L2TP VPN Clients**</a>

<a href="docs/clients-xauth.md" target="_blank">**Configure IPsec/XAuth ("Cisco IPsec") VPN Clients**</a>

<a href="docs/ikev2-howto.md" target="_blank">**Guide: How to Set Up and Use IKEv2 VPN**</a>

If you get an error when trying to connect, see <a href="docs/clients.md#troubleshooting" target="_blank">Troubleshooting</a>.

Enjoy your very own VPN! :sparkles::tada::rocket::sparkles:

## Important notes

*Read this in other languages: [English](README.md#important-notes), [简体中文](README-zh.md#重要提示).*

**Windows users**: A <a href="docs/clients.md#windows-error-809" target="_blank">one-time registry change</a> is required if the VPN server or client is behind NAT (e.g. home router).

**Android users**: If you encounter connection issues, try <a href="docs/clients.md#android-mtumss-issues" target="_blank">these steps</a>.

The same VPN account can be used by your multiple devices. However, due to an IPsec/L2TP limitation, if you wish to connect multiple devices simultaneously from behind the same NAT (e.g. home router), you must use only <a href="docs/clients-xauth.md" target="_blank">IPsec/XAuth mode</a>, or <a href="docs/ikev2-howto.md" target="_blank">set up IKEv2</a>.

If you wish to view or update VPN user accounts, see <a href="docs/manage-users.md" target="_blank">Manage VPN Users</a>. Helper scripts are included for convenience.

For servers with an external firewall (e.g. <a href="https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html" target="_blank">EC2</a>/<a href="https://cloud.google.com/vpc/docs/firewalls" target="_blank">GCE</a>), open UDP ports 500 and 4500 for the VPN. Aliyun users, see <a href="https://github.com/hwdsl2/setup-ipsec-vpn/issues/433" target="_blank">#433</a>.

Clients are set to use <a href="https://developers.google.com/speed/public-dns/" target="_blank">Google Public DNS</a> when the VPN is active. If another DNS provider is preferred, [read below](#use-alternative-dns-servers).

Using kernel support could improve IPsec/L2TP performance. It is available on [all supported OS](#requirements). Ubuntu users should install the `linux-modules-extra-$(uname -r)` (or `linux-image-extra`) package and run `service xl2tpd restart`.

The scripts will backup existing config files before making changes, with `.old-date-time` suffix.

## Upgrade Libreswan

The additional scripts in <a href="extras/" target="_blank">extras/</a> can be used to upgrade <a href="https://libreswan.org" target="_blank">Libreswan</a> (<a href="https://github.com/libreswan/libreswan/blob/master/CHANGES" target="_blank">changelog</a> | <a href="https://lists.libreswan.org/mailman/listinfo/swan-announce" target="_blank">announce</a>). Edit the `SWAN_VER` variable as necessary. The latest supported version is `4.4`. Check which version is installed: `ipsec --version`.

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

## Advanced usage

*Read this in other languages: [English](README.md#advanced-usage), [简体中文](README-zh.md#高级用法).*

- [Use alternative DNS servers](#use-alternative-dns-servers)
- [DNS name and server IP changes](#dns-name-and-server-ip-changes)
- [Internal VPN IPs](#internal-vpn-ips)
- [IKEv2 only VPN](#ikev2-only-vpn)
- [Modify IPTables rules](#modify-iptables-rules)

### Use alternative DNS servers

Clients are set to use <a href="https://developers.google.com/speed/public-dns/" target="_blank">Google Public DNS</a> when the VPN is active. If another DNS provider is preferred, you may replace `8.8.8.8` and `8.8.4.4` in these files: `/etc/ppp/options.xl2tpd`, `/etc/ipsec.conf` and `/etc/ipsec.d/ikev2.conf` (if exists). Then run `service ipsec restart` and `service xl2tpd restart`.

Advanced users can define `VPN_DNS_SRV1` and optionally `VPN_DNS_SRV2` when running the VPN setup script and the <a href="docs/ikev2-howto.md#using-helper-scripts" target="_blank">IKEv2 helper script</a>. For example, if you want to use [Cloudflare's DNS service](https://1.1.1.1):

```
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 sh vpn.sh
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 bash /opt/src/ikev2.sh --auto
```

### DNS name and server IP changes

For `IPsec/L2TP` and `IPsec/XAuth ("Cisco IPsec")` modes, you may use a DNS name (e.g. `vpn.example.com`) instead of an IP address to connect to the VPN server, without additional configuration. In addition, the VPN should generally continue to work after server IP changes, such as after restoring a snapshot to a new server with a different IP, although a reboot may be required.

For `IKEv2` mode, if you want the VPN to continue to work after server IP changes, you must specify a DNS name to be used as the VPN server's address when <a href="docs/ikev2-howto.md" target="_blank">setting up IKEv2</a>. The DNS name must be a fully qualified domain name (FQDN). Example:

```
sudo VPN_DNS_NAME='vpn.example.com' bash /opt/src/ikev2.sh --auto
```

Alternatively, you may customize IKEv2 setup options by running the <a href="docs/ikev2-howto.md#using-helper-scripts" target="_blank">helper script</a> without the `--auto` parameter.

### Internal VPN IPs

When connecting using `IPsec/L2TP` mode, the VPN server has internal IP `192.168.42.1` within the VPN subnet `192.168.42.0/24`. Clients are assigned internal IPs from `192.168.42.10` to `192.168.42.250`. To check which IP is assigned to a client, view the connection status on the VPN client.

When connecting using `IPsec/XAuth ("Cisco IPsec")` or `IKEv2` mode, the VPN server \*does not\* have an internal IP within the VPN subnet `192.168.43.0/24`. Clients are assigned internal IPs from `192.168.43.10` to `192.168.43.250`.

You may use these internal VPN IPs for communication. However, note that the IPs assigned to VPN clients are dynamic, and firewalls on client devices may block such traffic.

Client-to-client traffic is allowed by default. If you want to \*disallow\* client-to-client traffic, run the following commands on the VPN server. Add them to `/etc/rc.local` to persist after reboot.

```
iptables -I FORWARD 2 -i ppp+ -o ppp+ -s 192.168.42.0/24 -d 192.168.42.0/24 -j DROP
iptables -I FORWARD 3 -s 192.168.43.0/24 -d 192.168.43.0/24 -j DROP
```

### IKEv2 only VPN

Libreswan 4.2 and newer versions support the `ikev1-policy` config option. Using this option, advanced users can set up an IKEv2-only VPN, i.e. only IKEv2 connections are accepted by the VPN server, while IKEv1 connections (including the IPsec/L2TP and IPsec/XAuth ("Cisco IPsec") modes) are dropped.

To set up an IKEv2-only VPN, first install the VPN server and set up IKEv2 using instructions in this README. Then check Libreswan version using `ipsec --version`, and [update Libreswan](#upgrade-libreswan) if needed. After that, edit `/etc/ipsec.conf` on the VPN server. Append `ikev1-policy=drop` to the end of the `config setup` section, indented by two spaces. Save the file and run `service ipsec restart`. When finished, you can run `ipsec status` to verify that only the `ikev2-cp` connection is enabled.

### Modify IPTables rules

If you want to modify the IPTables rules after install, edit `/etc/iptables.rules` and/or `/etc/iptables/rules.v4` (Ubuntu/Debian), or `/etc/sysconfig/iptables` (CentOS/RHEL). Then reboot your server.

## Bugs & Questions

- Got a question? Please first search other people's comments <a href="https://gist.github.com/hwdsl2/9030462#comments" target="_blank">in this Gist</a> and <a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#disqus_thread" target="_blank">on my blog</a>.
- Ask VPN related questions on the <a href="https://lists.libreswan.org/mailman/listinfo/swan" target="_blank">Libreswan</a> or <a href="https://lists.strongswan.org/mailman/listinfo/users" target="_blank">strongSwan</a> mailing list, or read these wikis: <a href="https://libreswan.org/wiki/Main_Page" target="_blank">[1]</a> <a href="https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/sec-securing_virtual_private_networks" target="_blank">[2]</a> <a href="https://wiki.strongswan.org/projects/strongswan/wiki/UserDocumentation" target="_blank">[3]</a> <a href="https://wiki.gentoo.org/wiki/IPsec_L2TP_VPN_server" target="_blank">[4]</a> <a href="https://wiki.archlinux.org/index.php/Openswan_L2TP/IPsec_VPN_client_setup" target="_blank">[5]</a>.
- If you found a reproducible bug, open a <a href="https://github.com/hwdsl2/setup-ipsec-vpn/issues?q=is%3Aissue" target="_blank">GitHub Issue</a> to submit a bug report.

## Uninstallation

See <a href="docs/uninstall.md" target="_blank">Uninstall the VPN</a>.

## See also

- <a href="https://github.com/hwdsl2/docker-ipsec-vpn-server" target="_blank">IPsec VPN Server on Docker</a>

## License

Copyright (C) 2014-2021 <a href="https://www.linkedin.com/in/linsongui" target="_blank">Lin Song</a> <a href="https://www.linkedin.com/in/linsongui" target="_blank"><img src="https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png" width="160" height="25" border="0" alt="View my profile on LinkedIn"></a>   
Based on <a href="https://github.com/sarfata/voodooprivacy" target="_blank">the work of Thomas Sarlandie</a> (Copyright 2012)

<a rel="license" href="http://creativecommons.org/licenses/by-sa/3.0/"><img alt="Creative Commons License" style="border-width:0" src="https://i.creativecommons.org/l/by-sa/3.0/88x31.png" /></a>   
This work is licensed under the <a href="http://creativecommons.org/licenses/by-sa/3.0/" target="_blank">Creative Commons Attribution-ShareAlike 3.0 Unported License</a>  
Attribution required: please include my name in any derivative and let me know how you have improved it!
