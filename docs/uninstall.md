# Uninstall IPsec/L2TP VPN

To remove the VPN:

## Steps

* [First step](#first-step)
* [Second step](#second-step)
* [Third step](#third-step)
* [Fourth step](#fourth-step)
* [Optional](#optional)
* [When finished](#when-finished)

## First step
```
service ipsec stop
service xl2tpd stop
rm -rf /usr/local/sbin/ipsec /usr/local/libexec/ipsec
rm -f /etc/init.d/ipsec /lib/systemd/system/ipsec.service
rm -rf /opt/src/libreswan-*
```

## Second step

### For Ubuntu/Debian:

`apt-get remove xl2tpd`

### For CentOS/RHEL:

`yum remove xl2tpd`

## Third step

### For Ubuntu/Debian: 

Edit `/etc/iptables.rules` and remove unneeded rules. 
Your original rules (if any) are backed up as `/etc/iptables.rules.old-date-time`. 
In addition, edit `/etc/iptables/rules.v4` if the file exists. 
If using IPv6, also edit `/etc/ip6tables.rules` and `/etc/iptables/rules.v6`.

### For CentOS/RHEL: 

Edit `/etc/sysconfig/iptables` and `/etc/sysconfig/ip6tables`

## Fourth step

Edit `/etc/sysctl.conf` and remove the lines after `# Added by hwdsl2 VPN script`

Edit `/etc/rc.local` and remove the lines after `# Added by hwdsl2 VPN script`, *except exit 0 (if any)*

## Optional

Remove these config files:
* /etc/ipsec.conf
* /etc/ipsec.secrets
* /etc/xl2tpd/xl2tpd.conf
* /etc/ppp/options.xl2tpd
* /etc/ppp/chap-secrets
* /etc/ipsec.d/*
* /etc/pam.d/pluto
* /etc/sysconfig/pluto

copy && paste for fast remove:

`sudo rm -f /etc/ipsec.conf /etc/ipsec.secrets /etc/xl2tpd/xl2tpd.conf /etc/ppp/options.xl2tpd /etc/ppp/chap-secrets /etc/ipsec.d/* /etc/pam.d/pluto /etc/sysconfig/pluto`

## When finished

Reboot your server.
