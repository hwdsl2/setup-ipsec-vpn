#!/bin/bash

VPN_USER=""
VPN_PASSWORD=""

function read_user()
{

	while  [[ "$VPN_USER" == "" ]]
	do
		echo  -e "VPN USER:\c" ; VPN_USER= ; read VPN_USER
	done

	while  [[ "$VPN_PASSWORD" == "" ]]
	do
		echo  -e "VPN PASSWORD:\c" ; VPN_PASSWORD= ; read VPN_PASSWORD
	done
}

read_user

PUBLIC_IP=$(dig @resolver1.opendns.com -t A -4 myip.opendns.com +short)
VPN_IPSEC_PSK=$(cat /etc/ipsec.secrets | grep PSK | awk '{print $5}')

echo VPN_PASSWORD: $VPN_PASSWORD
echo VPN_USER: $VPN_USER
echo "\"$VPN_USER\" l2tpd \"$VPN_PASSWORD\" *" >> /etc/ppp/chap-secrets


VPN_PASSWORD_ENC=$(openssl passwd -1 "$VPN_PASSWORD")
echo VPN_PASSWORD_ENC: $VPN_PASSWORD_ENC
echo "$VPN_USER:$VPN_PASSWORD_ENC:xauth-psk" >> /etc/ipsec.d/passwd



cat <<EOF

================================================

Add New VPN User

Server IP: $PUBLIC_IP
IPsec PSK: $VPN_IPSEC_PSK
Username: $VPN_USER
Password: $VPN_PASSWORD

Write these down. You'll need them to connect!

Important notes:   https://git.io/vpnnotes
Setup VPN clients: https://git.io/vpnclients

================================================

EOF

service ipsec restart 2>/dev/null
service xl2tpd restart 2>/dev/null

