#!/bin/bash
#
# Script to update VPN users for both IPsec/L2TP and Cisco IPsec
#
# Copyright (C) 2018-2024 Lin Song <linsongui@gmail.com>
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

# =====================================================

# Define your own values for these variables
# - List of VPN usernames and passwords, separated by spaces
# - All values MUST be placed inside 'single quotes'
# - DO NOT use these special characters within values: \ " '

YOUR_USERNAMES=''
YOUR_PASSWORDS=''

# Example:
# YOUR_USERNAMES='username1 username2'
# YOUR_PASSWORDS='password1 password2'

# WARNING: *ALL* existing VPN users will be removed
#          and replaced with the users listed here.

# =====================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
SYS_DT=$(date +%F-%T | tr ':' '_')

exiterr()  { echo "Error: $1" >&2; exit 1; }
conf_bk() { /bin/cp -f "$1" "$1.old-$SYS_DT" 2>/dev/null; }
onespace() { printf '%s' "$1" | tr -s ' '; }
noquotes() { printf '%s' "$1" | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"; }
noquotes2() { printf '%s' "$1" | sed -e 's/" "/ /g' -e "s/' '/ /g"; }

update_vpn_users() {
  if [ "$(id -u)" != 0 ]; then
    exiterr "Script must be run as root. Try 'sudo bash $0'"
  fi
  if ! grep -qs "hwdsl2 VPN script" /etc/sysctl.conf \
    || [ ! -f /etc/ppp/chap-secrets ] || [ ! -f /etc/ipsec.d/passwd ]; then
cat 1>&2 <<'EOF'
Error: Your must first set up the IPsec VPN server before updating VPN users.
       See: https://github.com/hwdsl2/setup-ipsec-vpn
EOF
    exit 1
  fi
  command -v openssl >/dev/null 2>&1 || exiterr "'openssl' not found. Abort."
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
cat 1>&2 <<'EOF'
For usage information, visit https://github.com/hwdsl2/setup-ipsec-vpn,
then click on Manage VPN Users.
EOF
    exit 1
  fi
  [ -n "$YOUR_USERNAMES" ] && VPN_USERS="$YOUR_USERNAMES"
  [ -n "$YOUR_PASSWORDS" ] && VPN_PASSWORDS="$YOUR_PASSWORDS"
  VPN_USERS=$(noquotes "$VPN_USERS")
  VPN_USERS=$(onespace "$VPN_USERS")
  VPN_USERS=$(noquotes2 "$VPN_USERS")
  VPN_PASSWORDS=$(noquotes "$VPN_PASSWORDS")
  VPN_PASSWORDS=$(onespace "$VPN_PASSWORDS")
  VPN_PASSWORDS=$(noquotes2 "$VPN_PASSWORDS")
  if [ -z "$VPN_USERS" ] || [ -z "$VPN_PASSWORDS" ]; then
    exiterr "All VPN credentials must be specified. Edit the script and re-enter them."
  fi
  if printf '%s' "$VPN_USERS $VPN_PASSWORDS" | LC_ALL=C grep -q '[^ -~]\+'; then
    exiterr "VPN credentials must not contain non-ASCII characters."
  fi
  case "$VPN_USERS $VPN_PASSWORDS" in
    *[\\\"\']*)
      exiterr "VPN credentials must not contain these special characters: \\ \" '"
      ;;
  esac
  if printf '%s' "$VPN_USERS" | tr ' ' '\n' | sort | uniq -c | grep -qv '^ *1 '; then
    exiterr "VPN usernames must not contain duplicates."
  fi
cat <<'EOF'

Welcome! Use this script to update VPN user accounts for both
IPsec/L2TP and IPsec/XAuth ("Cisco IPsec") modes.

WARNING: *ALL* existing VPN users will be removed and replaced
         with the users listed below.

==================================================

Updated list of VPN users (username | password):

EOF
  count=1
  vpn_user=$(printf '%s' "$VPN_USERS" | cut -d ' ' -f 1)
  vpn_password=$(printf '%s' "$VPN_PASSWORDS" | cut -d ' ' -f 1)
  while [ -n "$vpn_user" ] && [ -n "$vpn_password" ]; do
cat <<EOF
$vpn_user | $vpn_password
EOF
    count=$((count+1))
    vpn_user=$(printf '%s' "$VPN_USERS" | cut -s -d ' ' -f "$count")
    vpn_password=$(printf '%s' "$VPN_PASSWORDS" | cut -s -d ' ' -f "$count")
  done
cat <<'EOF'

Write these down. You'll need them to connect!

VPN client setup: https://vpnsetup.net/clients

==================================================

EOF
  printf "Do you want to continue? [Y/n] "
  read -r response
  case $response in
    [yY][eE][sS]|[yY]|'')
      echo
      echo "Updating VPN users..."
      echo
      ;;
    *)
      echo "Abort. No changes were made."
      exit 1
      ;;
  esac
  # Backup and remove config files
  conf_bk "/etc/ppp/chap-secrets"
  conf_bk "/etc/ipsec.d/passwd"
  /bin/rm -f /etc/ppp/chap-secrets /etc/ipsec.d/passwd
  # Update VPN users
  count=1
  vpn_user=$(printf '%s' "$VPN_USERS" | cut -d ' ' -f 1)
  vpn_password=$(printf '%s' "$VPN_PASSWORDS" | cut -d ' ' -f 1)
  while [ -n "$vpn_user" ] && [ -n "$vpn_password" ]; do
    vpn_password_enc=$(openssl passwd -1 "$vpn_password")
cat >> /etc/ppp/chap-secrets <<EOF
"$vpn_user" l2tpd "$vpn_password" *
EOF
cat >> /etc/ipsec.d/passwd <<EOF
$vpn_user:$vpn_password_enc:xauth-psk
EOF
    count=$((count+1))
    vpn_user=$(printf '%s' "$VPN_USERS" | cut -s -d ' ' -f "$count")
    vpn_password=$(printf '%s' "$VPN_PASSWORDS" | cut -s -d ' ' -f "$count")
  done
  # Update file attributes
  chmod 600 /etc/ppp/chap-secrets* /etc/ipsec.d/passwd*
cat <<'EOF'
Done!

Note: All VPN users will share the same IPsec PSK.
      If you forgot the PSK, check /etc/ipsec.secrets.

EOF
}

## Defer until we have the complete script
update_vpn_users "$@"

exit 0
