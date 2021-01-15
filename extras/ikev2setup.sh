#!/bin/bash
#
# Script to set up IKEv2 on Ubuntu, Debian, CentOS/RHEL and Amazon Linux 2
#
# The latest version of this script is available at:
# https://github.com/hwdsl2/setup-ipsec-vpn
#
# Copyright (C) 2020-2021 Lin Song <linsongui@gmail.com>
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
SYS_DT=$(date +%F-%T | tr ':' '_')

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

create_mobileconfig() {

  bigecho2 "Creating .mobileconfig for iOS and macOS..."

  [ -z "$p12_password" ] && exiterr "Password for .p12 file cannot be empty."

  if [ -z "$server_addr" ]; then
    server_addr=$(grep "leftcert=" /etc/ipsec.d/ikev2.conf | cut -f2 -d=)
    [ -z "$server_addr" ] && server_addr=$(grep "leftcert=" /etc/ipsec.conf | cut -f2 -d=)
    check_ip "$server_addr" || check_dns_name "$server_addr" || exiterr "Could not get VPN server address."
  fi

  if ! command -v base64 >/dev/null 2>&1 || ! command -v uuidgen >/dev/null 2>&1; then
    if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] || [ "$os_type" = "raspbian" ]; then
      export DEBIAN_FRONTEND=noninteractive
      apt-get -yqq update || exiterr "'apt-get update' failed."
      apt-get -yqq install coreutils uuid-runtime || exiterr "'apt-get install' failed."
    else
      yum -yq install coreutils util-linux || exiterr "'yum install' failed."
    fi
  fi

  if [ "$in_container" = "0" ]; then
    p12_base64=$(base64 -w 52 ~/"$client_name-$SYS_DT.p12")
  else
    p12_base64=$(base64 -w 52 "/etc/ipsec.d/$client_name-$SYS_DT.p12")
  fi
  [ -z "$p12_base64" ] && exiterr "Could not encode .p12 file."

  ca_base64=$(certutil -L -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" -a | grep -v CERTIFICATE)
  [ -z "$ca_base64" ] && exiterr "Could not encode IKEv2 VPN CA certificate."

  uuid1=$(uuidgen)
  [ -z "$uuid1" ] && exiterr "Could not generate UUID value."

  if [ "$in_container" = "0" ]; then
    mc_file=~/"$client_name-$SYS_DT.mobileconfig"
  else
    mc_file="/etc/ipsec.d/$client_name-$SYS_DT.mobileconfig"
  fi

cat > "$mc_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>IKEv2</key>
      <dict>
        <key>AuthenticationMethod</key>
        <string>Certificate</string>
        <key>ChildSecurityAssociationParameters</key>
        <dict>
          <key>DiffieHellmanGroup</key>
          <integer>14</integer>
          <key>EncryptionAlgorithm</key>
          <string>AES-256-GCM</string>
          <key>LifeTimeInMinutes</key>
          <integer>1440</integer>
        </dict>
        <key>DeadPeerDetectionRate</key>
        <string>Medium</string>
        <key>DisableRedirect</key>
        <true/>
        <key>EnableCertificateRevocationCheck</key>
        <integer>0</integer>
        <key>EnablePFS</key>
        <integer>0</integer>
        <key>IKESecurityAssociationParameters</key>
        <dict>
          <key>DiffieHellmanGroup</key>
          <integer>14</integer>
          <key>EncryptionAlgorithm</key>
          <string>AES-256</string>
          <key>IntegrityAlgorithm</key>
          <string>SHA2-256</string>
          <key>LifeTimeInMinutes</key>
          <integer>1440</integer>
        </dict>
        <key>LocalIdentifier</key>
        <string>$client_name</string>
        <key>PayloadCertificateUUID</key>
        <string>$uuid1</string>
        <key>OnDemandEnabled</key>
        <integer>0</integer>
        <key>OnDemandRules</key>
        <array>
          <dict>
          <key>Action</key>
          <string>Connect</string>
          </dict>
        </array>
        <key>RemoteAddress</key>
        <string>$server_addr</string>
        <key>RemoteIdentifier</key>
        <string>$server_addr</string>
        <key>UseConfigurationAttributeInternalIPSubnet</key>
        <integer>0</integer>
      </dict>
      <key>IPv4</key>
      <dict>
        <key>OverridePrimary</key>
        <integer>1</integer>
      </dict>
      <key>PayloadDescription</key>
      <string>Configures VPN settings</string>
      <key>PayloadDisplayName</key>
      <string>VPN</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.vpn.managed.$(uuidgen)</string>
      <key>PayloadType</key>
      <string>com.apple.vpn.managed</string>
      <key>PayloadUUID</key>
      <string>$(uuidgen)</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>Proxies</key>
      <dict>
        <key>HTTPEnable</key>
        <integer>0</integer>
        <key>HTTPSEnable</key>
        <integer>0</integer>
      </dict>
      <key>UserDefinedName</key>
      <string>$server_addr</string>
      <key>VPNType</key>
      <string>IKEv2</string>
    </dict>
    <dict>
      <key>PayloadCertificateFileName</key>
      <string>$client_name</string>
      <key>PayloadContent</key>
      <data>
$p12_base64
      </data>
      <key>PayloadDescription</key>
      <string>Adds a PKCS#12-formatted certificate</string>
      <key>PayloadDisplayName</key>
      <string>$client_name</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.security.pkcs12.$(uuidgen)</string>
      <key>PayloadType</key>
      <string>com.apple.security.pkcs12</string>
      <key>PayloadUUID</key>
      <string>$uuid1</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
    <dict>
      <key>PayloadContent</key>
      <data>
$ca_base64
      </data>
      <key>PayloadCertificateFileName</key>
      <string>ikev2vpnca</string>
      <key>PayloadDescription</key>
      <string>Adds a CA root certificate</string>
      <key>PayloadDisplayName</key>
      <string>Certificate Authority (CA)</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.security.root.$(uuidgen)</string>
      <key>PayloadType</key>
      <string>com.apple.security.root</string>
      <key>PayloadUUID</key>
      <string>$(uuidgen)</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
  </array>
  <key>PayloadDisplayName</key>
  <string>IKEv2 VPN configuration ($server_addr)</string>
  <key>PayloadIdentifier</key>
  <string>com.apple.vpn.managed.$(uuidgen)</string>
  <key>PayloadRemovalDisallowed</key>
  <false/>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>$(uuidgen)</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
</dict>
</plist>
EOF

}

new_client() {

  bigecho2 "Generating client certificate..."

  sleep $((RANDOM % 3 + 1))

  certutil -z <(head -c 1024 /dev/urandom) \
    -S -c "IKEv2 VPN CA" -n "$client_name" \
    -s "O=IKEv2 VPN,CN=$client_name" \
    -k rsa -g 4096 -v "$client_validity" \
    -d sql:/etc/ipsec.d -t ",," \
    --keyUsage digitalSignature,keyEncipherment \
    --extKeyUsage serverAuth,clientAuth -8 "$client_name" >/dev/null || exit 1

  bigecho "Exporting .p12 file..."

  p12_password=$(LC_CTYPE=C tr -dc 'A-HJ-NPR-Za-km-z2-9' < /dev/urandom | head -c 16)
  [ -z "$p12_password" ] && exiterr "Could not generate a random password for .p12 file."
  if [ "$in_container" = "0" ]; then
    pk12util -W "$p12_password" -d sql:/etc/ipsec.d -n "$client_name" -o ~/"$client_name-$SYS_DT.p12" || exit 1
  else
    pk12util -W "$p12_password" -d sql:/etc/ipsec.d -n "$client_name" -o "/etc/ipsec.d/$client_name-$SYS_DT.p12" || exit 1
  fi

  create_mobileconfig

}

ikev2setup() {

if grep -qs -e "release 7" -e "release 8" /etc/redhat-release; then
  os_type=centos
  if grep -qs "Red Hat" /etc/redhat-release; then
    os_type=rhel
  fi
elif grep -qs "Amazon Linux release 2" /etc/system-release; then
  os_type=amzn
else
  os_type=$(lsb_release -si 2>/dev/null)
  [ -z "$os_type" ] && [ -f /etc/os-release ] && os_type=$(. /etc/os-release && printf '%s' "$ID")
  case $os_type in
    [Uu]buntu)
      os_type=ubuntu
      ;;
    [Dd]ebian)
      os_type=debian
      ;;
    [Rr]aspbian)
      os_type=raspbian
      ;;
    *)
      exiterr "This script only supports Ubuntu, Debian, CentOS/RHEL 7/8 and Amazon Linux 2."
      exit 1
      ;;
  esac
fi

if [ "$(id -u)" != 0 ]; then
  exiterr "Script must be run as root. Try 'sudo bash $0'"
fi

ipsec_ver=$(/usr/local/sbin/ipsec --version 2>/dev/null)
swan_ver=$(printf '%s' "$ipsec_ver" | sed -e 's/Linux //' -e 's/Libreswan //' -e 's/ (netkey).*//')
if ( ! grep -qs "hwdsl2 VPN script" /etc/sysctl.conf && ! grep -qs "hwdsl2" /opt/src/run.sh ) \
  || ! printf '%s' "$ipsec_ver" | grep -q "Libreswan" \
  || [ ! -f /etc/ppp/chap-secrets ] || [ ! -f /etc/ipsec.d/passwd ]; then
cat 1>&2 <<'EOF'
Error: Your must first set up the IPsec VPN server before setting up IKEv2.
  See: https://github.com/hwdsl2/setup-ipsec-vpn
EOF
  exit 1
fi

case $swan_ver in
  3.19|3.2[01235679]|3.3[12]|4.*)
    /bin/true
    ;;
  *)
cat 1>&2 <<EOF
Error: Libreswan version '$swan_ver' is not supported.
  This script requires one of these versions:
  3.19-3.23, 3.25-3.27, 3.29, 3.31-3.32 or 4.x
  To update Libreswan, see:
  https://github.com/hwdsl2/setup-ipsec-vpn#upgrade-libreswan
EOF
    exit 1
    ;;
esac

command -v certutil >/dev/null 2>&1 || exiterr "'certutil' not found. Abort."
command -v pk12util >/dev/null 2>&1 || exiterr "'pk12util' not found. Abort."

in_container=0
if grep -qs "hwdsl2" /opt/src/run.sh; then
  in_container=1
fi

if grep -qs "conn ikev2-cp" /etc/ipsec.conf || [ -f /etc/ipsec.d/ikev2.conf ]; then
  echo "It looks like IKEv2 has already been set up on this server."
  printf "Do you want to add a new VPN client? [y/N] "
  read -r response
  case $response in
    [yY][eE][sS]|[yY])
      echo
      ;;
    *)
      echo "Abort. No changes were made."
      exit 1
      ;;
  esac

  echo "Provide a name for the IKEv2 VPN client."
  echo "Use one word only, no special characters except '-' and '_'."
  read -rp "Client name: " client_name
  while [ -z "$client_name" ] || [ "${#client_name}" -gt "64" ] \
    || printf '%s' "$client_name" | LC_ALL=C grep -q '[^A-Za-z0-9_-]\+' \
    || certutil -L -d sql:/etc/ipsec.d -n "$client_name" >/dev/null 2>&1; do
    if [ -z "$client_name" ] || [ "${#client_name}" -gt "64" ] \
      || printf '%s' "$client_name" | LC_ALL=C grep -q '[^A-Za-z0-9_-]\+'; then
      echo "Invalid client name."
    else
      echo "Invalid client name. Client '$client_name' already exists."
    fi
    read -rp "Client name: " client_name
  done

  echo
  echo "Specify the validity period (in months) for this VPN client certificate."
  read -rp "Enter a number between 1 and 120: [120] " client_validity
  [ -z "$client_validity" ] && client_validity=120
  while printf '%s' "$client_validity" | LC_ALL=C grep -q '[^0-9]\+' \
    || [ "$client_validity" -lt "1" ] || [ "$client_validity" -gt "120" ] \
    || [ "$client_validity" != "$((10#$client_validity))" ]; do
    echo "Invalid validity period."
    read -rp "Enter a number between 1 and 120: [120] " client_validity
    [ -z "$client_validity" ] && client_validity=120
  done

  # Create client configuration
  new_client

cat <<EOF

===============================================================

New IKEv2 VPN client "$client_name" added!

Client configuration is available at:

EOF

if [ "$in_container" = "0" ]; then
  printf '%s\n' ~/"$client_name-$SYS_DT.p12 (for Windows & Android)"
  printf '%s\n' ~/"$client_name-$SYS_DT.mobileconfig (for iOS & macOS)"
else
  printf '%s\n' "/etc/ipsec.d/$client_name-$SYS_DT.p12 (for Windows & Android)"
  printf '%s\n' "/etc/ipsec.d/$client_name-$SYS_DT.mobileconfig (for iOS & macOS)"
fi

cat <<EOF

(Important) Password for .p12 and .mobileconfig files:
$p12_password
Write this down, you'll need it to import to your device!

Next steps: Configure IKEv2 VPN clients. See:
https://git.io/ikev2clients

To add more IKEv2 VPN clients, run this script again.

===============================================================

EOF

  exit 0
fi

if certutil -L -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" >/dev/null 2>&1; then
  exiterr "Certificate 'IKEv2 VPN CA' already exists. Abort."
fi

clear

cat <<'EOF'
Welcome! Use this script to set up IKEv2 after setting up your own IPsec VPN server.
Alternatively, you may manually set up IKEv2. See: https://git.io/ikev2

I need to ask you a few questions before starting setup.
You can use the default options and just press enter if you are OK with them.

EOF

echo "Do you want IKEv2 VPN clients to connect to this server using a DNS name,"
printf "e.g. vpn.example.com, instead of its IP address? [y/N] "
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
  echo "Trying to auto discover IP of this server..."
  echo
  public_ip=$(dig @resolver1.opendns.com -t A -4 myip.opendns.com +short)
  check_ip "$public_ip" || public_ip=$(wget -t 3 -T 15 -qO- http://ipv4.icanhazip.com)
  read -rp "Enter the IPv4 address of this VPN server: [$public_ip] " server_addr
  [ -z "$server_addr" ] && server_addr="$public_ip"
  until check_ip "$server_addr"; do
    echo "Invalid IP address."
    read -rp "Enter the IPv4 address of this VPN server: [$public_ip] " server_addr
    [ -z "$server_addr" ] && server_addr="$public_ip"
  done
fi

if certutil -L -d sql:/etc/ipsec.d -n "$server_addr" >/dev/null 2>&1; then
  exiterr "Certificate '$server_addr' already exists. Abort."
fi

# Enter client name
echo
echo "Provide a name for the IKEv2 VPN client."
echo "Use one word only, no special characters except '-' and '_'."
read -rp "Client name: [vpnclient] " client_name
[ -z "$client_name" ] && client_name=vpnclient
while [ "${#client_name}" -gt "64" ] \
  || printf '%s' "$client_name" | LC_ALL=C grep -q '[^A-Za-z0-9_-]\+' \
  || certutil -L -d sql:/etc/ipsec.d -n "$client_name" >/dev/null 2>&1; do
    if [ "${#client_name}" -gt "64" ] \
      || printf '%s' "$client_name" | LC_ALL=C grep -q '[^A-Za-z0-9_-]\+'; then
      echo "Invalid client name."
    else
      echo "Invalid client name. Client '$client_name' already exists."
    fi
  read -rp "Client name: [vpnclient] " client_name
  [ -z "$client_name" ] && client_name=vpnclient
done

# Enter validity period
echo
echo "Specify the validity period (in months) for this VPN client certificate."
read -rp "Enter a number between 1 and 120: [120] " client_validity
[ -z "$client_validity" ] && client_validity=120
while printf '%s' "$client_validity" | LC_ALL=C grep -q '[^0-9]\+' \
  || [ "$client_validity" -lt "1" ] || [ "$client_validity" -gt "120" ] \
  || [ "$client_validity" != "$((10#$client_validity))" ]; do
  echo "Invalid validity period."
  read -rp "Enter a number between 1 and 120: [120] " client_validity
  [ -z "$client_validity" ] && client_validity=120
done

# Enter custom DNS servers
echo
echo "By default, clients are set to use Google Public DNS when the VPN is active."
printf "Do you want to specify custom DNS servers for IKEv2? [y/N] "
read -r response
case $response in
  [yY][eE][sS]|[yY])
    use_custom_dns=1
    ;;
  *)
    use_custom_dns=0
    dns_server_1=8.8.8.8
    dns_server_2=8.8.4.4
    dns_servers="8.8.8.8 8.8.4.4"
    ;;
esac

if [ "$use_custom_dns" = "1" ]; then
  read -rp "Enter primary DNS server: " dns_server_1
  until check_ip "$dns_server_1"; do
    echo "Invalid DNS server."
    read -rp "Enter primary DNS server: " dns_server_1
  done

  read -rp "Enter secondary DNS server (Enter to skip): " dns_server_2
  until [ -z "$dns_server_2" ] || check_ip "$dns_server_2"; do
    echo "Invalid DNS server."
    read -rp "Enter secondary DNS server (Enter to skip): " dns_server_2
  done

  if [ -n "$dns_server_2" ]; then
    dns_servers="$dns_server_1 $dns_server_2"
  else
    dns_servers="$dns_server_1"
  fi
else
  echo "Using Google Public DNS (8.8.8.8, 8.8.4.4)."
fi

# Check for MOBIKE support
mobike_support=0
case $swan_ver in
  3.2[35679]|3.3[12]|4.*)
    mobike_support=1
    ;;
esac

if uname -m | grep -qi -e '^arm' -e '^aarch64'; then
  modprobe -q configs
  if [ -f /proc/config.gz ]; then
    if ! zcat /proc/config.gz | grep -q "CONFIG_XFRM_MIGRATE=y"; then
      mobike_support=0
    fi
  fi
fi

kernel_conf="/boot/config-$(uname -r)"
if [ -f "$kernel_conf" ]; then
  if ! grep -qs "CONFIG_XFRM_MIGRATE=y" "$kernel_conf"; then
    mobike_support=0
  fi
fi

# Linux kernels on Ubuntu do not support MOBIKE
if [ "$in_container" = "0" ]; then
  if [ "$os_type" = "ubuntu" ] || uname -v | grep -qi ubuntu; then
    mobike_support=0
  fi
else
  if uname -v | grep -qi ubuntu; then
    mobike_support=0
  fi
fi

echo
echo -n "Checking for MOBIKE support... "
if [ "$mobike_support" = "1" ]; then
  echo "available"
else
  echo "not available"
fi

mobike_enable=0
if [ "$mobike_support" = "1" ]; then
  echo
  echo "The MOBIKE IKEv2 extension allows VPN clients to change network attachment points,"
  echo "e.g. switch between mobile data and Wi-Fi and keep the IPsec tunnel up on the new IP."
  echo
  printf "Do you want to enable MOBIKE support? [Y/n] "
  read -r response
  case $response in
    [yY][eE][sS]|[yY]|'')
      mobike_enable=1
      ;;
    *)
      mobike_enable=0
      ;;
  esac
fi

cat <<EOF

Below are the IKEv2 setup options you selected.
Please double check before continuing!

================================================

VPN server address: $server_addr
VPN client name: $client_name

EOF

if [ "$client_validity" = "1" ]; then
  echo "Client cert valid for: 1 month"
else
  echo "Client cert valid for: $client_validity months"
fi

if [ "$mobike_support" = "1" ]; then
  if [ "$mobike_enable" = "1" ]; then
    echo "MOBIKE support: Enable"
  else
    echo "MOBIKE support: Disable"
  fi
else
  echo "MOBIKE support: Not available"
fi

cat <<EOF
DNS server(s): $dns_servers

================================================

EOF

printf "We are ready to set up IKEv2 now. Do you want to continue? [y/N] "
read -r response
case $response in
  [yY][eE][sS]|[yY])
    echo
    ;;
  *)
    echo "Abort. No changes were made."
    exit 1
    ;;
esac

bigecho2 "Generating CA certificate..."

certutil -z <(head -c 1024 /dev/urandom) \
  -S -x -n "IKEv2 VPN CA" \
  -s "O=IKEv2 VPN,CN=IKEv2 VPN CA" \
  -k rsa -g 4096 -v 120 \
  -d sql:/etc/ipsec.d -t "CT,," -2 >/dev/null <<ANSWERS || exit 1
y

N
ANSWERS

sleep $((RANDOM % 3 + 1))

bigecho2 "Generating VPN server certificate..."

if [ "$use_dns_name" = "1" ]; then
  certutil -z <(head -c 1024 /dev/urandom) \
    -S -c "IKEv2 VPN CA" -n "$server_addr" \
    -s "O=IKEv2 VPN,CN=$server_addr" \
    -k rsa -g 4096 -v 120 \
    -d sql:/etc/ipsec.d -t ",," \
    --keyUsage digitalSignature,keyEncipherment \
    --extKeyUsage serverAuth \
    --extSAN "dns:$server_addr" >/dev/null || exit 1
else
  certutil -z <(head -c 1024 /dev/urandom) \
    -S -c "IKEv2 VPN CA" -n "$server_addr" \
    -s "O=IKEv2 VPN,CN=$server_addr" \
    -k rsa -g 4096 -v 120 \
    -d sql:/etc/ipsec.d -t ",," \
    --keyUsage digitalSignature,keyEncipherment \
    --extKeyUsage serverAuth \
    --extSAN "ip:$server_addr,dns:$server_addr" >/dev/null || exit 1
fi

# Create client configuration
new_client

echo
bigecho "Adding a new IKEv2 connection..."

if ! grep -qs '^include /etc/ipsec\.d/\*\.conf$' /etc/ipsec.conf; then
  echo >> /etc/ipsec.conf
  echo 'include /etc/ipsec.d/*.conf' >> /etc/ipsec.conf
fi

cat > /etc/ipsec.d/ikev2.conf <<EOF

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
  fragmentation=yes
  ike=aes256-sha2,aes128-sha2,aes256-sha1,aes128-sha1,aes256-sha2;modp1024,aes128-sha1;modp1024
  phase2alg=aes_gcm-null,aes128-sha1,aes256-sha1,aes128-sha2,aes256-sha2
  encapsulation=yes
EOF

case $swan_ver in
  3.2[35679]|3.3[12]|4.*)
    if [ -n "$dns_server_2" ]; then
cat >> /etc/ipsec.d/ikev2.conf <<EOF
  modecfgdns="$dns_servers"
EOF
    else
cat >> /etc/ipsec.d/ikev2.conf <<EOF
  modecfgdns=$dns_server_1
EOF
    fi
    if [ "$mobike_enable" = "1" ]; then
      echo "  mobike=yes" >> /etc/ipsec.d/ikev2.conf
    else
      echo "  mobike=no" >> /etc/ipsec.d/ikev2.conf
    fi
    ;;
  3.19|3.2[012])
    if [ -n "$dns_server_2" ]; then
cat >> /etc/ipsec.d/ikev2.conf <<EOF
  modecfgdns1=$dns_server_1
  modecfgdns2=$dns_server_2
EOF
    else
cat >> /etc/ipsec.d/ikev2.conf <<EOF
  modecfgdns1=$dns_server_1
EOF
    fi
    ;;
esac

bigecho "Restarting IPsec service..."

mkdir -p /run/pluto
service ipsec restart

cat <<EOF

===============================================================

IKEv2 VPN setup is now complete!

VPN server address: $server_addr
VPN client name: $client_name

Client configuration is available at:

EOF

if [ "$in_container" = "0" ]; then
  printf '%s\n' ~/"$client_name-$SYS_DT.p12 (for Windows & Android)"
  printf '%s\n' ~/"$client_name-$SYS_DT.mobileconfig (for iOS & macOS)"
else
  printf '%s\n' "/etc/ipsec.d/$client_name-$SYS_DT.p12 (for Windows & Android)"
  printf '%s\n' "/etc/ipsec.d/$client_name-$SYS_DT.mobileconfig (for iOS & macOS)"
fi

cat <<EOF

(Important) Password for .p12 and .mobileconfig files:
$p12_password
Write this down, you'll need it to import to your device!

Next steps: Configure IKEv2 VPN clients. See:
https://git.io/ikev2clients

To add more IKEv2 VPN clients, run this script again.

===============================================================

EOF

}

## Defer setup until we have the complete script
ikev2setup "$@"

exit 0
