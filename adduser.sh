echo "Enter username"
read username
if grep "^"$username":" /etc/ipsec.d/passwd
then
  echo "username exist"
  exit 1
fi
echo "Enter password"
read password
password=$(openssl passwd -1 "$password")
echo $username":"$password":xauth-psk" >> /etc/ipsec.d/passwd
