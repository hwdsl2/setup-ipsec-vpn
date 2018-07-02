#!/bin/sh
#
# Script to upgrade Libreswan on Ubuntu and Debian
#
# Copyright (C) 2016-2018 Lin Song <linsongui@gmail.com>
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

# Check https://libreswan.org for the latest version
SWAN_VER=3.22

### DO NOT edit below this line ###

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

exiterr()  { echo "Error: $1" >&2; exit 1; }
exiterr2() { exiterr "'apt-get install' failed."; }

vpnupgrade() {

os_type="$(lsb_release -si 2>/dev/null)"
if [ -z "$os_type" ]; then
  [ -f /etc/os-release  ] && os_type="$(. /etc/os-release  && echo "$ID")"
  [ -f /etc/lsb-release ] && os_type="$(. /etc/lsb-release && echo "$DISTRIB_ID")"
fi
if ! printf '%s' "$os_type" | head -n 1 | grep -qiF -e ubuntu -e debian -e raspbian; then
  exiterr "This script only supports Ubuntu and Debian."
fi

if [ "$(sed 's/\..*//' /etc/debian_version)" = "7" ]; then
  exiterr "Debian 7 is not supported."
fi

if [ -f /proc/user_beancounters ]; then
  exiterr "OpenVZ VPS is not supported."
fi

if [ "$(id -u)" != 0 ]; then
  exiterr "Script must be run as root. Try 'sudo sh $0'"
fi

if [ -z "$SWAN_VER" ]; then
  exiterr "Libreswan version 'SWAN_VER' not specified."
fi

case "$SWAN_VER" in
  3.24|3.2[6-9])
    exiterr "Libreswan version $SWAN_VER is not available."
    ;;
esac

ipsec_ver="$(/usr/local/sbin/ipsec --version 2>/dev/null)"
if ! printf '%s' "$ipsec_ver" | grep -q "Libreswan"; then
  exiterr "This script requires Libreswan already installed."
fi

if printf '%s' "$ipsec_ver" | grep -qF "$SWAN_VER"; then
  echo "You already have Libreswan version $SWAN_VER installed! "
  echo "If you continue, the same version will be re-installed."
  echo
  printf "Do you wish to continue anyway? [y/N] "
  read -r response
  case $response in
    [yY][eE][sS]|[yY])
      echo
      ;;
    *)
      echo "Aborting."
      exit 1
      ;;
  esac
fi

is_downgrade_to_322=0
if [ "$SWAN_VER" = "3.22" ]; then
  if printf '%s' "$ipsec_ver" | grep -qF -e "3.23" -e "3.25"; then
    is_downgrade_to_322=1
  fi
fi

clear

cat <<EOF
Welcome! This script will build and install Libreswan $SWAN_VER on your server.
Additional packages required for compilation will also be installed.

It is intended for upgrading servers to a newer Libreswan version.

Current version: $ipsec_ver
Version to be installed: Libreswan $SWAN_VER

EOF

if [ "$SWAN_VER" = "3.23" ] || [ "$SWAN_VER" = "3.25" ]; then
cat <<'EOF'
WARNING: Libreswan 3.23 and 3.25 have an issue with connecting multiple
         IPsec/XAuth VPN clients from behind the same NAT (e.g. home router).
         DO NOT upgrade to 3.23/3.25 if your use cases include the above.

EOF
fi

cat <<'EOF'
NOTE: Libreswan versions 3.19 and newer require some configuration changes.
      This script will make the following changes to your /etc/ipsec.conf:

      Replace this line:
          auth=esp
      with the following:
          phase2=esp

      Replace this line:
          forceencaps=yes
      with the following:
          encapsulation=yes

      Consolidate VPN ciphers for "ike=" and "phase2alg=".
      Re-add "MODP1024" to the list of allowed "ike=" ciphers,
      which was removed from the defaults in Libreswan 3.19.

      Your other VPN configuration files will not be modified.

EOF

printf "Do you wish to continue? [y/N] "
read -r response
case $response in
  [yY][eE][sS]|[yY])
    echo
    echo "Please be patient. Setup is continuing..."
    echo
    ;;
  *)
    echo "Aborting."
    exit 1
    ;;
esac

# Create and change to working dir
mkdir -p /opt/src
cd /opt/src || exit 1

# Update package index and install Wget
export DEBIAN_FRONTEND=noninteractive
apt-get -yq update || exiterr "'apt-get update' failed."
apt-get -yq install wget || exiterr2

# Install necessary packages
apt-get -yq install libnss3-dev libnspr4-dev pkg-config \
  libpam0g-dev libcap-ng-dev libcap-ng-utils libselinux1-dev \
  libcurl4-nss-dev flex bison gcc make libnss3-tools \
  libevent-dev || exiterr2

# Compile and install Libreswan
swan_file="libreswan-$SWAN_VER.tar.gz"
swan_url1="https://github.com/libreswan/libreswan/archive/v$SWAN_VER.tar.gz"
swan_url2="https://download.libreswan.org/$swan_file"
if ! { wget -t 3 -T 30 -nv -O "$swan_file" "$swan_url1" || wget -t 3 -T 30 -nv -O "$swan_file" "$swan_url2"; }; then
  exit 1
fi
/bin/rm -rf "/opt/src/libreswan-$SWAN_VER"
tar xzf "$swan_file" && /bin/rm -f "$swan_file"
cd "libreswan-$SWAN_VER" || exit 1
[ "$SWAN_VER" = "3.22" ] && sed -i '/^#define LSWBUF_CANARY/s/-2$/((char) -2)/' include/lswlog.h
sed -i '/docker-targets\.mk/d' Makefile
cat > Makefile.inc.local <<'EOF'
WERROR_CFLAGS =
USE_DNSSEC = false
USE_GLIBC_KERN_FLIP_HEADERS = true
EOF
if [ "$(packaging/utils/lswan_detect.sh init)" = "systemd" ]; then
  apt-get -yq install libsystemd-dev || exiterr2
fi
NPROCS="$(grep -c ^processor /proc/cpuinfo)"
[ -z "$NPROCS" ] && NPROCS=1
make "-j$((NPROCS+1))" -s base && make -s install-base

# Verify the install and clean up
cd /opt/src || exit 1
/bin/rm -rf "/opt/src/libreswan-$SWAN_VER"
if ! /usr/local/sbin/ipsec --version 2>/dev/null | grep -qF "$SWAN_VER"; then
  exiterr "Libreswan $SWAN_VER failed to build."
fi

# Update ipsec.conf for Libreswan 3.19 and newer
IKE_NEW="  ike=3des-sha1,3des-sha2,aes-sha1,aes-sha1;modp1024,aes-sha2,aes-sha2;modp1024"
PHASE2_NEW="  phase2alg=3des-sha1,3des-sha2,aes-sha1,aes-sha2,aes256-sha2_512"
if uname -m | grep -qi '^arm'; then
  PHASE2_NEW="  phase2alg=3des-sha1,3des-sha2,aes-sha1,aes-sha2"
fi
sed -i".old-$(date +%F-%T)" \
    -e "s/^[[:space:]]\+auth=esp\$/  phase2=esp/" \
    -e "s/^[[:space:]]\+forceencaps=yes\$/  encapsulation=yes/" \
    -e "s/^[[:space:]]\+ike=.\+\$/$IKE_NEW/" \
    -e "s/^[[:space:]]\+phase2alg=.\+\$/$PHASE2_NEW/" /etc/ipsec.conf

# Restart IPsec service
mkdir -p /run/pluto
service ipsec restart

echo
echo "Libreswan $SWAN_VER was installed successfully! "
echo

case "$SWAN_VER" in
  3.2[3-9])
cat <<'EOF'
NOTE: Users upgrading to Libreswan 3.23 or newer should edit "/etc/ipsec.conf" and replace these two lines:
          modecfgdns1=DNS_SERVER_1
          modecfgdns2=DNS_SERVER_2
      with a single line like this:
          modecfgdns="DNS_SERVER_1, DNS_SERVER_2"
      Then run "service ipsec restart".

EOF
    ;;
esac

if [ "$is_downgrade_to_322" = "1" ]; then
cat <<'EOF'
NOTE: Users downgrading to Libreswan 3.22 should edit "/etc/ipsec.conf" and replace this line:
          modecfgdns="DNS_SERVER_1, DNS_SERVER_2"
      with two lines like this:
          modecfgdns1=DNS_SERVER_1
          modecfgdns2=DNS_SERVER_2
      Then run "service ipsec restart".

EOF
fi

}

## Defer setup until we have the complete script
vpnupgrade "$@"

exit 0
