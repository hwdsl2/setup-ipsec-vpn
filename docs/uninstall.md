# Uninstall the VPN

*Read this in other languages: [English](uninstall.md), [简体中文](uninstall-zh.md).*

Follow these steps to remove the VPN. Commands must be run as `root`, or with `sudo`.

## Steps

* [First step](#first-step)
* [Second step](#second-step)
* [Third step](#third-step)
* [Fourth step](#fourth-step)
* [Optional](#optional)
* [When finished](#when-finished)

## First step

```bash
service ipsec stop
service xl2tpd stop
rm -rf /usr/local/sbin/ipsec /usr/local/libexec/ipsec
rm -f /etc/init/ipsec.conf /lib/systemd/system/ipsec.service \
      /etc/init.d/ipsec /usr/lib/systemd/system/ipsec.service
```

## Second step

### Ubuntu & Debian

`apt-get purge xl2tpd`

### CentOS/RHEL & Amazon Linux 2

`yum remove xl2tpd`

## Third step

### Ubuntu & Debian

Edit `/etc/iptables.rules` and remove unneeded rules. Your original rules (if any) are backed up as `/etc/iptables.rules.old-date-time`. In addition, edit `/etc/iptables/rules.v4` if the file exists.   

### CentOS/RHEL & Amazon Linux 2

Edit `/etc/sysconfig/iptables` and remove unneeded rules. Your original rules (if any) are backed up as `/etc/sysconfig/iptables.old-date-time`.

**Note:** If using CentOS/RHEL 8 and firewalld was active during VPN setup, nftables may be configured. Edit `/etc/sysconfig/nftables.conf` and remove unneeded rules. Your original rules are backed up as `/etc/sysconfig/nftables.conf.old-date-time`.

## Fourth step

Edit `/etc/sysctl.conf` and remove the lines after `# Added by hwdsl2 VPN script`.   
Edit `/etc/rc.local` and remove the lines after `# Added by hwdsl2 VPN script`. DO NOT remove `exit 0` (if any).

## Optional

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

## When finished

Reboot your server.

## License

Copyright (C) 2016-2021 <a href="https://www.linkedin.com/in/linsongui" target="_blank">Lin Song</a>   

<a rel="license" href="http://creativecommons.org/licenses/by-sa/3.0/"><img alt="Creative Commons License" style="border-width:0" src="https://i.creativecommons.org/l/by-sa/3.0/88x31.png" /></a>   
This work is licensed under the <a href="http://creativecommons.org/licenses/by-sa/3.0/" target="_blank">Creative Commons Attribution-ShareAlike 3.0 Unported License</a>  
Attribution required: please include my name in any derivative and let me know how you have improved it!
