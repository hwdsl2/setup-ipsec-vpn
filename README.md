# IPsec VPN Server Auto Setup Scripts <a href="https://travis-ci.org/hwdsl2/setup-ipsec-vpn"><img align="right" src="https://travis-ci.org/hwdsl2/setup-ipsec-vpn.svg?branch=master" alt="Build status" /></a>

*Read this in other languages: [English](README.md), [简体中文](README-zh.md).*

These scripts will let you set up your own IPsec VPN server, with IPsec/L2TP and Cisco IPsec on Ubuntu, Debian & CentOS. All you need to do is provide your own VPN credentials, and the scripts will handle the rest.

We will use <a href="https://libreswan.org/" target="_blank">Libreswan</a> as the IPsec server, and <a href="https://github.com/xelerance/xl2tpd" target="_blank">xl2tpd</a> as the L2TP provider.

<a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/" target="_blank">**&raquo; Related tutorial: IPsec VPN Server Auto Setup with Libreswan**</a>

#### Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
  - [Ubuntu & Debian](#ubuntu--debian)
  - [CentOS & RHEL](#centos--rhel)
- [Next Steps](#next-steps)
- [Important Notes](#important-notes)
- [Upgrading Libreswan](#upgrading-libreswan)
- [Bugs & Questions](#bugs--questions)
- [See Also](#see-also)
- [Author](#author)
- [License](#license)

## Features

- **NEW:** The faster `IPsec/XAuth ("Cisco IPsec")` mode is now supported
- **NEW:** A pre-built <a href="https://github.com/hwdsl2/docker-ipsec-vpn-server" target="_blank">Docker image</a> of the VPN server is now available
- Fully automated IPsec VPN server setup, no user input needed
- Encapsulates all VPN traffic in UDP - does not need ESP protocol
- Can be directly used as "user-data" for a new Amazon EC2 instance
- Automatically determines public IP and private IP of server
- Includes basic IPTables rules and `sysctl.conf` settings
- Tested with Ubuntu 16.04/14.04/12.04, Debian 8 and CentOS 6 & 7

## Requirements

A newly created <a href="https://aws.amazon.com/ec2/" target="_blank">Amazon EC2</a> instance, using these AMIs: (See <a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#vpnsetup" target="_blank">instructions</a>)
- <a href="https://cloud-images.ubuntu.com/locator/" target="_blank">Ubuntu 16.04 (Xenial), 14.04 (Trusty) or 12.04 (Precise)</a>
- <a href="https://wiki.debian.org/Cloud/AmazonEC2Image" target="_blank">Debian 8 (Jessie) EC2 Images</a>
- <a href="https://aws.amazon.com/marketplace/pp/B00O7WM7QW" target="_blank">CentOS 7 (x86_64) with Updates</a>
- <a href="https://aws.amazon.com/marketplace/pp/B00NQAYLWO" target="_blank">CentOS 6 (x86_64) with Updates</a>

**-OR-**

A dedicated server or KVM/Xen-based Virtual Private Server (VPS), freshly installed with one of the above OS. In addition, Debian 7 (Wheezy) can also be used with <a href="extras/vpnsetup-debian-7-workaround.sh" target="_blank">this workaround</a>. OpenVZ VPS users should instead try <a href="https://github.com/Nyr/openvpn-install" target="_blank">OpenVPN</a>.

<a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#gettingavps" target="_blank">**&raquo; I want to run my own VPN but don't have a server for that**</a>

:warning: **DO NOT** run these scripts on your PC or Mac! They should only be used on a server!

## Installation

### Ubuntu & Debian

First, update your system with `apt-get update && apt-get dist-upgrade` and reboot. This is optional, but recommended.

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

### CentOS & RHEL

First, update your system with `yum update` and reboot. This is optional, but recommended.

Follow the same steps as above, but replace `https://git.io/vpnsetup` with `https://git.io/vpnsetup-centos`.

Note: If unable to download via `wget`, you may also open <a href="vpnsetup.sh" target="_blank">vpnsetup.sh</a> (or <a href="vpnsetup_centos.sh" target="_blank">vpnsetup_centos.sh</a>) and click the **`Raw`** button. Press `Ctrl-A` to select all, `Ctrl-C` to copy, then paste into your favorite editor.

## Next Steps

Get your computer or device to use the VPN. Please refer to:

<a href="docs/clients.md" target="_blank">Configure IPsec/L2TP VPN Clients</a>   
<a href="docs/clients-xauth.md" target="_blank">Configure IPsec/XAuth VPN Clients</a>

Enjoy your very own VPN! :sparkles::tada::rocket::sparkles:

## Important Notes

For **Windows users**, a <a href="docs/clients.md#regkey" target="_blank">one-time registry change</a> is required if the VPN server and/or client is behind NAT (e.g. home router). Also, if you see `Error 628`, open the "Security" tab of VPN connection properties and make sure <a href="https://github.com/hwdsl2/setup-ipsec-vpn/issues/7#issuecomment-182571109" target="_blank">only "CHAP" is selected</a>.

**Android 6 (Marshmallow) users**: Please see notes in <a href="docs/clients.md#android" target="_blank">Configure IPsec/L2TP VPN Clients</a>.

If you wish to add, edit or remove VPN user accounts, refer to <a href="docs/manage-users.md" target="_blank">Manage VPN Users</a>.

Clients are set to use <a href="https://developers.google.com/speed/public-dns/" target="_blank">Google Public DNS</a> when the VPN is active. If another DNS provider is preferred, replace `8.8.8.8` and `8.8.4.4` in both `options.xl2tpd` and `ipsec.conf` with new ones. Then reboot your server.

For servers with a custom SSH port (not 22) or other services, edit IPTables rules in the script before using.

The scripts will backup existing config files before making changes, with `.old-date-time` suffix.

## Upgrading Libreswan

The additional scripts <a href="extras/vpnupgrade_Libreswan.sh" target="_blank">vpnupgrade_Libreswan.sh</a> and <a href="extras/vpnupgrade_Libreswan_centos.sh" target="_blank">vpnupgrade_Libreswan_centos.sh</a> can be used to upgrade Libreswan. Check the <a href="https://libreswan.org" target="_blank">official website</a> and update the `swan_ver` variable as necessary.

## Bugs & Questions

- Got a question? Please first search other people's comments <a href="https://gist.github.com/hwdsl2/9030462#comments" target="_blank">in this Gist</a> and <a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#disqus_thread" target="_blank">on my blog</a>.
- Ask Libreswan (IPsec) related questions <a href="https://lists.libreswan.org/mailman/listinfo/swan" target="_blank">on the mailing list</a>, or read these articles: <a href="https://libreswan.org/wiki/Main_Page" target="_blank">[1]</a> <a href="https://wiki.gentoo.org/wiki/IPsec_L2TP_VPN_server" target="_blank">[2]</a> <a href="https://wiki.archlinux.org/index.php/L2TP/IPsec_VPN_client_setup" target="_blank">[3]</a> <a href="https://help.ubuntu.com/community/L2TPServer" target="_blank">[4]</a> <a href="https://libreswan.org/man/ipsec.conf.5.html" target="_blank">[5]</a>.
- If you found a reproducible bug, open a <a href="https://github.com/hwdsl2/setup-ipsec-vpn/issues?q=is%3Aissue" target="_blank">GitHub Issue</a> to submit a bug report.

## See Also

- [IPsec VPN Server on Docker](https://github.com/hwdsl2/docker-ipsec-vpn-server)
- [For uninstallation see this](/docs/uninstall.md)

## Author

**Lin Song** (linsongui@gmail.com)   
- Final year U.S. PhD candidate, majoring in Electrical and Computer Engineering (ECE)
- Actively seeking opportunities in areas such as Software or Systems Engineering
- Contact me on LinkedIn: <a href="https://www.linkedin.com/in/linsongui" target="_blank">https://www.linkedin.com/in/linsongui</a>

Thanks to [all contributors](https://github.com/hwdsl2/setup-ipsec-vpn/graphs/contributors) of this project!

## License

Copyright (C) 2014-2016&nbsp;Lin Song&nbsp;&nbsp;&nbsp;<a href="https://www.linkedin.com/in/linsongui" target="_blank"><img src="https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png" width="160" height="25" border="0" alt="View my profile on LinkedIn"></a>    
Based on <a href="https://github.com/sarfata/voodooprivacy" target="_blank">the work of Thomas Sarlandie</a> (Copyright 2012)

This work is licensed under the <a href="http://creativecommons.org/licenses/by-sa/3.0/" target="_blank">Creative Commons Attribution-ShareAlike 3.0 Unported License</a>  
Attribution required: please include my name in any derivative and let me know how you have improved it!
