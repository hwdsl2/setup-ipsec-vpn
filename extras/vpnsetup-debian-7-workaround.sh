#!/bin/sh
#
# Debian 7 (Wheezy) does NOT have the required libnss version (>= 3.16) for Libreswan.
# This script provides a workaround by installing unofficial packages from download.libreswan.org.
# Debian 7 users: Run this script first, before using the VPN setup script.
#
# IMPORTANT: These unofficial packages do not receive the latest security updates compared to
# official Debian packages. They could contain unpatched vulnerabilities. Use at your own risk!
#
# Copyright (C) 2015-2016 Lin Song <linsongui@gmail.com>
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

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

echoerr() { echo "$@" 1>&2; }

if [ "$(sed 's/\..*//' /etc/debian_version 2>/dev/null)" != "7" ]; then
  echoerr "This script only supports Debian 7 (Wheezy)."
  exit 1
fi

if [ "$(uname -m)" != "x86_64" ]; then
  echoerr "This script only supports 64-bit Debian 7."
  exit 1
fi

if [ "$(id -u)" != 0 ]; then
  echoerr "Script must be run as root. Try 'sudo sh $0'"
  exit 1
fi

# Create and change to working dir
mkdir -p /opt/src
cd /opt/src || exit 1

# Update package index and install wget
export DEBIAN_FRONTEND=noninteractive
apt-get -yq update
apt-get -yq install wget

# Install libnss/libnspr packages from download.libreswan.org.
# Ref: https://libreswan.org/wiki/3.14_on_Debian_Wheezy
base_url=https://download.libreswan.org/binaries/debian/wheezy

deb1=libnspr4_4.10.7-1_amd64.deb
deb2=libnspr4-dev_4.10.7-1_amd64.deb
deb3=libnss3_3.17.2-1.1_amd64.deb
deb4=libnss3-dev_3.17.2-1.1_amd64.deb
deb5=libnss3-tools_3.17.2-1.1_amd64.deb

wget -t 3 -T 30 -nv -O "$deb1" "$base_url/$deb1"
wget -t 3 -T 30 -nv -O "$deb2" "$base_url/$deb2"
wget -t 3 -T 30 -nv -O "$deb3" "$base_url/$deb3"
wget -t 3 -T 30 -nv -O "$deb4" "$base_url/$deb4"
wget -t 3 -T 30 -nv -O "$deb5" "$base_url/$deb5"

if [ -s "$deb1" ] && [ -s "$deb2" ] && [ -s "$deb3" ] && [ -s "$deb4" ] && [ -s "$deb5" ]; then
  dpkg -i "$deb1" "$deb2" "$deb3" "$deb4" "$deb5" && /bin/rm -f "$deb1" "$deb2" "$deb3" "$deb4" "$deb5"
  apt-get install -f
  echo
  echo 'Completed! If no error, you may now proceed to run the VPN setup script.'
  exit 0
else
  echoerr
  echoerr 'Could not download libnss/libnspr package(s). Aborting.'
  /bin/rm -f "$deb1" "$deb2" "$deb3" "$deb4" "$deb5"
  exit 1
fi
