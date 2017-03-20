# 卸载 VPN

*其他语言版本: [English](uninstall.md), [简体中文](uninstall-zh.md).*

按照以下步骤移除 VPN。这些命令需要用 `root` 账户运行，或者使用 `sudo`。

## 步骤

* [第一步](#第一步)
* [第二步](#第二步)
* [第三步](#第三步)
* [第四步](#第四步)
* [可选步骤](#可选步骤)
* [完成后](#完成后)

## 第一步

```bash
service ipsec stop
service xl2tpd stop
rm -rf /usr/local/sbin/ipsec /usr/local/libexec/ipsec
rm -f /etc/init/ipsec.conf /lib/systemd/system/ipsec.service \
      /etc/init.d/ipsec /usr/lib/systemd/system/ipsec.service
```

## 第二步

### Ubuntu/Debian

`apt-get purge xl2tpd`

### CentOS/RHEL

`yum remove xl2tpd`

## 第三步

### Ubuntu/Debian

编辑 `/etc/iptables.rules` 并删除不需要的规则。   
你以前的防火墙规则（如果有）会备份在 `/etc/iptables.rules.old-日期-时间`。   
另外如果文件 `/etc/iptables/rules.v4` 存在，请编辑它。   

### CentOS/RHEL

编辑 `/etc/sysconfig/iptables` 并删除不需要的规则。   
你以前的防火墙规则（如果有）会备份在 `/etc/sysconfig/iptables.old-日期-时间`。   

## 第四步

编辑 `/etc/sysctl.conf` 并删除该标记后面的行： `# Added by hwdsl2 VPN script`。   
编辑 `/etc/rc.local` 并删除该标记后面的行： `# Added by hwdsl2 VPN script`。\*不要\* 删除 `exit 0` （如果有）。

## 可选步骤

注： 这一步是可选的。

删除这些配置文件：

* /etc/ipsec.conf*
* /etc/ipsec.secrets*
* /etc/ppp/chap-secrets*
* /etc/ppp/options.xl2tpd*
* /etc/pam.d/pluto
* /etc/sysconfig/pluto
* /etc/default/pluto
* /etc/ipsec.d (目录)
* /etc/xl2tpd (目录)

要快速删除，可以复制并粘贴以下命令：

```bash
rm -f /etc/ipsec.conf* /etc/ipsec.secrets* /etc/ppp/chap-secrets* /etc/ppp/options.xl2tpd* \
      /etc/pam.d/pluto /etc/sysconfig/pluto /etc/default/pluto
rm -rf /etc/ipsec.d /etc/xl2tpd
```

## 完成后

重启你的服务器。
