#!/bin/bash
#
# Script to uninstall IPsec VPN on Ubuntu, Debian, CentOS/RHEL,
# Rocky Linux, AlmaLinux, Amazon Linux 2 and Alpine Linux
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
SYS_DT=$(date +%F-%T | tr ':' '_')

exiterr()  { echo "Error: $1" >&2; exit 1; }
conf_bk() { /bin/cp -f "$1" "$1.old-$SYS_DT" 2>/dev/null; }
bigecho() { echo "## $1"; }

check_root() {
  if [ "$(id -u)" != 0 ]; then
    exiterr "Script must be run as root. Try 'sudo bash $0'"
  fi
}

check_os() {
  os_type=centos
  rh_file="/etc/redhat-release"
  if grep -qs "Red Hat" "$rh_file"; then
    os_type=rhel
  fi
  if grep -qs "release 7" "$rh_file" || grep -qs "release 8" "$rh_file"; then
    grep -qi rocky "$rh_file" && os_type=rocky
    grep -qi alma "$rh_file" && os_type=alma
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
  fi
}

check_libreswan() {
  ipsec_ver=$(ipsec --version 2>/dev/null)
  if ! grep -qs "hwdsl2 VPN script" /etc/sysctl.conf \
    || ! printf '%s' "$ipsec_ver" | grep -q "Libreswan"; then
    exiterr "Cannot remove IPsec VPN because it has not been set up on this server."
  fi
}

check_iface() {
  def_iface=$(route 2>/dev/null | grep -m 1 '^default' | grep -o '[^ ]*$')
  if [ "$os_type" != "alpine" ]; then
    [ -z "$def_iface" ] && def_iface=$(ip -4 route list 0/0 2>/dev/null | grep -m 1 -Po '(?<=dev )(\S+)')
  fi
  def_state=$(cat "/sys/class/net/$def_iface/operstate" 2>/dev/null)
  if [ -n "$def_state" ] && [ "$def_state" != "down" ]; then
    check_wl=0
    if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] || [ "$os_type" = "raspbian" ]; then
      if ! uname -m | grep -qi -e '^arm' -e '^aarch64'; then
        check_wl=1
      fi
    else
      check_wl=1
    fi
    if [ "$check_wl" = "1" ]; then
      case $def_iface in
        wl*)
          exiterr "Wireless interface '$def_iface' detected. DO NOT run this script on your PC or Mac!"
          ;;
      esac
    fi
    NET_IFACE="$def_iface"
  else
    eth0_state=$(cat "/sys/class/net/eth0/operstate" 2>/dev/null)
    if [ -z "$eth0_state" ] || [ "$eth0_state" = "down" ]; then
      exiterr "Could not detect the default network interface."
    fi
    NET_IFACE=eth0
  fi
}

abort_and_exit() {
  echo "Abort. No changes were made." >&2
  exit 1
}

confirm_or_abort() {
  printf '%s' "$1"
  read -r response
  case $response in
    [yY][eE][sS]|[yY])
      echo
      ;;
    *)
      abort_and_exit
      ;;
  esac
}

confirm_remove() {
cat <<'EOF'

WARNING: This script will remove IPsec VPN from this server. All VPN configuration
         will be *permanently deleted*, and Libreswan and xl2tpd will be removed.
         This *cannot* be undone!

EOF
  confirm_or_abort "Are you sure you want to remove the VPN? [y/N] "
}

stop_services() {
  bigecho "Stopping services..."
  service ipsec stop
  service xl2tpd stop
}

remove_ipsec() {
  bigecho "Removing IPsec..."
  /bin/rm -rf /usr/local/sbin/ipsec /usr/local/libexec/ipsec /usr/local/share/doc/libreswan
  /bin/rm -f /etc/init/ipsec.conf /lib/systemd/system/ipsec.service /etc/init.d/ipsec \
    /usr/lib/systemd/system/ipsec.service /etc/logrotate.d/libreswan \
    /usr/lib/tmpfiles.d/libreswan.conf
}

remove_xl2tpd() {
  bigecho "Removing xl2tpd..."
  if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] || [ "$os_type" = "raspbian" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get -yqq purge xl2tpd >/dev/null
  elif [ "$os_type" = "alpine" ]; then
    apk del -q xl2tpd
  else
    yum -y -q remove xl2tpd >/dev/null
  fi
}

remove_ikev2_script() {
  bigecho "Removing IKEv2 script..."
  if [ "$(readlink -f /usr/bin/ikev2.sh 2>/dev/null)" = "/opt/src/ikev2.sh" ]; then
    /bin/rm -f /usr/bin/ikev2.sh
  fi
  /bin/rm -f /opt/src/ikev2.sh
}

update_sysctl() {
  if grep -qs "hwdsl2 VPN script" /etc/sysctl.conf; then
    bigecho "Updating sysctl settings..."
    conf_bk "/etc/sysctl.conf"
    if [ "$os_type" = "alpine" ]; then
      sed -i '/# Added by hwdsl2 VPN script/,+17d' /etc/sysctl.conf
    else
      sed --follow-symlinks -i '/# Added by hwdsl2 VPN script/,+17d' /etc/sysctl.conf
    fi
    echo 0 > /proc/sys/net/ipv4/ip_forward
  fi
}

update_rclocal() {
  if grep -qs "hwdsl2 VPN script" /etc/rc.local; then
    bigecho "Updating rc.local..."
    conf_bk "/etc/rc.local"
    if [ "$os_type" = "alpine" ]; then
      sed -i '/# Added by hwdsl2 VPN script/,+4d' /etc/rc.local
    else
      sed --follow-symlinks -i '/# Added by hwdsl2 VPN script/,+4d' /etc/rc.local
    fi
  fi
}

update_iptables_rules() {
  use_nft=0
  if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] || [ "$os_type" = "raspbian" ] \
    || [ "$os_type" = "alpine" ]; then
    IPT_FILE=/etc/iptables.rules
    IPT_FILE2=/etc/iptables/rules.v4
  else
    IPT_FILE=/etc/sysconfig/iptables
    if grep -qs "hwdsl2 VPN script" /etc/sysconfig/nftables.conf; then
      use_nft=1
      IPT_FILE=/etc/sysconfig/nftables.conf
    fi
  fi
  ipt_flag=0
  if grep -qs "hwdsl2 VPN script" "$IPT_FILE"; then
    ipt_flag=1
  fi

  ipi='iptables -D INPUT'
  ipf='iptables -D FORWARD'
  ipp='iptables -t nat -D POSTROUTING'
  res='RELATED,ESTABLISHED'
  if [ "$ipt_flag" = "1" ]; then
    if [ "$use_nft" = "0" ]; then
      bigecho "Updating IPTables rules..."
      iptables-save > "$IPT_FILE.old-$SYS_DT"
      $ipi -p udp --dport 1701 -m policy --dir in --pol none -j DROP
      $ipi -m conntrack --ctstate INVALID -j DROP
      $ipi -m conntrack --ctstate "$res" -j ACCEPT
      $ipi -p udp -m multiport --dports 500,4500 -j ACCEPT
      $ipi -p udp --dport 1701 -m policy --dir in --pol ipsec -j ACCEPT
      $ipi -p udp --dport 1701 -j DROP
      $ipf -m conntrack --ctstate INVALID -j DROP
      $ipf -i "$NET_IFACE" -o ppp+ -m conntrack --ctstate "$res" -j ACCEPT
      $ipf -i ppp+ -o "$NET_IFACE" -j ACCEPT
      $ipf -i ppp+ -o ppp+ -j ACCEPT
      $ipf -i "$NET_IFACE" -d 192.168.43.0/24 -m conntrack --ctstate "$res" -j ACCEPT
      $ipf -s 192.168.43.0/24 -o "$NET_IFACE" -j ACCEPT
      $ipf -s 192.168.43.0/24 -o ppp+ -j ACCEPT
      iptables -D FORWARD -j DROP
      $ipp -s 192.168.43.0/24 -o "$NET_IFACE" -m policy --dir out --pol none -j MASQUERADE
      $ipp -s 192.168.42.0/24 -o "$NET_IFACE" -j MASQUERADE
      iptables-save > "$IPT_FILE"

      if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] || [ "$os_type" = "raspbian" ]; then
        if [ -f "$IPT_FILE2" ]; then
          conf_bk "$IPT_FILE2"
          /bin/cp -f "$IPT_FILE" "$IPT_FILE2"
        fi
      fi
    else
      nft_bk=$(find /etc/sysconfig -maxdepth 1 -name 'nftables.conf.old-*-*-*-*_*_*' -print0 \
        | xargs -r -0 ls -1 -t | head -1)
      if [ -f "$nft_bk" ] \
        && [ "$(diff -y --suppress-common-lines "$IPT_FILE" "$nft_bk" | wc -l)" = "25" ]; then
        bigecho "Restoring nftables rules..."
        conf_bk "$IPT_FILE"
        /bin/cp -f "$nft_bk" "$IPT_FILE" && /bin/rm -f "$nft_bk"
        nft flush ruleset
        systemctl restart nftables
      else
cat <<'EOF'

Note: This script cannot automatically remove nftables rules for the VPN.
      To manually clean them up, edit /etc/sysconfig/nftables.conf
      and remove unneeded rules. Your original rules are backed up as file
      /etc/sysconfig/nftables.conf.old-date-time.

EOF
      fi
    fi
  fi
}

remove_config_files() {
  bigecho "Removing VPN configuration..."
  /bin/rm -f /etc/ipsec.conf* /etc/ipsec.secrets* /etc/ppp/chap-secrets* /etc/ppp/options.xl2tpd* \
      /etc/pam.d/pluto /etc/sysconfig/pluto /etc/default/pluto
  /bin/rm -rf /etc/ipsec.d /etc/xl2tpd
}

remove_vpn() {
  stop_services
  remove_ipsec
  remove_xl2tpd
  remove_ikev2_script
  update_sysctl
  update_rclocal
  update_iptables_rules
  remove_config_files
}

print_vpn_removed() {
  echo
  echo "IPsec VPN removed! Please reboot your server."
}

vpnuninstall() {
  check_root
  check_os
  check_libreswan
  check_iface
  confirm_remove
  remove_vpn
  print_vpn_removed
}

## Defer until we have the complete script
vpnuninstall "$@"

exit 0
