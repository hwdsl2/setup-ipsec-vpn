#!/bin/sh
#
# Script for automatic setup of an IPsec/L2TP VPN server on 64-bit CentOS/RHEL 6 & 7.
# Works on dedicated servers and any KVM- or Xen-based Virtual Private Server (VPS).
#
# DO NOT RUN THIS SCRIPT ON YOUR PC OR MAC! THIS IS MEANT TO BE RUN
# ON YOUR DEDICATED SERVER OR VPS!
#
# Copyright (C) 2015-2016 Lin Song
# Based on the work of Thomas Sarlandie (Copyright 2012)
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

# ------------------------------------------------------------

# Define your own values for these variables
# - All values MUST be quoted using 'single quotes'
# - DO NOT use these characters inside values:  \ " '

IPSEC_PSK='your_ipsec_pre_shared_key'
VPN_USER='your_vpn_username'
VPN_PASSWORD='your_very_secure_password'

# Please read IMPORTANT NOTES at:
# https://github.com/hwdsl2/setup-ipsec-vpn#important-notes

# ------------------------------------------------------------

if [ "$(uname)" = "Darwin" ]; then
  echo 'DO NOT run this script on your Mac! It should only be used on a server.'
  exit 1
fi

if [ ! -f /etc/redhat-release ]; then
  echo "This script only supports CentOS or RHEL systems."
  exit 1
fi

if ! grep -qs -e "release 6" -e "release 7" /etc/redhat-release; then
  echo "This script only supports CentOS/RHEL 6 and 7."
  exit 1
fi

if [ "$(uname -m)" != "x86_64" ]; then
  echo "This script only supports 64-bit CentOS/RHEL."
  exit 1
fi

if [ -f /proc/user_beancounters ]; then
  echo "This script does NOT support OpenVZ VPS."
  echo "Try alternative: https://github.com/Nyr/openvpn-install"
  exit 1
fi

if [ "$(id -u)" != 0 ]; then
  echo "Script must be run as root. Try 'sudo sh $0'"
  exit 1
fi

if [ ! -f /sys/class/net/eth0/operstate ]; then
  echo "Network interface 'eth0' is not available. Aborting."
  echo
  echo "CentOS 7 users should change interfaces to use old naming convention"
  echo "before running this script. See: https://wiki.centos.org/FAQ/CentOS7"
  exit 1
fi

if [ -z "$IPSEC_PSK" ] || [ -z "$VPN_USER" ] || [ -z "$VPN_PASSWORD" ]; then
  echo "VPN credentials cannot be empty. Edit the script and re-enter."
  exit 1
fi

# Create and change to working dir
mkdir -p /opt/src
cd /opt/src || { echo "Failed to change working dir to /opt/src. Aborting."; exit 1; }

# Install Wget and dig (bind-utils)
yum -y install wget bind-utils

echo
echo 'Trying to find Public/Private IP of this server...'
echo
echo 'In case the script hangs here for more than a few minutes, press Ctrl-C to interrupt.'
echo 'Then edit it and follow instructions to manually enter server IPs.'
echo

# In Amazon EC2, these two variables will be retrieved from metadata.
# For all other servers, you may replace them with actual IPs,
# or comment them out to use auto-detection in the next section.
# If your server only has a public IP, put that IP on both lines.
PUBLIC_IP=$(wget --retry-connrefused -t 3 -T 15 -qO- 'http://169.254.169.254/latest/meta-data/public-ipv4')
PRIVATE_IP=$(wget --retry-connrefused -t 3 -T 15 -qO- 'http://169.254.169.254/latest/meta-data/local-ipv4')

# Try to determine IPs for non-EC2 servers
[ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)
[ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(wget -t 3 -T 15 -qO- http://ipv4.icanhazip.com)
[ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(wget -t 3 -T 15 -qO- http://ipecho.net/plain)
[ -z "$PRIVATE_IP" ] && PRIVATE_IP=$(ip -4 route get 1 | awk '{print $NF;exit}')
[ -z "$PRIVATE_IP" ] && PRIVATE_IP=$(ifconfig eth0 | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*')

# Check IPs for correct format
IP_REGEX="^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$"
if ! printf %s "$PUBLIC_IP" | grep -Eq "$IP_REGEX"; then
  echo "Cannot find valid public IP. Edit the script and manually enter."
  exit 1
fi
if ! printf %s "$PRIVATE_IP" | grep -Eq "$IP_REGEX"; then
  echo "Cannot find valid private IP. Edit the script and manually enter."
  exit 1
fi

# Add the EPEL repository
yum -y install epel-release
yum list installed epel-release >/dev/null 2>&1
if [ "$?" != "0" ]; then
  if grep -qs "release 6" /etc/redhat-release; then
    EPEL_RPM=epel-release-latest-6.noarch.rpm
    EPEL_URL=https://dl.fedoraproject.org/pub/epel/$EPEL_RPM
  elif grep -qs "release 7" /etc/redhat-release; then
    EPEL_RPM=epel-release-latest-7.noarch.rpm
    EPEL_URL=https://dl.fedoraproject.org/pub/epel/$EPEL_RPM
  fi
  wget -t 3 -T 30 -nv -O "$EPEL_RPM" "$EPEL_URL"
  [ "$?" != "0" ] && { echo "Cannot retrieve EPEL repo RPM file. Aborting."; exit 1; }
  rpm -ivh --force "$EPEL_RPM" && /bin/rm -f "$EPEL_RPM"
fi

# Install necessary packages
yum -y install nss-devel nspr-devel pkgconfig pam-devel \
    libcap-ng-devel libselinux-devel \
    curl-devel flex bison gcc make \
    fipscheck-devel unbound-devel xmlto
yum -y install ppp xl2tpd

# Install Fail2Ban to protect SSH
yum -y install fail2ban

# Install IP6Tables for CentOS/RHEL 6
if grep -qs "release 6" /etc/redhat-release; then
  yum -y install iptables-ipv6
fi

# Installed Libevent2. Use backported version for CentOS 6.
if grep -qs "release 6" /etc/redhat-release; then
  LE2_URL=https://download.libreswan.org/binaries/rhel/6/x86_64
  RPM1=libevent2-2.0.22-1.el6.x86_64.rpm
  RPM2=libevent2-devel-2.0.22-1.el6.x86_64.rpm
  wget -t 3 -T 30 -nv -O "$RPM1" "$LE2_URL/$RPM1"
  [ "$?" != "0" ] && { echo "Cannot retrieve Libevent2 RPM file(s). Aborting."; exit 1; }
  wget -t 3 -T 30 -nv -O "$RPM2" "$LE2_URL/$RPM2"
  [ "$?" != "0" ] && { echo "Cannot retrieve Libevent2 RPM file(s). Aborting."; exit 1; }
  rpm -ivh --force "$RPM1" "$RPM2" && /bin/rm -f "$RPM1" "$RPM2"
elif grep -qs "release 7" /etc/redhat-release; then
  yum -y install libevent-devel
fi

# Compile and install Libreswan
SWAN_VER=3.17
SWAN_FILE="libreswan-${SWAN_VER}.tar.gz"
SWAN_URL="https://download.libreswan.org/$SWAN_FILE"
wget -t 3 -T 30 -nv -O "$SWAN_FILE" "$SWAN_URL"
[ "$?" != "0" ] && { echo "Cannot retrieve Libreswan source file. Aborting."; exit 1; }
/bin/rm -rf "/opt/src/libreswan-$SWAN_VER"
tar xvzf "$SWAN_FILE" && /bin/rm -f "$SWAN_FILE"
cd "libreswan-$SWAN_VER" || { echo "Failed to enter Libreswan source dir. Aborting."; exit 1; }
# Workaround for Libreswan compile issues
cat > Makefile.inc.local <<EOF
WERROR_CFLAGS =
EOF
make programs && make install

# Check if Libreswan install was successful
/usr/local/sbin/ipsec --version 2>/dev/null | grep -qs "$SWAN_VER"
[ "$?" != "0" ] && { echo; echo "Sorry, Libreswan $SWAN_VER failed to build. Aborting."; exit 1; }

# Prepare various config files
# Create IPsec (Libreswan) config
SYS_DT="$(date +%Y-%m-%d-%H:%M:%S)"
/bin/cp -f /etc/ipsec.conf "/etc/ipsec.conf.old-$SYS_DT" 2>/dev/null
cat > /etc/ipsec.conf <<EOF
version 2.0

config setup
  virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12,%v4:!192.168.42.0/24
  protostack=netkey
  nhelpers=0
  interfaces=%defaultroute

conn vpnpsk
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
/bin/cp -f /etc/ipsec.secrets "/etc/ipsec.secrets.old-$SYS_DT" 2>/dev/null
cat > /etc/ipsec.secrets <<EOF
$PUBLIC_IP  %any  : PSK "$IPSEC_PSK"
EOF

# Create xl2tpd config
/bin/cp -f /etc/xl2tpd/xl2tpd.conf "/etc/xl2tpd/xl2tpd.conf.old-$SYS_DT" 2>/dev/null
cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701

[lns default]
ip range = 192.168.42.10-192.168.42.250
local ip = 192.168.42.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

# Specify xl2tpd options
/bin/cp -f /etc/ppp/options.xl2tpd "/etc/ppp/options.xl2tpd.old-$SYS_DT" 2>/dev/null
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
/bin/cp -f /etc/ppp/chap-secrets "/etc/ppp/chap-secrets.old-$SYS_DT" 2>/dev/null
cat > /etc/ppp/chap-secrets <<EOF
# Secrets for authentication using CHAP
# client  server  secret  IP addresses
"$VPN_USER" l2tpd "$VPN_PASSWORD" *
EOF

# Update sysctl settings for VPN and performance
if ! grep -qs "hwdsl2 VPN script" /etc/sysctl.conf; then
/bin/cp -f /etc/sysctl.conf "/etc/sysctl.conf.old-$SYS_DT" 2>/dev/null
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

# Create basic IPTables rules. First check if there are existing rules.
# 1. If IPTables is "empty", write out the new set of rules.
# 2. If *not* empty, insert new rules and save them together with existing ones.
if ! grep -qs "hwdsl2 VPN script" /etc/sysconfig/iptables; then
/bin/cp -f /etc/sysconfig/iptables "/etc/sysconfig/iptables.old-$SYS_DT" 2>/dev/null
service fail2ban stop >/dev/null 2>&1
if [ "$(iptables-save | grep -c '^\-')" = "0" ]; then
cat > /etc/sysconfig/iptables <<EOF
# Added by hwdsl2 VPN script
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m conntrack --ctstate INVALID -j DROP
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -d 127.0.0.0/8 -j REJECT
-A INPUT -p icmp -j ACCEPT
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
COMMIT
*nat
:PREROUTING ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 192.168.42.0/24 -o eth+ -j SNAT --to-source "$PRIVATE_IP"
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
iptables -t nat -I POSTROUTING -s 192.168.42.0/24 -o eth+ -j SNAT --to-source "$PRIVATE_IP"

echo "# Modified by hwdsl2 VPN script" > /etc/sysconfig/iptables
iptables-save >> /etc/sysconfig/iptables
fi
fi

# Create basic IP6Tables (IPv6) rules
if ! grep -qs "hwdsl2 VPN script" /etc/sysconfig/ip6tables; then
/bin/cp -f /etc/sysconfig/ip6tables "/etc/sysconfig/ip6tables.old-$SYS_DT" 2>/dev/null
cat > /etc/sysconfig/ip6tables <<EOF
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

# Create basic Fail2Ban rules if not present
if [ ! -f /etc/fail2ban/jail.local ] ; then
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
ignoreip = 127.0.0.1/8
bantime  = 600
findtime  = 600
maxretry = 5
backend = auto

[ssh-iptables]
enabled  = true
filter   = sshd
action   = iptables[name=SSH, port=ssh, protocol=tcp]
logpath  = /var/log/secure
EOF
fi

# Update rc.local to start services at boot
if ! grep -qs "hwdsl2 VPN script" /etc/rc.local; then
/bin/cp -f /etc/rc.local "/etc/rc.local.old-$SYS_DT" 2>/dev/null
cat >> /etc/rc.local <<EOF

# Added by hwdsl2 VPN script
iptables-restore < /etc/sysconfig/iptables
ip6tables-restore < /etc/sysconfig/ip6tables
service fail2ban restart
service ipsec start
service xl2tpd start
echo 1 > /proc/sys/net/ipv4/ip_forward
EOF
fi

# Initialize Libreswan DB
if [ ! -f /etc/ipsec.d/cert8.db ] ; then
   echo > /var/tmp/libreswan-nss-pwd
   certutil -N -f /var/tmp/libreswan-nss-pwd -d /etc/ipsec.d
   /bin/rm -f /var/tmp/libreswan-nss-pwd
fi

# Restore SELinux contexts
restorecon /etc/ipsec.d/*db 2>/dev/null
restorecon /usr/local/sbin -Rv 2>/dev/null
restorecon /usr/local/libexec/ipsec -Rv 2>/dev/null

# Reload sysctl.conf
sysctl -p

# Update file attributes
chmod +x /etc/rc.local
chmod 600 /etc/ipsec.secrets* /etc/ppp/chap-secrets*

# Apply new IPTables rules
iptables-restore < /etc/sysconfig/iptables
ip6tables-restore < /etc/sysconfig/ip6tables >/dev/null 2>&1

# Restart services
service fail2ban stop >/dev/null 2>&1
service ipsec stop >/dev/null 2>&1
service xl2tpd stop >/dev/null 2>&1
service fail2ban start
service ipsec start
service xl2tpd start

echo
echo '============================================================'
echo 'IPsec/L2TP VPN server setup is complete!'
echo
echo 'Connect to your new VPN with these details:'
echo
echo "Server IP: $PUBLIC_IP"
echo "IPsec PSK: $IPSEC_PSK"
echo "Username: $VPN_USER"
echo "Password: $VPN_PASSWORD"
echo '============================================================'
echo
echo 'Please read IMPORTANT NOTES at:'
echo 'https://github.com/hwdsl2/setup-ipsec-vpn#important-notes'
echo

exit 0
