#!/bin/sh

export VPN_IPSEC_PSK="$1"
export VPN_USER="$2"
export VPN_PASSWORD="$3"

VPN_SETUP_REF="ba2b765b5e9a05f89aaf56f3c8a326399674bcdf"
VPN_SETUP_SHA256="b2559dd6b2dd6ca80823db3a9efd9c3560d78554caa573b635b8bcbd4a903708"
VPN_SETUP_URL="https://raw.githubusercontent.com/hwdsl2/setup-ipsec-vpn/$VPN_SETUP_REF/vpnsetup.sh"

umask 077
tmp_file=$(mktemp /tmp/vpnsetup.XXXXXX) || exit 1
trap 'rm -f "$tmp_file"' 0
trap 'exit 1' HUP INT TERM

wget -t 3 -T 30 -nv --max-redirect=0 -O "$tmp_file" "$VPN_SETUP_URL" || exit 1

printf '%s  %s\n' "$VPN_SETUP_SHA256" "$tmp_file" | sha256sum -c - || exit 1

/bin/sh "$tmp_file" >/dev/null
status=$?
exit "$status"
