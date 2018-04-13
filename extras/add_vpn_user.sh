#!/bin/bash

exiterr()  { echo "Error: $1" >&2; exit 1; }
conf_bk() { /bin/cp -f "$1" "$1.old-$SYS_DT" 2>/dev/null; }
del_vpn_user() {
lineno=$(grep -n $1 $2 | cut -d : -f1)
sed -i "${lineno}d" $2
}

VPN_USER=$1
VPN_PASSWORD=$2

if [ -z "$VPN_USER" ] || [ -z "$VPN_PASSWORD" ]; then
  exiterr "All VPN credentials must be specified. Usage: add_vpn_user.sh 'user' 'password' "
fi

if printf '%s' "$VPN_USER $VPN_PASSWORD" | LC_ALL=C grep -q '[^ -~]\+'; then
  exiterr "VPN credentials must not contain non-ASCII characters."
fi

case "$VPN_USER $VPN_PASSWORD" in
  *[\\\"\']*)
    exiterr "VPN credentials must not contain these special characters: \\ \" '"
    ;;
esac

# Create VPN credentials
conf_bk "/etc/ppp/chap-secrets"
# delete any existing line for this user first
lineno=$(grep -n "^\"$VPN_USER\" " /etc/ppp/chap-secrets | cut -d : -f1)
sed -i "${lineno}d" $2
[ -z $lineno ] || sed -i "${lineno}d" /etc/ppp/chap-secrets
# append a line for the user with the new password
cat >> /etc/ppp/chap-secrets <<EOF
"$VPN_USER" l2tpd "$VPN_PASSWORD" *
EOF

conf_bk "/etc/ipsec.d/passwd"
# delete any existing line for this user first
lineno=$(grep -n "^$VPN_USER:" /etc/ipsec.d/passwd | cut -d : -f1)
sed -i "${lineno}d" $2
[ -z $lineno ] || sed -i "${lineno}d" /etc/ipsec.d/passwd
# append a line for the user with the new password
VPN_PASSWORD_ENC=$(openssl passwd -1 "$VPN_PASSWORD")
cat >> /etc/ipsec.d/passwd <<EOF
$VPN_USER:$VPN_PASSWORD_ENC:xauth-psk
EOF

echo "Added a vpn user"
echo "  User: $VPN_USER"
echo "  Password: $VPN_PASSWORD"
echo "to /etc/ppp/chap-secrets and /etc/ipsec.d/passwd"
echo

