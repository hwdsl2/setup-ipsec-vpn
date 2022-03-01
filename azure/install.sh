#!/bin/sh

export VPN_IPSEC_PSK=$1
export VPN_USER=$2
export VPN_PASSWORD=$3

wget -t 3 -T 30 -nv -O vpn.sh https://git.io/vpnstart && sh vpn.sh
