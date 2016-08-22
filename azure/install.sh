#!/bin/bash
export VPN_IPSEC_PSK=$1
export VPN_USER=$2
export VPN_PASSWORD=$3

# Debian on Azure has no lsb_release installed.
if ! [[ -x "/usr/bin/lsb_release" ]]
then
    apt-get update
    apt-get install -y lsb-release
fi

wget https://git.io/vpnsetup -O vpnsetup.sh && sh vpnsetup.sh