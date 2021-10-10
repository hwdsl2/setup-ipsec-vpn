# 卸载 VPN

*其他语言版本: [English](uninstall.md), [简体中文](uninstall-zh.md).*

* [使用辅助脚本卸载 VPN](#使用辅助脚本卸载-vpn)
* [手动卸载 VPN](#手动卸载-vpn)

## 使用辅助脚本卸载 VPN

**警告：** 此[辅助脚本](../extras/vpnuninstall.sh)将从你的服务器中删除 IPsec VPN。所有的 VPN 配置将被**永久删除**，并且 Libreswan 和 xl2tpd 将被移除。此操作**不可撤销**！

```bash
wget https://git.io/vpnuninstall -O vpnunst.sh
sudo bash vpnunst.sh
```

在完成后重启你的服务器。

## 手动卸载 VPN

另外，你也可以手动卸载 VPN。按照以下步骤操作。这些命令需要用 `root` 账户运行，或者使用 `sudo`。

**警告：** 以下步骤将从你的服务器中删除 IPsec VPN。所有的 VPN 配置将被**永久删除**，并且 Libreswan 和 xl2tpd 将被移除。此操作**不可撤销**！

### 步骤

* [第一步](#第一步)
* [第二步](#第二步)
* [第三步](#第三步)
* [第四步](#第四步)
* [可选步骤](#可选步骤)
* [完成后](#完成后)

### 第一步

```bash
service ipsec stop
service xl2tpd stop
rm -rf /usr/local/sbin/ipsec /usr/local/libexec/ipsec /usr/local/share/doc/libreswan
rm -f /etc/init/ipsec.conf /lib/systemd/system/ipsec.service /etc/init.d/ipsec \
      /usr/lib/systemd/system/ipsec.service /etc/logrotate.d/libreswan \
      /usr/lib/tmpfiles.d/libreswan.conf
```

### 第二步

#### Ubuntu & Debian

`apt-get purge xl2tpd`

#### CentOS/RHEL, Rocky Linux, AlmaLinux & Amazon Linux 2

`yum remove xl2tpd`

#### Alpine Linux

`apk del xl2tpd`

### 第三步

#### Ubuntu, Debian & Alpine Linux

编辑 `/etc/iptables.rules` 并删除不需要的规则。你之前的防火墙规则（如果有）备份在 `/etc/iptables.rules.old-日期-时间`。另外如果文件 `/etc/iptables/rules.v4` 存在，请编辑它。

#### CentOS/RHEL, Rocky Linux, AlmaLinux & Amazon Linux 2

编辑 `/etc/sysconfig/iptables` 并删除不需要的规则。你之前的防火墙规则（如果有）备份在 `/etc/sysconfig/iptables.old-日期-时间`。

**注：** 如果使用 Rocky Linux, AlmaLinux 或者 CentOS/RHEL 8 并且在安装 VPN 时 firewalld 正在运行，则可能已配置 nftables。编辑 `/etc/sysconfig/nftables.conf` 并删除不需要的规则。你之前的防火墙规则备份在 `/etc/sysconfig/nftables.conf.old-日期-时间`。

### 第四步

编辑 `/etc/sysctl.conf` 并删除该标记后面的行： `# Added by hwdsl2 VPN script`。   
编辑 `/etc/rc.local` 并删除该标记后面的行： `# Added by hwdsl2 VPN script`。\*不要\* 删除 `exit 0` （如果有）。

### 可选步骤

**注：** 这一步是可选的。

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

删除 IKEv2 脚本：

```bash
rm -f /usr/bin/ikev2.sh /opt/src/ikev2.sh
```

### 完成后

重启你的服务器。

## 授权协议

版权所有 (C) 2016-2021 [Lin Song](https://github.com/hwdsl2) [![View my profile on LinkedIn](https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png)](https://www.linkedin.com/in/linsongui)   

[![Creative Commons License](https://i.creativecommons.org/l/by-sa/3.0/88x31.png)](http://creativecommons.org/licenses/by-sa/3.0/)   
这个项目是以 [知识共享署名-相同方式共享3.0](http://creativecommons.org/licenses/by-sa/3.0/) 许可协议授权。   
必须署名： 请包括我的名字在任何衍生产品，并且让我知道你是如何改善它的！
