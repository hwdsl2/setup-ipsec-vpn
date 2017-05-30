# Manage VPN Users

*Read this in other languages: [English](manage-users.md), [简体中文](manage-users-zh.md).*

By default, a single user account for VPN login is created. If you wish to add, edit or remove users, read this document.

First, the IPsec PSK (pre-shared key) is stored in `/etc/ipsec.secrets`. To change to a new PSK, just edit this file. All VPN users will share the same IPsec PSK.

```bash
%any  %any  : PSK "your_ipsec_pre_shared_key"
```

For `IPsec/L2TP`, VPN users are specified in `/etc/ppp/chap-secrets`. The format of this file is:

```bash
"your_vpn_username_1"  l2tpd  "your_vpn_password_1"  *
"your_vpn_username_2"  l2tpd  "your_vpn_password_2"  *
... ...
```

You can add more users, use one line for each user. DO NOT use these characters within values: `\ " '`

For `IPsec/XAuth ("Cisco IPsec")`, VPN users are specified in `/etc/ipsec.d/passwd`. The format of this file is:

```bash
your_vpn_username_1:your_vpn_password_1_hashed:xauth-psk
your_vpn_username_2:your_vpn_password_2_hashed:xauth-psk
... ...
```

Passwords in this file are salted and hashed. This step can be done using e.g. the `openssl` utility:

```bash
# The output will be your_vpn_password_1_hashed
openssl passwd -1 'your_vpn_password_1'
```

When finished, restart services:

```bash
service ipsec restart
service xl2tpd restart
```
