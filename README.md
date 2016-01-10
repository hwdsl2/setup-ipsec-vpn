# IPsec/L2TP VPN Server Auto Setup Scripts

Note: This repository was created from (and replaces) these GitHub Gists:
- <a href="https://gist.github.com/hwdsl2/9030462/2aaaf443855de0275dad8a4e45bea523b5b0f966" target="_blank"  rel="nofollow">gist.github.com/hwdsl2/9030462</a> (224 Stars, 87 Forks as of 01/08/2016)
- <a href="https://gist.github.com/hwdsl2/e9a78a50e300d12ae195/5f68fb260c5c143e10d3cf6b3ce2c2f5426f7c1e" target="_blank"  rel="nofollow">gist.github.com/hwdsl2/e9a78a50e300d12ae195</a> (9 Stars, 5 Forks)

## Overview

Scripts for automatic configuration of IPsec/L2TP VPN server on Ubuntu 14.04 & 12.04, Debian 8 and CentOS/RHEL 6 & 7. All you need to do is providing your own values for `IPSEC_PSK`, `VPN_USER` and `VPN_PASSWORD`, and they will handle the rest. These scripts can also be directly used as the Amazon EC2 "user-data" when creating a new instance.

We will use <a href="https://libreswan.org/" target="_blank">Libreswan</a> as the IPsec server, and <a href="https://www.xelerance.com/services/software/xl2tpd/" target="_blank">xl2tpd</a> as the L2TP provider. 

#### <a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/" target="_blank">Link to my VPN tutorial with detailed usage instructions</a>  

## Features

- Fully automated IPsec/L2TP VPN server setup, no user input needed
- Encapsulates all VPN traffic in UDP - does not need the <a href="http://www.tcpipguide.com/free/t_IPSecEncapsulatingSecurityPayloadESP.htm" target="_blank">ESP protocol</a>
- Can be directly used as "user-data" for a new Amazon EC2 instance
- Automatically determines public IP and private IP of server
- Includes basic IPTables rules and `sysctl.conf` settings
- Tested with Ubuntu 14.04 & 12.04, Debian 8 and CentOS/RHEL 6 & 7


## Requirements

A newly created Amazon EC2 instance, using these AMIs: (See the link above for usage instructions)
- <a href="http://cloud-images.ubuntu.com/releases/trusty/release/" target="_blank">Ubuntu 14.04 (Trusty)</a> or <a href="http://cloud-images.ubuntu.com/releases/precise/release/" target="_blank">12.04 (Precise)</a>
- <a href="https://wiki.debian.org/Cloud/AmazonEC2Image/Jessie" target="_blank">Debian 8 (Jessie) EC2 Images</a>
- <a href="https://aws.amazon.com/marketplace/pp/B00O7WM7QW" target="_blank">CentOS 7 (x86_64) with Updates HVM</a>
- <a href="https://aws.amazon.com/marketplace/pp/B00NQAYLWO" target="_blank">CentOS 6 (x86_64) with Updates HVM</a> - Does NOT have cloud-init. Run script manually via SSH.

**-OR-**

A dedicated server or any KVM- or Xen-based Virtual Private Server (VPS), with **freshly installed**:
- Ubuntu 14.04 (Trusty) or 12.04 (Precise)
- Debian 8 (Jessie)
- Debian 7 (Wheezy) - Not recommended. A workaround is required, see below.
- CentOS / Red Hat Enterprise Linux (RHEL) 6 or 7

OpenVZ VPS users should instead use <a href="https://github.com/Nyr/openvpn-install" target="_blank">Nyr's OpenVPN script</a>.

#### <a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#gettingavps" target="_blank">I want to run my own VPN but don't have a server for that</a>

##### Do NOT run these scripts on your PC or Mac! They are meant to be run on a dedicated server or VPS!

## Installation

### For Ubuntu and Debian:

```bash
wget https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup.sh -O vpnsetup.sh
nano -w vpnsetup.sh
[Edit and replace IPSEC_PSK, VPN_USER and VPN_PASSWORD with your own values]
/bin/sh vpnsetup.sh
```

Workaround required for Debian 7 (Wheezy) ONLY: (Run these commands first)

```bash
wget https://gist.github.com/hwdsl2/5a769b2c4436cdf02a90/raw -O vpnsetup-workaround.sh
/bin/sh vpnsetup-workaround.sh
```

### For CentOS and RHEL:

```bash
yum -y install wget nano
wget https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup_centos.sh -O vpnsetup_centos.sh
nano -w vpnsetup_centos.sh
[Edit and replace IPSEC_PSK, VPN_USER and VPN_PASSWORD with your own values]
/bin/sh vpnsetup_centos.sh
```

## Upgrading Libreswan

You may use `vpnupgrade_Libreswan.sh` (for Ubuntu/Debian) and `vpnupgrade_Libreswan_centos.sh` (for CentOS/RHEL) to upgrade <a href="https://libreswan.org/" target="_blank">Libreswan</a> to a newer version. Check and update the `SWAN_VER` variable on top of the scripts as necessary.

## Important Notes

For **Windows users**, a <a href="https://documentation.meraki.com/MX-Z/Client_VPN/Troubleshooting_Client_VPN#Windows_Error_809" target="_blank">one-time registry change</a> is required for connections to a VPN server behind NAT (e.g. Amazon EC2).

To support multiple VPN users with different credentials, just <a href="https://gist.github.com/hwdsl2/123b886f29f4c689f531" target="_blank">edit a few lines</a> in the scripts.

Clients are configured to use <a href="https://developers.google.com/speed/public-dns/" target="_blank">Google Public DNS</a> when the VPN connection is active. This setting is controlled by `ms-dns` in `/etc/ppp/options.xl2tpd`.

If using Amazon EC2, these ports must be open in the instance's security group: **UDP ports 500 & 4500**, and **TCP port 22** (optional, for SSH).

If your server uses a custom SSH port (not 22), or if you wish to allow other services through IPTables, be sure to edit the IPTables rules in the scripts before using.

The scripts will backup files `/etc/rc.local`, `/etc/sysctl.conf`, `/etc/iptables.rules` and `/etc/sysconfig/iptables` before overwriting them. Backups can be found under the same folder with `.old` suffix.

## Copyright and license

Copyright (C) 2014&nbsp;Lin Song&nbsp;&nbsp;&nbsp;<a href="https://www.linkedin.com/in/linsongui" target="_blank"><img src="https://static.licdn.com/scds/common/u/img/webpromo/btn_profile_bluetxt_80x15.png" width="80" height="15" border="0" alt="View my profile on LinkedIn"></a>   
Based on <a href="https://github.com/sarfata/voodooprivacy" target="_blank">the work of Thomas Sarlandie</a> (Copyright 2012)

This work is licensed under the <a href="http://creativecommons.org/licenses/by-sa/3.0/" target="_blank">Creative Commons Attribution-ShareAlike 3.0 Unported License</a>  
Attribution required: please include my name in any derivative and let me know how you have improved it!
