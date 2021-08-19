#!/bin/sh
#
# Quick start script to set up an IPsec VPN server with IPsec/L2TP, Cisco IPsec and IKEv2
# Works on any dedicated server or virtual private server (VPS)
#
# DO NOT RUN THIS SCRIPT ON YOUR PC OR MAC!
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
      *)
        exiterr "This script only supports Ubuntu, Debian, CentOS/RHEL 7/8 and Amazon Linux 2."
        ;;
    esac
    os_ver=$(sed 's/\..*//' /etc/debian_version | tr -dc 'A-Za-z0-9')
    if [ "$os_ver" = "8" ] || [ "$os_ver" = "jessiesid" ]; then
      exiterr "Debian 8 or Ubuntu < 16.04 is not supported."
    fi
    if { [ "$os_ver" = "10" ] || [ "$os_ver" = "11" ]; } && [ ! -e /dev/ppp ]; then
      exiterr "/dev/ppp is missing. Debian 11 or 10 users, see: https://git.io/vpndebian10"
    fi
  fi
}

check_iface() {
  def_iface=$(route 2>/dev/null | grep -m 1 '^default' | grep -o '[^ ]*$')
  [ -z "$def_iface" ] && def_iface=$(ip -4 route list 0/0 2>/dev/null | grep -m 1 -Po '(?<=dev )(\S+)')
  def_state=$(cat "/sys/class/net/$def_iface/operstate" 2>/dev/null)
  check_wl=0
  if [ -n "$def_state" ] && [ "$def_state" != "down" ]; then
    if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] || [ "$os_type" = "raspbian" ]; then
      if ! uname -m | grep -qi -e '^arm' -e '^aarch64'; then
        check_wl=1
      fi
    else
      check_wl=1
    fi
  fi
  if [ "$check_wl" = "1" ]; then
    case $def_iface in
      wl*)
        exiterr "Wireless interface '$def_iface' detected. DO NOT run this script on your PC or Mac!"
        ;;
    esac
  fi
}

check_iptables() {
  if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] || [ "$os_type" = "raspbian" ]; then
    if [ -x /sbin/iptables ] && ! iptables -nL INPUT >/dev/null 2>&1; then
      exiterr "IPTables check failed. Reboot and re-run this script."
    fi
  fi
}

wait_for_apt() {
  count=0
  apt_lk=/var/lib/apt/lists/lock
  pkg_lk=/var/lib/dpkg/lock
  while fuser "$apt_lk" "$pkg_lk" >/dev/null 2>&1 \
    || lsof "$apt_lk" >/dev/null 2>&1 || lsof "$pkg_lk" >/dev/null 2>&1; do
    [ "$count" = "0" ] && echo "## Waiting for apt to be available..."
    [ "$count" -ge "100" ] && exiterr "Could not get apt/dpkg lock."
    count=$((count+1))
    printf '%s' '.'
    sleep 3
  done
}

install_wget() {
  if ! command -v wget >/dev/null 2>&1; then
    if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] || [ "$os_type" = "raspbian" ]; then
      wait_for_apt
      export DEBIAN_FRONTEND=noninteractive
      (
        set -x
        apt-get -yqq update
      ) || exiterr "'apt-get update' failed."
      (
        set -x
        apt-get -yqq install wget >/dev/null
      ) || exiterr "'apt-get install wget' failed."
    else
      (
        set -x
        yum -y -q install wget >/dev/null
      ) || exiterr "'yum install wget' failed."
    fi
  fi
}

get_setup_url() {
  base_url="https://github.com/hwdsl2/setup-ipsec-vpn/raw/master"
  sh_file="vpnsetup_ubuntu.sh"
  if [ "$os_type" = "centos" ] || [ "$os_type" = "rhel" ] || [ "$os_type" = "rocky" ] || [ "$os_type" = "alma" ]; then
    sh_file="vpnsetup_centos.sh"
  elif [ "$os_type" = "amzn" ]; then
    sh_file="vpnsetup_amzn.sh"
  fi
  setup_url="$base_url/$sh_file"
}

run_setup() {
  status=0
  TMPDIR=$(mktemp -d /tmp/vpnsetup.XXXXX 2>/dev/null)
  if [ -d "$TMPDIR" ]; then
    if ( set -x; wget -t 3 -T 30 -q -O "$TMPDIR/vpn.sh" "$setup_url" \
      || curl -fsL "$setup_url" -o "$TMPDIR/vpn.sh" 2>/dev/null ); then
      if /bin/bash "$TMPDIR/vpn.sh"; then
        if [ -s /opt/src/ikev2.sh ] && [ ! -f /etc/ipsec.d/ikev2.conf ]; then
          sleep 1
          /bin/bash /opt/src/ikev2.sh --auto || status=1
        fi
      else
        status=1
      fi
    else
      status=1
      echo "Error: Could not download VPN setup script." >&2
    fi
    /bin/rm -f "$TMPDIR/vpn.sh"
    /bin/rmdir "$TMPDIR"
  else
    exiterr "Could not create temporary directory."
  fi
}

quickstart() {
  check_root
  check_vz
  check_os
  check_iface
  check_iptables
  install_wget
  get_setup_url
  run_setup
}

## Defer setup until we have the complete script
quickstart "$@"

exit "$status"
