#!/bin/sh
#
# Script to upgrade Libreswan on CentOS and RHEL
#
# Copyright (C) 2016-2020 Lin Song <linsongui@gmail.com>
#
# This work is licensed under the Creative Commons Attribution-ShareAlike 3.0
# Unported License: http://creativecommons.org/licenses/by-sa/3.0/
#
# Attribution required: please include my name in any derivative and let me
# know how you have improved it!

# Specify which Libreswan version to install. See: https://libreswan.org
SWAN_VER=3.29

### DO NOT edit below this line ###

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

exiterr()  { echo "Error: $1" >&2; exit 1; }
exiterr2() { exiterr "'yum install' failed."; }

vpnupgrade() {

if ! grep -qs -e "release 6" -e "release 7" -e "release 8" /etc/redhat-release; then
  echo "Error: This script only supports CentOS/RHEL 6, 7 and 8." >&2
  echo "For Ubuntu/Debian, use https://git.io/vpnupgrade" >&2
  exit 1
fi

if [ -f /proc/user_beancounters ]; then
  exiterr "OpenVZ VPS is not supported."
fi

if [ "$(id -u)" != 0 ]; then
  exiterr "Script must be run as root. Try 'sudo sh $0'"
fi

case "$SWAN_VER" in
  3.19|3.2[01235679])
    /bin/true
    ;;
  *)
cat 1>&2 <<EOF
Error: Libreswan version '$SWAN_VER' is not supported.
  This script can install one of the following versions:
  3.19-3.23, 3.25-3.27 and 3.29
EOF
    exit 1
    ;;
esac

dns_state=0
case "$SWAN_VER" in
  3.2[35679])
    DNS_SRV1=$(grep "modecfgdns1=" /etc/ipsec.conf | head -n 1 | cut -d '=' -f 2)
    DNS_SRV2=$(grep "modecfgdns2=" /etc/ipsec.conf | head -n 1 | cut -d '=' -f 2)
    [ -n "$DNS_SRV1" ] && dns_state=2
    [ -n "$DNS_SRV1" ] && [ -n "$DNS_SRV2" ] && dns_state=1
    [ "$(grep -c "modecfgdns1=" /etc/ipsec.conf)" -gt "1" ] && dns_state=5
    ;;
  3.19|3.2[012])
    DNS_SRVS=$(grep "modecfgdns=" /etc/ipsec.conf | head -n 1 | cut -d '=' -f 2)
    DNS_SRVS=$(printf '%s' "$DNS_SRVS" | cut -d '"' -f 2 | cut -d "'" -f 2 | sed 's/,/ /g' | tr -s ' ')
    DNS_SRV1=$(printf '%s' "$DNS_SRVS" | cut -d ' ' -f 1)
    DNS_SRV2=$(printf '%s' "$DNS_SRVS" | cut -s -d ' ' -f 2)
    [ -n "$DNS_SRV1" ] && dns_state=4
    [ -n "$DNS_SRV1" ] && [ -n "$DNS_SRV2" ] && dns_state=3
    [ "$(grep -c "modecfgdns=" /etc/ipsec.conf)" -gt "1" ] && dns_state=6
    ;;
esac

ipsec_ver=$(/usr/local/sbin/ipsec --version 2>/dev/null)
ipsec_ver_short=$(printf '%s' "$ipsec_ver" | sed -e 's/Linux Libreswan/Libreswan/' -e 's/ (netkey) on .*//')
if ! printf '%s' "$ipsec_ver" | grep -q "Libreswan"; then
  exiterr "This script requires Libreswan already installed."
fi

if printf '%s' "$ipsec_ver" | grep -qF "$SWAN_VER"; then
  echo "You already have Libreswan version $SWAN_VER installed! "
  echo "If you continue, the same version will be re-installed."
  echo
  printf "Do you wish to continue anyway? [y/N] "
  read -r response
  case $response in
    [yY][eE][sS]|[yY])
      echo
      ;;
    *)
      echo "Aborting."
      exit 1
      ;;
  esac
fi

clear

cat <<EOF
Welcome! This script will build and install Libreswan on your server.
Additional packages required for compilation will also be installed.

It is intended for upgrading servers to a newer Libreswan version.

Current version:    $ipsec_ver_short
Version to install: Libreswan $SWAN_VER

EOF

case "$SWAN_VER" in
  3.19|3.2[0123567])
cat <<'EOF'
WARNING: Older versions of Libreswan may contain security vulnerabilities.
    See: https://libreswan.org/security/
    Are you sure you want to install an older version?

EOF
    ;;
esac

case "$SWAN_VER" in
  3.2[35])
cat <<'EOF'
WARNING: Libreswan 3.23 and 3.25 have an issue with connecting multiple
    IPsec/XAuth VPN clients from behind the same NAT (e.g. home router).
    DO NOT install 3.23/3.25 if your use cases include the above.

EOF
    ;;
esac

cat <<'EOF'
NOTE: Libreswan versions 3.19 and newer require some configuration changes.
    This script will make the following updates to your /etc/ipsec.conf:

    - Replace "auth=esp" with "phase2=esp"
    - Replace "forceencaps=yes" with "encapsulation=yes"
    - Optimize VPN ciphers for "ike=" and "phase2alg="
EOF

if [ "$dns_state" = "1" ] || [ "$dns_state" = "2" ]; then
cat <<'EOF'
    - Replace "modecfgdns1" and "modecfgdns2" with "modecfgdns"
EOF
fi

if [ "$dns_state" = "3" ] || [ "$dns_state" = "4" ]; then
cat <<'EOF'
    - Replace "modecfgdns" with "modecfgdns1" and "modecfgdns2"
EOF
fi

if [ "$SWAN_VER" = "3.29" ]; then
cat <<'EOF'
    - Move "ikev2=never" to section "conn shared"
EOF
fi

cat <<'EOF'

    Your other VPN configuration files will not be modified.

EOF

printf "Do you wish to continue? [y/N] "
read -r response
case $response in
  [yY][eE][sS]|[yY])
    echo
    echo "Please be patient. Setup is continuing..."
    echo
    ;;
  *)
    echo "Aborting."
    exit 1
    ;;
esac

# Create and change to working dir
mkdir -p /opt/src
cd /opt/src || exit 1

# Add the EPEL repository
epel_url="https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E '%{rhel}').noarch.rpm"
yum -y install epel-release || yum -y install "$epel_url" || exiterr2

# Install necessary packages
yum -y install nss-devel nspr-devel pkgconfig pam-devel \
  libcap-ng-devel libselinux-devel curl-devel nss-tools \
  flex bison gcc make wget sed tar || exiterr2

REPO1='--enablerepo=*server-optional*'
REPO2='--enablerepo=*releases-optional*'
REPO3='--enablerepo=PowerTools'

if grep -qs "release 6" /etc/redhat-release; then
  yum -y remove libevent-devel
  yum "$REPO1" "$REPO2" -y install libevent2-devel fipscheck-devel || exiterr2
elif grep -qs "release 7" /etc/redhat-release; then
  yum -y install systemd-devel || exiterr2
  yum "$REPO1" "$REPO2" -y install libevent-devel fipscheck-devel || exiterr2
else
  if [ -f /usr/sbin/subscription-manager ]; then
    subscription-manager repos --enable "codeready-builder-for-rhel-8-*-rpms"
    yum -y install systemd-devel libevent-devel fipscheck-devel || exiterr2
  else
    yum "$REPO3" -y install systemd-devel libevent-devel fipscheck-devel || exiterr2
  fi
fi

# Compile and install Libreswan
swan_file="libreswan-$SWAN_VER.tar.gz"
swan_url1="https://github.com/libreswan/libreswan/archive/v$SWAN_VER.tar.gz"
swan_url2="https://download.libreswan.org/$swan_file"
if ! { wget -t 3 -T 30 -nv -O "$swan_file" "$swan_url1" || wget -t 3 -T 30 -nv -O "$swan_file" "$swan_url2"; }; then
  exit 1
fi
/bin/rm -rf "/opt/src/libreswan-$SWAN_VER"
tar xzf "$swan_file" && /bin/rm -f "$swan_file"
cd "libreswan-$SWAN_VER" || exit 1
[ "$SWAN_VER" = "3.22" ] && sed -i '/^#define LSWBUF_CANARY/s/-2$/((char) -2)/' include/lswlog.h
[ "$SWAN_VER" = "3.23" ] || [ "$SWAN_VER" = "3.25" ] && sed -i '/docker-targets\.mk/d' Makefile
[ "$SWAN_VER" = "3.26" ] && sed -i 's/-lfreebl //' mk/config.mk
[ "$SWAN_VER" = "3.26" ] && sed -i '/blapi\.h/d' programs/pluto/keys.c
cat > Makefile.inc.local <<'EOF'
WERROR_CFLAGS =
USE_DNSSEC = false
USE_DH31 = false
USE_NSS_AVA_COPY = true
USE_NSS_IPSEC_PROFILE = false
USE_GLIBC_KERN_FLIP_HEADERS = true
EOF
NPROCS=$(grep -c ^processor /proc/cpuinfo)
[ -z "$NPROCS" ] && NPROCS=1
make "-j$((NPROCS+1))" -s base && make -s install-base

# Verify the install and clean up
cd /opt/src || exit 1
/bin/rm -rf "/opt/src/libreswan-$SWAN_VER"
if ! /usr/local/sbin/ipsec --version 2>/dev/null | grep -qF "$SWAN_VER"; then
  exiterr "Libreswan $SWAN_VER failed to build."
fi

# Restore SELinux contexts
restorecon /etc/ipsec.d/*db 2>/dev/null
restorecon /usr/local/sbin -Rv 2>/dev/null
restorecon /usr/local/libexec/ipsec -Rv 2>/dev/null

# Update ipsec.conf
IKE_NEW="  ike=aes256-sha2,aes128-sha2,aes256-sha1,aes128-sha1,aes256-sha2;modp1024,aes128-sha1;modp1024"
PHASE2_NEW="  phase2alg=aes_gcm-null,aes128-sha1,aes256-sha1,aes256-sha2_512,aes128-sha2,aes256-sha2"

sed -i".old-$(date +%F-%T)" \
    -e "s/^[[:space:]]\+auth=esp\$/  phase2=esp/g" \
    -e "s/^[[:space:]]\+forceencaps=yes\$/  encapsulation=yes/g" \
    -e "s/^[[:space:]]\+ike=.\+\$/$IKE_NEW/g" \
    -e "s/^[[:space:]]\+phase2alg=.\+\$/$PHASE2_NEW/g" /etc/ipsec.conf

if [ "$dns_state" = "1" ]; then
  sed -i -e "s/modecfgdns1=.*/modecfgdns=\"$DNS_SRV1 $DNS_SRV2\"/" \
      -e "/modecfgdns2/d" /etc/ipsec.conf
elif [ "$dns_state" = "2" ]; then
  sed -i "s/modecfgdns1=.*/modecfgdns=$DNS_SRV1/" /etc/ipsec.conf
elif [ "$dns_state" = "3" ]; then
  sed -i "/modecfgdns=/a \  modecfgdns2=$DNS_SRV2" /etc/ipsec.conf
  sed -i "s/modecfgdns=.*/modecfgdns1=$DNS_SRV1/" /etc/ipsec.conf
elif [ "$dns_state" = "4" ]; then
  sed -i "s/modecfgdns=.*/modecfgdns1=$DNS_SRV1/" /etc/ipsec.conf
fi

if [ "$SWAN_VER" = "3.29" ]; then
  sed -i "/ikev2=never/d" /etc/ipsec.conf
  sed -i "/dpdaction=clear/a \  ikev2=never" /etc/ipsec.conf
fi

# Restart IPsec service
mkdir -p /run/pluto
service ipsec restart

cat <<EOF


===================================================

Libreswan $SWAN_VER has been successfully installed!

===================================================

EOF

if [ "$dns_state" = "5" ]; then
cat <<'EOF'
IMPORTANT: Users upgrading to Libreswan 3.23 or newer must edit /etc/ipsec.conf
    and replace all occurrences of these two lines:

      modecfgdns1=DNS_SERVER_1
      modecfgdns2=DNS_SERVER_2

    with a single line like this:

      modecfgdns="DNS_SERVER_1 DNS_SERVER_2"

    Then run "sudo service ipsec restart".

EOF
elif [ "$dns_state" = "6" ]; then
cat <<'EOF'
IMPORTANT: Users downgrading to Libreswan 3.22 or older must edit /etc/ipsec.conf
    and replace all occurrences of this line:

      modecfgdns="DNS_SERVER_1 DNS_SERVER_2"

    with two lines like this:

      modecfgdns1=DNS_SERVER_1
      modecfgdns2=DNS_SERVER_2

    Then run "sudo service ipsec restart".

EOF
fi

}

## Defer setup until we have the complete script
vpnupgrade "$@"

exit 0
