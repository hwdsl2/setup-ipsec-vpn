#!/bin/sh
#
# Amazon EC2 user-data file for automatic configuration of IPsec/L2TP VPN server
# on a Ubuntu or Debian instance. Tested with Ubuntu 14.04 & 12.04 and Debian 8.
# Besides EC2, this script *can also be used* on dedicated servers or any KVM-
# or Xen-based Virtual Private Server (VPS) from other providers.
#
# DO NOT RUN THIS SCRIPT ON YOUR PC OR MAC! THIS IS MEANT TO BE RUN
# ON YOUR DEDICATED SERVER OR VPS!
#
# Copyright (C) 2014 Lin Song
# Based on the work of Thomas Sarlandie (Copyright 2012)
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0 
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it! 

# ------------------------------------------------------------

# Please define your own values for these variables
# - All values MUST be quoted using 'single quotes'
# - DO NOT use these characters inside values:  \ " '

IPSEC_PSK='your_ipsec_pre_shared_key'
VPN_USER='your_vpn_username'
VPN_PASSWORD='your_very_secure_password'

# Be sure to read *important notes* at the URL below:
# https://github.com/hwdsl2/setup-ipsec-vpn#important-notes

# ------------------------------------------------------------

if [ "$(uname)" = "Darwin" ]; then
  echo 'DO NOT run this script on your Mac! It should only be run on a newly-created EC2 instance'
  echo 'or other dedicated server / VPS, after you have modified it to set the variables above.'
  exit 1
fi

if [ "$(lsb_release -si 2>/dev/null)" != "Ubuntu" ] && [ "$(lsb_release -si 2>/dev/null)" != "Debian" ]; then
  echo "Looks like you aren't running this script on a Ubuntu or Debian system."
  exit 1
fi

if [ -f "/proc/user_beancounters" ]; then
  echo "This script does NOT support OpenVZ VPS."
  echo "Try Nyr's OpenVPN script: https://github.com/Nyr/openvpn-install"
  exit 1
fi

if [ "$(id -u)" != 0 ]; then
  echo "Sorry, you need to run this script as root."
  exit 1
fi

if [ ! -f /sys/class/net/eth0/operstate ]; then
  echo "Network interface 'eth0' is not available. Aborting."
  exit 1
fi

if [ -z "$IPSEC_PSK" ] || [ -z "$VPN_USER" ] || [ -z "$VPN_PASSWORD" ]; then
  echo "VPN credentials cannot be empty, please edit the VPN script."
  exit 1
fi

# Create and change to working dir
mkdir -p /opt/src
cd /opt/src || { echo "Failed to change working directory to /opt/src. Aborting."; exit 1; }

# Update package index and install Wget and dig (dnsutils)
export DEBIAN_FRONTEND=noninteractive
apt-get -y update
apt-get -y install wget dnsutils

echo
echo 'Please wait... Trying to find Public/Private IP of this server.'
echo
echo 'If the script hangs here for more than a few minutes, press Ctrl-C to interrupt,'
echo 'then edit and comment out the next two lines PUBLIC_IP= and PRIVATE_IP=, or replace'
echo 'them with actual IPs. If your server only has a public IP, put it on both lines.'
echo

# In Amazon EC2, these two variables will be found automatically.
# For all other servers, you may replace them with the actual IPs,
# or comment out and let the script auto-detect in the next section.
# If your server only has a public IP, put it on both lines.
PUBLIC_IP=$(wget --retry-connrefused -t 3 -T 15 -qO- 'http://169.254.169.254/latest/meta-data/public-ipv4')
PRIVATE_IP=$(wget --retry-connrefused -t 3 -T 15 -qO- 'http://169.254.169.254/latest/meta-data/local-ipv4')

# Attempt to find server IPs for non-EC2 servers
[ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)
[ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(wget -t 3 -T 15 -qO- http://ipv4.icanhazip.com)
[ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(wget -t 3 -T 15 -qO- http://ipecho.net/plain)
[ -z "$PRIVATE_IP" ] && PRIVATE_IP=$(ip -4 route get 1 | awk '{print $NF;exit}')
[ -z "$PRIVATE_IP" ] && PRIVATE_IP=$(ifconfig eth0 | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*')

# Check IPs for correct format
IP_REGEX="^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$"
if ! printf %s "$PUBLIC_IP" | grep -Eq "$IP_REGEX"; then
  echo "Cannot find valid Public IP, please edit the VPN script manually."
  exit 1
fi
if ! printf %s "$PRIVATE_IP" | grep -Eq "$IP_REGEX"; then
  echo "Cannot find valid Private IP, please edit the VPN script manually."
  exit 1
fi

# Install necessary packages
apt-get -y install libnss3-dev libnspr4-dev pkg-config libpam0g-dev \
        libcap-ng-dev libcap-ng-utils libselinux1-dev \
        libcurl4-nss-dev libgmp3-dev flex bison gcc make \
        libunbound-dev libnss3-tools libevent-dev
apt-get -y --no-install-recommends install xmlto
apt-get -y install xl2tpd

# Install Fail2Ban to protect SSH server
apt-get -y install fail2ban

# Compile and install Libreswan
SWAN_VER=3.16
SWAN_FILE="libreswan-${SWAN_VER}.tar.gz"
SWAN_URL="https://download.libreswan.org/${SWAN_FILE}"
wget -t 3 -T 30 -nv -O "$SWAN_FILE" "$SWAN_URL"
[ ! -f "$SWAN_FILE" ] && { echo "Cannot retrieve Libreswan source file. Aborting."; exit 1; }
/bin/rm -rf "/opt/src/libreswan-${SWAN_VER}"
tar xvzf "$SWAN_FILE" && rm -f "$SWAN_FILE"
cd "libreswan-${SWAN_VER}" || { echo "Failed to enter Libreswan source dir. Aborting."; exit 1; }
make programs && make install

# Check if the install was successful
/usr/local/sbin/ipsec --version 2>/dev/null | grep -qs "${SWAN_VER}"
[ "$?" != "0" ] && { echo "Sorry, Libreswan ${SWAN_VER} failed to compile or install. Aborting."; exit 1; }

# Prepare various config files
# Create IPsec (Libreswan) configuration
SYS_DT="$(/bin/date +%Y-%m-%d-%H:%M:%S)"
/bin/cp -f /etc/ipsec.conf "/etc/ipsec.conf.old-${SYS_DT}" 2>/dev/null
cat > /etc/ipsec.conf <<EOF
version 2.0

config setup
  dumpdir=/var/run/pluto/
  nat_traversal=yes
  virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12,%v4:!192.168.42.0/24
  oe=off
  protostack=netkey
  nhelpers=0
  interfaces=%defaultroute

conn vpnpsk
  connaddrfamily=ipv4
  auto=add
  left=$PRIVATE_IP
  leftid=$PUBLIC_IP
  leftsubnet=$PRIVATE_IP/32
  leftnexthop=%defaultroute
  leftprotoport=17/1701
  rightprotoport=17/%any
  right=%any
  rightsubnetwithin=0.0.0.0/0
  forceencaps=yes
  authby=secret
  pfs=no
  type=transport
  auth=esp
  ike=3des-sha1,aes-sha1
  phase2alg=3des-sha1,aes-sha1
  rekey=no
  keyingtries=5
  dpddelay=30
  dpdtimeout=120
  dpdaction=clear
EOF

# Specify IPsec PSK
/bin/cp -f /etc/ipsec.secrets "/etc/ipsec.secrets.old-${SYS_DT}" 2>/dev/null
cat > /etc/ipsec.secrets <<EOF
$PUBLIC_IP  %any  : PSK "$IPSEC_PSK"
EOF

# Create xl2tpd config
/bin/cp -f /etc/xl2tpd/xl2tpd.conf "/etc/xl2tpd/xl2tpd.conf.old-${SYS_DT}" 2>/dev/null
cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701

;debug avp = yes
;debug network = yes
;debug state = yes
;debug tunnel = yes

[lns default]
ip range = 192.168.42.10-192.168.42.250
local ip = 192.168.42.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
;ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

# Specify xl2tpd options
/bin/cp -f /etc/ppp/options.xl2tpd "/etc/ppp/options.xl2tpd.old-${SYS_DT}" 2>/dev/null
cat > /etc/ppp/options.xl2tpd <<EOF
ipcp-accept-local
ipcp-accept-remote
ms-dns 8.8.8.8
ms-dns 8.8.4.4
noccp
auth
crtscts
idle 1800
mtu 1280
mru 1280
lock
lcp-echo-failure 10
lcp-echo-interval 60
connect-delay 5000
EOF

# Create VPN credentials
/bin/cp -f /etc/ppp/chap-secrets "/etc/ppp/chap-secrets.old-${SYS_DT}" 2>/dev/null
cat > /etc/ppp/chap-secrets <<EOF
# Secrets for authentication using CHAP
# client  server  secret  IP addresses
"$VPN_USER" l2tpd "$VPN_PASSWORD" *
EOF

# Update sysctl settings for VPN and performance
if ! grep -qs "hwdsl2 VPN script" /etc/sysctl.conf; then
/bin/cp -f /etc/sysctl.conf "/etc/sysctl.conf.old-${SYS_DT}" 2>/dev/null
cat >> /etc/sysctl.conf <<EOF

# Added by hwdsl2 VPN script
kernel.msgmnb = 65536
kernel.msgmax = 65536
kernel.shmmax = 68719476736
kernel.shmall = 4294967296

net.ipv4.ip_forward = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.lo.send_redirects = 0
net.ipv4.conf.eth0.send_redirects = 0
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.lo.rp_filter = 0
net.ipv4.conf.eth0.rp_filter = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

net.core.wmem_max = 12582912
net.core.rmem_max = 12582912
net.ipv4.tcp_rmem = 10240 87380 12582912
net.ipv4.tcp_wmem = 10240 87380 12582912
EOF
fi

# Create basic IPTables rules. First check if there are existing IPTables rules loaded.
# 1. If IPTables is "empty", write out the new set of rules below.
# 2. If *not* empty, insert new rules and save them together with existing ones.
if ! grep -qs "hwdsl2 VPN script" /etc/iptables.rules; then
/bin/cp -f /etc/iptables.rules "/etc/iptables.rules.old-${SYS_DT}" 2>/dev/null
/usr/sbin/service fail2ban stop >/dev/null 2>&1
if [ "$(/sbin/iptables-save | grep -c '^\-')" = "0" ]; then
cat > /etc/iptables.rules <<EOF
# Added by hwdsl2 VPN script
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:ICMPALL - [0:0]
-A INPUT -m conntrack --ctstate INVALID -j DROP
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -d 127.0.0.0/8 -j REJECT
-A INPUT -p icmp --icmp-type 255 -j ICMPALL
-A INPUT -p udp --dport 67:68 --sport 67:68 -j ACCEPT
-A INPUT -p tcp --dport 22 -j ACCEPT
-A INPUT -p udp -m multiport --dports 500,4500 -j ACCEPT
-A INPUT -p udp --dport 1701 -m policy --dir in --pol ipsec -j ACCEPT
-A INPUT -p udp --dport 1701 -j DROP
-A INPUT -j DROP
-A FORWARD -m conntrack --ctstate INVALID -j DROP
-A FORWARD -i eth+ -o ppp+ -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -i ppp+ -o eth+ -j ACCEPT
# If you wish to allow traffic between VPN clients themselves, uncomment this line:
# -A FORWARD -i ppp+ -o ppp+ -s 192.168.42.0/24 -d 192.168.42.0/24 -j ACCEPT
-A FORWARD -j DROP
-A ICMPALL -p icmp -f -j DROP
-A ICMPALL -p icmp --icmp-type 0 -j ACCEPT
-A ICMPALL -p icmp --icmp-type 3 -j ACCEPT
-A ICMPALL -p icmp --icmp-type 4 -j ACCEPT
-A ICMPALL -p icmp --icmp-type 8 -j ACCEPT
-A ICMPALL -p icmp --icmp-type 11 -j ACCEPT
-A ICMPALL -p icmp -j DROP
COMMIT
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 192.168.42.0/24 -o eth+ -j SNAT --to-source "${PRIVATE_IP}"
COMMIT
EOF

else

iptables -I INPUT 1 -p udp -m multiport --dports 500,4500 -j ACCEPT
iptables -I INPUT 2 -p udp --dport 1701 -m policy --dir in --pol ipsec -j ACCEPT
iptables -I INPUT 3 -p udp --dport 1701 -j DROP
iptables -I FORWARD 1 -m conntrack --ctstate INVALID -j DROP
iptables -I FORWARD 2 -i eth+ -o ppp+ -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -I FORWARD 3 -i ppp+ -o eth+ -j ACCEPT
# iptables -I FORWARD 4 -i ppp+ -o ppp+ -s 192.168.42.0/24 -d 192.168.42.0/24 -j ACCEPT
iptables -A FORWARD -j DROP
iptables -t nat -I POSTROUTING -s 192.168.42.0/24 -o eth+ -j SNAT --to-source "${PRIVATE_IP}"

echo "# Modified by hwdsl2 VPN script" > /etc/iptables.rules
/sbin/iptables-save >> /etc/iptables.rules
fi
fi

# Create basic IP6Tables (IPv6) rules
if ! grep -qs "hwdsl2 VPN script" /etc/ip6tables.rules; then
/bin/cp -f /etc/ip6tables.rules "/etc/ip6tables.rules.old-${SYS_DT}" 2>/dev/null
cat > /etc/ip6tables.rules <<EOF
# Added by hwdsl2 VPN script
*filter
:INPUT ACCEPT [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -m rt --rt-type 0 -j DROP
-A INPUT -s fe80::/10 -j ACCEPT
-A INPUT -p ipv6-icmp -j ACCEPT
-A INPUT -j DROP
COMMIT
EOF
fi

# Load IPTables rules at system boot
cat > /etc/network/if-pre-up.d/iptablesload <<EOF
#!/bin/sh
/sbin/iptables-restore < /etc/iptables.rules
exit 0
EOF

cat > /etc/network/if-pre-up.d/ip6tablesload <<EOF
#!/bin/sh
/sbin/ip6tables-restore < /etc/ip6tables.rules
exit 0
EOF

# Update rc.local to start services at boot
if ! grep -qs "hwdsl2 VPN script" /etc/rc.local; then
/bin/cp -f /etc/rc.local "/etc/rc.local.old-${SYS_DT}" 2>/dev/null
/bin/sed --follow-symlinks -i -e '/^exit 0/d' /etc/rc.local
cat >> /etc/rc.local <<EOF

# Added by hwdsl2 VPN script
/usr/sbin/service fail2ban restart || /bin/true
/usr/sbin/service ipsec start
/usr/sbin/service xl2tpd start
echo 1 > /proc/sys/net/ipv4/ip_forward
exit 0
EOF
fi

# Initialize Libreswan DB
if [ ! -f /etc/ipsec.d/cert8.db ] ; then
   echo > /var/tmp/libreswan-nss-pwd
   /usr/bin/certutil -N -f /var/tmp/libreswan-nss-pwd -d /etc/ipsec.d
   /bin/rm -f /var/tmp/libreswan-nss-pwd
fi

# Reload sysctl.conf
/sbin/sysctl -p

# Update file attributes
/bin/chmod +x /etc/rc.local
/bin/chmod +x /etc/network/if-pre-up.d/iptablesload
/bin/chmod +x /etc/network/if-pre-up.d/ip6tablesload
/bin/chmod 600 /etc/ipsec.secrets* /etc/ppp/chap-secrets*

# Apply new IPTables rules
/sbin/iptables-restore < /etc/iptables.rules
/sbin/ip6tables-restore < /etc/ip6tables.rules

# Restart services
/usr/sbin/service fail2ban stop >/dev/null 2>&1
/usr/sbin/service ipsec stop >/dev/null 2>&1
/usr/sbin/service xl2tpd stop >/dev/null 2>&1
/usr/sbin/service fail2ban start
/usr/sbin/service ipsec start
/usr/sbin/service xl2tpd start
