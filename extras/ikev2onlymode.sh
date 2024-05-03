#!/bin/bash
#
# Script to enable or disable IKEv2-only mode
#
# Copyright (C) 2022-2024 Lin Song <linsongui@gmail.com>
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
SYS_DT=$(date +%F-%T | tr ':' '_')

exiterr() { echo "Error: $1" >&2; exit 1; }
bigecho() { echo "## $1"; }

check_root() {
  if [ "$(id -u)" != 0 ]; then
    exiterr "Script must be run as root. Try 'sudo bash $0'"
  fi
}

abort_and_exit() {
  echo "Abort. No changes were made." >&2
  exit 1
}

continue_or_abort() {
  printf '%s' "$1"
  read -r response
  case $response in
    [yY][eE][sS]|[yY]|'')
      echo
      ;;
    *)
      abort_and_exit
      ;;
  esac
}

check_ikev2_exists() {
  grep -qs "conn ikev2-cp" /etc/ipsec.conf || [ -f /etc/ipsec.d/ikev2.conf ]
}

check_libreswan() {
  ipsec_ver=$(ipsec --version 2>/dev/null)
  swan_ver=$(printf '%s' "$ipsec_ver" | sed -e 's/.*Libreswan U\?//' -e 's/\( (\|\/K\).*//')
  if ! grep -qs "hwdsl2 VPN script" /etc/sysctl.conf \
    || ! grep -qs "config setup" /etc/ipsec.conf \
    || ! printf '%s' "$ipsec_ver" | grep -qi 'libreswan'; then
cat 1>&2 <<'EOF'
Error: Your must first set up the IPsec VPN server before selecting IKEv2-only mode.
       See: https://github.com/hwdsl2/setup-ipsec-vpn
EOF
    exit 1
  fi
  if ! check_ikev2_exists; then
cat 1>&2 <<'EOF'
Error: Your must first set up IKEv2 before selecting IKEv2-only mode.
       See: https://vpnsetup.net/ikev2
EOF
    exit 1
  fi
}

check_swan_ver() {
  if ! printf '%s\n%s' "4.2" "$swan_ver" | sort -C -V; then
cat 1>&2 <<EOF
Error: Libreswan version '$swan_ver' is not supported.
       IKEv2-only mode requires Libreswan 4.2 or newer.
       To update Libreswan, run:
       wget https://get.vpnsetup.net/upg -O vpnup.sh && sudo sh vpnup.sh
EOF
    exit 1
  fi
}

get_ikev2_only_status() {
  if grep -qs "ikev1-policy=drop" /etc/ipsec.conf \
    || grep -qs "ikev1-policy=reject" /etc/ipsec.conf; then
    ikev2_only_status=ENABLED
    option_text="Disable IKEv2-only mode"
  else
    ikev2_only_status=DISABLED
    option_text="Enable IKEv2-only mode"
  fi
}

confirm_disable_ikev2_only() {
cat <<'EOF'

Note: This option will disable IKEv2-only mode on this VPN server. With IKEv2-only
      mode disabled, VPN clients can connect to this server using IKEv1 (including
      IPsec/L2TP and IPsec/XAuth ("Cisco IPsec") modes) in addition to IKEv2.

EOF
  continue_or_abort "Do you want to continue? [Y/n] "
}

confirm_enable_ikev2_only() {
cat <<'EOF'

Note: This option will enable IKEv2-only mode on this VPN server. With IKEv2-only
      mode enabled, VPN clients can *only* connect to this server using IKEv2.
      All IKEv1 connections (including IPsec/L2TP and IPsec/XAuth ("Cisco IPsec")
      modes) will be dropped.

EOF
  continue_or_abort "Do you want to continue? [Y/n] "
}

toggle_ikev2_only() {
  if [ "$ikev2_only_status" = "ENABLED" ]; then
    confirm_disable_ikev2_only
    bigecho "Disabling IKEv2-only mode..."
    sed -i".old-$SYS_DT" "/ikev1-policy=/d" /etc/ipsec.conf
    sed -i "/config setup/a \  ikev1-policy=accept" /etc/ipsec.conf
  elif [ "$ikev2_only_status" = "DISABLED" ]; then
    confirm_enable_ikev2_only
    bigecho "Enabling IKEv2-only mode..."
    sed -i".old-$SYS_DT" "/ikev1-policy=/d" /etc/ipsec.conf
    sed -i "/config setup/a \  ikev1-policy=drop" /etc/ipsec.conf
  fi
}

restart_ipsec_service() {
  bigecho "Restarting IPsec service..."
  mkdir -p /run/pluto
  service ipsec restart 2>/dev/null
}

print_complete() {
cat <<'EOF'
Done!

EOF
}

select_menu_option() {
cat <<EOF

IKEv2-only mode is currently $ikev2_only_status on this VPN server.

Select an option:
  1) $option_text
  2) Exit
EOF
  read -rp "Option: " selected_option
  until [[ "$selected_option" =~ ^[1-2]$ ]]; do
    printf '%s\n' "$selected_option: invalid selection."
    read -rp "Option: " selected_option
  done
}

ikev2onlymode() {
  check_root
  check_libreswan
  check_swan_ver
  get_ikev2_only_status
  select_menu_option
  case $selected_option in
    1)
      toggle_ikev2_only
      restart_ipsec_service
      print_complete
      exit 0
      ;;
    *)
      exit 0
      ;;
  esac
}

## Defer until we have the complete script
ikev2onlymode "$@"

exit 0
