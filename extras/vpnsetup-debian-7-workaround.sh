#!/bin/sh
#
# Debian 7 (Wheezy) does NOT have the required libnss version (>= 3.16) for Libreswan.
# This script provides a workaround by installing newer packages from download.libreswan.org.
# Debian 7 users: Run this script first, before using my VPN setup script (vpnsetup.sh).
#
# IMPORTANT NOTE:
# These newer packages may not have the latest security updates compared to official Debian packages.
# They could contain unpatched security vulnerabilities. Use them at your own risk!
#
# Copyright (C) 2015 Lin Song
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see http://www.gnu.org/licenses/.

if [ "$(sed 's/\..*//' /etc/debian_version 2>/dev/null)" != "7" ]; then
  echo "This script only supports Debian 7 (Wheezy)."
  exit 1
fi

if [ "$(uname -m)" != "x86_64" ]; then
  echo "This script only supports 64-bit Debian 7."
  exit 1
fi

if [ "$(id -u)" != 0 ]; then
  echo "Script must be run as root. Try 'sudo sh $0'"
  exit 1
fi

# Create and change to working dir
mkdir -p /opt/src
cd /opt/src || { echo "Failed to change directory to /opt/src. Aborting."; exit 1; }

# Update package index and install wget
export DEBIAN_FRONTEND=noninteractive
apt-get -y update
apt-get -y install wget

# Install newer libnss/libnspr packages from download.libreswan.org.
# Ref: https://libreswan.org/wiki/3.14_on_Debian_Wheezy
base_url=https://download.libreswan.org/binaries/debian/wheezy

FILE1=libnspr4_4.10.7-1_amd64.deb
FILE2=libnspr4-dev_4.10.7-1_amd64.deb
FILE3=libnss3_3.17.2-1.1_amd64.deb
FILE4=libnss3-dev_3.17.2-1.1_amd64.deb
FILE5=libnss3-tools_3.17.2-1.1_amd64.deb

wget -t 3 -T 30 -nv -O $FILE1 $base_url/$FILE1
wget -t 3 -T 30 -nv -O $FILE2 $base_url/$FILE2
wget -t 3 -T 30 -nv -O $FILE3 $base_url/$FILE3
wget -t 3 -T 30 -nv -O $FILE4 $base_url/$FILE4
wget -t 3 -T 30 -nv -O $FILE5 $base_url/$FILE5

if [ -s $FILE1 ] && [ -s $FILE2 ] && [ -s $FILE3 ] && [ -s $FILE4 ] && [ -s $FILE5 ]; then
  dpkg -i $FILE1 $FILE2 $FILE3 $FILE4 $FILE5 && /bin/rm -f $FILE1 $FILE2 $FILE3 $FILE4 $FILE5
  apt-get install -f
  echo
  echo 'Completed! If no error occurred in the output above, you may now proceed to run vpnsetup.sh.'
  echo
  exit 0
else
  echo
  echo 'Could not retrieve libnss/libnspr package(s) from download.libreswan.org. Aborting.'
  echo
  /bin/rm -f $FILE1 $FILE2 $FILE3 $FILE4 $FILE5
  exit 1
fi
