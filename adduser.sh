#!/bin/bash

echo "Enter username"
read -r username
if grep "^$username:" /etc/ipsec.d/passwd
then
  echo "Username already exist"
  exit 1
fi
echo "Enter password"
read -r password
password=$(openssl passwd -1 "$password")
echo $username":"$password":xauth-psk" >> /etc/ipsec.d/passwd
if grep "^$username:" /etc/ipsec.d/passwd
then
  echo "Success to add"
else
  echo "Fail to add"
fi
