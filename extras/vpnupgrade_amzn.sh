#!/bin/sh
#
# Script to upgrade Libreswan on Amazon Linux 2
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

# Specify which Libreswan version to install. See: https://libreswan.org
SWAN_VER=4.4

### DO NOT edit below this line ###

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

exiterr()  { echo "Error: $1" >&2; exit 1; }
exiterr2() { exiterr "'yum install' failed."; }
bigecho() { echo "## $1"; }

vpnupgrade() {

os_arch=$(uname -m | tr -dc 'A-Za-z0-9_-')
if ! grep -qs "Amazon Linux release 2" /etc/system-release; then
  echo "Error: This script only supports Amazon Linux 2." >&2
  echo "For Ubuntu/Debian, use https://git.io/vpnupgrade" >&2
  echo "For CentOS/RHEL, use https://git.io/vpnupgrade-centos" >&2
  exit 1
fi

if [ "$(id -u)" != 0 ]; then
  exiterr "Script must be run as root. Try 'sudo sh $0'"
fi

case $SWAN_VER in
  3.32|4.[1234])
    true
    ;;
  *)
cat 1>&2 <<EOF
Error: Libreswan version '$SWAN_VER' is not supported.
       This script can install one of these versions:
       3.32, 4.1-4.3 or 4.4
EOF
    exit 1
    ;;
esac

ipsec_ver=$(/usr/local/sbin/ipsec --version 2>/dev/null)
swan_ver_old=$(printf '%s' "$ipsec_ver" | sed -e 's/Linux Libreswan //' -e 's/ (netkey).*//' -e 's/^U//' -e 's/\/K.*//')
if ! printf '%s' "$ipsec_ver" | grep -q "Libreswan"; then
cat 1>&2 <<'EOF'
Error: This script requires Libreswan already installed.
       See: https://github.com/hwdsl2/setup-ipsec-vpn
EOF
  exit 1
fi

swan_ver_cur=4.4
swan_ver_url="https://dl.ls20.com/v1/amzn/2/swanverupg?arch=$os_arch&ver1=$swan_ver_old&ver2=$SWAN_VER"
swan_ver_latest=$(wget -t 3 -T 15 -qO- "$swan_ver_url")
if printf '%s' "$swan_ver_latest" | grep -Eq '^([3-9]|[1-9][0-9]{1,2})(\.([0-9]|[1-9][0-9]{1,2})){1,2}$' \
  && [ "$swan_ver_cur" != "$swan_ver_latest" ] \
  && printf '%s\n%s' "$swan_ver_cur" "$swan_ver_latest" | sort -C -V; then
  echo "Note: A newer version of Libreswan ($swan_ver_latest) is available."
  echo "      To update to the new version, exit this script and run:"
  echo "      wget https://git.io/vpnupgrade-amzn -O vpnup.sh && sudo sh vpnup.sh"
  echo
  printf "Do you want to continue anyway? [y/N] "
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
fi

if [ "$swan_ver_old" = "$SWAN_VER" ]; then
  echo "You already have Libreswan version $SWAN_VER installed! "
  echo "If you continue, the same version will be re-installed."
  echo
  printf "Do you want to continue anyway? [y/N] "
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
fi

clear

cat <<EOF
Welcome! This script will build and install Libreswan on your server.
Additional packages required for compilation will also be installed.
It is intended for upgrading servers to a newer Libreswan version.

Current version:    Libreswan $swan_ver_old
Version to install: Libreswan $SWAN_VER

EOF

cat <<'EOF'
Note: This script will make the following changes to your VPN configuration:
      - Fix obsolete ipsec.conf and/or ikev2.conf options
      - Optimize VPN ciphers
      Your other VPN config files will not be modified.

EOF

if [ "$SWAN_VER" != "4.4" ]; then
cat <<'EOF'
WARNING: Older versions of Libreswan could contain known security vulnerabilities.
         See https://libreswan.org/security/ for more information.
         Are you sure you want to install an older version?

EOF
fi

printf "Do you want to continue? [y/N] "
read -r response
case $response in
  [yY][eE][sS]|[yY])
    echo
    bigecho "Please be patient. Setup is continuing..."
    ;;
  *)
    echo "Abort. No changes were made."
    exit 1
    ;;
esac

mkdir -p /opt/src
cd /opt/src || exit 1

bigecho "Installing required packages..."

(
  set -x
  yum -y -q install nss-devel nspr-devel pkgconfig pam-devel \
    libcap-ng-devel libselinux-devel curl-devel nss-tools \
    flex bison gcc make wget sed tar \
    systemd-devel libevent-devel fipscheck-devel >/dev/null
) || exiterr2

bigecho "Downloading Libreswan..."

swan_file="libreswan-$SWAN_VER.tar.gz"
swan_url1="https://github.com/libreswan/libreswan/archive/v$SWAN_VER.tar.gz"
swan_url2="https://download.libreswan.org/$swan_file"
(
  set -x
  wget -t 3 -T 30 -q -O "$swan_file" "$swan_url1" || wget -t 3 -T 30 -q -O "$swan_file" "$swan_url2"
) || exit 1
/bin/rm -rf "/opt/src/libreswan-$SWAN_VER"
tar xzf "$swan_file" && /bin/rm -f "$swan_file"

bigecho "Compiling and installing Libreswan, please wait..."

cd "libreswan-$SWAN_VER" || exit 1
[ "$SWAN_VER" = "4.1" ] && sed -i 's/ sysv )/ sysvinit )/' programs/setup/setup.in
cat > Makefile.inc.local <<'EOF'
WERROR_CFLAGS=-w
USE_DNSSEC=false
EOF
echo "USE_DH2=true" >> Makefile.inc.local
if ! grep -qs IFLA_XFRM_LINK /usr/include/linux/if_link.h; then
  echo "USE_XFRM_INTERFACE_IFLA_HEADER=true" >> Makefile.inc.local
fi
if [ "$SWAN_VER" != "3.32" ]; then
  echo "USE_NSS_KDF=false" >> Makefile.inc.local
  echo "FINALNSSDIR=/etc/ipsec.d" >> Makefile.inc.local
fi
NPROCS=$(grep -c ^processor /proc/cpuinfo)
[ -z "$NPROCS" ] && NPROCS=1
(
  set -x
  make "-j$((NPROCS+1))" -s base >/dev/null && make -s install-base >/dev/null
)

cd /opt/src || exit 1
/bin/rm -rf "/opt/src/libreswan-$SWAN_VER"
if ! /usr/local/sbin/ipsec --version 2>/dev/null | grep -qF "$SWAN_VER"; then
  exiterr "Libreswan $SWAN_VER failed to build."
fi

# Restore SELinux contexts
restorecon /etc/ipsec.d/*db 2>/dev/null
restorecon /usr/local/sbin -Rv 2>/dev/null
restorecon /usr/local/libexec/ipsec -Rv 2>/dev/null

bigecho "Updating VPN configuration..."

IKE_NEW="  ike=aes256-sha2,aes128-sha2,aes256-sha1,aes128-sha1,aes256-sha2;modp1024,aes128-sha1;modp1024"
PHASE2_NEW="  phase2alg=aes_gcm-null,aes128-sha1,aes256-sha1,aes256-sha2_512,aes128-sha2,aes256-sha2"

dns_state=0
DNS_SRV1=$(grep "modecfgdns1=" /etc/ipsec.conf | head -n 1 | cut -d '=' -f 2)
DNS_SRV2=$(grep "modecfgdns2=" /etc/ipsec.conf | head -n 1 | cut -d '=' -f 2)
[ -n "$DNS_SRV1" ] && dns_state=2
[ -n "$DNS_SRV1" ] && [ -n "$DNS_SRV2" ] && dns_state=1
[ "$(grep -c "modecfgdns1=" /etc/ipsec.conf)" -gt "1" ] && dns_state=3

sed -i".old-$(date +%F-%T)" \
    -e "s/^[[:space:]]\+auth=/  phase2=/" \
    -e "s/^[[:space:]]\+forceencaps=/  encapsulation=/" \
    -e "s/^[[:space:]]\+ike-frag=/  fragmentation=/" \
    -e "s/^[[:space:]]\+sha2_truncbug=/  sha2-truncbug=/" \
    -e "s/^[[:space:]]\+sha2-truncbug=yes/  sha2-truncbug=no/" \
    -e "s/^[[:space:]]\+ike=.\+/$IKE_NEW/" \
    -e "s/^[[:space:]]\+phase2alg=.\+/$PHASE2_NEW/" /etc/ipsec.conf

if [ "$dns_state" = "1" ]; then
  sed -i -e "s/^[[:space:]]\+modecfgdns1=.\+/  modecfgdns=\"$DNS_SRV1 $DNS_SRV2\"/" \
      -e "/modecfgdns2=/d" /etc/ipsec.conf
elif [ "$dns_state" = "2" ]; then
  sed -i "s/^[[:space:]]\+modecfgdns1=.\+/  modecfgdns=$DNS_SRV1/" /etc/ipsec.conf
fi

sed -i "/ikev2=never/d" /etc/ipsec.conf
sed -i "/conn shared/a \  ikev2=never" /etc/ipsec.conf

if grep -qs ike-frag /etc/ipsec.d/ikev2.conf; then
  sed -i 's/^[[:space:]]\+ike-frag=/  fragmentation=/' /etc/ipsec.d/ikev2.conf
fi

bigecho "Restarting IPsec service..."

mkdir -p /run/pluto
service ipsec restart 2>/dev/null

cat <<EOF

================================================

Libreswan $SWAN_VER has been successfully installed!

================================================

EOF

if [ "$dns_state" = "3" ]; then
cat <<'EOF'
IMPORTANT: You must edit /etc/ipsec.conf and replace
           all occurrences of these two lines:
             modecfgdns1=DNS_SERVER_1
             modecfgdns2=DNS_SERVER_2

           with a single line like this:
             modecfgdns="DNS_SERVER_1 DNS_SERVER_2"

           Then run "sudo service ipsec restart".

EOF
fi

}

## Defer setup until we have the complete script
vpnupgrade "$@"

exit 0
