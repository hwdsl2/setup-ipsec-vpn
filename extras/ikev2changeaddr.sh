#!/bin/bash
#
# Script to change IKEv2 VPN server address
#
# The latest version of this script is available at:
# https://github.com/hwdsl2/setup-ipsec-vpn
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

check_ip() {
  IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "$IP_REGEX"
}

check_dns_name() {
  FQDN_REGEX='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "$FQDN_REGEX"
}

check_root() {
  if [ "$(id -u)" != 0 ]; then
    exiterr "Script must be run as root. Try 'sudo bash $0'"
  fi
}

check_os() {
  os_type=$(lsb_release -si 2>/dev/null)
  [ -z "$os_type" ] && [ -f /etc/os-release ] && os_type=$(. /etc/os-release && printf '%s' "$ID")
  case $os_type in
    [Aa]lpine)
      os_type=alpine
      ;;
    *)
      os_type=other
      ;;
  esac
}

check_libreswan() {
  ipsec_ver=$(ipsec --version 2>/dev/null)
  if ( ! grep -qs "hwdsl2 VPN script" /etc/sysctl.conf && ! grep -qs "hwdsl2" /opt/src/run.sh ) \
    || ! printf '%s' "$ipsec_ver" | grep -qi 'libreswan'; then
cat 1>&2 <<'EOF'
Error: This script can only be used with an IPsec server created using:
       https://github.com/hwdsl2/setup-ipsec-vpn
EOF
    exit 1
  fi
}

check_ikev2() {
  if ! grep -qs "conn ikev2-cp" /etc/ipsec.d/ikev2.conf; then
cat 1>&2 <<'EOF'
Error: You must first set up IKEv2 before changing IKEv2 server address.
       See: https://vpnsetup.net/ikev2
EOF
    exit 1
  fi
}

check_utils_exist() {
  command -v certutil >/dev/null 2>&1 || exiterr "'certutil' not found. Abort."
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

check_cert_exists() {
  certutil -L -d sql:/etc/ipsec.d -n "$1" >/dev/null 2>&1
}

check_ca_cert_exists() {
  check_cert_exists "IKEv2 VPN CA" || exiterr "Certificate 'IKEv2 VPN CA' does not exist. Abort."
}

get_server_address() {
  server_addr_old=$(grep -s "leftcert=" /etc/ipsec.d/ikev2.conf | cut -f2 -d=)
  check_ip "$server_addr_old" || check_dns_name "$server_addr_old" || exiterr "Could not get current VPN server address."
}

show_welcome() {
cat <<EOF
Welcome! Use this script to change this IKEv2 VPN server's address.

Current server address: $server_addr_old

EOF
}

get_default_ip() {
  def_ip=$(ip -4 route get 1 | sed 's/ uid .*//' | awk '{print $NF;exit}' 2>/dev/null)
  if check_ip "$def_ip" \
    && ! printf '%s' "$def_ip" | grep -Eq '^(10|127|172\.(1[6-9]|2[0-9]|3[0-1])|192\.168|169\.254)\.'; then
    public_ip="$def_ip"
  fi
}

get_server_ip() {
  use_default_ip=0
  public_ip=${VPN_PUBLIC_IP:-''}
  check_ip "$public_ip" || get_default_ip
  check_ip "$public_ip" && { use_default_ip=1; return 0; }
  bigecho "Trying to auto discover IP of this server..."
  check_ip "$public_ip" || public_ip=$(dig @resolver1.opendns.com -t A -4 myip.opendns.com +short)
  check_ip "$public_ip" || public_ip=$(wget -t 2 -T 10 -qO- http://ipv4.icanhazip.com)
  check_ip "$public_ip" || public_ip=$(wget -t 2 -T 10 -qO- http://ip1.dynupdate.no-ip.com)
}

enter_server_address() {
  echo "Do you want IKEv2 VPN clients to connect to this server using a DNS name,"
  printf "e.g. vpn.example.com, instead of its IP address? [y/N] "
  read -r response
  case $response in
    [yY][eE][sS]|[yY])
      use_dns_name=1
      echo
      ;;
    *)
      use_dns_name=0
      echo
      ;;
  esac
  if [ "$use_dns_name" = 1 ]; then
    read -rp "Enter the DNS name of this VPN server: " server_addr
    until check_dns_name "$server_addr"; do
      echo "Invalid DNS name. You must enter a fully qualified domain name (FQDN)."
      read -rp "Enter the DNS name of this VPN server: " server_addr
    done
  else
    get_server_ip
    [ "$use_default_ip" = 0 ] && echo
    read -rp "Enter the IPv4 address of this VPN server: [$public_ip] " server_addr
    [ -z "$server_addr" ] && server_addr="$public_ip"
    until check_ip "$server_addr"; do
      echo "Invalid IP address."
      read -rp "Enter the IPv4 address of this VPN server: [$public_ip] " server_addr
      [ -z "$server_addr" ] && server_addr="$public_ip"
    done
  fi
}

check_server_address() {
  if [ "$server_addr" = "$server_addr_old" ]; then
    echo >&2
    echo "Error: IKEv2 server address is already '$server_addr'. Nothing to do." >&2
    abort_and_exit
  fi
}

confirm_changes() {
cat <<EOF

You are about to change this IKEv2 VPN server's address.

*IMPORTANT* After running this script, you must manually update
the server address (and remote ID, if applicable) on any existing
IKEv2 client devices. For iOS clients, you'll need to export and
re-import client configuration using the IKEv2 helper script.

===========================================

Current server address: $server_addr_old
New server address:     $server_addr

===========================================

EOF
  printf "Do you want to continue? [Y/n] "
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

create_server_cert() {
  if check_cert_exists "$server_addr"; then
    bigecho "Server certificate '$server_addr' already exists, skipping..."
  else
    bigecho "Generating server certificate..."
    if [ "$use_dns_name" = 1 ]; then
      certutil -z <(head -c 1024 /dev/urandom) \
        -S -c "IKEv2 VPN CA" -n "$server_addr" \
        -s "O=IKEv2 VPN,CN=$server_addr" \
        -k rsa -g 3072 -v 120 \
        -d sql:/etc/ipsec.d -t ",," \
        --keyUsage digitalSignature,keyEncipherment \
        --extKeyUsage serverAuth \
        --extSAN "dns:$server_addr" >/dev/null 2>&1 || exiterr "Failed to create server certificate."
    else
      certutil -z <(head -c 1024 /dev/urandom) \
        -S -c "IKEv2 VPN CA" -n "$server_addr" \
        -s "O=IKEv2 VPN,CN=$server_addr" \
        -k rsa -g 3072 -v 120 \
        -d sql:/etc/ipsec.d -t ",," \
        --keyUsage digitalSignature,keyEncipherment \
        --extKeyUsage serverAuth \
        --extSAN "ip:$server_addr,dns:$server_addr" >/dev/null 2>&1 || exiterr "Failed to create server certificate."
    fi
  fi
}

update_ikev2_conf() {
  bigecho "Updating IKEv2 configuration..."
  if ! grep -qs '^include /etc/ipsec\.d/\*\.conf$' /etc/ipsec.conf; then
    echo >> /etc/ipsec.conf
    echo 'include /etc/ipsec.d/*.conf' >> /etc/ipsec.conf
  fi
  sed -i".old-$SYS_DT" \
      -e "/^[[:space:]]\+leftcert=/d" \
      -e "/^[[:space:]]\+leftid=/d" /etc/ipsec.d/ikev2.conf
  if [ "$use_dns_name" = 1 ]; then
    sed -i "/conn ikev2-cp/a \  leftid=@$server_addr" /etc/ipsec.d/ikev2.conf
  else
    sed -i "/conn ikev2-cp/a \  leftid=$server_addr" /etc/ipsec.d/ikev2.conf
  fi
  sed -i "/conn ikev2-cp/a \  leftcert=$server_addr" /etc/ipsec.d/ikev2.conf
}

update_ikev2_log() {
  ikev2_log="/etc/ipsec.d/ikev2setup.log"
  if [ -s "$ikev2_log" ]; then
    sed -i "/VPN server address:/s/$server_addr_old/$server_addr/" "$ikev2_log"
  fi
}

restart_ipsec_service() {
  bigecho "Restarting IPsec service..."
  mkdir -p /run/pluto
  service ipsec restart 2>/dev/null
}

print_client_info() {
cat <<EOF

Successfully changed IKEv2 server address!

EOF
}

ikev2changeaddr() {
  check_root
  check_os
  check_libreswan
  check_ikev2
  check_utils_exist
  check_ca_cert_exists
  get_server_address

  show_welcome
  enter_server_address
  check_server_address
  confirm_changes

  create_server_cert
  update_ikev2_conf
  update_ikev2_log
  if [ "$os_type" = "alpine" ]; then
    ipsec auto --replace ikev2-cp >/dev/null
  else
    restart_ipsec_service
  fi
  print_client_info
}

## Defer until we have the complete script
ikev2changeaddr "$@"

exit 0
