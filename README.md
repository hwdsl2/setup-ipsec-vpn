# IPsec/L2TP VPN Server Auto Setup Scripts

Scripts for automatic configuration of IPsec/L2TP VPN server on Ubuntu 14.04 & 12.04, Debian 8 and CentOS/RHEL 6 & 7. All you need to do is providing your own values for `IPSEC_PSK`, `VPN_USER` and `VPN_PASSWORD`, and let them handle the rest.

We will use <a href="https://libreswan.org/" target="_blank">Libreswan</a> as the IPsec server, and <a href="https://www.xelerance.com/services/software/xl2tpd/" target="_blank">xl2tpd</a> as the L2TP provider. 

#### <a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/" target="_blank">Link to my VPN tutorial with detailed usage instructions</a>

## Features

- Fully automated IPsec/L2TP VPN server setup, no user input needed
- Encapsulates all VPN traffic in UDP - does not need ESP protocol
- Can be directly used as "user-data" for a new Amazon EC2 instance
- Automatically determines public IP and private IP of server
- Includes basic IPTables rules and `sysctl.conf` settings
- Tested with Ubuntu 14.04 & 12.04, Debian 8 and CentOS 6 & 7

## Requirements

A newly created <a href="https://aws.amazon.com/ec2/" target="_blank">Amazon EC2</a> instance, using these AMIs: (See <a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#vpnsetup" target="_blank">instructions</a>)
- <a href="http://cloud-images.ubuntu.com/trusty/current/" target="_blank">Ubuntu 14.04 (Trusty)</a> or <a href="http://cloud-images.ubuntu.com/precise/current/" target="_blank">12.04 (Precise)</a>
- <a href="https://wiki.debian.org/Cloud/AmazonEC2Image/Jessie" target="_blank">Debian 8 (Jessie) EC2 Images</a>
- <a href="https://aws.amazon.com/marketplace/pp/B00O7WM7QW" target="_blank">CentOS 7 (x86_64) with Updates HVM</a>
- <a href="https://aws.amazon.com/marketplace/pp/B00NQAYLWO" target="_blank">CentOS 6 (x86_64) with Updates HVM</a>

**-OR-**

A dedicated server or KVM/Xen-based Virtual Private Server (VPS), running one of these OS:   
&nbsp;(Note: Using the VPN scripts on a freshly installed system is recommended)
- Ubuntu 14.04 (Trusty) or 12.04 (Precise)
- Debian 8 (Jessie)
- Debian 7 (Wheezy) - Not recommended. Requires <a href="https://gist.github.com/hwdsl2/5a769b2c4436cdf02a90" target="_blank">this workaround</a> to work.
- CentOS / Red Hat Enterprise Linux (RHEL) 6 or 7

OpenVZ VPS users should instead try <a href="https://github.com/Nyr/openvpn-install" target="_blank">Nyr's OpenVPN script</a>.

<a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#gettingavps" target="_blank">**&raquo; I want to run my own VPN but don't have a server for that**</a>

:warning: **DO NOT run these scripts on your PC or Mac! They should only be run on a dedicated server or VPS!**

## Installation

### For Ubuntu and Debian:

First, update your system with `apt-get update && apt-get dist-upgrade` and reboot. This is optional, but recommended.

```bash
wget https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup.sh -O vpnsetup.sh
nano -w vpnsetup.sh
[Edit and replace IPSEC_PSK, VPN_USER and VPN_PASSWORD with your own values]
/bin/sh vpnsetup.sh
```

### For CentOS and RHEL:

First, update your system with `yum update` and reboot. This is optional, but recommended.

```bash
yum -y install wget nano
wget https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup_centos.sh -O vpnsetup_centos.sh
nano -w vpnsetup_centos.sh
[Edit and replace IPSEC_PSK, VPN_USER and VPN_PASSWORD with your own values]
/bin/sh vpnsetup_centos.sh
```

If unable to download via `wget`, you may alternatively open [vpnsetup.sh](vpnsetup.sh) (or [vpnsetup_centos.sh](vpnsetup_centos.sh)) and click the **`Raw`** button. Press `Ctrl+A` to select all, `Ctrl-C` to copy, then paste into your favorite editor.

## Next Steps

Get your computer to use the VPN. Search the web for instructions, e.g. https://www.google.com/search?q=setup+l2tp+client

Enjoy your very own VPN! :sparkles::tada::rocket::sparkles:

## Important Notes

For **Windows users**, a <a href="https://documentation.meraki.com/MX-Z/Client_VPN/Troubleshooting_Client_VPN#Windows_Error_809" target="_blank">one-time registry change</a> is required if the VPN server and/or client is behind NAT (e.g. home router). In addition, make sure `CHAP` <a href="https://github.com/hwdsl2/setup-ipsec-vpn/issues/7#issuecomment-182571109" target="_blank">is enabled</a> under "Allow these protocols" in the "Security" tab of VPN connection properties.

**Android 6 (Marshmallow) users**: After install, edit `/etc/ipsec.conf` and append `,aes256-sha2_256` to both `ike=` and `phase2alg=`. Then <a href="https://libreswan.org/wiki/FAQ#Android_6.0_connection_comes_up_but_no_packet_flow" target="_blank">add a new line</a> `sha2-truncbug=yes`. Indent lines with two spaces. Finally, run `service ipsec restart`.

**iPhone/iPad users**: In iOS settings, choose `L2TP` (instead of `IPSec`) as the VPN type. In case you are unable to connect, edit `ipsec.conf` and replace `rightprotoport=17/%any` with `rightprotoport=17/0`. Then restart `ipsec` service.

If you wish to enable multiple VPN users with different credentials, just <a href="https://gist.github.com/hwdsl2/123b886f29f4c689f531" target="_blank">edit a few lines</a> in the scripts.

Clients are configured to use <a href="https://developers.google.com/speed/public-dns/" target="_blank">Google Public DNS</a> when the VPN is active. To change, set `ms-dns` in `options.xl2tpd`.

If using Amazon EC2, open **UDP ports 500 & 4500** and **TCP port 22** (optional, for SSH) in the instance's <a href="https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-network-security.html" target="_blank">security group</a>.

If you configured a custom SSH port or wish to allow other services, edit the IPTables rules within the scripts before using.

The scripts will backup your existing config files before making changes, to the same folder with `.old-date-time` suffix.

## Upgrading Libreswan

The additional scripts [vpnupgrade_Libreswan.sh](vpnupgrade_Libreswan.sh) and [vpnupgrade_Libreswan_centos.sh](vpnupgrade_Libreswan_centos.sh) can be used to periodically upgrade Libreswan to the latest version. Check the <a href="https://libreswan.org" target="_blank">official website</a> and update the `SWAN_VER` variable as necessary.

## Bugs & Questions

- Have a question? Please first search other people's comments <a href="https://gist.github.com/hwdsl2/9030462#comments" target="_blank">in this Gist</a> and <a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#disqus_thread" target="_blank">on my blog</a>.
- Ask Libreswan (IPsec) related questions <a href="https://lists.libreswan.org/mailman/listinfo/swan" target="_blank">on this mailing list</a>, or check out its <a href="https://libreswan.org/wiki/Main_Page" target="_blank">official wiki</a>.
- If you found a reproducible bug, open a <a href="https://github.com/hwdsl2/setup-ipsec-vpn/issues" target="_blank">GitHub Issue</a> to submit a bug report.

## Copyright and License

Copyright (C) 2014-2016&nbsp;Lin Song&nbsp;&nbsp;&nbsp;<a href="https://www.linkedin.com/in/linsongui" target="_blank"><img src="https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png" width="160" height="25" border="0" alt="View my profile on LinkedIn"></a>    
Based on <a href="https://github.com/sarfata/voodooprivacy" target="_blank">the work of Thomas Sarlandie</a> (Copyright 2012)

This work is licensed under the <a href="http://creativecommons.org/licenses/by-sa/3.0/" target="_blank">Creative Commons Attribution-ShareAlike 3.0 Unported License</a>  
Attribution required: please include my name in any derivative and let me know how you have improved it!
