#!/bin/sh
#
# Script to upgrade Libreswan on Ubuntu and Debian
#
# Copyright (C) 2016 Lin Song
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

# Check https://libreswan.org and update version number if necessary
SWAN_VER=3.17

### Do not edit below this line

os_type="$(lsb_release -si 2>/dev/null)"
if [ "$os_type" != "Ubuntu" ] && [ "$os_type" != "Debian" ]; then
  echo "This script only supports Ubuntu or Debian systems."
  exit 1
fi

if [ -f /proc/user_beancounters ]; then
  echo "This script does NOT support OpenVZ VPS."
  exit 1
fi

if [ "$(id -u)" != 0 ]; then
  echo "Script must be run as root. Try 'sudo sh $0'"
  exit 1
fi

/usr/local/sbin/ipsec --version 2>/dev/null | grep -qs "Libreswan"
if [ "$?" != "0" ]; then
  echo "This upgrade script requires Libreswan already installed."
  exit 1
fi

/usr/local/sbin/ipsec --version 2>/dev/null | grep -qs "Libreswan $SWAN_VER"
if [ "$?" = "0" ]; then
  echo "You already have Libreswan version $SWAN_VER installed! "
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

echo "Welcome! This script will build and install Libreswan $SWAN_VER on your server."
echo "Additional packages required for Libreswan compilation will also be installed."
echo "This is intended for use on servers running an older version of Libreswan."
echo "Your existing VPN configuration files will NOT be modified."

if [ "$(sed 's/\..*//' /etc/debian_version 2>/dev/null)" = "7" ]; then
  echo
  echo "IMPORTANT NOTE for Debian 7 (Wheezy) users:"
  echo "A workaround is required for your system. See: https://gist.github.com/hwdsl2/5a769b2c4436cdf02a90"
  echo "Continue only after you have completed the workaround."
fi

echo
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
cd /opt/src || { echo "Failed to change working dir to /opt/src. Aborting."; exit 1; }

# Update package index and install Wget
export DEBIAN_FRONTEND=noninteractive
apt-get -y update
apt-get -y install wget

# Install necessary packages
apt-get -y install libnss3-dev libnspr4-dev pkg-config libpam0g-dev \
        libcap-ng-dev libcap-ng-utils libselinux1-dev \
        libcurl4-nss-dev flex bison gcc make sed \
        libunbound-dev libnss3-tools libevent-dev
apt-get -y --no-install-recommends install xmlto

# Compile and install Libreswan
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

# Restart IPsec service
service ipsec restart

# Check if Libreswan install was successful
/usr/local/sbin/ipsec --version 2>/dev/null | grep -qs "$SWAN_VER"
[ "$?" != "0" ] && { echo; echo "Sorry, Libreswan $SWAN_VER failed to build. Aborting."; exit 1; }

echo
echo "Libreswan $SWAN_VER was installed successfully! "
echo
exit 0
