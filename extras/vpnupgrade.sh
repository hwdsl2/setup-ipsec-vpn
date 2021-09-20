#!/bin/sh
#
# Script to update Libreswan on Ubuntu, Debian, CentOS/RHEL, Rocky Linux,
# AlmaLinux, Amazon Linux 2 and Alpine Linux
#
# The latest version of this script is available at:
# https://github.com/hwdsl2/setup-ipsec-vpn
#
# Copyright (C) 2021 Lin Song <linsongui@gmail.com>
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

# Specify which Libreswan version to install. See: https://libreswan.org
SWAN_VER=4.5

### DO NOT edit below this line ###

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

exiterr() { echo "Error: $1" >&2; exit 1; }

check_root() {
  if [ "$(id -u)" != 0 ]; then
    exiterr "Script must be run as root. Try 'sudo sh $0'"
  fi
}

check_vz() {
  if [ -f /proc/user_beancounters ]; then
    exiterr "OpenVZ VPS is not supported."
  fi
}

check_os() {
  os_type=centos
  rh_file="/etc/redhat-release"
  if grep -qs "Red Hat" "$rh_file"; then
    os_type=rhel
  fi
  if grep -qs "release 7" "$rh_file"; then
    os_ver=7
  elif grep -qs "release 8" "$rh_file"; then
    os_ver=8
    grep -qi stream "$rh_file" && os_ver=8s
    grep -qi rocky "$rh_file" && os_type=rocky
    grep -qi alma "$rh_file" && os_type=alma
  elif grep -qs "Amazon Linux release 2" /etc/system-release; then
    os_type=amzn
    os_ver=2
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
      [Aa]lpine)
        os_type=alpine
        ;;
      *)
cat 1>&2 <<'EOF'
Error: This script only supports one of the following OS:
       Ubuntu, Debian, CentOS/RHEL 7/8, Rocky Linux, AlmaLinux,
       Amazon Linux 2 or Alpine Linux
EOF
        exit 1
        ;;
    esac
    if [ "$os_type" = "alpine" ]; then
      os_ver=$(. /etc/os-release && printf '%s' "$VERSION_ID" | cut -d '.' -f 1,2)
      if [ "$os_ver" != "3.14" ]; then
        exiterr "This script only supports Alpine Linux 3.14."
      fi
    else
      os_ver=$(sed 's/\..*//' /etc/debian_version | tr -dc 'A-Za-z0-9')
      if [ "$os_ver" = "8" ] || [ "$os_ver" = "jessiesid" ]; then
        exiterr "Debian 8 or Ubuntu < 16.04 is not supported."
      fi
    fi
  fi
}

check_libreswan() {
  if [ "$os_type" != "alpine" ]; then
    case $SWAN_VER in
      3.32|4.[1-5])
        true
        ;;
      *)
cat 1>&2 <<EOF
Error: Libreswan version '$SWAN_VER' is not supported.
       This script can install one of these versions:
       3.32, 4.1-4.4 or 4.5
EOF
        exit 1
        ;;
    esac
  else
    case $SWAN_VER in
      4.5)
        true
        ;;
      *)
cat 1>&2 <<EOF
Error: Libreswan version '$SWAN_VER' is not supported.
       This script can install Libreswan 4.5.
EOF
        exit 1
        ;;
    esac
  fi

  if [ "$SWAN_VER" = "3.32" ] && [ "$os_ver" = "11" ]; then
    exiterr "Libreswan 3.32 is not supported on Debian 11."
  fi

  ipsec_ver=$(/usr/local/sbin/ipsec --version 2>/dev/null)
  if ! printf '%s' "$ipsec_ver" | grep -q "Libreswan"; then
cat 1>&2 <<'EOF'
Error: This script requires Libreswan already installed.
       See: https://github.com/hwdsl2/setup-ipsec-vpn
EOF
    exit 1
  fi
}

install_pkgs() {
  if ! command -v wget >/dev/null 2>&1; then
    if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] || [ "$os_type" = "raspbian" ]; then
      export DEBIAN_FRONTEND=noninteractive
      (
        set -x
        apt-get -yqq update
      ) || exiterr "'apt-get update' failed."
      (
        set -x
        apt-get -yqq install wget >/dev/null
      ) || exiterr "'apt-get install wget' failed."
    elif [ "$os_type" != "alpine" ]; then
      (
        set -x
        yum -y -q install wget >/dev/null
      ) || exiterr "'yum install wget' failed."
    fi
  fi
  if [ "$os_type" = "alpine" ]; then
    (
      set -x
      apk add -U -q bash coreutils grep sed wget
    ) || exiterr "'apk add' failed."
  fi
}

get_setup_url() {
  base_url="https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/extras"
  sh_file="vpnupgrade_ubuntu.sh"
  if [ "$os_type" = "centos" ] || [ "$os_type" = "rhel" ] || [ "$os_type" = "rocky" ] || [ "$os_type" = "alma" ]; then
    sh_file="vpnupgrade_centos.sh"
  elif [ "$os_type" = "amzn" ]; then
    sh_file="vpnupgrade_amzn.sh"
  elif [ "$os_type" = "alpine" ]; then
    sh_file="vpnupgrade_alpine.sh"
  fi
  setup_url="$base_url/$sh_file"
}

run_setup() {
  status=0
  if tmpdir=$(mktemp --tmpdir -d vpn.XXXXX 2>/dev/null); then
    if ( set -x; wget -t 3 -T 30 -q -O "$tmpdir/vpnup.sh" "$setup_url" \
      || curl -fsL "$setup_url" -o "$tmpdir/vpnup.sh" 2>/dev/null ); then
      VPN_UPDATE_SWAN_VER="$SWAN_VER" /bin/bash "$tmpdir/vpnup.sh" || status=1
    else
      status=1
      echo "Error: Could not download update script." >&2
    fi
    /bin/rm -f "$tmpdir/vpnup.sh"
    /bin/rmdir "$tmpdir"
  else
    exiterr "Could not create temporary directory."
  fi
}

vpnupgrade() {
  check_root
  check_vz
  check_os
  check_libreswan
  install_pkgs
  get_setup_url
  run_setup
}

## Defer setup until we have the complete script
vpnupgrade "$@"

exit "$status"
