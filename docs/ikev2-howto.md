# How-To: IKEv2 VPN for Windows and Android

*Read this in other languages: [English](ikev2-howto.md), [简体中文](ikev2-howto-zh.md).*

---

**IMPORTANT:** This guide is for **advanced users** only. Other users please use <a href="clients.md" target="_blank">IPsec/L2TP</a> or <a href="clients-xauth.md" target="_blank">IPsec/XAuth</a>.

---

Windows 7 and newer releases support the IKEv2 standard through Microsoft's Agile VPN functionality. Internet Key Exchange (IKE or IKEv2) is the protocol used to set up a Security Association (SA) in the IPsec protocol suite. Compared to IKE version 1, IKEv2 has <a href="https://en.wikipedia.org/wiki/Internet_Key_Exchange#Improvements_with_IKEv2" target="_blank">multiple improvements</a> such as Standard Mobility support through MOBIKE, and improved reliability.

Libreswan can authenticate IKEv2 clients on the basis of X.509 Machine Certificates using RSA signatures. This method does not require an IPsec PSK, username or password. It can be used with:

- Windows 7, 8.x and 10
- Windows Phone 8.1 and above
- strongSwan Android VPN client
- <a href="https://github.com/gaomd/docker-ikev2-vpn-server" target="_blank">iOS (iPhone/iPad) and macOS</a> <-- See also

The following example shows how to configure IKEv2 with Libreswan. Commands below must be run as `root`.

Before continuing, make sure you have successfully <a href="https://github.com/hwdsl2/setup-ipsec-vpn" target="_blank">set up your VPN server</a>.

1. Find the VPN server's public IP, save it to a variable and check.

   ```bash
   $ PUBLIC_IP=$(wget -t 3 -T 15 -qO- http://ipv4.icanhazip.com)
   $ echo "$PUBLIC_IP"
   (Check the displayed public IP)
   ```

   **Note:** Alternatively, you may specify the server's DNS name here. e.g. `PUBLIC_IP=myvpn.example.com`.

1. Add a new IKEv2 connection to `/etc/ipsec.conf`:

   ```bash
   $ cat >> /etc/ipsec.conf <<EOF

   conn ikev2-cp
     left=%defaultroute
     leftcert=$PUBLIC_IP
     leftid=@$PUBLIC_IP
     leftsendcert=always
     leftsubnet=0.0.0.0/0
     leftrsasigkey=%cert
     right=%any
     rightaddresspool=192.168.43.10-192.168.43.250
     rightca=%same
     rightrsasigkey=%cert
     modecfgdns1=8.8.8.8
     modecfgdns2=8.8.4.4
     narrowing=yes
     dpddelay=30
     dpdtimeout=120
     dpdaction=clear
     auto=add
     ikev2=insist
     rekey=no
     fragmentation=yes
     ike=3des-sha1,3des-sha2,aes-sha1,aes-sha1;modp1024,aes-sha2,aes-sha2;modp1024,aes256-sha2_512
     phase2alg=3des-sha1,3des-sha2,aes-sha1,aes-sha2,aes256-sha2_512
   EOF
   ```

   We need to add one more line to that file. First check your Libreswan version:

   ```bash
   $ ipsec --version
   ```

   For Libreswan 3.19 and newer, run command:

   ```bash
   $ echo " encapsulation=yes" >> /etc/ipsec.conf
   ```

   For Libreswan 3.18 and older, run command:

   ```bash
   $ echo " forceencaps=yes" >> /etc/ipsec.conf
   ```

1. Generate Certificate Authority (CA) and VPN server certificates:

   **Note:** Specify the certificate validity period (in months) using "-v". e.g. "-v 36". In addition, if you specified the server's DNS name (instead of its IP address) in step 1 above, replace `--extSAN "ip:$PUBLIC_IP,dns:$PUBLIC_IP"` with `--extSAN "dns:$PUBLIC_IP"` in the command below.

   ```bash
   $ certutil -S -x -n "Example CA" -s "O=Example,CN=Example CA" -k rsa -g 4096 -v 36 -d sql:/etc/ipsec.d -t "CT,," -2

   A random seed must be generated that will be used in the
   creation of your key.  One of the easiest ways to create a
   random seed is to use the timing of keystrokes on a keyboard.

   To begin, type keys on the keyboard until this progress meter
   is full.  DO NOT USE THE AUTOREPEAT FUNCTION ON YOUR KEYBOARD!

   Continue typing until the progress meter is full:

   |************************************************************|

   Finished.  Press enter to continue:

   Generating key.  This may take a few moments...

   Is this a CA certificate [y/N]?
   y
   Enter the path length constraint, enter to skip [<0 for unlimited path]: >
   Is this a critical extension [y/N]?
   N

   $ certutil -S -c "Example CA" -n "$PUBLIC_IP" -s "O=Example,CN=$PUBLIC_IP" -k rsa -g 4096 -v 36 -d sql:/etc/ipsec.d -t ",," \
      --keyUsage digitalSignature,keyEncipherment --extKeyUsage serverAuth --extSAN "ip:$PUBLIC_IP,dns:$PUBLIC_IP"

   A random seed must be generated that will be used in the
   creation of your key.  One of the easiest ways to create a
   random seed is to use the timing of keystrokes on a keyboard.

   To begin, type keys on the keyboard until this progress meter
   is full.  DO NOT USE THE AUTOREPEAT FUNCTION ON YOUR KEYBOARD!

   Continue typing until the progress meter is full:

   |************************************************************|

   Finished.  Press enter to continue:

   Generating key.  This may take a few moments...
   ```

1. Generate client certificate(s), and export the `.p12` file that contains the client certificate, private key, and CA certificate:

   ```bash
   $ certutil -S -c "Example CA" -n "vpnclient" -s "O=Example,CN=vpnclient" -k rsa -g 4096 -v 36 -d sql:/etc/ipsec.d -t ",," \
      --keyUsage digitalSignature,keyEncipherment --extKeyUsage serverAuth,clientAuth -8 "vpnclient"

   A random seed must be generated that will be used in the
   creation of your key.  One of the easiest ways to create a
   random seed is to use the timing of keystrokes on a keyboard.

   To begin, type keys on the keyboard until this progress meter
   is full.  DO NOT USE THE AUTOREPEAT FUNCTION ON YOUR KEYBOARD!

   Continue typing until the progress meter is full:

   |************************************************************|

   Finished.  Press enter to continue:

   Generating key.  This may take a few moments...

   $ pk12util -o vpnclient.p12 -n "vpnclient" -d sql:/etc/ipsec.d

   Enter password for PKCS12 file:
   Re-enter password:
   pk12util: PKCS12 EXPORT SUCCESSFUL
   ```

   Repeat this step for additional VPN clients, but replace every `vpnclient` with `vpnclient2`, etc.

   **Note:** If you wish to connect multiple VPN clients simultaneously, you must generate a unique certificate for each.

1. The database should now contain:

   ```bash
   $ certutil -L -d sql:/etc/ipsec.d

   Certificate Nickname                               Trust Attributes
                                                      SSL,S/MIME,JAR/XPI

   Example CA                                         CTu,u,u
   ($PUBLIC_IP)                                       u,u,u
   vpnclient                                          u,u,u
   ```

   **Note:** To display a certificate, use `certutil -L -d sql:/etc/ipsec.d -n "Nickname"`. To delete a certificate, replace `-L` with `-D`. For other `certutil` usage, read <a href="http://manpages.ubuntu.com/manpages/zesty/man1/certutil.1.html" target="_blank">this page</a>.

1. Restart IPsec service:

   ```bash
   $ service ipsec restart
   ```

1. The `vpnclient.p12` file should then be securely transferred to the VPN client device. Next steps:

   #### Windows 7, 8.x and 10

   1. Import the `.p12` file to the "Computer account" certificate store. Make sure that the client cert is placed in "Personal -> Certificates", and the CA cert is placed in "Trusted Root Certification Authorities -> Certificates".

      Detailed instructions:   
      https://wiki.strongswan.org/projects/strongswan/wiki/Win7Certs

   1. On the Windows computer, add a new IKEv2 VPN connection：   
      https://wiki.strongswan.org/projects/strongswan/wiki/Win7Config

   1. Start the new IKEv2 VPN connection, and enjoy your VPN!   
      https://wiki.strongswan.org/projects/strongswan/wiki/Win7Connect

   1. (Optional) You may enable stronger ciphers by adding <a href="https://wiki.strongswan.org/projects/strongswan/wiki/Windows7#AES-256-CBC-and-MODP2048" target="_blank">this registry key</a> and reboot.

   #### Android 4.x and newer

   1. Install <a href="https://play.google.com/store/apps/details?id=org.strongswan.android" target="_blank">strongSwan VPN Client</a> from **Google Play**.
   1. Launch the VPN client and tap **Add VPN Profile**.
   1. Enter `Your VPN Server IP` in the **Server** field.
   1. Select **IKEv2 Certificate** from the **VPN Type** drop-down menu.
   1. Tap to add a **User certificate**, then tap **Install**.
   1. Choose the `.p12` file you copied from the VPN server, and follow the prompts.
   1. Save the new VPN connection, then tap to connect.

   #### Windows Phone 8.1 and above

   First import the `.p12` file, then follow <a href="https://technet.microsoft.com/en-us/windows/dn673608.aspx" target="_blank">these instructions</a> to configure a certificate-based IKEv2 VPN.

1. Once successfully connected, you can verify that your traffic is being routed properly by <a href="https://encrypted.google.com/search?q=my+ip" target="_blank">looking up your IP address on Google</a>. It should say "Your public IP address is `Your VPN Server IP`".

## Known Issues

The built-in VPN client in Windows does not support IKEv2 fragmentation. On some networks, this can cause the connection to fail or have other issues. You may try <a href="clients.md#troubleshooting" target="_blank">this registry fix</a>, or connect using <a href="clients.md" target="_blank">IPsec/L2TP</a> or <a href="clients-xauth.md" target="_blank">IPsec/XAuth</a> mode instead.

## References

* https://libreswan.org/wiki/VPN_server_for_remote_clients_using_IKEv2
* https://libreswan.org/wiki/HOWTO:_Using_NSS_with_libreswan
* https://libreswan.org/man/ipsec.conf.5.html
* https://wiki.strongswan.org/projects/strongswan/wiki/Windows7
* https://wiki.strongswan.org/projects/strongswan/wiki/AndroidVpnClient
