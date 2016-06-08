#!/bin/sh
#
# Script to upgrade Libreswan on Ubuntu and Debian
#
# Copyright (C) 2016 Lin Song <linsongui@gmail.com>
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

# Check https://libreswan.org for the latest version
SWAN_VER=3.17

### Do not edit below this line

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

echoerr() { echo "$@" 1>&2; }

os_type="$(lsb_release -si 2>/dev/null)"
if [ "$os_type" != "Ubuntu" ] && [ "$os_type" != "Debian" ]; then
  echoerr "This script only supports Ubuntu/Debian."
  exit 1
fi

if [ -f /proc/user_beancounters ]; then
  echoerr "This script does not support OpenVZ VPS."
  exit 1
fi

if [ "$(id -u)" != 0 ]; then
  echoerr "Script must be run as root. Try 'sudo sh $0'"
  exit 1
fi

/usr/local/sbin/ipsec --version 2>/dev/null | grep -qs "Libreswan"
if [ "$?" != "0" ]; then
  echoerr "This upgrade script requires Libreswan already installed."
  exit 1
fi

/usr/local/sbin/ipsec --version 2>/dev/null | grep -qs "Libreswan $SWAN_VER"
if [ "$?" = "0" ]; then
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

clear

cat <<EOF
Welcome! This script will build and install Libreswan $SWAN_VER on your server.
Additional packages required for Libreswan compilation will also be installed.

This is intended for use on servers running an older version of Libreswan.
Your existing VPN configuration files will NOT be modified.

EOF

if [ "$(sed 's/\..*//' /etc/debian_version)" = "7" ]; then
cat <<'EOF'
IMPORTANT: Workaround required for Debian 7 (Wheezy).
First, run the script at: https://git.io/vpndebian7
Continue only after completing this workaround.

EOF
fi

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
apt-get -yq update
apt-get -yq install wget

# Install necessary packages
apt-get -yq install libnss3-dev libnspr4-dev pkg-config libpam0g-dev \
        libcap-ng-dev libcap-ng-utils libselinux1-dev \
        libcurl4-nss-dev flex bison gcc make \
        libunbound-dev libnss3-tools libevent-dev
apt-get -yq --no-install-recommends install xmlto

# Compile and install Libreswan
swan_file="libreswan-${SWAN_VER}.tar.gz"
swan_url1="https://download.libreswan.org/$swan_file"
swan_url2="https://github.com/libreswan/libreswan/archive/v${SWAN_VER}.tar.gz"
wget -t 3 -T 30 -nv -O "$swan_file" "$swan_url1" || wget -t 3 -T 30 -nv -O "$swan_file" "$swan_url2"
[ "$?" != "0" ] && { echoerr "Cannot download Libreswan source. Aborting."; exit 1; }
/bin/rm -rf "/opt/src/libreswan-$SWAN_VER"
tar xzf "$swan_file" && /bin/rm -f "$swan_file"
cd "libreswan-$SWAN_VER" || { echoerr "Cannot enter Libreswan source dir. Aborting."; exit 1; }
echo "WERROR_CFLAGS =" > Makefile.inc.local
make -s programs && make -s install

# Verify the install and clean up
cd /opt/src || exit 1
/bin/rm -rf "/opt/src/libreswan-$SWAN_VER"
/usr/local/sbin/ipsec --version 2>/dev/null | grep -qs "$SWAN_VER"
[ "$?" != "0" ] && { echoerr; echoerr "Libreswan $SWAN_VER failed to build. Aborting."; exit 1; }

# Restart IPsec service
service ipsec restart

echo
echo "Libreswan $SWAN_VER was installed successfully! "
echo

exit 0
