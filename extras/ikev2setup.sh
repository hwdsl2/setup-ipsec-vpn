#!/bin/bash
#
# Script to set up and manage IKEv2 on Ubuntu, Debian, CentOS/RHEL,
# Rocky Linux, AlmaLinux, Amazon Linux 2 and Alpine Linux
#
# DO NOT RUN THIS SCRIPT ON YOUR PC OR MAC!
#
# The latest version of this script is available at:
# https://github.com/hwdsl2/setup-ipsec-vpn
#
# Copyright (C) 2020-2021 Lin Song <linsongui@gmail.com>
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

exiterr() { echo "Error: $1" >&2; exit 1; }
bigecho() { echo "## $1"; }
bigecho2() { printf '\e[2K\r%s' "## $1"; }

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
  os_type=centos
  os_arch=$(uname -m | tr -dc 'A-Za-z0-9_-')
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
    fi
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

check_libreswan() {
  ipsec_ver=$(ipsec --version 2>/dev/null)
  swan_ver=$(printf '%s' "$ipsec_ver" | sed -e 's/.*Libreswan U\?//' -e 's/\( (\|\/K\).*//')
  if ( ! grep -qs "hwdsl2 VPN script" /etc/sysctl.conf && ! grep -qs "hwdsl2" /opt/src/run.sh ) \
    || ! printf '%s' "$ipsec_ver" | grep -q "Libreswan"; then
cat 1>&2 <<'EOF'
Error: Your must first set up the IPsec VPN server before setting up IKEv2.
       See: https://github.com/hwdsl2/setup-ipsec-vpn
EOF
    exit 1
  fi
  case $swan_ver in
    3.2[35679]|3.3[12]|4.*)
      true
      ;;
    *)
cat 1>&2 <<EOF
Error: Libreswan version '$swan_ver' is not supported.
       This script requires one of these versions:
       3.23, 3.25-3.27, 3.29, 3.31-3.32 or 4.x
       To update Libreswan, run:
       wget https://git.io/vpnupgrade -O vpnup.sh && sudo sh vpnup.sh
EOF
      exit 1
      ;;
  esac
}

check_utils_exist() {
  command -v certutil >/dev/null 2>&1 || exiterr "'certutil' not found. Abort."
  command -v crlutil >/dev/null 2>&1 || exiterr "'crlutil' not found. Abort."
  command -v pk12util >/dev/null 2>&1 || exiterr "'pk12util' not found. Abort."
}

check_container() {
  in_container=0
  if grep -qs "hwdsl2" /opt/src/run.sh; then
    in_container=1
  fi
}

show_header() {
cat <<'EOF'

IKEv2 Script   Copyright (c) 2020-2021 Lin Song   7 Nov 2021

EOF
}

show_usage() {
  if [ -n "$1" ]; then
    echo "Error: $1" >&2;
  fi
  show_header
cat 1>&2 <<EOF
Usage: bash $0 [options]

Options:
  --auto                        run IKEv2 setup in auto mode using default options (for initial setup only)
  --addclient [client name]     add a new client using default options
  --exportclient [client name]  export configuration for an existing client
  --listclients                 list the names of existing clients
  --revokeclient [client name]  revoke a client certificate
  --removeikev2                 remove IKEv2 and delete all certificates and keys from the IPsec database
  -h, --help                    show this help message and exit

To customize IKEv2 or client options, run this script without arguments.
For documentation, see: https://git.io/ikev2
EOF
  exit 1
}

check_ikev2_exists() {
  grep -qs "conn ikev2-cp" /etc/ipsec.conf || [ -f /etc/ipsec.d/ikev2.conf ]
}

check_client_name() {
  ! { [ "${#1}" -gt "64" ] || printf '%s' "$1" | LC_ALL=C grep -q '[^A-Za-z0-9_-]\+' \
    || case $1 in -*) true;; *) false;; esac; }
}

check_cert_exists() {
  certutil -L -d sql:/etc/ipsec.d -n "$1" >/dev/null 2>&1
}

check_cert_exists_and_exit() {
  if certutil -L -d sql:/etc/ipsec.d -n "$1" >/dev/null 2>&1; then
    echo "Error: Certificate '$1' already exists." >&2
    abort_and_exit
  fi
}

check_cert_status() {
  cert_status=$(certutil -V -u C -d sql:/etc/ipsec.d -n "$1")
}

check_arguments() {
  if [ "$use_defaults" = "1" ]; then
    if check_ikev2_exists; then
      echo "Warning: Ignoring parameter '--auto'. Use '-h' for usage information." >&2
    fi
  fi
  if [ "$((add_client + export_client + list_clients + revoke_client))" -gt 1 ]; then
    show_usage "Invalid parameters. Specify only one of '--addclient', '--exportclient', '--listclients' or '--revokeclient'."
  fi
  if [ "$add_client" = "1" ]; then
    check_ikev2_exists || exiterr "You must first set up IKEv2 before adding a client."
    if [ -z "$client_name" ] || ! check_client_name "$client_name"; then
      exiterr "Invalid client name. Use one word only, no special characters except '-' and '_'."
    elif check_cert_exists "$client_name"; then
      exiterr "Invalid client name. Client '$client_name' already exists."
    fi
  fi
  if [ "$export_client" = "1" ]; then
    check_ikev2_exists || exiterr "You must first set up IKEv2 before exporting a client."
    get_server_address
    if [ -z "$client_name" ] || ! check_client_name "$client_name" \
      || [ "$client_name" = "IKEv2 VPN CA" ] || [ "$client_name" = "$server_addr" ] \
      || ! check_cert_exists "$client_name"; then
      exiterr "Invalid client name, or client does not exist."
    fi
    if ! check_cert_status "$client_name"; then
      printf '%s' "Error: Certificate '$client_name' " >&2
      if printf '%s' "$cert_status" | grep -q "revoked"; then
        echo "has been revoked." >&2
      elif printf '%s' "$cert_status" | grep -q "expired"; then
        echo "has expired." >&2
      else
        echo "is invalid." >&2
      fi
      exit 1
    fi
  fi
  if [ "$list_clients" = "1" ]; then
    check_ikev2_exists || exiterr "You must first set up IKEv2 before listing clients."
  fi
  if [ "$revoke_client" = "1" ]; then
    check_ikev2_exists || exiterr "You must first set up IKEv2 before revoking a client certificate."
    get_server_address
    if [ -z "$client_name" ] || ! check_client_name "$client_name" \
      || [ "$client_name" = "IKEv2 VPN CA" ] || [ "$client_name" = "$server_addr" ] \
      || ! check_cert_exists "$client_name"; then
      exiterr "Invalid client name, or client does not exist."
    fi
    if ! check_cert_status "$client_name"; then
      printf '%s' "Error: Certificate '$client_name' " >&2
      if printf '%s' "$cert_status" | grep -q "revoked"; then
        echo "has already been revoked." >&2
      elif printf '%s' "$cert_status" | grep -q "expired"; then
        echo "has expired." >&2
      else
        echo "is invalid." >&2
      fi
      exit 1
    fi
  fi
  if [ "$remove_ikev2" = "1" ]; then
    check_ikev2_exists || exiterr "Cannot remove IKEv2 because it has not been set up on this server."
    if [ "$((add_client + export_client + list_clients + revoke_client + use_defaults))" -gt 0 ]; then
      show_usage "Invalid parameters. '--removeikev2' cannot be specified with other parameters."
    fi
  fi
}

check_server_dns_name() {
  if [ -n "$VPN_DNS_NAME" ]; then
    check_dns_name "$VPN_DNS_NAME" || exiterr "Invalid DNS name. 'VPN_DNS_NAME' must be a fully qualified domain name (FQDN)."
  fi
}

check_custom_dns() {
  if { [ -n "$VPN_DNS_SRV1" ] && ! check_ip "$VPN_DNS_SRV1"; } \
    || { [ -n "$VPN_DNS_SRV2" ] && ! check_ip "$VPN_DNS_SRV2"; } then
    exiterr "Invalid DNS server(s)."
  fi
}

check_swan_ver() {
  if [ "$in_container" = "0" ]; then
    swan_ver_url="https://dl.ls20.com/v1/$os_type/$os_ver/swanverikev2?arch=$os_arch&ver=$swan_ver&auto=$use_defaults"
  else
    swan_ver_url="https://dl.ls20.com/v1/docker/$os_type/$os_arch/swanverikev2?ver=$swan_ver&auto=$use_defaults"
  fi
  [ "$1" != "0" ] && swan_ver_url="$swan_ver_url&e=$2"
  swan_ver_latest=$(wget -t 3 -T 15 -qO- "$swan_ver_url")
}

show_update_info() {
  if printf '%s' "$swan_ver_latest" | grep -Eq '^([3-9]|[1-9][0-9]{1,2})(\.([0-9]|[1-9][0-9]{1,2})){1,2}$' \
    && [ "$1" = "0" ] && check_ikev2_exists && [ "$swan_ver" != "$swan_ver_latest" ] \
    && printf '%s\n%s' "$swan_ver" "$swan_ver_latest" | sort -C -V; then
    echo "Note: A newer version of Libreswan ($swan_ver_latest) is available."
    if [ "$in_container" = "0" ]; then
      echo "      To update, run:"
      echo "      wget https://git.io/vpnupgrade -O vpnup.sh && sudo sh vpnup.sh"
    else
      echo "      To update this Docker image, see: https://git.io/updatedockervpn"
    fi
    echo
  fi
}

finish() {
  check_swan_ver "$1" "$2"
  show_update_info "$1"
  exit "$1"
}

show_welcome() {
cat <<'EOF'
Welcome! Use this script to set up IKEv2 on your IPsec VPN server.

I need to ask you a few questions before starting setup.
You can use the default options and just press enter if you are OK with them.

EOF
}

show_start_setup() {
  if [ -n "$VPN_DNS_NAME" ] || [ -n "$VPN_CLIENT_NAME" ] || [ -n "$VPN_DNS_SRV1" ]; then
    bigecho "Starting IKEv2 setup in auto mode."
    printf '%s' "## Using custom option(s): "
    [ -n "$VPN_DNS_NAME" ] && printf '%s' "VPN_DNS_NAME "
    [ -n "$VPN_CLIENT_NAME" ] && printf '%s' "VPN_CLIENT_NAME "
    if [ -n "$VPN_DNS_SRV1" ] && [ -n "$VPN_DNS_SRV2" ]; then
      printf '%s' "VPN_DNS_SRV1 VPN_DNS_SRV2"
    elif [ -n "$VPN_DNS_SRV1" ]; then
      printf '%s' "VPN_DNS_SRV1"
    fi
    echo
  else
    bigecho "Starting IKEv2 setup in auto mode, using default options."
  fi
}

show_add_client() {
  bigecho "Adding a new IKEv2 client '$client_name', using default options."
}

show_export_client() {
  bigecho "Exporting existing IKEv2 client '$client_name'."
}

get_export_dir() {
  export_to_home_dir=0
  if grep -qs "hwdsl2" /opt/src/run.sh; then
    export_dir="/etc/ipsec.d/"
  else
    export_dir=~/
    if [ -n "$SUDO_USER" ] && getent group "$SUDO_USER" >/dev/null 2>&1; then
      user_home_dir=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
      if [ -d "$user_home_dir" ] && [ "$user_home_dir" != "/" ]; then
        export_dir="$user_home_dir/"
        export_to_home_dir=1
      fi
    fi
  fi
}

get_server_ip() {
  bigecho2 "Trying to auto discover IP of this server..."
  public_ip=${VPN_PUBLIC_IP:-''}
  check_ip "$public_ip" || public_ip=$(dig @resolver1.opendns.com -t A -4 myip.opendns.com +short)
  check_ip "$public_ip" || public_ip=$(wget -t 3 -T 15 -qO- http://ipv4.icanhazip.com)
}

get_server_address() {
  server_addr=$(grep -s "leftcert=" /etc/ipsec.d/ikev2.conf | cut -f2 -d=)
  [ -z "$server_addr" ] && server_addr=$(grep -s "leftcert=" /etc/ipsec.conf | cut -f2 -d=)
  check_ip "$server_addr" || check_dns_name "$server_addr" || exiterr "Could not get VPN server address."
}

list_existing_clients() {
  echo "Checking for existing IKEv2 client(s)..."
  echo
  client_names=$(certutil -L -d sql:/etc/ipsec.d | grep -v -e '^$' -e 'IKEv2 VPN CA' -e '\.' | tail -n +3 | cut -f1 -d ' ')
  max_len=$(printf '%s\n' "$client_names" | wc -L 2>/dev/null)
  [[ $max_len =~ ^[0-9]+$ ]] || max_len=64
  [ "$max_len" -gt "64" ] && max_len=64
  [ "$max_len" -lt "16" ] && max_len=16
  printf "%-${max_len}s  %s\n" 'Client Name' 'Certificate Status'
  printf "%-${max_len}s  %s\n" '------------' '-------------------'
  printf '%s\n' "$client_names" | while read -r line; do
    printf "%-${max_len}s  " "$line"
    client_status=$(certutil -V -u C -d sql:/etc/ipsec.d -n "$line" | grep -o -e ' valid' -e expired -e revoked | sed -e 's/^ //')
    [ -z "$client_status" ] && client_status=unknown
    printf '%s\n' "$client_status"
  done
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
  if [ "$use_dns_name" = "1" ]; then
    read -rp "Enter the DNS name of this VPN server: " server_addr
    until check_dns_name "$server_addr"; do
      echo "Invalid DNS name. You must enter a fully qualified domain name (FQDN)."
      read -rp "Enter the DNS name of this VPN server: " server_addr
    done
  else
    get_server_ip
    echo
    echo
    read -rp "Enter the IPv4 address of this VPN server: [$public_ip] " server_addr
    [ -z "$server_addr" ] && server_addr="$public_ip"
    until check_ip "$server_addr"; do
      echo "Invalid IP address."
      read -rp "Enter the IPv4 address of this VPN server: [$public_ip] " server_addr
      [ -z "$server_addr" ] && server_addr="$public_ip"
    done
  fi
}

enter_client_name() {
  echo
  echo "Provide a name for the IKEv2 VPN client."
  echo "Use one word only, no special characters except '-' and '_'."
  read -rp "Client name: " client_name
  [ -z "$client_name" ] && abort_and_exit
  while ! check_client_name "$client_name" || check_cert_exists "$client_name"; do
    if ! check_client_name "$client_name"; then
      echo "Invalid client name."
    else
      echo "Invalid client name. Client '$client_name' already exists."
    fi
    read -rp "Client name: " client_name
    [ -z "$client_name" ] && abort_and_exit
  done
}

enter_client_name_with_defaults() {
  echo
  echo "Provide a name for the IKEv2 VPN client."
  echo "Use one word only, no special characters except '-' and '_'."
  read -rp "Client name: [vpnclient] " client_name
  [ -z "$client_name" ] && client_name=vpnclient
  while ! check_client_name "$client_name" || check_cert_exists "$client_name"; do
      if ! check_client_name "$client_name"; then
        echo "Invalid client name."
      else
        echo "Invalid client name. Client '$client_name' already exists."
      fi
    read -rp "Client name: [vpnclient] " client_name
    [ -z "$client_name" ] && client_name=vpnclient
  done
}

enter_client_name_for() {
  echo
  list_existing_clients
  get_server_address
  echo
  read -rp "Enter the name of the IKEv2 client to $1: " client_name
  [ -z "$client_name" ] && abort_and_exit
  while ! check_client_name "$client_name" || [ "$client_name" = "IKEv2 VPN CA" ] \
    || [ "$client_name" = "$server_addr" ] || ! check_cert_exists "$client_name" \
    || ! check_cert_status "$client_name"; do
    if ! check_client_name "$client_name" || [ "$client_name" = "IKEv2 VPN CA" ] \
    || [ "$client_name" = "$server_addr" ] || ! check_cert_exists "$client_name"; then
      echo "Invalid client name, or client does not exist."
    else
      printf '%s' "Error: Certificate '$client_name' "
      if printf '%s' "$cert_status" | grep -q "revoked"; then
        if [ "$1" = "revoke" ]; then
          echo "has already been revoked."
        else
          echo "has been revoked."
        fi
      elif printf '%s' "$cert_status" | grep -q "expired"; then
        echo "has expired."
      else
        echo "is invalid."
      fi
    fi
    read -rp "Enter the name of the IKEv2 client to $1: " client_name
    [ -z "$client_name" ] && abort_and_exit
  done
}

enter_client_cert_validity() {
  echo
  echo "Specify the validity period (in months) for this client certificate."
  read -rp "Enter a number between 1 and 120: [120] " client_validity
  [ -z "$client_validity" ] && client_validity=120
  while printf '%s' "$client_validity" | LC_ALL=C grep -q '[^0-9]\+' \
    || [ "$client_validity" -lt "1" ] || [ "$client_validity" -gt "120" ] \
    || [ "$client_validity" != "$((10#$client_validity))" ]; do
    echo "Invalid validity period."
    read -rp "Enter a number between 1 and 120: [120] " client_validity
    [ -z "$client_validity" ] && client_validity=120
  done
}

enter_custom_dns() {
  echo
  echo "By default, clients are set to use Google Public DNS when the VPN is active."
  printf "Do you want to specify custom DNS servers for IKEv2? [y/N] "
  read -r response
  case $response in
    [yY][eE][sS]|[yY])
      use_custom_dns=1
      ;;
    *)
      use_custom_dns=0
      dns_server_1=8.8.8.8
      dns_server_2=8.8.4.4
      dns_servers="8.8.8.8 8.8.4.4"
      ;;
  esac
  if [ "$use_custom_dns" = "1" ]; then
    read -rp "Enter primary DNS server: " dns_server_1
    until check_ip "$dns_server_1"; do
      echo "Invalid DNS server."
      read -rp "Enter primary DNS server: " dns_server_1
    done
    read -rp "Enter secondary DNS server (enter to skip): " dns_server_2
    until [ -z "$dns_server_2" ] || check_ip "$dns_server_2"; do
      echo "Invalid DNS server."
      read -rp "Enter secondary DNS server (enter to skip): " dns_server_2
    done
    if [ -n "$dns_server_2" ]; then
      dns_servers="$dns_server_1 $dns_server_2"
    else
      dns_servers="$dns_server_1"
    fi
  else
    echo "Using Google Public DNS (8.8.8.8, 8.8.4.4)."
  fi
  echo
}

check_mobike_support() {
  mobike_support=1
  if uname -m | grep -qi -e '^arm' -e '^aarch64'; then
    modprobe -q configs
    if [ -f /proc/config.gz ]; then
      if ! zcat /proc/config.gz | grep -q "CONFIG_XFRM_MIGRATE=y"; then
        mobike_support=0
      fi
    else
      mobike_support=0
    fi
  fi
  kernel_conf="/boot/config-$(uname -r)"
  if [ -f "$kernel_conf" ]; then
    if ! grep -qs "CONFIG_XFRM_MIGRATE=y" "$kernel_conf"; then
      mobike_support=0
    fi
  fi
  # Linux kernels on Ubuntu do not support MOBIKE
  if [ "$in_container" = "0" ]; then
    if [ "$os_type" = "ubuntu" ] || uname -v | grep -qi ubuntu; then
      mobike_support=0
    fi
  else
    if uname -v | grep -qi ubuntu; then
      mobike_support=0
    fi
  fi
  if uname -a | grep -qi qnap; then
    mobike_support=0
  fi
  if [ "$mobike_support" = "1" ]; then
    bigecho2 "Checking for MOBIKE support... available"
  else
    bigecho2 "Checking for MOBIKE support... not available"
  fi
}

select_mobike() {
  echo
  mobike_enable=0
  if [ "$mobike_support" = "1" ]; then
cat <<'EOF'

The MOBIKE IKEv2 extension allows VPN clients to change network attachment points,
e.g. switch between mobile data and Wi-Fi and keep the IPsec tunnel up on the new IP.

EOF
    printf "Do you want to enable MOBIKE support? [Y/n] "
    read -r response
    case $response in
      [yY][eE][sS]|[yY]|'')
        mobike_enable=1
        ;;
      *)
        mobike_enable=0
        ;;
    esac
  fi
}

select_menu_option() {
cat <<'EOF'
IKEv2 is already set up on this server.

Select an option:
  1) Add a new client
  2) Export configuration for an existing client
  3) List existing clients
  4) Revoke a client certificate
  5) Remove IKEv2
  6) Exit
EOF
  read -rp "Option: " selected_option
  until [[ "$selected_option" =~ ^[1-6]$ ]]; do
    printf '%s\n' "$selected_option: invalid selection."
    read -rp "Option: " selected_option
  done
}

print_server_client_info() {
cat <<EOF
VPN server address: $server_addr
VPN client name: $client_name

EOF
}

confirm_setup_options() {
cat <<EOF

We are ready to set up IKEv2 now. Below are the setup options you selected.
Please double check before continuing!

======================================

EOF
  print_server_client_info
  if [ "$client_validity" = "1" ]; then
    echo "Client cert valid for: 1 month"
  else
    echo "Client cert valid for: $client_validity months"
  fi
  if [ "$mobike_support" = "1" ]; then
    if [ "$mobike_enable" = "1" ]; then
      echo "MOBIKE support: Enable"
    else
      echo "MOBIKE support: Disable"
    fi
  else
    echo "MOBIKE support: Not available"
  fi
cat <<EOF
DNS server(s): $dns_servers

======================================

EOF
  confirm_or_abort "Do you want to continue? [y/N] "
}

create_client_cert() {
  bigecho2 "Generating client certificate..."
  sleep 1
  certutil -z <(head -c 1024 /dev/urandom) \
    -S -c "IKEv2 VPN CA" -n "$client_name" \
    -s "O=IKEv2 VPN,CN=$client_name" \
    -k rsa -g 3072 -v "$client_validity" \
    -d sql:/etc/ipsec.d -t ",," \
    --keyUsage digitalSignature,keyEncipherment \
    --extKeyUsage serverAuth,clientAuth -8 "$client_name" >/dev/null 2>&1 || exiterr "Failed to create client certificate."
}

create_p12_password() {
  config_file="/etc/ipsec.d/.vpnconfig"
  if grep -qs '^IKEV2_CONFIG_PASSWORD=.\+' "$config_file"; then
    . "$config_file"
    p12_password="$IKEV2_CONFIG_PASSWORD"
  else
    p12_password=$(LC_CTYPE=C tr -dc 'A-HJ-NPR-Za-km-z2-9' </dev/urandom 2>/dev/null | head -c 18)
    [ -z "$p12_password" ] && exiterr "Could not generate a random password for .p12 file."
    mkdir -p /etc/ipsec.d
    printf '%s\n' "IKEV2_CONFIG_PASSWORD='$p12_password'" >> "$config_file"
    chmod 600 "$config_file"
  fi
}

export_p12_file() {
  bigecho2 "Creating client configuration..."
  create_p12_password
  p12_file="$export_dir$client_name.p12"
  pk12util -W "$p12_password" -d sql:/etc/ipsec.d -n "$client_name" -o "$p12_file" >/dev/null || exit 1
  if [ "$os_type" = "alpine" ]; then
    pem_file="$export_dir$client_name.temp.pem"
    openssl pkcs12 -in "$p12_file" -out "$pem_file" -passin "pass:$p12_password" -passout "pass:$p12_password" || exit 1
    openssl pkcs12 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -export -in "$pem_file" -out "$p12_file" \
      -name "$client_name" -passin "pass:$p12_password" -passout "pass:$p12_password" || exit 1
    /bin/rm -f "$pem_file"
  fi
  if [ "$export_to_home_dir" = "1" ]; then
    chown "$SUDO_USER:$SUDO_USER" "$p12_file"
  fi
  chmod 600 "$p12_file"
}

install_base64_uuidgen() {
  if ! command -v base64 >/dev/null 2>&1 || ! command -v uuidgen >/dev/null 2>&1; then
    bigecho2 "Installing required packages..."
    if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] || [ "$os_type" = "raspbian" ]; then
      export DEBIAN_FRONTEND=noninteractive
      apt-get -yqq update || exiterr "'apt-get update' failed."
    fi
  fi
  if ! command -v base64 >/dev/null 2>&1; then
    if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] || [ "$os_type" = "raspbian" ]; then
      apt-get -yqq install coreutils >/dev/null || exiterr "'apt-get install' failed."
    else
      yum -y -q install coreutils >/dev/null || exiterr "'yum install' failed."
    fi
  fi
  if ! command -v uuidgen >/dev/null 2>&1; then
    if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] || [ "$os_type" = "raspbian" ]; then
      apt-get -yqq install uuid-runtime >/dev/null || exiterr "'apt-get install' failed."
    else
      yum -y -q install util-linux >/dev/null || exiterr "'yum install' failed."
    fi
  fi
}

install_uuidgen() {
  if ! command -v uuidgen >/dev/null 2>&1; then
    bigecho2 "Installing required packages..."
    apk add -U -q uuidgen || exiterr "'apk add' failed."
  fi
}

create_mobileconfig() {
  [ -z "$server_addr" ] && get_server_address
  p12_base64=$(base64 -w 52 "$export_dir$client_name.p12")
  [ -z "$p12_base64" ] && exiterr "Could not encode .p12 file."
  ca_base64=$(certutil -L -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" -a | grep -v CERTIFICATE)
  [ -z "$ca_base64" ] && exiterr "Could not encode IKEv2 VPN CA certificate."
  uuid1=$(uuidgen)
  [ -z "$uuid1" ] && exiterr "Could not generate UUID value."
  mc_file="$export_dir$client_name.mobileconfig"
cat > "$mc_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>IKEv2</key>
      <dict>
        <key>AuthenticationMethod</key>
        <string>Certificate</string>
        <key>ChildSecurityAssociationParameters</key>
        <dict>
          <key>DiffieHellmanGroup</key>
          <integer>14</integer>
          <key>EncryptionAlgorithm</key>
          <string>AES-128-GCM</string>
          <key>LifeTimeInMinutes</key>
          <integer>1410</integer>
        </dict>
        <key>DeadPeerDetectionRate</key>
        <string>Medium</string>
        <key>DisableRedirect</key>
        <true/>
        <key>EnableCertificateRevocationCheck</key>
        <integer>0</integer>
        <key>EnablePFS</key>
        <integer>0</integer>
        <key>IKESecurityAssociationParameters</key>
        <dict>
          <key>DiffieHellmanGroup</key>
          <integer>14</integer>
          <key>EncryptionAlgorithm</key>
          <string>AES-256</string>
          <key>IntegrityAlgorithm</key>
          <string>SHA2-256</string>
          <key>LifeTimeInMinutes</key>
          <integer>1410</integer>
        </dict>
        <key>LocalIdentifier</key>
        <string>$client_name</string>
        <key>PayloadCertificateUUID</key>
        <string>$uuid1</string>
        <key>OnDemandEnabled</key>
        <integer>0</integer>
        <key>OnDemandRules</key>
        <array>
          <dict>
          <key>Action</key>
          <string>Connect</string>
          </dict>
        </array>
        <key>RemoteAddress</key>
        <string>$server_addr</string>
        <key>RemoteIdentifier</key>
        <string>$server_addr</string>
        <key>UseConfigurationAttributeInternalIPSubnet</key>
        <integer>0</integer>
      </dict>
      <key>IPv4</key>
      <dict>
        <key>OverridePrimary</key>
        <integer>1</integer>
      </dict>
      <key>PayloadDescription</key>
      <string>Configures VPN settings</string>
      <key>PayloadDisplayName</key>
      <string>VPN</string>
      <key>PayloadOrganization</key>
      <string>IKEv2 VPN</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.vpn.managed.$(uuidgen)</string>
      <key>PayloadType</key>
      <string>com.apple.vpn.managed</string>
      <key>PayloadUUID</key>
      <string>$(uuidgen)</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>Proxies</key>
      <dict>
        <key>HTTPEnable</key>
        <integer>0</integer>
        <key>HTTPSEnable</key>
        <integer>0</integer>
      </dict>
      <key>UserDefinedName</key>
      <string>$server_addr</string>
      <key>VPNType</key>
      <string>IKEv2</string>
    </dict>
    <dict>
      <key>PayloadCertificateFileName</key>
      <string>$client_name</string>
      <key>PayloadContent</key>
      <data>
$p12_base64
      </data>
      <key>PayloadDescription</key>
      <string>Adds a PKCS#12-formatted certificate</string>
      <key>PayloadDisplayName</key>
      <string>$client_name</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.security.pkcs12.$(uuidgen)</string>
      <key>PayloadType</key>
      <string>com.apple.security.pkcs12</string>
      <key>PayloadUUID</key>
      <string>$uuid1</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
    <dict>
      <key>PayloadContent</key>
      <data>
$ca_base64
      </data>
      <key>PayloadCertificateFileName</key>
      <string>ikev2vpnca</string>
      <key>PayloadDescription</key>
      <string>Adds a CA root certificate</string>
      <key>PayloadDisplayName</key>
      <string>Certificate Authority (CA)</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.security.root.$(uuidgen)</string>
      <key>PayloadType</key>
      <string>com.apple.security.root</string>
      <key>PayloadUUID</key>
      <string>$(uuidgen)</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
  </array>
  <key>PayloadDisplayName</key>
  <string>IKEv2 VPN ($server_addr)</string>
  <key>PayloadIdentifier</key>
  <string>com.apple.vpn.managed.$(uuidgen)</string>
  <key>PayloadRemovalDisallowed</key>
  <false/>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>$(uuidgen)</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
</dict>
</plist>
EOF
  if [ "$export_to_home_dir" = "1" ]; then
    chown "$SUDO_USER:$SUDO_USER" "$mc_file"
  fi
  chmod 600 "$mc_file"
}

create_android_profile() {
  [ -z "$server_addr" ] && get_server_address
  p12_base64_oneline=$(base64 -w 52 "$export_dir$client_name.p12" | sed 's/$/\\n/' | tr -d '\n')
  [ -z "$p12_base64_oneline" ] && exiterr "Could not encode .p12 file."
  uuid2=$(uuidgen)
  [ -z "$uuid2" ] && exiterr "Could not generate UUID value."
  sswan_file="$export_dir$client_name.sswan"
cat > "$sswan_file" <<EOF
{
  "uuid": "$uuid2",
  "name": "IKEv2 VPN ($server_addr)",
  "type": "ikev2-cert",
  "remote": {
    "addr": "$server_addr"
  },
  "local": {
    "p12": "$p12_base64_oneline",
    "rsa-pss": "true"
  },
  "ike-proposal": "aes256-sha256-modp2048",
  "esp-proposal": "aes128gcm16"
}
EOF
  if [ "$export_to_home_dir" = "1" ]; then
    chown "$SUDO_USER:$SUDO_USER" "$sswan_file"
  fi
  chmod 600 "$sswan_file"
}

export_client_config() {
  if [ "$os_type" != "alpine" ]; then
    install_base64_uuidgen
  else
    install_uuidgen
  fi
  export_p12_file
  create_mobileconfig
  create_android_profile
}

create_ca_server_certs() {
  bigecho2 "Generating CA and server certificates..."
  certutil -z <(head -c 1024 /dev/urandom) \
    -S -x -n "IKEv2 VPN CA" \
    -s "O=IKEv2 VPN,CN=IKEv2 VPN CA" \
    -k rsa -g 3072 -v 120 \
    -d sql:/etc/ipsec.d -t "CT,," -2 >/dev/null 2>&1 <<ANSWERS || exiterr "Failed to create CA certificate."
y

N
ANSWERS
  sleep 1
  if [ "$use_dns_name" = "1" ]; then
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
}

add_ikev2_connection() {
  bigecho2 "Adding a new IKEv2 connection..."
  if ! grep -qs '^include /etc/ipsec\.d/\*\.conf$' /etc/ipsec.conf; then
    echo >> /etc/ipsec.conf
    echo 'include /etc/ipsec.d/*.conf' >> /etc/ipsec.conf
  fi
cat > /etc/ipsec.d/ikev2.conf <<EOF

conn ikev2-cp
  left=%defaultroute
  leftcert=$server_addr
  leftsendcert=always
  leftsubnet=0.0.0.0/0
  leftrsasigkey=%cert
  right=%any
  rightid=%fromcert
  rightaddresspool=192.168.43.10-192.168.43.250
  rightca=%same
  rightrsasigkey=%cert
  narrowing=yes
  dpddelay=30
  dpdtimeout=120
  dpdaction=clear
  auto=add
  ikev2=insist
  rekey=no
  pfs=no
  ike=aes256-sha2,aes128-sha2,aes256-sha1,aes128-sha1
  phase2alg=aes_gcm-null,aes128-sha1,aes256-sha1,aes128-sha2,aes256-sha2
  ikelifetime=24h
  salifetime=24h
  encapsulation=yes
EOF
  if [ "$use_dns_name" = "1" ]; then
cat >> /etc/ipsec.d/ikev2.conf <<EOF
  leftid=@$server_addr
EOF
  else
cat >> /etc/ipsec.d/ikev2.conf <<EOF
  leftid=$server_addr
EOF
  fi
  if [ -n "$dns_server_2" ]; then
cat >> /etc/ipsec.d/ikev2.conf <<EOF
  modecfgdns="$dns_servers"
EOF
  else
cat >> /etc/ipsec.d/ikev2.conf <<EOF
  modecfgdns=$dns_server_1
EOF
  fi
  if [ "$mobike_enable" = "1" ]; then
    echo "  mobike=yes" >> /etc/ipsec.d/ikev2.conf
  else
    echo "  mobike=no" >> /etc/ipsec.d/ikev2.conf
  fi
}

start_setup() {
  # shellcheck disable=SC2154
  trap 'dlo=$dl;dl=$LINENO' DEBUG 2>/dev/null
  trap 'finish $? $((dlo+1))' EXIT
}

apply_ubuntu1804_nss_fix() {
  if [ "$os_type" = "ubuntu" ] && [ "$os_ver" = "bustersid" ] && [ "$os_arch" = "x86_64" ]; then
    nss_url1="https://mirrors.kernel.org/ubuntu/pool/main/n/nss"
    nss_url2="https://mirrors.kernel.org/ubuntu/pool/universe/n/nss"
    nss_deb1="libnss3_3.49.1-1ubuntu1.5_amd64.deb"
    nss_deb2="libnss3-dev_3.49.1-1ubuntu1.5_amd64.deb"
    nss_deb3="libnss3-tools_3.49.1-1ubuntu1.5_amd64.deb"
    if tmpdir=$(mktemp --tmpdir -d vpn.XXXXX 2>/dev/null); then
      bigecho2 "Applying fix for NSS bug on Ubuntu 18.04..."
      export DEBIAN_FRONTEND=noninteractive
      if wget -t 3 -T 30 -q -O "$tmpdir/1.deb" "$nss_url1/$nss_deb1" \
        && wget -t 3 -T 30 -q -O "$tmpdir/2.deb" "$nss_url1/$nss_deb2" \
        && wget -t 3 -T 30 -q -O "$tmpdir/3.deb" "$nss_url2/$nss_deb3"; then
        apt-get -yqq update
        apt-get -yqq install "$tmpdir/1.deb" "$tmpdir/2.deb" "$tmpdir/3.deb" >/dev/null
      fi
      /bin/rm -f "$tmpdir/1.deb" "$tmpdir/2.deb" "$tmpdir/3.deb"
      /bin/rmdir "$tmpdir"
    fi
  fi
}

restart_ipsec_service() {
  if [ "$in_container" = "0" ] || { [ "$in_container" = "1" ] && service ipsec status >/dev/null 2>&1; } then
    bigecho2 "Restarting IPsec service..."
    mkdir -p /run/pluto
    service ipsec restart 2>/dev/null
  fi
}

create_crl() {
  if ! crlutil -L -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" >/dev/null 2>&1; then
    crlutil -G -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" -c /dev/null >/dev/null
  fi
  sleep 2
}

add_client_cert_to_crl() {
  sn_txt=$(certutil -L -d sql:/etc/ipsec.d -n "$client_name" | grep -A 1 'Serial Number' | tail -n 1)
  sn_hex=$(printf '%s' "$sn_txt" | sed -e 's/^ *//' -e 's/://g')
  sn_dec=$((16#$sn_hex))
  [ -z "$sn_dec" ] && exiterr "Could not find serial number of client certificate."
crlutil -M -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" >/dev/null <<EOF || exiterr "Failed to add client certificate to CRL."
addcert $sn_dec $(date -u +%Y%m%d%H%M%SZ)
EOF
}

reload_crls() {
  ipsec crls
}

print_client_added() {
cat <<EOF


================================================

New IKEv2 VPN client "$client_name" added!

EOF
  print_server_client_info
}

print_client_exported() {
cat <<EOF


================================================

IKEv2 VPN client "$client_name" exported!

EOF
  print_server_client_info
}

print_client_revoked() {
  echo "Certificate '$client_name' revoked!"
}

print_setup_complete() {
  if [ -n "$VPN_DNS_NAME" ] || [ -n "$VPN_CLIENT_NAME" ] || [ -n "$VPN_DNS_SRV1" ]; then
    printf '\e[2K\r'
  else
    printf '\e[2K\e[1A\e[2K\r'
    [ "$use_defaults" = "1" ] && printf '\e[1A\e[2K\e[1A\e[2K\e[1A\e[2K\r'
  fi
cat <<EOF
================================================

IKEv2 setup successful. Details for IKEv2 mode:

EOF
  print_server_client_info
}

print_client_info() {
  if [ "$in_container" = "0" ]; then
cat <<'EOF'
Client configuration is available at:
EOF
  else
cat <<'EOF'
Client configuration is available inside the
Docker container at:
EOF
  fi
cat <<EOF
$export_dir$client_name.p12 (for Windows & Linux)
$export_dir$client_name.sswan (for Android)
$export_dir$client_name.mobileconfig (for iOS & macOS)

*IMPORTANT* Password for client config files:
$p12_password
Write this down, you'll need it for import!
EOF
cat <<'EOF'

Next steps: Configure IKEv2 VPN clients. See:
https://git.io/ikev2clients

================================================

EOF
}

check_ipsec_conf() {
  if grep -qs "conn ikev2-cp" /etc/ipsec.conf; then
cat 1>&2 <<'EOF'
Error: IKEv2 configuration section found in /etc/ipsec.conf.
       This script cannot automatically remove IKEv2 from this server.
       To manually remove IKEv2, see https://git.io/ikev2
EOF
    abort_and_exit
  fi
}

confirm_revoke_cert() {
cat <<EOF
WARNING: You have selected to revoke IKEv2 client certificate '$client_name'.
         After revocation, this certificate *cannot* be used by VPN client(s)
         to connect to this VPN server.

EOF
  confirm_or_abort "Are you sure you want to revoke '$client_name'? [y/N] "
}

confirm_remove_ikev2() {
cat <<'EOF'
WARNING: This option will remove IKEv2 from this VPN server, but keep the IPsec/L2TP
         and IPsec/XAuth ("Cisco IPsec") modes, if installed. All IKEv2 configuration
         including certificates and keys will be *permanently deleted*.
         This *cannot* be undone!

EOF
  confirm_or_abort "Are you sure you want to remove IKEv2? [y/N] "
}

delete_ikev2_conf() {
  bigecho "Deleting /etc/ipsec.d/ikev2.conf..."
  /bin/rm -f /etc/ipsec.d/ikev2.conf
}

delete_certificates() {
  echo
  bigecho "Deleting certificates and keys from the IPsec database..."
  certutil -L -d sql:/etc/ipsec.d | grep -v -e '^$' -e 'IKEv2 VPN CA' | tail -n +3 | cut -f1 -d ' ' | while read -r line; do
    certutil -F -d sql:/etc/ipsec.d -n "$line"
    certutil -D -d sql:/etc/ipsec.d -n "$line" 2>/dev/null
  done
  crlutil -D -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" 2>/dev/null
  certutil -F -d sql:/etc/ipsec.d -n "IKEv2 VPN CA"
  certutil -D -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" 2>/dev/null
  config_file="/etc/ipsec.d/.vpnconfig"
  if grep -qs '^IKEV2_CONFIG_PASSWORD=.\+' "$config_file"; then
    sed -i '/IKEV2_CONFIG_PASSWORD=/d' "$config_file"
  fi
}

print_ikev2_removed() {
  echo
  echo "IKEv2 removed!"
}

ikev2setup() {
  check_root
  check_container
  check_os
  check_libreswan
  check_utils_exist

  use_defaults=0
  add_client=0
  export_client=0
  list_clients=0
  revoke_client=0
  remove_ikev2=0
  while [ "$#" -gt 0 ]; do
    case $1 in
      --auto)
        use_defaults=1
        shift
        ;;
      --addclient)
        add_client=1
        client_name="$2"
        shift
        shift
        ;;
      --exportclient)
        export_client=1
        client_name="$2"
        shift
        shift
        ;;
      --listclients)
        list_clients=1
        shift
        ;;
      --revokeclient)
        revoke_client=1
        client_name="$2"
        shift
        shift
        ;;
      --removeikev2)
        remove_ikev2=1
        shift
        ;;
      -h|--help)
        show_usage
        ;;
      *)
        show_usage "Unknown parameter: $1"
        ;;
    esac
  done

  check_arguments
  get_export_dir

  if [ "$add_client" = "1" ]; then
    show_header
    show_add_client
    client_validity=120
    create_client_cert
    export_client_config
    print_client_added
    print_client_info
    exit 0
  fi

  if [ "$export_client" = "1" ]; then
    show_header
    show_export_client
    export_client_config
    print_client_exported
    print_client_info
    exit 0
  fi

  if [ "$list_clients" = "1" ]; then
    show_header
    list_existing_clients
    exit 0
  fi

  if [ "$revoke_client" = "1" ]; then
    show_header
    confirm_revoke_cert
    create_crl
    add_client_cert_to_crl
    reload_crls
    print_client_revoked
    exit 0
  fi

  if [ "$remove_ikev2" = "1" ]; then
    check_ipsec_conf
    show_header
    confirm_remove_ikev2
    delete_ikev2_conf
    if [ "$os_type" = "alpine" ]; then
      ipsec auto --delete ikev2-cp
    else
      restart_ipsec_service
    fi
    delete_certificates
    print_ikev2_removed
    exit 0
  fi

  if check_ikev2_exists; then
    show_header
    select_menu_option
    case $selected_option in
      1)
        enter_client_name
        enter_client_cert_validity
        echo
        create_client_cert
        export_client_config
        print_client_added
        print_client_info
        exit 0
        ;;
      2)
        enter_client_name_for export
        echo
        export_client_config
        print_client_exported
        print_client_info
        exit 0
        ;;
      3)
        echo
        list_existing_clients
        exit 0
        ;;
      4)
        enter_client_name_for revoke
        echo
        confirm_revoke_cert
        create_crl
        add_client_cert_to_crl
        reload_crls
        print_client_revoked
        exit 0
        ;;
      5)
        check_ipsec_conf
        echo
        confirm_remove_ikev2
        delete_ikev2_conf
        if [ "$os_type" = "alpine" ]; then
          ipsec auto --delete ikev2-cp
        else
          restart_ipsec_service
        fi
        delete_certificates
        print_ikev2_removed
        exit 0
        ;;
      *)
        exit 0
        ;;
    esac
  fi

  check_cert_exists_and_exit "IKEv2 VPN CA"

  if [ "$use_defaults" = "0" ]; then
    show_header
    show_welcome
    enter_server_address
    check_cert_exists_and_exit "$server_addr"
    enter_client_name_with_defaults
    enter_client_cert_validity
    enter_custom_dns
    check_mobike_support
    select_mobike
    confirm_setup_options
  else
    check_server_dns_name
    check_custom_dns
    if [ -n "$VPN_CLIENT_NAME" ]; then
      client_name="$VPN_CLIENT_NAME"
      check_client_name "$client_name" \
        || exiterr "Invalid client name. Use one word only, no special characters except '-' and '_'."
    else
      client_name=vpnclient
    fi
    check_cert_exists "$client_name" && exiterr "Client '$client_name' already exists."
    client_validity=120
    show_header
    show_start_setup
    if [ -n "$VPN_DNS_NAME" ]; then
      use_dns_name=1
      server_addr="$VPN_DNS_NAME"
    else
      use_dns_name=0
      get_server_ip
      check_ip "$public_ip" || exiterr "Cannot detect this server's public IP."
      server_addr="$public_ip"
    fi
    check_cert_exists_and_exit "$server_addr"
    if [ -n "$VPN_DNS_SRV1" ] && [ -n "$VPN_DNS_SRV2" ]; then
      dns_server_1="$VPN_DNS_SRV1"
      dns_server_2="$VPN_DNS_SRV2"
      dns_servers="$VPN_DNS_SRV1 $VPN_DNS_SRV2"
    elif [ -n "$VPN_DNS_SRV1" ]; then
      dns_server_1="$VPN_DNS_SRV1"
      dns_server_2=""
      dns_servers="$VPN_DNS_SRV1"
    else
      dns_server_1=8.8.8.8
      dns_server_2=8.8.4.4
      dns_servers="8.8.8.8 8.8.4.4"
    fi
    check_mobike_support
    mobike_enable="$mobike_support"
  fi

  start_setup
  apply_ubuntu1804_nss_fix
  create_ca_server_certs
  create_client_cert
  export_client_config
  add_ikev2_connection
  if [ "$os_type" = "alpine" ]; then
    ipsec auto --add ikev2-cp >/dev/null
  else
    restart_ipsec_service
  fi
  print_setup_complete
  print_client_info
}

## Defer setup until we have the complete script
ikev2setup "$@"

exit 0
