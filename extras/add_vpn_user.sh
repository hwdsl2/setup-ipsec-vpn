#!/bin/sh
#
# Script to add/update an VPN user for both IPsec/L2TP and Cisco IPsec
#
# Copyright (C) 2018-2021 Lin Song <linsongui@gmail.com>
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
SYS_DT=$(date +%F-%T | tr ':' '_')

exiterr()  { echo "Error: $1" >&2; exit 1; }
conf_bk() { /bin/cp -f "$1" "$1.old-$SYS_DT" 2>/dev/null; }

add_vpn_user() {

if [ "$(id -u)" != 0 ]; then
  exiterr "Script must be run as root. Try 'sudo sh $0'"
fi

if ! grep -qs "hwdsl2 VPN script" /etc/sysctl.conf \
  || [ ! -f /etc/ppp/chap-secrets ] || [ ! -f /etc/ipsec.d/passwd ]; then
cat 1>&2 <<'EOF'
Error: Your must first set up the IPsec VPN server before adding VPN users.
       See: https://github.com/hwdsl2/setup-ipsec-vpn
EOF
  exit 1
fi

command -v openssl >/dev/null 2>&1 || exiterr "'openssl' not found. Abort."

VPN_USER=$1
VPN_PASSWORD=$2

if [ -z "$VPN_USER" ] || [ -z "$VPN_PASSWORD" ]; then
cat 1>&2 <<EOF
Usage: sudo sh $0 'username_to_add' 'password'
       sudo sh $0 'username_to_update' 'new_password'
EOF
  exit 1
fi

if printf '%s' "$VPN_USER $VPN_PASSWORD" | LC_ALL=C grep -q '[^ -~]\+'; then
  exiterr "VPN credentials must not contain non-ASCII characters."
fi

case "$VPN_USER $VPN_PASSWORD" in
  *[\\\"\']*)
    exiterr "VPN credentials must not contain these special characters: \\ \" '"
    ;;
esac

clear

cat <<EOF

Welcome! This script will add or update an VPN user account for both
IPsec/L2TP and IPsec/XAuth ("Cisco IPsec") modes.

If the username you specified already exists, it will be updated
with the new password. Otherwise, a new VPN user will be added.

Please double check before continuing!

================================================

VPN user to add or update:

Username: $VPN_USER
Password: $VPN_PASSWORD

Write these down. You'll need them to connect!

Important notes:   https://git.io/vpnnotes
Setup VPN clients: https://git.io/vpnclients

================================================

EOF

printf "Do you want to continue? [y/N] "
read -r response
case $response in
  [yY][eE][sS]|[yY])
    echo
    echo "Adding or updating VPN user..."
    echo
    ;;
  *)
    echo "Abort. No changes were made."
    exit 1
    ;;
esac

# Backup config files
conf_bk "/etc/ppp/chap-secrets"
conf_bk "/etc/ipsec.d/passwd"

# Add or update VPN user
sed -i "/^\"$VPN_USER\" /d" /etc/ppp/chap-secrets
cat >> /etc/ppp/chap-secrets <<EOF
"$VPN_USER" l2tpd "$VPN_PASSWORD" *
EOF

# shellcheck disable=SC2016
sed -i '/^'"$VPN_USER"':\$1\$/d' /etc/ipsec.d/passwd
VPN_PASSWORD_ENC=$(openssl passwd -1 "$VPN_PASSWORD")
cat >> /etc/ipsec.d/passwd <<EOF
$VPN_USER:$VPN_PASSWORD_ENC:xauth-psk
EOF

# Update file attributes
chmod 600 /etc/ppp/chap-secrets* /etc/ipsec.d/passwd*

cat <<'EOF'
Done!

Note: All VPN users will share the same IPsec PSK.
      If you forgot the PSK, check /etc/ipsec.secrets.

EOF

}

## Defer until we have the complete script
add_vpn_user "$@"

exit 0
