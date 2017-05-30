# 管理 VPN 用户

*其他语言版本: [English](manage-users.md), [简体中文](manage-users-zh.md).*

在默认情况下，将只创建一个用于 VPN 登录的用户账户。如果你需要添加，修改或者删除用户，请阅读本文档。

首先，IPsec PSK (预共享密钥) 保存在文件 `/etc/ipsec.secrets` 中。如果要更换一个新的 PSK，可以编辑此文件。所有的 VPN 用户将共享同一个 IPsec PSK。

```bash
%any  %any  : PSK "your_ipsec_pre_shared_key"
```

对于 `IPsec/L2TP`，VPN 用户账户信息保存在文件 `/etc/ppp/chap-secrets`。该文件的格式如下：

```bash
"your_vpn_username_1"  l2tpd  "your_vpn_password_1"  *
"your_vpn_username_2"  l2tpd  "your_vpn_password_2"  *
... ...
```

你可以添加更多用户，每个用户对应文件中的一行。**不要**在用户名，密码或 PSK 中使用这些字符：`\ " '`

对于 `IPsec/XAuth ("Cisco IPsec")`， VPN 用户账户信息保存在文件 `/etc/ipsec.d/passwd`。该文件的格式如下：

```bash
your_vpn_username_1:your_vpn_password_1_hashed:xauth-psk
your_vpn_username_2:your_vpn_password_2_hashed:xauth-psk
... ...
```

这个文件中的密码以 salted and hashed 的形式保存。该步骤可以借助比如 `openssl` 工具来完成：

```bash
# 以下命令的输出为 your_vpn_password_1_hashed
openssl passwd -1 'your_vpn_password_1'
```

在完成后重启服务：

```bash
service ipsec restart
service xl2tpd restart
```
