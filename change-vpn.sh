#!/bin/bash

ACTIVE_VPN=`nmcli con show -a | grep 'vpn'`
INACTIVE_VPNS=( $(nmcli con show | grep 'vpn.*-') )

VPNS=()

for index in ${!INACTIVE_VPNS[@]}
do
  if [[ ${INACTIVE_VPNS[$index]} == *"VPN-"* ]]; then
    VPNS+=(${INACTIVE_VPNS[$index]})
  fi
done

rand=$[$RANDOM % ${#VPNS[@]}]
NEW_CONNECTION=${VPNS[$rand]}

nmcli con down $ACTIVE_VPN

sleep 15

nmcli con up $NEW_CONNECTION
