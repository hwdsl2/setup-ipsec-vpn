#!/bin/bash
#
# Script to delete a VPN user for both IPsec/L2TP and Cisco IPsec
#
# Copyright (C) 2018-2024 Lin Song <linsongui@gmail.com>
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

show_intro() {
cat <<'EOF'

Welcome! Use this script to delete a VPN user account for both
IPsec/L2TP and IPsec/XAuth ("Cisco IPsec") modes.
EOF
}

del_vpn_user() {
  if [ "$(id -u)" != 0 ]; then
    exiterr "Script must be run as root. Try 'sudo bash $0'"
  fi
  if ! grep -qs "hwdsl2 VPN script" /etc/sysctl.conf \
    || [ ! -f /etc/ppp/chap-secrets ] || [ ! -f /etc/ipsec.d/passwd ]; then
cat 1>&2 <<'EOF'
Error: Your must first set up the IPsec VPN server before deleting VPN users.
       See: https://github.com/hwdsl2/setup-ipsec-vpn
EOF
    exit 1
  fi
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
cat 1>&2 <<EOF
Usage: sudo bash $0 'username_to_delete'
You may also run this script interactively without arguments.
EOF
    exit 1
  fi
  VPN_USER=$1
  if [ -z "$VPN_USER" ]; then
    show_intro
    echo
    echo "List of existing VPN usernames:"
    cut -f1 -d : /etc/ipsec.d/passwd | LC_ALL=C sort
    echo
    echo "Enter the VPN username you want to delete."
    read -rp "Username: " VPN_USER
    if [ -z "$VPN_USER" ]; then
      echo "Abort. No changes were made." >&2
      exit 1
    fi
  fi
  if printf '%s' "$VPN_USER" | LC_ALL=C grep -q '[^ -~]\+'; then
    exiterr "VPN username must not contain non-ASCII characters."
  fi
  case "$VPN_USER" in
    *[\\\"\']*)
      exiterr "VPN username must not contain these special characters: \\ \" '"
      ;;
  esac
  if [ "$(grep -c "^\"$VPN_USER\" " /etc/ppp/chap-secrets)" = 0 ] \
    || [ "$(grep -c "^$VPN_USER:\\\$1\\\$" /etc/ipsec.d/passwd)" = 0 ]; then
cat 1>&2 <<'EOF'
Error: The specified VPN user does not exist in /etc/ppp/chap-secrets
       and/or /etc/ipsec.d/passwd.
EOF
    exit 1
  fi
  if [ "$(grep -c -v -e '^#' -e '^[[:space:]]*$' /etc/ppp/chap-secrets)" = 1 ] \
    || [ "$(grep -c -v -e '^#' -e '^[[:space:]]*$' /etc/ipsec.d/passwd)" = 1 ]; then
cat 1>&2 <<'EOF'
Error: Could not delete the only VPN user from /etc/ppp/chap-secrets
       and/or /etc/ipsec.d/passwd.
EOF
    exit 1
  fi
  [ -n "$1" ] && show_intro
cat <<EOF

================================================

VPN user to delete:

Username: $VPN_USER

================================================

EOF
  printf "Do you want to continue? [Y/n] "
  read -r response
  case $response in
    [yY][eE][sS]|[yY]|'')
      echo
      echo "Deleting VPN user..."
      echo
      ;;
    *)
      echo "Abort. No changes were made."
      exit 1
      ;;
  esac
  # Backup config files
  conf_bk "/etc/ppp/chap-secrets"
  conf_bk "/etc/ipsec.d/passwd"
  # Delete VPN user
  sed -i "/^\"$VPN_USER\" /d" /etc/ppp/chap-secrets
  # shellcheck disable=SC2016
  sed -i '/^'"$VPN_USER"':\$1\$/d' /etc/ipsec.d/passwd
  # Update file attributes
  chmod 600 /etc/ppp/chap-secrets* /etc/ipsec.d/passwd*
cat <<'EOF'
Done!

EOF
}

## Defer until we have the complete script
del_vpn_user "$@"

exit 0
