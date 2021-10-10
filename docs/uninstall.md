# Uninstall the VPN

*Read this in other languages: [English](uninstall.md), [简体中文](uninstall-zh.md).*

* [Uninstall using helper script](#uninstall-using-helper-script)
* [Manually uninstall the VPN](#manually-uninstall-the-vpn)

## Uninstall using helper script

**Warning:** This [helper script](../extras/vpnuninstall.sh) will remove IPsec VPN from your server. All VPN configuration will be **permanently deleted**, and Libreswan and xl2tpd will be removed. This **cannot be undone**!

```bash
wget https://git.io/vpnuninstall -O vpnunst.sh
sudo bash vpnunst.sh
```

When finished, reboot your server.

## Manually uninstall the VPN

Alternatively, you may manually uninstall the VPN by following these steps. Commands must be run as `root`, or with `sudo`.

**Warning:** These steps will remove IPsec VPN from your server. All VPN configuration will be **permanently deleted**, and Libreswan and xl2tpd will be removed. This **cannot be undone**!

### Steps

* [First step](#first-step)
* [Second step](#second-step)
* [Third step](#third-step)
* [Fourth step](#fourth-step)
* [Optional](#optional)
* [When finished](#when-finished)

### First step

```bash
service ipsec stop
service xl2tpd stop
rm -rf /usr/local/sbin/ipsec /usr/local/libexec/ipsec /usr/local/share/doc/libreswan
rm -f /etc/init/ipsec.conf /lib/systemd/system/ipsec.service /etc/init.d/ipsec \
      /usr/lib/systemd/system/ipsec.service /etc/logrotate.d/libreswan \
      /usr/lib/tmpfiles.d/libreswan.conf
```

### Second step

#### Ubuntu & Debian

`apt-get purge xl2tpd`

#### CentOS/RHEL, Rocky Linux, AlmaLinux & Amazon Linux 2

`yum remove xl2tpd`

#### Alpine Linux

`apk del xl2tpd`

### Third step

#### Ubuntu, Debian & Alpine Linux

Edit `/etc/iptables.rules` and remove unneeded rules. Your original rules (if any) are backed up as `/etc/iptables.rules.old-date-time`. In addition, edit `/etc/iptables/rules.v4` if the file exists.   

#### CentOS/RHEL, Rocky Linux, AlmaLinux & Amazon Linux 2

Edit `/etc/sysconfig/iptables` and remove unneeded rules. Your original rules (if any) are backed up as `/etc/sysconfig/iptables.old-date-time`.

**Note:** If using Rocky Linux, AlmaLinux or CentOS/RHEL 8 and firewalld was active during VPN setup, nftables may be configured. Edit `/etc/sysconfig/nftables.conf` and remove unneeded rules. Your original rules are backed up as `/etc/sysconfig/nftables.conf.old-date-time`.

### Fourth step

Edit `/etc/sysctl.conf` and remove the lines after `# Added by hwdsl2 VPN script`.   
Edit `/etc/rc.local` and remove the lines after `# Added by hwdsl2 VPN script`. DO NOT remove `exit 0` (if any).

### Optional

**Note:** This step is optional.

Remove these config files:

* /etc/ipsec.conf*
* /etc/ipsec.secrets*
* /etc/ppp/chap-secrets*
* /etc/ppp/options.xl2tpd*
* /etc/pam.d/pluto
* /etc/sysconfig/pluto
* /etc/default/pluto
* /etc/ipsec.d (directory)
* /etc/xl2tpd (directory)

Copy and paste for fast removal:

```bash
rm -f /etc/ipsec.conf* /etc/ipsec.secrets* /etc/ppp/chap-secrets* /etc/ppp/options.xl2tpd* \
      /etc/pam.d/pluto /etc/sysconfig/pluto /etc/default/pluto
rm -rf /etc/ipsec.d /etc/xl2tpd
```

Remove IKEv2 script:

```bash
rm -f /usr/bin/ikev2.sh /opt/src/ikev2.sh
```

### When finished

Reboot your server.

## License

Copyright (C) 2016-2021 [Lin Song](https://github.com/hwdsl2) [![View my profile on LinkedIn](https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png)](https://www.linkedin.com/in/linsongui)   

[![Creative Commons License](https://i.creativecommons.org/l/by-sa/3.0/88x31.png)](http://creativecommons.org/licenses/by-sa/3.0/)   
This work is licensed under the [Creative Commons Attribution-ShareAlike 3.0 Unported License](http://creativecommons.org/licenses/by-sa/3.0/)  
Attribution required: please include my name in any derivative and let me know how you have improved it!
