#!/bin/bash
#
# Script to set up and manage IKEv2 on Ubuntu, Debian, CentOS/RHEL, Rocky Linux,
# AlmaLinux, Oracle Linux, Amazon Linux 2 and Alpine Linux
#
# DO NOT RUN THIS SCRIPT ON YOUR PC OR MAC!
#
# The latest version of this script is available at:
# https://github.com/hwdsl2/setup-ipsec-vpn
#
# Copyright (C) 2020-2024 Lin Song <linsongui@gmail.com>
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

check_container() {
  in_container=0
  if grep -qs "hwdsl2" /opt/src/run.sh; then
    in_container=1
  fi
}

check_os() {
  rh_file="/etc/redhat-release"
  if [ -f "$rh_file" ]; then
    os_type=centos
    if grep -q "Red Hat" "$rh_file"; then
      os_type=rhel
    fi
    [ -f /etc/oracle-release ] && os_type=ol
    grep -qi rocky "$rh_file" && os_type=rocky
    grep -qi alma "$rh_file" && os_type=alma
    if grep -q "release 7" "$rh_file"; then
      os_ver=7
    elif grep -q "release 8" "$rh_file"; then
      os_ver=8
      grep -qi stream "$rh_file" && os_ver=8s
    elif grep -q "release 9" "$rh_file"; then
      os_ver=9
      grep -qi stream "$rh_file" && os_ver=9s
    else
      exiterr "This script only supports CentOS/RHEL 7-9."
    fi
    if [ "$os_type" = "centos" ] \
      && { [ "$os_ver" = 7 ] || [ "$os_ver" = 8 ] || [ "$os_ver" = 8s ]; }; then
      exiterr "CentOS Linux $os_ver is EOL and not supported."
    fi
  elif grep -qs "Amazon Linux release 2 " /etc/system-release; then
    os_type=amzn
    os_ver=2
  else
    os_type=$(lsb_release -si 2>/dev/null)
    [ -z "$os_type" ] && [ -f /etc/os-release ] && os_type=$(. /etc/os-release && printf '%s' "$ID")
    case $os_type in
      [Uu]buntu)
        os_type=ubuntu
        ;;
      [Dd]ebian|[Kk]ali)
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
       Ubuntu, Debian, CentOS/RHEL, Rocky Linux, AlmaLinux,
       Oracle Linux, Amazon Linux 2 or Alpine Linux
EOF
        exit 1
        ;;
    esac
    if [ "$os_type" = "alpine" ]; then
      os_ver=$(. /etc/os-release && printf '%s' "$VERSION_ID" | cut -d '.' -f 1,2)
      if [ "$os_ver" != "3.19" ] && [ "$os_ver" != "3.20" ]; then
        exiterr "This script only supports Alpine Linux 3.19/3.20."
      fi
    else
      os_ver=$(sed 's/\..*//' /etc/debian_version | tr -dc 'A-Za-z0-9')
      if [ "$os_ver" = 8 ] || [ "$os_ver" = 9 ] || [ "$os_ver" = "jessiesid" ] \
        || [ "$os_ver" = "bustersid" ]; then
cat 1>&2 <<EOF
Error: This script requires Debian >= 10 or Ubuntu >= 20.04.
       This version of Ubuntu/Debian is too old and not supported.
EOF
        exit 1
      fi
    fi
  fi
}

check_libreswan() {
  ipsec_ver=$(ipsec --version 2>/dev/null)
  if ( ! grep -qs "hwdsl2 VPN script" /etc/sysctl.conf && ! grep -qs "hwdsl2" /opt/src/run.sh ) \
    || ! printf '%s' "$ipsec_ver" | grep -qi 'libreswan'; then
cat 1>&2 <<'EOF'
Error: Your must first set up the IPsec VPN server before setting up IKEv2.
       See: https://github.com/hwdsl2/setup-ipsec-vpn
EOF
    exit 1
  fi
}

check_swan_ver() {
  swan_ver=$(printf '%s' "$ipsec_ver" | sed -e 's/.*Libreswan U\?//' -e 's/\( (\|\/K\).*//')
  if ! printf '%s\n%s' "3.23" "$swan_ver" | sort -C -V; then
cat 1>&2 <<EOF
Error: Libreswan version '$swan_ver' is not supported.
       This script requires Libreswan 3.23 or newer.
       To update Libreswan, run:
       wget https://get.vpnsetup.net/upg -O vpnup.sh && sudo sh vpnup.sh
EOF
    exit 1
  fi
}

check_utils_exist() {
  command -v certutil >/dev/null 2>&1 || exiterr "'certutil' not found. Abort."
  command -v crlutil >/dev/null 2>&1 || exiterr "'crlutil' not found. Abort."
  command -v pk12util >/dev/null 2>&1 || exiterr "'pk12util' not found. Abort."
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

show_header() {
cat <<'EOF'

IKEv2 Script   Copyright (c) 2020-2024 Lin Song   28 Jul 2024

EOF
}

show_usage() {
  if [ -n "$1" ]; then
    echo "Error: $1" >&2
  fi
  show_header
cat 1>&2 <<EOF
Usage: bash $0 [options]

Options:
  --auto                        run IKEv2 setup in auto mode using default options (for initial setup only)
  --addclient [client name]     add a new client using default options
  --exportclient [client name]  export configuration for an existing client
  --listclients                 list the names of existing clients
  --revokeclient [client name]  revoke an existing client
  --deleteclient [client name]  delete an existing client
  --removeikev2                 remove IKEv2 and delete all certificates and keys from the IPsec database
  -y, --yes                     assume "yes" as answer to prompts when revoking/deleting a client or removing IKEv2
  -h, --help                    show this help message and exit

To customize IKEv2 or client options, run this script without arguments.
For documentation, see: https://vpnsetup.net/ikev2
EOF
  exit 1
}

check_ikev2_exists() {
  grep -qs "conn ikev2-cp" "$IPSEC_CONF" || [ -f "$IKEV2_CONF" ]
}

check_client_name() {
  ! { [ "${#1}" -gt "64" ] || printf '%s' "$1" | LC_ALL=C grep -q '[^A-Za-z0-9_-]\+' \
    || case $1 in -*) true ;; *) false ;; esac; }
}

check_cert_exists() {
  certutil -L -d "$CERT_DB" -n "$1" >/dev/null 2>&1
}

check_cert_exists_and_exit() {
  if certutil -L -d "$CERT_DB" -n "$1" >/dev/null 2>&1; then
    echo "Error: Certificate '$1' already exists." >&2
    abort_and_exit
  fi
}

check_cert_status() {
  cert_status=$(certutil -V -u C -d "$CERT_DB" -n "$1")
}

check_arguments() {
  if [ "$use_defaults" = 1 ] && check_ikev2_exists; then
    echo "Error: Invalid parameter '--auto'. IKEv2 is already set up on this server." >&2
    echo "       To manage VPN clients, re-run this script without '--auto'." >&2
    echo "       To change IKEv2 server address, see https://vpnsetup.net/ikev2" >&2
    exit 1
  fi
  if [ "$((add_client + export_client + list_clients + revoke_client + delete_client))" -gt 1 ]; then
    show_usage "Invalid parameters. Specify only one of '--addclient', '--exportclient', '--listclients', '--revokeclient' or '--deleteclient'."
  fi
  if [ "$remove_ikev2" = 1 ]; then
    if [ "$((add_client + export_client + list_clients + revoke_client + delete_client + use_defaults))" -gt 0 ]; then
      show_usage "Invalid parameters. '--removeikev2' cannot be specified with other parameters."
    fi
  fi
  if ! check_ikev2_exists; then
    [ "$add_client" = 1 ] && exiterr "You must first set up IKEv2 before adding a client."
    [ "$export_client" = 1 ] && exiterr "You must first set up IKEv2 before exporting a client."
    [ "$list_clients" = 1 ] && exiterr "You must first set up IKEv2 before listing clients."
    [ "$revoke_client" = 1 ] && exiterr "You must first set up IKEv2 before revoking a client."
    [ "$delete_client" = 1 ] && exiterr "You must first set up IKEv2 before deleting a client."
    [ "$remove_ikev2" = 1 ] && exiterr "Cannot remove IKEv2 because it has not been set up on this server."
  fi
  if [ "$add_client" = 1 ]; then
    if [ -z "$client_name" ] || ! check_client_name "$client_name"; then
      exiterr "Invalid client name. Use one word only, no special characters except '-' and '_'."
    elif check_cert_exists "$client_name"; then
      exiterr "Invalid client name. Client '$client_name' already exists."
    fi
  fi
  if [ "$export_client" = 1 ] || [ "$revoke_client" = 1 ] || [ "$delete_client" = 1 ]; then
    get_server_address
    if [ -z "$client_name" ] || ! check_client_name "$client_name" \
      || [ "$client_name" = "$CA_NAME" ] || [ "$client_name" = "$server_addr" ] \
      || ! check_cert_exists "$client_name"; then
      exiterr "Invalid client name, or client does not exist."
    fi
    if [ "$delete_client" = 0 ] && ! check_cert_status "$client_name"; then
      printf '%s' "Error: Certificate '$client_name' " >&2
      if printf '%s' "$cert_status" | grep -q "revoked"; then
        if [ "$revoke_client" = 1 ]; then
          echo "has already been revoked." >&2
        else
          echo "has been revoked." >&2
        fi
      elif printf '%s' "$cert_status" | grep -q "expired"; then
        echo "has expired." >&2
      else
        echo "is invalid." >&2
      fi
      exit 1
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
    || { [ -n "$VPN_DNS_SRV2" ] && ! check_ip "$VPN_DNS_SRV2"; }; then
    exiterr "Invalid DNS server(s)."
  fi
}

check_client_validity() {
  ! { printf '%s' "$1" | LC_ALL=C grep -q '[^0-9]\+' || [ "$1" -lt "1" ] \
  || [ "$1" -gt "120" ] || [ "$1" != "$((10#$1))" ]; }
}

check_and_set_client_name() {
  if [ -n "$VPN_CLIENT_NAME" ]; then
    client_name="$VPN_CLIENT_NAME"
    check_client_name "$client_name" \
      || exiterr "Invalid client name. Use one word only, no special characters except '-' and '_'."
  else
    client_name=vpnclient
  fi
  check_cert_exists "$client_name" && exiterr "Client '$client_name' already exists."
}

check_and_set_client_validity() {
  if [ -n "$VPN_CLIENT_VALIDITY" ]; then
    client_validity="$VPN_CLIENT_VALIDITY"
    if ! check_client_validity "$client_validity"; then
cat <<EOF
WARNING: Invalid client cert validity period. Must be an integer between 1 and 120.
         Falling back to default validity (120 months).
EOF
      VPN_CLIENT_VALIDITY=""
      client_validity=120
    fi
  else
    client_validity=120
  fi
}

set_server_address() {
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
}

set_dns_servers() {
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
}

show_welcome() {
cat <<'EOF'
Welcome! Use this script to set up IKEv2 on your VPN server.

I need to ask you a few questions before starting setup.
You can use the default options and just press enter if you are OK with them.

EOF
}

show_start_setup() {
  op_text=default
  if [ -n "$VPN_DNS_NAME" ] || [ -n "$VPN_CLIENT_NAME" ] \
    || [ -n "$VPN_DNS_SRV1" ] || [ -n "$VPN_PROTECT_CONFIG" ] \
    || [ -n "$VPN_CLIENT_VALIDITY" ]; then
    op_text=custom
  fi
  bigecho "Starting IKEv2 setup in auto mode, using $op_text options."
}

show_add_client() {
  op_text=default
  if [ -n "$VPN_CLIENT_VALIDITY" ]; then
    op_text=custom
  fi
  bigecho "Adding a new IKEv2 client '$client_name', using $op_text options."
}

show_export_client() {
  bigecho "Exporting IKEv2 client '$client_name'."
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
  bigecho2 "Trying to auto discover IP of this server..."
  check_ip "$public_ip" || public_ip=$(dig @resolver1.opendns.com -t A -4 myip.opendns.com +short)
  check_ip "$public_ip" || public_ip=$(wget -t 2 -T 10 -qO- http://ipv4.icanhazip.com)
  check_ip "$public_ip" || public_ip=$(wget -t 2 -T 10 -qO- http://ip1.dynupdate.no-ip.com)
}

get_server_address() {
  server_addr=$(grep -s "leftcert=" "$IKEV2_CONF" | cut -f2 -d=)
  [ -z "$server_addr" ] && server_addr=$(grep -s "leftcert=" "$IPSEC_CONF" | cut -f2 -d=)
  check_ip "$server_addr" || check_dns_name "$server_addr" || exiterr "Could not get VPN server address."
}

list_existing_clients() {
  echo "Checking for existing IKEv2 client(s)..."
  echo
  client_names=$(certutil -L -d "$CERT_DB" | grep -v -e '^$' -e "$CA_NAME" -e '\.' | tail -n +3 | cut -f1 -d ' ')
  max_len=$(printf '%s\n' "$client_names" | wc -L 2>/dev/null)
  [[ $max_len =~ ^[0-9]+$ ]] || max_len=64
  [ "$max_len" -gt "64" ] && max_len=64
  [ "$max_len" -lt "16" ] && max_len=16
  printf "%-${max_len}s  %s\n" 'Client Name' 'Certificate Status'
  printf "%-${max_len}s  %s\n" '------------' '-------------------'
  if [ -n "$client_names" ]; then
    client_list=$(printf '%s\n' "$client_names" | LC_ALL=C sort)
    while IFS= read -r line; do
      printf "%-${max_len}s  " "$line"
      client_status=$(certutil -V -u C -d "$CERT_DB" -n "$line" | grep -o -e ' valid' -e expired -e revoked | sed -e 's/^ //')
      [ -z "$client_status" ] && client_status=unknown
      printf '%s\n' "$client_status"
    done <<< "$client_list"
  fi
  client_count=$(printf '%s\n' "$client_names" | wc -l 2>/dev/null)
  [ -z "$client_names" ] && client_count=0
  if [ "$client_count" = 1 ]; then
    printf '\n%s\n' "Total: 1 client"
  elif [ -n "$client_count" ]; then
    printf '\n%s\n' "Total: $client_count clients"
  fi
}

enter_server_address() {
  echo "Do you want IKEv2 clients to connect to this server using a DNS name,"
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
    [ "$use_default_ip" = 0 ] && { echo; echo; }
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
  echo "Provide a name for the IKEv2 client."
  echo "Use one word only, no special characters except '-' and '_'."
  if [ "$1" = "with_defaults" ]; then
    read -rp "Client name: [vpnclient] " client_name
    [ -z "$client_name" ] && client_name=vpnclient
  else
    read -rp "Client name: " client_name
    [ -z "$client_name" ] && abort_and_exit
  fi
  while ! check_client_name "$client_name" || check_cert_exists "$client_name"; do
    if ! check_client_name "$client_name"; then
      echo "Invalid client name."
    else
      echo "Invalid client name. Client '$client_name' already exists."
    fi
    if [ "$1" = "with_defaults" ]; then
      read -rp "Client name: [vpnclient] " client_name
      [ -z "$client_name" ] && client_name=vpnclient
    else
      read -rp "Client name: " client_name
      [ -z "$client_name" ] && abort_and_exit
    fi
  done
}

enter_client_name_for() {
  echo
  list_existing_clients
  if [ "$client_count" = 0 ]; then
    echo
    echo "No IKEv2 clients in the IPsec database. Nothing to $1." >&2
    exit 1
  fi
  get_server_address
  echo
  read -rp "Enter the name of the IKEv2 client to $1: " client_name
  [ -z "$client_name" ] && abort_and_exit
  while ! check_client_name "$client_name" || [ "$client_name" = "$CA_NAME" ] \
    || [ "$client_name" = "$server_addr" ] || ! check_cert_exists "$client_name" \
    || ! check_cert_status "$client_name"; do
    if ! check_client_name "$client_name" || [ "$client_name" = "$CA_NAME" ] \
    || [ "$client_name" = "$server_addr" ] || ! check_cert_exists "$client_name"; then
      echo "Invalid client name, or client does not exist."
    else
      [ "$1" = "delete" ] && break
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

enter_client_validity() {
  echo
  echo "Specify the validity period (in months) for this client certificate."
  read -rp "Enter an integer between 1 and 120: [120] " client_validity
  [ -z "$client_validity" ] && client_validity=120
  while ! check_client_validity "$client_validity"; do
    echo "Invalid validity period."
    read -rp "Enter an integer between 1 and 120: [120] " client_validity
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
  if [ "$use_custom_dns" = 1 ]; then
    read -rp "Enter primary DNS server: " dns_server_1
    until check_ip "$dns_server_1"; do
      echo "Invalid DNS server."
      read -rp "Enter primary DNS server: " dns_server_1
    done
    read -rp "Enter secondary DNS server (Enter to skip): " dns_server_2
    until [ -z "$dns_server_2" ] || check_ip "$dns_server_2"; do
      echo "Invalid DNS server."
      read -rp "Enter secondary DNS server (Enter to skip): " dns_server_2
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
  if [ "$in_container" = 0 ]; then
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
  if uname -a | grep -qi synology; then
    mobike_support=0
  fi
  if [ "$mobike_support" = 1 ]; then
    bigecho2 "Checking for MOBIKE support... available"
  else
    bigecho2 "Checking for MOBIKE support... not available"
  fi
}

select_mobike() {
  echo
  mobike_enable=0
  if [ "$mobike_support" = 1 ]; then
cat <<'EOF'

The MOBIKE IKEv2 extension allows VPN clients to change network attachment points,
e.g. switch between mobile data and Wi-Fi and keep the IPsec tunnel up on the new IP.

EOF
    printf "Enable MOBIKE support? [Y/n] "
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

check_config_password() {
  use_config_password=0
  case $VPN_PROTECT_CONFIG in
    [yY][eE][sS])
      use_config_password=1
      ;;
    *)
      if grep -qs '^IKEV2_CONFIG_PASSWORD=.\+' "$CONF_FILE"; then
        use_config_password=1
      fi
      ;;
  esac
}

select_config_password() {
  if [ "$use_config_password" = 0 ]; then
cat <<'EOF'

IKEv2 client config files contain the client certificate, private key and CA certificate.
This script can optionally generate a random password to protect these files.

EOF
    printf "Protect client config files using a password? [y/N] "
    read -r response
    case $response in
      [yY][eE][sS]|[yY])
        use_config_password=1
        ;;
      *)
        use_config_password=0
        ;;
    esac
  fi
}

select_menu_option() {
cat <<'EOF'
IKEv2 is already set up on this server.

Select an option:
  1) Add a new client
  2) Export config for an existing client
  3) List existing clients
  4) Revoke an existing client
  5) Delete an existing client
  6) Remove IKEv2
  7) Exit
EOF
  read -rp "Option: " selected_option
  until [[ "$selected_option" =~ ^[1-7]$ ]]; do
    printf '%s\n' "$selected_option: invalid selection."
    read -rp "Option: " selected_option
  done
}

print_server_info() {
cat <<EOF
VPN server address: $server_addr

EOF
}

confirm_setup_options() {
cat <<EOF

We are ready to set up IKEv2 now. Below are the setup options you selected.

======================================

Server address: $server_addr
Client name: $client_name

EOF
  if [ "$client_validity" = 1 ]; then
    echo "Client cert valid for: 1 month"
  else
    echo "Client cert valid for: $client_validity months"
  fi
  if [ "$mobike_support" = 1 ]; then
    if [ "$mobike_enable" = 1 ]; then
      echo "MOBIKE support: Enable"
    else
      echo "MOBIKE support: Disable"
    fi
  else
    echo "MOBIKE support: Not available"
  fi
  if [ "$use_config_password" = 1 ]; then
    echo "Protect client config: Yes"
  else
    echo "Protect client config: No"
  fi
cat <<EOF
DNS server(s): $dns_servers

======================================

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

create_client_cert() {
  bigecho2 "Generating client certificate..."
  sleep 1
  certutil -z <(head -c 1024 /dev/urandom) \
    -S -c "$CA_NAME" -n "$client_name" \
    -s "O=IKEv2 VPN,CN=$client_name" \
    -k rsa -g 3072 -v "$client_validity" \
    -d "$CERT_DB" -t ",," \
    --keyUsage digitalSignature,keyEncipherment \
    --extKeyUsage serverAuth,clientAuth -8 "$client_name" >/dev/null 2>&1 || exiterr "Failed to create client certificate."
}

create_p12_password() {
  p12_password=$(LC_CTYPE=C tr -dc 'A-HJ-NPR-Za-km-z2-9' </dev/urandom 2>/dev/null | head -c 18)
  [ -z "$p12_password" ] && exiterr "Could not generate a random password for .p12 file."
}

get_p12_password() {
  if [ "$use_config_password" = 0 ]; then
    create_p12_password
  else
    p12_password=$(grep -s '^IKEV2_CONFIG_PASSWORD=.\+' "$CONF_FILE" | tail -n 1 | cut -f2- -d= | sed -e "s/^'//" -e "s/'$//")
    if [ -z "$p12_password" ]; then
      create_p12_password
      if [ -n "$CONF_FILE" ] && [ -n "$CONF_DIR" ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "IKEV2_CONFIG_PASSWORD='$p12_password'" >> "$CONF_FILE"
        chmod 600 "$CONF_FILE"
      fi
    fi
  fi
}

export_p12_file() {
  bigecho2 "Creating client configuration..."
  get_p12_password
  p12_file="$export_dir$client_name.p12"
  p12_file_enc="$export_dir$client_name.enc.p12"
  pk12util -W "$p12_password" -d "$CERT_DB" -n "$client_name" -o "$p12_file_enc" >/dev/null || exit 1
  if [ "$os_ver" = "bookwormsid" ] || openssl version 2>/dev/null | grep -q "^OpenSSL 3"; then
    ca_crt="$export_dir$client_name.ca.crt"
    client_crt="$export_dir$client_name.client.crt"
    client_key="$export_dir$client_name.client.key"
    pem_file="$export_dir$client_name.temp.pem"
    openssl pkcs12 -in "$p12_file_enc" -passin "pass:$p12_password" -cacerts -nokeys -out "$ca_crt" || exit 1
    openssl pkcs12 -in "$p12_file_enc" -passin "pass:$p12_password" -clcerts -nokeys -out "$client_crt" || exit 1
    openssl pkcs12 -in "$p12_file_enc" -passin "pass:$p12_password" -passout "pass:$p12_password" \
      -nocerts -out "$client_key" || exit 1
    cat "$client_key" "$client_crt" "$ca_crt" > "$pem_file"
    /bin/rm -f "$client_key" "$client_crt" "$ca_crt"
    openssl pkcs12 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -export -in "$pem_file" -out "$p12_file_enc" \
      -legacy -name "$client_name" -passin "pass:$p12_password" -passout "pass:$p12_password" || exit 1
    if [ "$use_config_password" = 0 ]; then
      openssl pkcs12 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -export -in "$pem_file" -out "$p12_file" \
        -legacy -name "$client_name" -passin "pass:$p12_password" -passout pass: || exit 1
    fi
    /bin/rm -f "$pem_file"
  elif [ "$os_type" = "alpine" ] || [ "$os_ver" = "kalirolling" ] || [ "$os_ver" = "bullseyesid" ]; then
    pem_file="$export_dir$client_name.temp.pem"
    openssl pkcs12 -in "$p12_file_enc" -out "$pem_file" -passin "pass:$p12_password" -passout "pass:$p12_password" || exit 1
    openssl pkcs12 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -export -in "$pem_file" -out "$p12_file_enc" \
      -name "$client_name" -passin "pass:$p12_password" -passout "pass:$p12_password" || exit 1
    if [ "$use_config_password" = 0 ]; then
      openssl pkcs12 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -export -in "$pem_file" -out "$p12_file" \
        -name "$client_name" -passin "pass:$p12_password" -passout pass: || exit 1
    fi
    /bin/rm -f "$pem_file"
  elif [ "$use_config_password" = 0 ]; then
    pk12util -W "" -d "$CERT_DB" -n "$client_name" -o "$p12_file" >/dev/null || exit 1
  fi
  if [ "$use_config_password" = 1 ]; then
    /bin/cp -f "$p12_file_enc" "$p12_file"
  fi
  if [ "$export_to_home_dir" = 1 ]; then
    chown "$SUDO_USER:$SUDO_USER" "$p12_file"
  fi
  chmod 600 "$p12_file"
}

install_base64_uuidgen() {
  if ! command -v base64 >/dev/null 2>&1 || ! command -v uuidgen >/dev/null 2>&1; then
    bigecho2 "Installing required packages..."
    if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ] || [ "$os_type" = "raspbian" ]; then
      export DEBIAN_FRONTEND=noninteractive
      apt-get -yqq update || apt-get -yqq update || exiterr "'apt-get update' failed."
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

update_ikev2_conf() {
  if grep -qs 'ike=aes256-sha2,aes128-sha2,aes256-sha1,aes128-sha1$' "$IKEV2_CONF"; then
    bigecho2 "Updating IKEv2 configuration..."
    sed -i \
      "/ike=aes256-sha2,aes128-sha2,aes256-sha1,aes128-sha1$/s/ike=/ike=aes_gcm_c_256-hmac_sha2_256-ecp_256,/" \
      "$IKEV2_CONF"
    if [ "$os_type" = "alpine" ]; then
      ipsec auto --add ikev2-cp >/dev/null
    else
      restart_ipsec_service >/dev/null
    fi
  fi
}

create_mobileconfig() {
  [ -z "$server_addr" ] && get_server_address
  p12_file_enc="$export_dir$client_name.enc.p12"
  p12_base64=$(base64 -w 52 "$p12_file_enc")
  /bin/rm -f "$p12_file_enc"
  [ -z "$p12_base64" ] && exiterr "Could not encode .p12 file."
  ca_base64=$(certutil -L -d "$CERT_DB" -n "$CA_NAME" -a | grep -v CERTIFICATE)
  [ -z "$ca_base64" ] && exiterr "Could not encode $CA_NAME certificate."
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
          <integer>19</integer>
          <key>EncryptionAlgorithm</key>
          <string>AES-256-GCM</string>
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
          <integer>19</integer>
          <key>EncryptionAlgorithm</key>
          <string>AES-256-GCM</string>
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
            <key>InterfaceTypeMatch</key>
            <string>WiFi</string>
            <key>URLStringProbe</key>
            <string>http://captive.apple.com/hotspot-detect.html</string>
            <key>Action</key>
            <string>Connect</string>
          </dict>
          <dict>
            <key>InterfaceTypeMatch</key>
            <string>Cellular</string>
            <key>Action</key>
            <string>Disconnect</string>
          </dict>
          <dict>
            <key>Action</key>
            <string>Ignore</string>
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
EOF
  if [ "$use_config_password" = 0 ]; then
cat >> "$mc_file" <<EOF
      <key>Password</key>
      <string>$p12_password</string>
EOF
  fi
cat >> "$mc_file" <<EOF
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
  <string>IKEv2 VPN $server_addr</string>
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
  if [ "$export_to_home_dir" = 1 ]; then
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
  "name": "IKEv2 VPN $server_addr",
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
  if [ "$export_to_home_dir" = 1 ]; then
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
  update_ikev2_conf
  export_p12_file
  create_mobileconfig
  create_android_profile
}

create_ca_server_certs() {
  bigecho2 "Generating CA and server certificates..."
  certutil -z <(head -c 1024 /dev/urandom) \
    -S -x -n "$CA_NAME" \
    -s "O=IKEv2 VPN,CN=$CA_NAME" \
    -k rsa -g 3072 -v 120 \
    -d "$CERT_DB" -t "CT,," -2 >/dev/null 2>&1 <<ANSWERS || exiterr "Failed to create CA certificate."
y

N
ANSWERS
  sleep 1
  if [ "$use_dns_name" = 1 ]; then
    certutil -z <(head -c 1024 /dev/urandom) \
      -S -c "$CA_NAME" -n "$server_addr" \
      -s "O=IKEv2 VPN,CN=$server_addr" \
      -k rsa -g 3072 -v 120 \
      -d "$CERT_DB" -t ",," \
      --keyUsage digitalSignature,keyEncipherment \
      --extKeyUsage serverAuth \
      --extSAN "dns:$server_addr" >/dev/null 2>&1 || exiterr "Failed to create server certificate."
  else
    certutil -z <(head -c 1024 /dev/urandom) \
      -S -c "$CA_NAME" -n "$server_addr" \
      -s "O=IKEv2 VPN,CN=$server_addr" \
      -k rsa -g 3072 -v 120 \
      -d "$CERT_DB" -t ",," \
      --keyUsage digitalSignature,keyEncipherment \
      --extKeyUsage serverAuth \
      --extSAN "ip:$server_addr,dns:$server_addr" >/dev/null 2>&1 || exiterr "Failed to create server certificate."
  fi
}

create_config_readme() {
  readme_file="$export_dir$client_name-README.txt"
  if [ "$in_container" = 0 ] && [ "$use_config_password" = 0 ] \
    && [ "$use_defaults" = 1 ] && [ ! -t 1 ] && [ ! -f "$readme_file" ]; then
cat > "$readme_file" <<'EOF'
These IKEv2 client config files were created during IPsec VPN setup.
To configure IKEv2 clients, see: https://vpnsetup.net/clients
EOF
    if [ "$export_to_home_dir" = 1 ]; then
      chown "$SUDO_USER:$SUDO_USER" "$readme_file"
    fi
    chmod 600 "$readme_file"
  fi
}

add_ikev2_connection() {
  bigecho2 "Adding a new IKEv2 connection..."
  XAUTH_POOL=${VPN_XAUTH_POOL:-'192.168.43.10-192.168.43.250'}
  if ! grep -qs '^include /etc/ipsec\.d/\*\.conf$' "$IPSEC_CONF"; then
    echo >> "$IPSEC_CONF"
    echo 'include /etc/ipsec.d/*.conf' >> "$IPSEC_CONF"
  fi
cat > "$IKEV2_CONF" <<EOF

conn ikev2-cp
  left=%defaultroute
  leftcert=$server_addr
  leftsendcert=always
  leftsubnet=0.0.0.0/0
  leftrsasigkey=%cert
  right=%any
  rightid=%fromcert
  rightaddresspool=$XAUTH_POOL
  rightca=%same
  rightrsasigkey=%cert
  narrowing=yes
  dpddelay=30
  retransmit-timeout=300s
  dpdaction=clear
  auto=add
  ikev2=insist
  rekey=no
  pfs=no
  ike=aes_gcm_c_256-hmac_sha2_256-ecp_256,aes256-sha2,aes128-sha2,aes256-sha1,aes128-sha1
  phase2alg=aes_gcm-null,aes128-sha1,aes256-sha1,aes128-sha2,aes256-sha2
  ikelifetime=24h
  salifetime=24h
  encapsulation=yes
EOF
  if [ "$use_dns_name" = 1 ]; then
cat >> "$IKEV2_CONF" <<EOF
  leftid=@$server_addr
EOF
  else
cat >> "$IKEV2_CONF" <<EOF
  leftid=$server_addr
EOF
  fi
  if [ -n "$dns_server_2" ]; then
cat >> "$IKEV2_CONF" <<EOF
  modecfgdns="$dns_servers"
EOF
  else
cat >> "$IKEV2_CONF" <<EOF
  modecfgdns=$dns_server_1
EOF
  fi
  if [ "$mobike_enable" = 1 ]; then
    echo "  mobike=yes" >> "$IKEV2_CONF"
  else
    echo "  mobike=no" >> "$IKEV2_CONF"
  fi
}

restart_ipsec_service() {
  if [ "$in_container" = 0 ] || { [ "$in_container" = 1 ] && service ipsec status >/dev/null 2>&1; }; then
    bigecho2 "Restarting IPsec service..."
    mkdir -p /run/pluto
    service ipsec restart 2>/dev/null
  fi
}

check_ikev2_connection() {
  if grep -qs 'mobike=yes' "$IKEV2_CONF"; then
    (sleep 3
    if ! ipsec status | grep -q ikev2-cp; then
      sed -i '/mobike=yes/s/yes/no/' "$IKEV2_CONF"
      if [ "$os_type" = "alpine" ]; then
        ipsec auto --add ikev2-cp >/dev/null
      else
        restart_ipsec_service >/dev/null
      fi
    fi) >/dev/null 2>&1 &
  fi
}

create_crl() {
  bigecho "Revoking client certificate..."
  if ! crlutil -L -d "$CERT_DB" -n "$CA_NAME" >/dev/null 2>&1; then
    crlutil -G -d "$CERT_DB" -n "$CA_NAME" -c /dev/null >/dev/null
  fi
  sleep 2
}

add_client_cert_to_crl() {
  sn_txt=$(certutil -L -d "$CERT_DB" -n "$client_name" | grep -A 1 'Serial Number' | tail -n 1)
  sn_hex=$(printf '%s' "$sn_txt" | sed -e 's/^ *//' -e 's/://g')
  sn_dec=$((16#$sn_hex))
  [ -z "$sn_dec" ] && exiterr "Could not find serial number of client certificate."
crlutil -M -d "$CERT_DB" -n "$CA_NAME" >/dev/null <<EOF || exiterr "Failed to add client certificate to CRL."
addcert $sn_dec $(date -u +%Y%m%d%H%M%SZ)
EOF
}

reload_crls() {
  ipsec crls
}

delete_client_cert() {
  bigecho "Deleting client certificate..."
  certutil -F -d "$CERT_DB" -n "$client_name"
  certutil -D -d "$CERT_DB" -n "$client_name" 2>/dev/null
}

remove_client_config() {
  p12_file="$export_dir$client_name.p12"
  mc_file="$export_dir$client_name.mobileconfig"
  sswan_file="$export_dir$client_name.sswan"
  if [ -f "$p12_file" ] || [ -f "$mc_file" ] || [ -f "$sswan_file" ]; then
    bigecho "Removing client config files..."
    if [ -f "$p12_file" ]; then
      printf '%s\n' "$p12_file"
      /bin/rm -f "$p12_file"
    fi
    if [ -f "$mc_file" ]; then
      printf '%s\n' "$mc_file"
      /bin/rm -f "$mc_file"
    fi
    if [ -f "$sswan_file" ]; then
      printf '%s\n' "$sswan_file"
      /bin/rm -f "$sswan_file"
    fi
  fi
}

print_client_added() {
cat <<EOF


================================================

New IKEv2 client "$client_name" added!

EOF
  print_server_info
}

print_client_exported() {
cat <<EOF


================================================

IKEv2 client "$client_name" exported!

EOF
  print_server_info
}

print_client_revoked() {
  echo
  echo "Client '$client_name' revoked!"
}

print_client_deleted() {
  echo
  echo "Client '$client_name' deleted!"
}

print_setup_complete() {
  printf '\e[2K\e[1A\e[2K\r'
  [ "$use_defaults" = 1 ] && printf '\e[1A\e[2K\e[1A\e[2K\e[1A\e[2K\r'
cat <<EOF
================================================

IKEv2 setup successful. Details for IKEv2 mode:

VPN server address: $server_addr
VPN client name: $client_name

EOF
}

print_client_info() {
  if [ "$in_container" = 0 ]; then
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
EOF
  if [ "$use_config_password" = 1 ]; then
cat <<EOF

*IMPORTANT* Password for client config files:
$p12_password
Write this down, you'll need it for import!
EOF
  fi
  config_url="https://vpnsetup.net/clients"
  if [ "$in_container" = 1 ]; then
    config_url="${config_url}2"
  fi
cat <<EOF

Next steps: Configure IKEv2 clients. See:
$config_url

================================================

EOF
}

check_swan_update() {
  base_url="https://github.com/hwdsl2/vpn-extras/releases/download/v1.0.0"
  swan_ver_url="$base_url/upg-$os_type-$os_ver-swanver"
  swan_ver_latest=$(wget -t 2 -T 10 -qO- "$swan_ver_url" | head -n 1)
  if printf '%s' "$swan_ver_latest" | grep -Eq '^([3-9]|[1-9][0-9]{1,2})(\.([0-9]|[1-9][0-9]{1,2})){1,2}$' \
    && [ -n "$swan_ver" ] && [ "$swan_ver" != "$swan_ver_latest" ] \
    && printf '%s\n%s' "$swan_ver" "$swan_ver_latest" | sort -C -V; then
cat <<EOF
Note: A newer version of Libreswan ($swan_ver_latest) is available.
      To update, run:
      wget https://get.vpnsetup.net/upg -O vpnup.sh && sudo sh vpnup.sh

EOF
  fi
}

check_ipsec_conf() {
  if grep -qs "conn ikev2-cp" "$IPSEC_CONF"; then
cat 1>&2 <<EOF
Error: IKEv2 configuration section found in $IPSEC_CONF.
       This script cannot automatically remove IKEv2 from this server.
       To manually remove IKEv2, see https://vpnsetup.net/ikev2
EOF
    abort_and_exit
  fi
  if grep -qs "ikev1-policy=drop" "$IPSEC_CONF" \
    || grep -qs "ikev1-policy=reject" "$IPSEC_CONF"; then
cat 1>&2 <<EOF
Error: IKEv2-only mode is currently enabled on this VPN server.
       You must first disable IKEv2-only mode before removing IKEv2.
       Otherwise, you will NOT be able to connect to this VPN server.
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
  if [ "$assume_yes" != 1 ]; then
    confirm_or_abort "Are you sure you want to revoke '$client_name'? [y/N] "
  fi
}

confirm_delete_cert() {
cat <<EOF
WARNING: Deleting a client certificate from the IPsec database *WILL NOT* prevent
         VPN client(s) from connecting using that certificate! For this use case,
         you *MUST* revoke the client certificate instead of deleting it.
         This *cannot* be undone!

EOF
  if [ "$assume_yes" != 1 ]; then
    confirm_or_abort "Are you sure you want to delete '$client_name'? [y/N] "
  fi
}

confirm_remove_ikev2() {
cat <<'EOF'
WARNING: This option will remove IKEv2 from this VPN server, but keep the IPsec/L2TP
         and IPsec/XAuth ("Cisco IPsec") modes, if installed. All IKEv2 configuration
         including certificates and keys will be *permanently deleted*.
         This *cannot* be undone!

EOF
  if [ "$assume_yes" != 1 ]; then
    confirm_or_abort "Are you sure you want to remove IKEv2? [y/N] "
  fi
}

delete_ikev2_conf() {
  bigecho "Deleting $IKEV2_CONF..."
  /bin/rm -f "$IKEV2_CONF"
}

delete_certificates() {
  echo
  bigecho "Deleting certificates and keys from the IPsec database..."
  cert_list=$(certutil -L -d "$CERT_DB" | grep -v -e '^$' -e "$CA_NAME" | tail -n +3 | cut -f1 -d ' ')
  while IFS= read -r line; do
    certutil -F -d "$CERT_DB" -n "$line"
    certutil -D -d "$CERT_DB" -n "$line" 2>/dev/null
  done <<< "$cert_list"
  crlutil -D -d "$CERT_DB" -n "$CA_NAME" 2>/dev/null
  certutil -F -d "$CERT_DB" -n "$CA_NAME"
  certutil -D -d "$CERT_DB" -n "$CA_NAME" 2>/dev/null
  if grep -qs '^IKEV2_CONFIG_PASSWORD=.\+' "$CONF_FILE"; then
    sed -i '/IKEV2_CONFIG_PASSWORD=/d' "$CONF_FILE"
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
  check_swan_ver
  check_utils_exist

  use_defaults=0
  assume_yes=0
  add_client=0
  export_client=0
  list_clients=0
  revoke_client=0
  delete_client=0
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
      --deleteclient)
        delete_client=1
        client_name="$2"
        shift
        shift
        ;;
      --removeikev2)
        remove_ikev2=1
        shift
        ;;
      -y|--yes)
        assume_yes=1
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

  CA_NAME="IKEv2 VPN CA"
  CERT_DB="sql:/etc/ipsec.d"
  CONF_DIR="/etc/ipsec.d"
  CONF_FILE="/etc/ipsec.d/.vpnconfig"
  IKEV2_CONF="/etc/ipsec.d/ikev2.conf"
  IPSEC_CONF="/etc/ipsec.conf"

  check_arguments
  check_config_password
  get_export_dir

  if [ "$add_client" = 1 ]; then
    check_and_set_client_validity
    show_header
    show_add_client
    create_client_cert
    export_client_config
    print_client_added
    print_client_info
    exit 0
  fi

  if [ "$export_client" = 1 ]; then
    show_header
    show_export_client
    export_client_config
    print_client_exported
    print_client_info
    exit 0
  fi

  if [ "$list_clients" = 1 ]; then
    show_header
    list_existing_clients
    echo
    exit 0
  fi

  if [ "$revoke_client" = 1 ]; then
    show_header
    confirm_revoke_cert
    create_crl
    add_client_cert_to_crl
    reload_crls
    remove_client_config
    print_client_revoked
    exit 0
  fi

  if [ "$delete_client" = 1 ]; then
    show_header
    confirm_delete_cert
    delete_client_cert
    remove_client_config
    print_client_deleted
    exit 0
  fi

  if [ "$remove_ikev2" = 1 ]; then
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
        enter_client_validity
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
        echo
        exit 0
        ;;
      4)
        enter_client_name_for revoke
        echo
        confirm_revoke_cert
        create_crl
        add_client_cert_to_crl
        reload_crls
        remove_client_config
        print_client_revoked
        exit 0
        ;;
      5)
        enter_client_name_for delete
        echo
        confirm_delete_cert
        delete_client_cert
        remove_client_config
        print_client_deleted
        exit 0
        ;;
      6)
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

  check_cert_exists_and_exit "$CA_NAME"

  if [ "$use_defaults" = 0 ]; then
    show_header
    show_welcome
    enter_server_address
    check_cert_exists_and_exit "$server_addr"
    enter_client_name with_defaults
    enter_client_validity
    enter_custom_dns
    check_mobike_support
    select_mobike
    select_config_password
    confirm_setup_options
  else
    check_server_dns_name
    check_custom_dns
    check_and_set_client_name
    check_and_set_client_validity
    show_header
    show_start_setup
    set_server_address
    set_dns_servers
    check_mobike_support
    mobike_enable="$mobike_support"
  fi

  create_ca_server_certs
  create_client_cert
  export_client_config
  create_config_readme
  add_ikev2_connection
  if [ "$os_type" = "alpine" ]; then
    ipsec auto --add ikev2-cp >/dev/null
  else
    restart_ipsec_service
  fi
  check_ikev2_connection
  print_setup_complete
  print_client_info
  if [ "$in_container" = 0 ]; then
    check_swan_update
  fi
}

## Defer setup until we have the complete script
ikev2setup "$@"

exit 0
