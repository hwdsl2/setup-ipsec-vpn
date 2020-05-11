#!/bin/bash
#
# Script to set up IKEv2 on Ubuntu, Debian and CentOS/RHEL
#
# Copyright (C) 2020 Lin Song <linsongui@gmail.com>
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
SYS_DT=$(date +%F-%T)

exiterr() { echo "Error: $1" >&2; exit 1; }
bigecho() { echo; echo "## $1"; echo; }
bigecho2() { echo; echo "## $1"; }

check_ip() {
  IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "$IP_REGEX"
}

check_dns_name() {
  FQDN_REGEX='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "$FQDN_REGEX"
}

ikev2setup() {

if [ "$(id -u)" != 0 ]; then
  exiterr "Script must be run as root. Try 'sudo bash $0'"
fi

ipsec_ver=$(/usr/local/sbin/ipsec --version 2>/dev/null)
swan_ver=$(printf '%s' "$ipsec_ver" | sed -e 's/Linux //' -e 's/Libreswan //' -e 's/ (netkey) on .*//')
if ! grep -qs "hwdsl2 VPN script" /etc/sysctl.conf \
  || ! printf '%s' "$ipsec_ver" | grep -q "Libreswan" \
  || [ ! -f "/etc/ppp/chap-secrets" ] || [ ! -f "/etc/ipsec.d/passwd" ]; then
cat 1>&2 <<'EOF'
Error: Your must first set up the IPsec VPN server before setting up IKEv2.
  See: https://github.com/hwdsl2/setup-ipsec-vpn
EOF
  exit 1
fi

case "$swan_ver" in
  3.19|3.2[01235679]|3.31)
    /bin/true
    ;;
  *)
cat 1>&2 <<EOF
Error: Libreswan version '$swan_ver' is not supported.
  This script requires one of these versions:
  3.19-3.23, 3.25-3.27, 3.29 or 3.31
  Upgrade Libreswan: https://git.io/vpnupgrade
EOF
    exit 1
    ;;
esac

if grep -qs "conn ikev2-cp" /etc/ipsec.conf; then
cat 1>&2 <<'EOF'
Error: It looks like IKEv2 has already been set up on this server.
  To generate certificates for additional VPN clients, see step 4 in section
  "Manually set up IKEv2 on the VPN server" at https://git.io/ikev2
EOF
  exit 1
fi

command -v certutil >/dev/null 2>&1 || { echo >&2 "Error: Command 'certutil' not found. Aborting."; exit 1; }
command -v pk12util >/dev/null 2>&1 || { echo >&2 "Error: Command 'pk12util' not found. Aborting."; exit 1; }

clear

cat <<'EOF'
Welcome! Use this script to set up IKEv2 after setting up your own IPsec VPN server.
Alternatively, you may manually set up IKEv2. See: https://git.io/ikev2

I need to ask you a few questions before starting setup.
You can use the default options and just press enter if you are OK with them.

EOF

echo "Do you want IKEv2 VPN clients to connect to this VPN server using a DNS name,"
printf "e.g. vpn.example.com, instead of its IP address [y/N]? "
read -r response
case $response in
  [yY][eE][sS]|[yY])
    use_dns_name=1
    echo
    ;;
  *)
    use_dns_name=0
    echo
    ;;
esac

# Enter VPN server address
if [ "$use_dns_name" = "1" ]; then
  read -rp "Enter the DNS name of this VPN server: " server_addr
  until check_dns_name "$server_addr"; do
    echo "Invalid DNS name. You must enter a fully qualified domain name (FQDN)."
    read -rp "Enter the DNS name of this VPN server: " server_addr
  done
else
  public_ip=$(dig @resolver1.opendns.com -t A -4 myip.opendns.com +short)
  [ -z "$public_ip" ] && public_ip=$(wget -t 3 -T 15 -qO- http://ipv4.icanhazip.com)
  read -rp "Enter the IPv4 address of this VPN server [$public_ip]: " server_addr
  [ -z "$server_addr" ] && server_addr="$public_ip"
  until check_ip "$server_addr"; do
    echo "Invalid IP address."
    read -rp "Enter the IPv4 address of this VPN server [$public_ip]: " server_addr
    [ -z "$server_addr" ] && server_addr="$public_ip"
  done
fi

# Check for MOBIKE support
mobike_support=0
case "$swan_ver" in
  3.2[35679]|3.31)
    mobike_support=1
    ;;
esac

if [ "$mobike_support" = "1" ]; then
  os_type="$(lsb_release -si 2>/dev/null)"
  if [ -z "$os_type" ]; then
    [ -f /etc/os-release  ] && os_type="$(. /etc/os-release  && printf '%s' "$ID")"
    [ -f /etc/lsb-release ] && os_type="$(. /etc/lsb-release && printf '%s' "$DISTRIB_ID")"
    [ "$os_type" = "ubuntu" ] && os_type=Ubuntu
  fi
  if [ -z "$os_type" ] || [ "$os_type" = "Ubuntu" ]; then
    mobike_support=0
  fi
fi

mobike_enable=0
if [ "$mobike_support" = "1" ]; then
  echo
  printf "Do you want to enable MOBIKE support [y/N]? "
  read -r response
  case $response in
    [yY][eE][sS]|[yY])
      mobike_enable=1
      ;;
    *)
      mobike_enable=0
      ;;
  esac
fi

echo
printf "We are ready to set up IKEv2 now. Continue [y/N]? "
read -r response
case $response in
  [yY][eE][sS]|[yY])
    echo
    ;;
  *)
    echo "Aborting. Your configuration was not changed."
    exit 1
    ;;
esac

bigecho "Adding a new IKEv2 connection to /etc/ipsec.conf..."

cat >> /etc/ipsec.conf <<EOF

conn ikev2-cp
  left=%defaultroute
  leftcert=$server_addr
  leftid=@$server_addr
  leftsendcert=always
  leftsubnet=0.0.0.0/0
  leftrsasigkey=%cert
  right=%any
  rightid=%fromcert
  rightaddresspool=192.168.43.10-192.168.43.250
  rightca=%same
  rightrsasigkey=%cert
  narrowing=yes
  dpddelay=30
  dpdtimeout=120
  dpdaction=clear
  auto=add
  ikev2=insist
  rekey=no
  pfs=no
  ike-frag=yes
  ike=aes256-sha2,aes128-sha2,aes256-sha1,aes128-sha1,aes256-sha2;modp1024,aes128-sha1;modp1024
  phase2alg=aes_gcm-null,aes128-sha1,aes256-sha1,aes128-sha2,aes256-sha2
EOF

case "$swan_ver" in
  3.2[35679]|3.31)
cat >> /etc/ipsec.conf <<'EOF'
  modecfgdns="8.8.8.8 8.8.4.4"
  encapsulation=yes
EOF
    if [ "$mobike_enable" = "1" ]; then
      echo "  mobike=yes" >> /etc/ipsec.conf
    else
      echo "  mobike=no" >> /etc/ipsec.conf
    fi
    ;;
  3.19|3.2[012])
cat >> /etc/ipsec.conf <<'EOF'
  modecfgdns1=8.8.8.8
  modecfgdns2=8.8.4.4
  encapsulation=yes
EOF
    ;;
esac

bigecho2 "Generating CA certificate..."

certutil -z <(head -c 1024 /dev/urandom) \
  -S -x -n "IKEv2 VPN CA" \
  -s "O=IKEv2 VPN,CN=IKEv2 VPN CA" \
  -k rsa -g 4096 -v 120 \
  -d sql:/etc/ipsec.d -t "CT,," -2 >/dev/null << ANSWERS
y

N
ANSWERS

sleep 1

bigecho2 "Generating VPN server certificate..."

if [ "$use_dns_name" = "1" ]; then
  certutil -z <(head -c 1024 /dev/urandom) \
    -S -c "IKEv2 VPN CA" -n "$server_addr" \
    -s "O=IKEv2 VPN,CN=$server_addr" \
    -k rsa -g 4096 -v 120 \
    -d sql:/etc/ipsec.d -t ",," \
    --keyUsage digitalSignature,keyEncipherment \
    --extKeyUsage serverAuth \
    --extSAN "dns:$server_addr" >/dev/null
else
  certutil -z <(head -c 1024 /dev/urandom) \
    -S -c "IKEv2 VPN CA" -n "$server_addr" \
    -s "O=IKEv2 VPN,CN=$server_addr" \
    -k rsa -g 4096 -v 120 \
    -d sql:/etc/ipsec.d -t ",," \
    --keyUsage digitalSignature,keyEncipherment \
    --extKeyUsage serverAuth \
    --extSAN "ip:$server_addr,dns:$server_addr" >/dev/null
fi

sleep 1

bigecho2 "Generating client certificate..."

certutil -z <(head -c 1024 /dev/urandom) \
  -S -c "IKEv2 VPN CA" -n "vpnclient" \
  -s "O=IKEv2 VPN,CN=vpnclient" \
  -k rsa -g 4096 -v 120 \
  -d sql:/etc/ipsec.d -t ",," \
  --keyUsage digitalSignature,keyEncipherment \
  --extKeyUsage serverAuth,clientAuth -8 "vpnclient" >/dev/null

bigecho "Exporting CA certificate..."

certutil -L -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" -a -o "vpnca-$SYS_DT.cer"

bigecho "Exporting .p12 file..."

cat <<'EOF'
Enter a *secure* password to protect the exported .p12 file.
This file contains the client certificate, private key, and CA certificate.
When importing into an iOS or macOS device, this password cannot be empty.

EOF

pk12util -o "vpnclient-$SYS_DT.p12" -n "vpnclient" -d sql:/etc/ipsec.d

bigecho "Restarting IPsec service..."

service ipsec restart

cat <<EOF
=================================================

IKEv2 VPN setup is now complete!

Files exported to the current folder:
vpnclient-$SYS_DT.p12
vpnca-$SYS_DT.cer (for iOS clients)

Next steps: Configure IKEv2 VPN clients. See:
https://git.io/ikev2clients

=================================================

EOF

}

## Defer setup until we have the complete script
ikev2setup "$@"

exit 0
