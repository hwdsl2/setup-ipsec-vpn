#!/bin/bash
#
# Script for adding a new vpn user
# Usage: ./add_vpn_user.sh username pa$$word
#

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

if [[ $# -ne 2 ]] ; then
    echo 'Usage: add_vpn_user.sh username pa$$word'
    exit 0
fi

echo "Adding user..."

echo "\"$1\"  l2tpd  \"$2\"  *" | tee -a /etc/ppp/chap-secrets > /dev/null
echo "$1:$(openssl passwd -1 $2):xauth-psk" | tee -a /etc/ipsec.d/passwd > /dev/null

echo "Restarting vpn service..."

service ipsec restart
service xl2tpd restart
