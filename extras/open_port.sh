#!/bin/sh

echo "Which port do you want to open?"
read PORT

echo "Which type of port? tcp OR udp?"
read TYPE

echo "For which client? | This is the list:"
ifconfig | grep -E -o "(192[\.]168[\.]4[2-3][\.][0-9]{2,3})"
read CLIENT_IP

#PORT=8080
#TYPE=tcp
#CLIENT_IP=192.168.42.10
VPN_L2TP=192.168.42.1
VPN_XAUTH=192.168.43.1

def_iface=$(route 2>/dev/null | grep -m 1 '^default' | grep -o '[^ ]*$')

iptables -D FORWARD -j DROP
iptables -A FORWARD -i $def_iface -o ppp+ -p $TYPE --dport $PORT -j ACCEPT
iptables -A FORWARD -j DROP
iptables -t nat -A PREROUTING -i $def_iface -p $TYPE --dport $PORT -j DNAT --to-dest $CLIENT_IP:$PORT

if [ $(echo "$CLIENT_IP" | grep -c 192.168.42) -eq 1 ]; then
        iptables -t nat -A POSTROUTING -d $CLIENT_IP -p $TYPE --dport $PORT -j SNAT --to-source $VPN_L2TP
fi

if  [ $(echo "$CLIENT_IP" | grep -c 192.168.43) -eq 1 ]; then
        iptables -t nat -A POSTROUTING -d $CLIENT_IP -p $TYPE --dport $PORT -j SNAT --to-source $VPN_XAUTH
fi

echo "Done"
