# Manage VPN Users

*Read this in other languages: [English](manage-users.md), [简体中文](manage-users-zh.md).*

By default, a single user account for VPN login is created. If you wish to add, edit or remove users, read this document.

**Note:** A helper script to update VPN users is now available. See [Helper script](#helper-script).

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

You can add more users, use one line for each user. DO NOT use these special characters within values: `\ " '`

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

Finally, restart services if you changed to a new PSK. For add, edit or remove VPN users, a restart is normally not required.

```bash
service ipsec restart
service xl2tpd restart
```

## Helper script

You may use [this helper script](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/extras/update_vpn_users.sh) to update VPN users. First download the script:

```bash
wget -O update_vpn_users.sh https://raw.githubusercontent.com/hwdsl2/setup-ipsec-vpn/master/extras/update_vpn_users.sh
```

To update VPN users, choose one of the following options:

**Important:** This script will remove **ALL** existing VPN users and replace them with the new users you specify. Therefore, you must include any existing user(s) you want to keep in the variables below. Or, you may update users manually (see above).

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
