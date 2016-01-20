#!/bin/sh
#
# Simple script to upgrade Libreswan on CentOS and RHEL
#
# Copyright (C) 2015 Lin Song
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

# Check https://libreswan.org and update version number if necessary
SWAN_VER=3.16

if [ ! -f /etc/redhat-release ]; then
  echo "Looks like you aren't running this script on a CentOS/RHEL system."
  exit 1
fi

if ! grep -qs -e "release 6" -e "release 7" /etc/redhat-release; then
  echo "This script only supports versions 6 and 7 of CentOS/RHEL."
  exit 1
fi

if [ "$(uname -m)" != "x86_64" ]; then
  echo "This script only supports 64-bit CentOS/RHEL."
  exit 1
fi

if [ -f "/proc/user_beancounters" ]; then
  echo "This script does NOT support OpenVZ VPS."
  exit 1
fi

if [ "$(id -u)" != 0 ]; then
  echo "Sorry, you need to run this script as root."
  exit 1
fi

/usr/local/sbin/ipsec --version 2>/dev/null | grep -qs "Libreswan"
if [ "$?" != "0" ]; then
  echo "This upgrade script requires you already have Libreswan installed."
  echo "Aborting."
  exit 1
fi

/usr/local/sbin/ipsec --version 2>/dev/null | grep -qs "Libreswan ${SWAN_VER}"
if [ "$?" = "0" ]; then
  echo "It looks like you already have Libreswan ${SWAN_VER} installed! "
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

echo "Welcome! This script will build and install Libreswan ${SWAN_VER} on your server."
echo "Related packages, such as those required by Libreswan compilation will also be installed."
echo "This is intended for use on VPN servers running an older version of Libreswan."
echo "Your existing VPN configuration files will NOT be modified."

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
cd /opt/src || { echo "Failed to change working directory to /opt/src. Aborting."; exit 1; }

# Install wget and nano
yum -y install wget nano

# Add the EPEL repository
if grep -qs "release 6" /etc/redhat-release; then
  EPEL_RPM="epel-release-6-8.noarch.rpm"
  EPEL_URL="http://download.fedoraproject.org/pub/epel/6/x86_64/$EPEL_RPM"
elif grep -qs "release 7" /etc/redhat-release; then
  EPEL_RPM="epel-release-7-5.noarch.rpm"
  EPEL_URL="http://download.fedoraproject.org/pub/epel/7/x86_64/e/$EPEL_RPM"
fi
wget -t 3 -T 30 -nv -O "$EPEL_RPM" "$EPEL_URL"
[ ! -f "$EPEL_RPM" ] && { echo "Cannot retrieve EPEL repo RPM file. Aborting."; exit 1; }
rpm -ivh --force "$EPEL_RPM" && /bin/rm -f "$EPEL_RPM"

# Install necessary packages
yum -y install nss-devel nspr-devel pkgconfig pam-devel \
    libcap-ng-devel libselinux-devel \
    curl-devel gmp-devel flex bison gcc make \
    fipscheck-devel unbound-devel gmp gmp-devel xmlto

# Installed Libevent2. Use backported version for CentOS 6.
if grep -qs "release 6" /etc/redhat-release; then
  LE2_URL="https://download.libreswan.org/binaries/rhel/6/x86_64"
  RPM1="libevent2-2.0.22-1.el6.x86_64.rpm"
  RPM2="libevent2-devel-2.0.22-1.el6.x86_64.rpm"
  wget -t 3 -T 30 -nv -O "$RPM1" "$LE2_URL/$RPM1"
  wget -t 3 -T 30 -nv -O "$RPM2" "$LE2_URL/$RPM2"
  [ ! -f "$RPM1" ] || [ ! -f "$RPM2" ] && { echo "Cannot retrieve Libevent2 RPM file(s). Aborting."; exit 1; }
  rpm -ivh --force "$RPM1" "$RPM2" && /bin/rm -f "$RPM1" "$RPM2"
elif grep -qs "release 7" /etc/redhat-release; then
  yum -y install libevent-devel
fi

# Compile and install Libreswan
SWAN_FILE="libreswan-${SWAN_VER}.tar.gz"
SWAN_URL="https://download.libreswan.org/${SWAN_FILE}"
wget -t 3 -T 30 -nv -O "$SWAN_FILE" "$SWAN_URL"
[ ! -f "$SWAN_FILE" ] && { echo "Cannot retrieve Libreswan source file. Aborting."; exit 1; }
/bin/rm -rf "/opt/src/libreswan-${SWAN_VER}"
tar xvzf "$SWAN_FILE" && rm -f "$SWAN_FILE"
cd "libreswan-${SWAN_VER}" || { echo "Failed to enter Libreswan source dir. Aborting."; exit 1; }
make programs && make install

# Restore SELinux contexts
restorecon /etc/ipsec.d/*db 2>/dev/null
restorecon /usr/local/sbin -Rv 2>/dev/null
restorecon /usr/local/libexec/ipsec -Rv 2>/dev/null

# Restart IPsec service
/sbin/service ipsec restart

# Check if Libreswan install was successful
/usr/local/sbin/ipsec --version 2>/dev/null | grep -qs "${SWAN_VER}"
if [ "$?" != "0" ]; then
  echo
  echo "Sorry, something went wrong."
  echo "Libreswan ${SWAN_VER} was NOT installed successfully."
  echo "Exiting script."
  exit 1
fi

echo
echo "Congratulations! Libreswan ${SWAN_VER} was installed successfully!"
exit 0
