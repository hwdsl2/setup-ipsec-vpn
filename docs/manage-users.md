## Manage VPN Users

*Read this in other languages: [English](manage-users.md), [简体中文](manage-users-zh.md).*

By default, a single user account for VPN login is created. If you wish to add, edit or remove users, read this document.

First, the IPsec PSK (pre-shared key) is stored in `/etc/ipsec.secrets`. To change to a new PSK, just edit this file. 

```bash
<VPN Server IP>  %any  : PSK "<VPN IPsec PSK>"
```

For `IPsec/L2TP`, VPN users are specified in `/etc/ppp/chap-secrets`. The format of this file is:

```bash
"<VPN User 1>"  l2tpd  "<VPN Password 1>"  *
"<VPN User 2>"  l2tpd  "<VPN Password 2>"  *
... ...
```

You can add more users, use one line for each user. DO NOT use these characters within values: `\ " '`

For `IPsec/XAuth ("Cisco IPsec")`, VPN users are specified in `/etc/ipsec.d/passwd`. The format of this file is:

```bash
<VPN User 1>:<VPN Password 1 (hashed)>:xauth-psk
<VPN User 2>:<VPN Password 2 (hashed)>:xauth-psk
... ...
```

Passwords in this file are salted and hashed. This step can be done using e.g. the `openssl` utility:

```bash
# The output will be <VPN Password 1 (hashed)>
openssl passwd -1 "<VPN Password 1>"
```

When finished making changes, run these commands or reboot your server.

```bash
service ipsec restart
service xl2tpd restart
```
