#!/bin/bash

#your vpn server public ip
SERVER_IP=''

#Verify that a string contains another string
Include(){
	bigStr=$1;
	smallStr=$2;
	result=$(echo $bigStr | grep $smallStr)

	if [ -z "$result" ]
	then
		echo 0
	else
		echo 1
	fi
}

mkdir -p /var/run/xl2tpd
touch /var/run/xl2tpd/l2tp-control

service strongswan restart
service xl2tpd restart

ipsec up myvpn

echo "c myvpn" > /var/run/xl2tpd/l2tp-control

route=`ip route`
echo ${route}


gw=${route#*default\ via\ }
gw=${gw%%\ *}
echo "your gateway is:${gw}"

while :
do
	cfg=`ifconfig`
	res=`Include "$cfg" "ppp0"`

	if [ $res -eq 1 ]
	then
		echo "ppp0 already activated"
		break
	else
		echo "waitting 1s"
		sleep 1s
	fi
	
done

route add  ${SERVER_IP} gw $gw
route add default dev ppp0
echo "done"
ifconfig





