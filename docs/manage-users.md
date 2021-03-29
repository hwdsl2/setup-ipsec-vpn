# Manage VPN Users

*Read this in other languages: [English](manage-users.md), [简体中文](manage-users-zh.md).*

By default, a single user account for VPN login is created. If you wish to view or manage users for the `IPsec/L2TP` and `IPsec/XAuth ("Cisco IPsec")` modes, read this document. For IKEv2, see [Manage client certificates](ikev2-howto.md#manage-client-certificates).

- [View or update the IPsec PSK](#view-or-update-the-ipsec-psk)
- [View VPN users](#view-vpn-users)
- [Manage VPN users using helper scripts](#manage-vpn-users-using-helper-scripts)
- [Manually manage VPN users](#manually-manage-vpn-users)

## View or update the IPsec PSK

The IPsec PSK (pre-shared key) is stored in `/etc/ipsec.secrets`. All VPN users will share the same IPsec PSK. The format of this file is:

```bash
%any  %any  : PSK "your_ipsec_pre_shared_key"
```

To change to a new PSK, just edit this file. DO NOT use these special characters within values: `\ " '`

You must restart services when finished:

```bash
service ipsec restart
service xl2tpd restart
```

## View VPN users

By default, the VPN setup scripts will create the same VPN user for both `IPsec/L2TP` and `IPsec/XAuth ("Cisco IPsec")` modes.

For `IPsec/L2TP`, VPN users are specified in `/etc/ppp/chap-secrets`. The format of this file is:

```bash
"username1"  l2tpd  "password1"  *
"username2"  l2tpd  "password2"  *
... ...
```

For `IPsec/XAuth ("Cisco IPsec")`, VPN users are specified in `/etc/ipsec.d/passwd`. Passwords in this file are salted and hashed. See [Manually manage VPN users](#manually-manage-vpn-users) for more details.

## Manage VPN users using helper scripts

You may use these scripts to more easily manage VPN users: [add_vpn_user.sh](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/extras/add_vpn_user.sh), [del_vpn_user.sh](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/extras/del_vpn_user.sh) and [update_vpn_users.sh](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/extras/update_vpn_users.sh). They will update users for both IPsec/L2TP and IPsec/XAuth ("Cisco IPsec"). Replace command parameters below with your own values. For IKEv2, see [Manage client certificates](ikev2-howto.md#manage-client-certificates).

**Note:** VPN users are stored in `/etc/ppp/chap-secrets` and `/etc/ipsec.d/passwd`. The scripts will backup these files before making changes, with `.old-date-time` suffix.

### Add or edit a VPN user

Add a new VPN user, or update an existing VPN user with a new password.

```bash
# Download the script
wget -O add_vpn_user.sh https://bit.ly/addvpnuser
```

```bash
# All values MUST be placed inside 'single quotes'
# DO NOT use these special characters within values: \ " '
sudo sh add_vpn_user.sh 'username_to_add' 'password'
# OR
sudo sh add_vpn_user.sh 'username_to_update' 'new_password'
```

### Delete a VPN user

Delete the specified VPN user.

```bash
# Download the script
wget -O del_vpn_user.sh https://bit.ly/delvpnuser
```

```bash
# All values MUST be placed inside 'single quotes'
# DO NOT use these special characters within values: \ " '
sudo sh del_vpn_user.sh 'username_to_delete'
```

### Update all VPN users

Remove all existing VPN users and replace with the list of users you specify.

```bash
# Download the script
wget -O update_vpn_users.sh https://bit.ly/updatevpnusers
```

To use this script, choose one of the following options:

**Important:** This script will remove **ALL** existing VPN users and replace them with the list of users you specify. Therefore, you must include any existing user(s) you want to keep in the variables below.

**Option 1:** Edit the script and enter VPN user details:

```bash
nano -w update_vpn_users.sh
[Replace with your own values: YOUR_USERNAMES and YOUR_PASSWORDS]
sudo sh update_vpn_users.sh
```

**Option 2:** Define VPN user details as environment variables:

```bash
# List of VPN usernames and passwords, separated by spaces
# All values MUST be placed inside 'single quotes'
# DO NOT use these special characters within values: \ " '
sudo \
VPN_USERS='username1 username2 ...' \
VPN_PASSWORDS='password1 password2 ...' \
sh update_vpn_users.sh
```

## Manually manage VPN users

For `IPsec/L2TP`, VPN users are specified in `/etc/ppp/chap-secrets`. The format of this file is:

```bash
"username1"  l2tpd  "password1"  *
"username2"  l2tpd  "password2"  *
... ...
```

You can add more users, use one line for each user. DO NOT use these special characters within values: `\ " '`

For `IPsec/XAuth ("Cisco IPsec")`, VPN users are specified in `/etc/ipsec.d/passwd`. The format of this file is:

```bash
username1:password1hashed:xauth-psk
username2:password2hashed:xauth-psk
... ...
```

Passwords in this file are salted and hashed. This step can be done using e.g. the `openssl` utility:

```bash
# The output will be password1hashed
# Put your password inside 'single quotes'
openssl passwd -1 'password1'
```

## License

Copyright (C) 2016-2021 <a href="https://www.linkedin.com/in/linsongui" target="_blank">Lin Song</a>   

<a rel="license" href="http://creativecommons.org/licenses/by-sa/3.0/"><img alt="Creative Commons License" style="border-width:0" src="https://i.creativecommons.org/l/by-sa/3.0/88x31.png" /></a>   
This work is licensed under the <a href="http://creativecommons.org/licenses/by-sa/3.0/" target="_blank">Creative Commons Attribution-ShareAlike 3.0 Unported License</a>  
Attribution required: please include my name in any derivative and let me know how you have improved it!
