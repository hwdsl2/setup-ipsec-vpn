# IPsec VPN Server Auto Setup Scripts

[![Build Status](https://img.shields.io/github/workflow/status/hwdsl2/setup-ipsec-vpn/vpn%20test.svg?cacheSeconds=3600)](https://github.com/hwdsl2/setup-ipsec-vpn/actions) [![GitHub Stars](https://img.shields.io/github/stars/hwdsl2/setup-ipsec-vpn.svg?cacheSeconds=86400)](https://github.com/hwdsl2/setup-ipsec-vpn/stargazers) [![Docker Stars](https://img.shields.io/docker/stars/hwdsl2/ipsec-vpn-server.svg?cacheSeconds=86400)](https://github.com/hwdsl2/docker-ipsec-vpn-server) [![Docker Pulls](https://img.shields.io/docker/pulls/hwdsl2/ipsec-vpn-server.svg?cacheSeconds=86400)](https://github.com/hwdsl2/docker-ipsec-vpn-server)

Set up your own IPsec VPN server in just a few minutes, with IPsec/L2TP, Cisco IPsec and IKEv2 on Ubuntu, Debian and CentOS. All you need to do is provide your own VPN credentials, and let the scripts handle the rest.

An IPsec VPN encrypts your network traffic, so that nobody between you and the VPN server can eavesdrop on your data as it travels via the Internet. This is especially useful when using unsecured networks, e.g. at coffee shops, airports or hotel rooms.

We will use [Libreswan](https://libreswan.org/) as the IPsec server, and [xl2tpd](https://github.com/xelerance/xl2tpd) as the L2TP provider.

[**&raquo; See also: IPsec VPN Server on Docker**](https://github.com/hwdsl2/docker-ipsec-vpn-server)

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
wget https://git.io/vpnsetup -O vpn.sh && sudo sh vpn.sh && sudo ikev2.sh --auto
```
</details>

<details>
<summary>
CentOS & RHEL
</summary>

```bash
wget https://git.io/vpnsetup-centos -O vpn.sh && sudo sh vpn.sh && sudo ikev2.sh --auto
```
</details>

<details>
<summary>
Amazon Linux 2
</summary>

```bash
wget https://git.io/vpnsetup-amzn -O vpn.sh && sudo sh vpn.sh && sudo ikev2.sh --auto
```
</details>

Your VPN login details will be randomly generated, and displayed on the screen when finished.

For other installation options and how to set up VPN clients, read the sections below.

\* A dedicated server or virtual private server (VPS). OpenVZ VPS is not supported.

## Features

- **New:** The faster IPsec/XAuth ("Cisco IPsec") and IKEv2 modes are supported
- **New:** A pre-built [Docker image](https://github.com/hwdsl2/docker-ipsec-vpn-server) of the VPN server is now available
- Fully automated IPsec VPN server setup, no user input needed
- Encapsulates all VPN traffic in UDP - does not need ESP protocol
- Can be directly used as "user-data" for a new Amazon EC2 instance
- Includes `sysctl.conf` optimizations for improved performance
- Tested with Ubuntu, Debian, CentOS/RHEL and Amazon Linux 2

## Requirements

A newly created [Amazon EC2](https://aws.amazon.com/ec2/) instance, from one of these images:
- [Ubuntu 20.04 (Focal) or 18.04 (Bionic)](https://cloud-images.ubuntu.com/locator/)
- [Debian 10 (Buster)](https://wiki.debian.org/Cloud/AmazonEC2Image)[\*](#debian-10-note)[ or 9 (Stretch)](https://wiki.debian.org/Cloud/AmazonEC2Image)
- [CentOS 8](https://wiki.centos.org/Cloud/AWS)[\*\*](#centos-8-note)[ or 7](https://wiki.centos.org/Cloud/AWS)
- [Red Hat Enterprise Linux (RHEL) 8 or 7](https://aws.amazon.com/partners/redhat/faqs/)
- [Amazon Linux 2](https://aws.amazon.com/amazon-linux-2/)

See [detailed instructions](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#vpnsetup) and [EC2 pricing](https://aws.amazon.com/ec2/pricing/). Alternatively, you may also deploy rapidly using [CloudFormation](aws/README.md).

**-OR-**

A dedicated server or virtual private server (VPS), freshly installed with one of the above OS. OpenVZ VPS is not supported, users could instead try [OpenVPN](https://github.com/Nyr/openvpn-install).

This also includes Linux VMs in public clouds, such as [DigitalOcean](https://blog.ls20.com/digitalocean), [Vultr](https://blog.ls20.com/vultr), [Linode](https://blog.ls20.com/linode), [Google Compute Engine](https://cloud.google.com/compute/), [Amazon Lightsail](https://aws.amazon.com/lightsail/), [Microsoft Azure](https://azure.microsoft.com), [IBM Cloud](https://www.ibm.com/cloud/virtual-servers), [OVH](https://www.ovh.com/world/vps/) and [Rackspace](https://www.rackspace.com).

[![Deploy to AWS](docs/images/aws-deploy-button.png)](aws/README.md) [![Deploy to Azure](docs/images/azure-deploy-button.png)](azure/README.md) [![Deploy to DigitalOcean](docs/images/do-install-button.png)](http://dovpn.carlfriess.com/) [![Deploy to Linode](docs/images/linode-deploy-button.png)](https://cloud.linode.com/stackscripts/37239)

[**&raquo; I want to run my own VPN but don't have a server for that**](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#gettingavps)

Advanced users can set up the VPN server on a $35 [Raspberry Pi](https://www.raspberrypi.org). See [[1]](https://elasticbyte.net/posts/setting-up-a-native-cisco-ipsec-vpn-server-using-a-raspberry-pi/) [[2]](https://www.stewright.me/2018/07/create-a-raspberry-pi-vpn-server-using-l2tpipsec/).

<a name="debian-10-note"></a>
\* Debian 10 users should use the standard Linux kernel (not the "cloud" version). Read more [here](docs/clients.md#debian-10-kernel). If using Debian 10 on EC2, you must first switch to the standard Linux kernel before running the VPN setup script.   
<a name="centos-8-note"></a>
\*\* Support for CentOS Linux 8 will end on December 31, 2021. Read more [here](https://wiki.centos.org/About/Product).   

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

After successful installation, it is recommended to [set up IKEv2](docs/ikev2-howto.md):

```bash
sudo ikev2.sh --auto
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

After successful installation, it is recommended to [set up IKEv2](docs/ikev2-howto.md):

```bash
sudo ikev2.sh --auto
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

After successful installation, it is recommended to [set up IKEv2](docs/ikev2-howto.md):

```bash
sudo ikev2.sh --auto
```

**Note:** If unable to download via `wget`, you may also open [vpnsetup.sh](vpnsetup.sh), [vpnsetup_centos.sh](vpnsetup_centos.sh) or [vpnsetup_amzn.sh](vpnsetup_amzn.sh), and click the **`Raw`** button on the right. Press `Ctrl-A` to select all, `Ctrl-C` to copy, then paste into your favorite editor.

## Next steps

Get your computer or device to use the VPN. Please refer to:

[**Configure IPsec/L2TP VPN Clients**](docs/clients.md)

[**Configure IPsec/XAuth ("Cisco IPsec") VPN Clients**](docs/clients-xauth.md)

[**Guide: How to Set Up and Use IKEv2 VPN**](docs/ikev2-howto.md)

If you get an error when trying to connect, see [Troubleshooting](docs/clients.md#troubleshooting).

Enjoy your very own VPN! :sparkles::tada::rocket::sparkles:

## Important notes

*Read this in other languages: [English](README.md#important-notes), [简体中文](README-zh.md#重要提示).*

**Windows users**: A [one-time registry change](docs/clients.md#windows-error-809) is required if the VPN server or client is behind NAT (e.g. home router).

**Android users**: If you encounter connection issues, try [these steps](docs/clients.md#android-mtumss-issues).

The same VPN account can be used by your multiple devices. However, due to an IPsec/L2TP limitation, if you wish to connect multiple devices simultaneously from behind the same NAT (e.g. home router), you must use only [IPsec/XAuth mode](docs/clients-xauth.md), or [set up IKEv2](docs/ikev2-howto.md).

If you wish to view or update VPN user accounts, see [Manage VPN Users](docs/manage-users.md). Helper scripts are included for convenience.

For servers with an external firewall (e.g. [EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html)/[GCE](https://cloud.google.com/vpc/docs/firewalls)), open UDP ports 500 and 4500 for the VPN. Aliyun users, see [#433](https://github.com/hwdsl2/setup-ipsec-vpn/issues/433).

Clients are set to use [Google Public DNS](https://developers.google.com/speed/public-dns/) when the VPN is active. If another DNS provider is preferred, [read below](#use-alternative-dns-servers).

Using kernel support could improve IPsec/L2TP performance. It is available on [all supported OS](#requirements). Ubuntu users should install the `linux-modules-extra-$(uname -r)` (or `linux-image-extra`) package and run `service xl2tpd restart`.

The scripts will backup existing config files before making changes, with `.old-date-time` suffix.

## Upgrade Libreswan

The additional scripts in [extras/](extras/) can be used to upgrade [Libreswan](https://libreswan.org) ([changelog](https://github.com/libreswan/libreswan/blob/master/CHANGES) | [announce](https://lists.libreswan.org/mailman/listinfo/swan-announce)). Edit the `SWAN_VER` variable as necessary. The latest supported version is `4.4`. Check which version is installed: `ipsec --version`.

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
- [Internal VPN IPs and traffic](#internal-vpn-ips-and-traffic)
- [Split tunneling](#split-tunneling)
- [Access VPN server's subnet](#access-vpn-servers-subnet)
- [IKEv2 only VPN](#ikev2-only-vpn)
- [Modify IPTables rules](#modify-iptables-rules)

### Use alternative DNS servers

Clients are set to use [Google Public DNS](https://developers.google.com/speed/public-dns/) when the VPN is active. If another DNS provider is preferred, you may replace `8.8.8.8` and `8.8.4.4` in these files: `/etc/ppp/options.xl2tpd`, `/etc/ipsec.conf` and `/etc/ipsec.d/ikev2.conf` (if exists). Then run `service ipsec restart` and `service xl2tpd restart`.

Advanced users can define `VPN_DNS_SRV1` and optionally `VPN_DNS_SRV2` when running the VPN setup script and the [IKEv2 helper script](docs/ikev2-howto.md#using-helper-scripts). For example, if you want to use [Cloudflare's DNS service](https://1.1.1.1):

```
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 sh vpn.sh
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 ikev2.sh --auto
```

### DNS name and server IP changes

For [IPsec/L2TP](docs/clients.md) and [IPsec/XAuth ("Cisco IPsec")](docs/clients-xauth.md) modes, you may use a DNS name (e.g. `vpn.example.com`) instead of an IP address to connect to the VPN server, without additional configuration. In addition, the VPN should generally continue to work after server IP changes, such as after restoring a snapshot to a new server with a different IP, although a reboot may be required.

For [IKEv2](docs/ikev2-howto.md) mode, if you want the VPN to continue to work after server IP changes, you must specify a DNS name to be used as the VPN server's address when [setting up IKEv2](docs/ikev2-howto.md). The DNS name must be a fully qualified domain name (FQDN). Example:

```
sudo VPN_DNS_NAME='vpn.example.com' ikev2.sh --auto
```

Alternatively, you may customize IKEv2 setup options by running the [helper script](docs/ikev2-howto.md#using-helper-scripts) without the `--auto` parameter.

### Internal VPN IPs and traffic

When connecting using [IPsec/L2TP](docs/clients.md) mode, the VPN server has internal IP `192.168.42.1` within the VPN subnet `192.168.42.0/24`. Clients are assigned internal IPs from `192.168.42.10` to `192.168.42.250`. To check which IP is assigned to a client, view the connection status on the VPN client.

When connecting using [IPsec/XAuth ("Cisco IPsec")](docs/clients-xauth.md) or [IKEv2](docs/ikev2-howto.md) mode, the VPN server does NOT have an internal IP within the VPN subnet `192.168.43.0/24`. Clients are assigned internal IPs from `192.168.43.10` to `192.168.43.250`.

You may use these internal VPN IPs for communication. However, note that the IPs assigned to VPN clients are dynamic, and firewalls on client devices may block such traffic.

For the IPsec/L2TP and IPsec/XAuth ("Cisco IPsec") modes, advanced users may optionally assign static IPs to VPN clients. Expand for details. IKEv2 mode does NOT support this feature.

<details>
<summary>
IPsec/L2TP mode: Assign static IPs to VPN clients
</summary>

The example below **ONLY** applies to IPsec/L2TP mode. Commands must be run as `root`.

1. First, create a new VPN user for each VPN client that you want to assign a static IP to. Refer to [Manage VPN Users](docs/manage-users.md). Helper scripts are included for convenience.
1. Edit `/etc/xl2tpd/xl2tpd.conf` on the VPN server. Replace `ip range = 192.168.42.10-192.168.42.250` with e.g. `ip range = 192.168.42.100-192.168.42.250`. This reduces the pool of auto-assigned IP addresses, so that more IPs are available to assign to clients as static IPs.
1. Edit `/etc/ppp/chap-secrets` on the VPN server. For example, if the file contains:
   ```
   "username1"  l2tpd  "password1"  *
   "username2"  l2tpd  "password2"  *
   "username3"  l2tpd  "password3"  *
   ```

   Let's assume that you want to assign static IP `192.168.42.2` to VPN user `username2`, assign static IP `192.168.42.3` to VPN user `username3`, while keeping `username1` unchanged (auto-assign from the pool). After editing, the file should look like:
   ```
   "username1"  l2tpd  "password1"  *
   "username2"  l2tpd  "password2"  192.168.42.2
   "username3"  l2tpd  "password3"  192.168.42.3
   ```

   **Note:** The assigned static IP(s) must be from the subnet `192.168.42.0/24`, and must NOT be from the pool of auto-assigned IPs (see `ip range` above). In addition, `192.168.42.1` is reserved for the VPN server itself. In the example above, you can only assign static IP(s) from the range `192.168.42.2-192.168.42.99`.
1. **(Important)** Restart the xl2tpd service:
   ```
   service xl2tpd restart
   ```
</details>

<details>
<summary>
IPsec/XAuth ("Cisco IPsec") mode: Assign static IPs to VPN clients
</summary>

The example below **ONLY** applies to IPsec/XAuth ("Cisco IPsec") mode. Commands must be run as `root`.

1. First, create a new VPN user for each VPN client that you want to assign a static IP to. Refer to [Manage VPN Users](docs/manage-users.md). Helper scripts are included for convenience.
1. Edit `/etc/ipsec.conf` on the VPN server. Replace `rightaddresspool=192.168.43.10-192.168.43.250` with e.g. `rightaddresspool=192.168.43.100-192.168.43.250`. This reduces the pool of auto-assigned IP addresses, so that more IPs are available to assign to clients as static IPs.
1. Edit `/etc/ipsec.d/ikev2.conf` on the VPN server (if exists). Replace `rightaddresspool=192.168.43.10-192.168.43.250` with the **same value** as the previous step.
1. Edit `/etc/ipsec.d/passwd` on the VPN server. For example, if the file contains:
   ```
   username1:password1hashed:xauth-psk
   username2:password2hashed:xauth-psk
   username3:password3hashed:xauth-psk
   ```

   Let's assume that you want to assign static IP `192.168.43.2` to VPN user `username2`, assign static IP `192.168.43.3` to VPN user `username3`, while keeping `username1` unchanged (auto-assign from the pool). After editing, the file should look like:
   ```
   username1:password1hashed:xauth-psk
   username2:password2hashed:xauth-psk:192.168.42.2
   username3:password3hashed:xauth-psk:192.168.42.3
   ```

   **Note:** The assigned static IP(s) must be from the subnet `192.168.43.0/24`, and must NOT be from the pool of auto-assigned IPs (see `rightaddresspool` above). In the example above, you can only assign static IP(s) from the range `192.168.43.1-192.168.43.99`.
1. **(Important)** Restart the IPsec service:
   ```
   service ipsec restart
   ```
</details>

Client-to-client traffic is allowed by default. If you want to **disallow** client-to-client traffic, run the following commands on the VPN server. Add them to `/etc/rc.local` to persist after reboot.

```
iptables -I FORWARD 2 -i ppp+ -o ppp+ -s 192.168.42.0/24 -d 192.168.42.0/24 -j DROP
iptables -I FORWARD 3 -s 192.168.43.0/24 -d 192.168.43.0/24 -j DROP
```

### Split tunneling

With [split tunneling](https://wiki.strongswan.org/projects/strongswan/wiki/ForwardingAndSplitTunneling#Split-Tunneling), VPN clients will only send traffic for specific destination subnet(s) through the VPN tunnel. Other traffic will NOT go through the VPN tunnel. Split tunneling has [some limitations](https://wiki.strongswan.org/projects/strongswan/wiki/ForwardingAndSplitTunneling#Split-Tunneling), and is not supported by all VPN clients.

Advanced users can optionally enable split tunneling for the [IPsec/XAuth ("Cisco IPsec")](docs/clients-xauth.md) and/or [IKEv2](docs/ikev2-howto.md) modes. Expand for details. IPsec/L2TP mode does NOT support this feature.

<details>
<summary>
IPsec/XAuth ("Cisco IPsec") mode: Enable split tunneling
</summary>

The example below **ONLY** applies to IPsec/XAuth ("Cisco IPsec") mode. Commands must be run as `root`.

1. Edit `/etc/ipsec.conf` on the VPN server. In the section `conn xauth-psk`, replace `leftsubnet=0.0.0.0/0` with the subnet(s) you want VPN clients to send traffic through the VPN tunnel. For example:   
   For a single subnet:
   ```
   leftsubnet=10.123.123.0/24
   ```
   For multiple subnets (use `leftsubnets` instead):
   ```
   leftsubnets="10.123.123.0/24,10.100.0.0/16"
   ```
1. **(Important)** Restart the IPsec service:
   ```
   service ipsec restart
   ```
</details>

<details>
<summary>
IKEv2 mode: Enable split tunneling
</summary>

The example below **ONLY** applies to IKEv2 mode. Commands must be run as `root`.

1. Edit `/etc/ipsec.d/ikev2.conf` on the VPN server. In the section `conn ikev2-cp`, replace `leftsubnet=0.0.0.0/0` with the subnet(s) you want VPN clients to send traffic through the VPN tunnel. For example:   
   For a single subnet:
   ```
   leftsubnet=10.123.123.0/24
   ```
   For multiple subnets (use `leftsubnets` instead):
   ```
   leftsubnets="10.123.123.0/24,10.100.0.0/16"
   ```
1. **(Important)** Restart the IPsec service:
   ```
   service ipsec restart
   ```
</details>

### Access VPN server's subnet

After connecting to the VPN, VPN clients can generally access services running on other devices that are within the same local subnet as the VPN server, without additional configuration. For example, if the VPN server's local subnet is `192.168.0.0/24`, and an Nginx server is running on IP `192.168.0.2`, VPN clients can use IP `192.168.0.2` to access the Nginx server.

Please note, additional configuration is required if the VPN server has multiple network interfaces (e.g. `eth0` and `eth1`), and you want VPN clients to access the local subnet behind the network interface that is NOT for Internet access. In this scenario, you must run the following commands to add IPTables rules. To persist after reboot, you may add these commands to `/etc/rc.local`.

```bash
# Replace eth1 with the name of the network interface
# on the VPN server that you want VPN clients to access
netif=eth1
iptables -I FORWARD 2 -i "$netif" -o ppp+ -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -I FORWARD 2 -i ppp+ -o "$netif" -j ACCEPT
iptables -I FORWARD 2 -i "$netif" -d 192.168.43.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -I FORWARD 2 -s 192.168.43.0/24 -o "$netif" -j ACCEPT
iptables -t nat -I POSTROUTING -s 192.168.43.0/24 -o "$netif" -m policy --dir out --pol none -j MASQUERADE
iptables -t nat -I POSTROUTING -s 192.168.42.0/24 -o "$netif" -j MASQUERADE
```

### IKEv2 only VPN

Libreswan 4.2 and newer versions support the `ikev1-policy` config option. Using this option, advanced users can set up an IKEv2-only VPN, i.e. only IKEv2 connections are accepted by the VPN server, while IKEv1 connections (including the IPsec/L2TP and IPsec/XAuth ("Cisco IPsec") modes) are dropped.

To set up an IKEv2-only VPN, first install the VPN server and set up IKEv2 using instructions in this README. Then check Libreswan version using `ipsec --version`, and [update Libreswan](#upgrade-libreswan) if needed. After that, edit `/etc/ipsec.conf` on the VPN server. Append `ikev1-policy=drop` to the end of the `config setup` section, indented by two spaces. Save the file and run `service ipsec restart`. When finished, you can run `ipsec status` to verify that only the `ikev2-cp` connection is enabled.

### Modify IPTables rules

If you want to modify the IPTables rules after install, edit `/etc/iptables.rules` and/or `/etc/iptables/rules.v4` (Ubuntu/Debian), or `/etc/sysconfig/iptables` (CentOS/RHEL). Then reboot your server.

## Bugs & Questions

- Got a question? Please first search other people's comments [in this Gist](https://gist.github.com/hwdsl2/9030462#comments) and [on my blog](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#disqus_thread).
- Ask VPN related questions on the [Libreswan](https://lists.libreswan.org/mailman/listinfo/swan) or [strongSwan](https://lists.strongswan.org/mailman/listinfo/users) mailing list, or read these wikis: [[1]](https://libreswan.org/wiki/Main_Page) [[2]](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/sec-securing_virtual_private_networks) [[3]](https://wiki.strongswan.org/projects/strongswan/wiki/UserDocumentation) [[4]](https://wiki.gentoo.org/wiki/IPsec_L2TP_VPN_server) [[5]](https://wiki.archlinux.org/index.php/Openswan_L2TP/IPsec_VPN_client_setup).
- If you found a reproducible bug, open a [GitHub Issue](https://github.com/hwdsl2/setup-ipsec-vpn/issues?q=is%3Aissue) to submit a bug report.

## Uninstallation

See [Uninstall the VPN](docs/uninstall.md).

## See also

- [IPsec VPN Server on Docker](https://github.com/hwdsl2/docker-ipsec-vpn-server)

## License

Copyright (C) 2014-2021 [Lin Song](https://github.com/hwdsl2) [![View my profile on LinkedIn](https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png)](https://www.linkedin.com/in/linsongui)   
Based on [the work of Thomas Sarlandie](https://github.com/sarfata/voodooprivacy) (Copyright 2012)

[![Creative Commons License](https://i.creativecommons.org/l/by-sa/3.0/88x31.png)](http://creativecommons.org/licenses/by-sa/3.0/)   
This work is licensed under the [Creative Commons Attribution-ShareAlike 3.0 Unported License](http://creativecommons.org/licenses/by-sa/3.0/)  
Attribution required: please include my name in any derivative and let me know how you have improved it!
