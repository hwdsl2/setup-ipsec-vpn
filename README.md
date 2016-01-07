# IPsec/L2TP VPN Server Auto Setup Scripts

Note: This repository was created from and replaces these GitHub Gists:
- https://gist.github.com/hwdsl2/9030462 (224 Stars, 87 Forks)
- https://gist.github.com/hwdsl2/e9a78a50e300d12ae195 (9 Stars, 5 Forks)

Scripts for automatic setup of an IPsec/L2TP VPN server on Ubuntu 14.04 & 12.04, Debian 8 and CentOS/RHEL 6 & 7. Works on dedicated servers or any KVM- or XEN-based Virtual Private Server (VPS), with **freshly installed** Linux OS.

They can also be used as Amazon EC2 "user-data" with the <a href="https://cloud-images.ubuntu.com/locator/ec2/" target="_blank">Ubuntu 14.04/12.04</a>, <a href="https://wiki.debian.org/Cloud/AmazonEC2Image/Jessie" target="_blank">Debian 8</a> or <a href="https://aws.amazon.com/marketplace/pp/B00O7WM7QW" target="_blank">CentOS 7</a> AMIs.

Do **NOT** run these scripts on your PC or Mac! They are meant to be run on a dedicated server or VPS.

#### <a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/" target="_blank">My VPN tutorial with detailed usage instructions</a>  
<a href="https://gist.github.com/hwdsl2/123b886f29f4c689f531" target="_blank">Enable multiple VPN users with different credentials</a>  
<a href="https://gist.github.com/hwdsl2/5a769b2c4436cdf02a90" target="_blank">Workaround for Debian 7 (Wheezy)</a>  
<a href="http://www.sarfata.org/posts/setting-up-an-amazon-vpn-server.md" target="_blank">Original post by Thomas Sarlandie</a>

## Installation

### For Ubuntu and Debian:

```bash
wget https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup.sh -O vpnsetup.sh
nano -w vpnsetup.sh
[Edit and replace IPSEC_PSK, VPN_USER and VPN_PASSWORD with your own values]
/bin/sh vpnsetup.sh
```

### For CentOS and RHEL:

```bash
wget https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup_centos.sh -O vpnsetup_centos.sh
nano -w vpnsetup_centos.sh
[Edit and replace IPSEC_PSK, VPN_USER and VPN_PASSWORD with your own values]
/bin/sh vpnsetup_centos.sh
```

## Important Notes

For Windows users, a <a href="https://documentation.meraki.com/MX-Z/Client_VPN/Troubleshooting_Client_VPN#Windows_Error_809" target="_blank">one-time registry change</a> is required for connections to a VPN server behind NAT (e.g. Amazon EC2).

If using Amazon EC2, these ports must be open in the security group of your VPN server: UDP ports 500 & 4500, and TCP port 22 (optional, for SSH).

If your server uses a custom SSH port (not 22), or if you wish to allow other services through IPTables, be sure to edit the IPTables rules in the scripts before using.

The scripts will backup /etc/rc.local, /etc/sysctl.conf, /etc/iptables.rules and /etc/sysconfig/iptables before overwriting them. Backups can be found under the same folder with .old suffix.

## Copyright and license

Copyright (C) 2014&nbsp;Lin Song&nbsp;&nbsp;&nbsp;<a href="https://www.linkedin.com/in/linsongui" target="_blank"><img src="https://static.licdn.com/scds/common/u/img/webpromo/btn_profile_bluetxt_80x15.png" width="80" height="15" border="0" alt="View my profile on LinkedIn"></a>   
Based on the work of Thomas Sarlandie (Copyright 2012)

This work is licensed under the <a href="http://creativecommons.org/licenses/by-sa/3.0/" target="_blank">Creative Commons Attribution-ShareAlike 3.0</a>  
Attribution required: please include my name in any derivative and let me know how you have improved it!
