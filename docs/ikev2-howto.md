# Step-by-Step Guide: How to Set Up IKEv2 VPN

*Read this in other languages: [English](ikev2-howto.md), [简体中文](ikev2-howto-zh.md).*

**Note:** You may also connect using [IPsec/L2TP](clients.md) or [IPsec/XAuth](clients-xauth.md) mode.

* [Introduction](#introduction)
* [Using helper scripts](#using-helper-scripts)
* [Configure IKEv2 VPN clients](#configure-ikev2-vpn-clients)
* [Manage client certificates](#manage-client-certificates)
* [Manually set up IKEv2 on the VPN server](#manually-set-up-ikev2-on-the-vpn-server)
* [Known issues](#known-issues)
* [Remove IKEv2](#remove-ikev2)
* [References](#references)

## Introduction

Modern operating systems (such as Windows 7 and newer) support the IKEv2 standard. Internet Key Exchange (IKE or IKEv2) is the protocol used to set up a Security Association (SA) in the IPsec protocol suite. Compared to IKE version 1, IKEv2 contains <a href="https://en.wikipedia.org/wiki/Internet_Key_Exchange#Improvements_with_IKEv2" target="_blank">improvements</a> such as Standard Mobility support through MOBIKE, and improved reliability.

Libreswan can authenticate IKEv2 clients on the basis of X.509 Machine Certificates using RSA signatures. This method does not require an IPsec PSK, username or password. It can be used with:

- Windows 7, 8.x and 10
- OS X (macOS)
- Android 4.x and newer (using the strongSwan VPN client)
- iOS (iPhone/iPad)

After following this guide, you will be able to connect to the VPN using IKEv2 in addition to the existing [IPsec/L2TP](clients.md) and [IPsec/XAuth ("Cisco IPsec")](clients-xauth.md) modes.

## Using helper scripts

**New:** For macOS and iOS clients, the helper script can now create .mobileconfig files to simplify client setup and improve VPN performance.

**Important:** Before continuing, you should have successfully <a href="https://github.com/hwdsl2/setup-ipsec-vpn" target="_blank">set up your own VPN server</a>, and (optional but recommended) <a href="../README.md#upgrade-libreswan" target="_blank">updated Libreswan</a>. **Docker users, see <a href="https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README.md#configure-and-use-ikev2-vpn" target="_blank">here</a>**.

Use this helper script to automatically set up IKEv2 on the VPN server:

```
wget https://git.io/ikev2setup -O ikev2.sh && sudo bash ikev2.sh --auto
```

The <a href="../extras/ikev2setup.sh" target="_blank">script</a> must be run using `bash`, not `sh`. The command above runs the helper script in auto mode, using default options. Remove the `--auto` parameter if you want to customize IKEv2 setup options. When finished, continue to [configure IKEv2 VPN clients](#configure-ikev2-vpn-clients).

<details>
<summary>
Click here to view detailed usage information for the IKEv2 helper script.
</summary>

```
Usage: bash ikev2.sh [options]

Options:
  --auto                        run IKEv2 setup in auto mode using default options (for initial IKEv2 setup only)
  --addclient [client name]     add a new IKEv2 client using default options (after IKEv2 setup)
  --exportclient [client name]  export an existing IKEv2 client using default options (after IKEv2 setup)
  --listclients                 list the names of existing IKEv2 clients (after IKEv2 setup)
  -h, --help                    show this help message and exit

To customize IKEv2 or client options, run this script without arguments.
```
</details>

## Configure IKEv2 VPN clients

*Read this in other languages: [English](ikev2-howto.md#configure-ikev2-vpn-clients), [简体中文](ikev2-howto-zh.md#配置-ikev2-vpn-客户端).*

**Note:** If you want to generate certificates for additional VPN clients, or export configuration for an existing client, just run the [helper script](#using-helper-scripts) again. Use option `-h` to show detailed usage information.

* [Windows 7, 8.x and 10](#windows-7-8x-and-10)
* [OS X (macOS)](#os-x-macos)
* [iOS (iPhone/iPad)](#ios)
* [Android](#android)

### Windows 7, 8.x and 10

1. Securely transfer the generated `.p12` file to your computer, then import it into the "Computer account" certificate store. Make sure that the client cert is placed in "Personal -> Certificates", and the CA cert is placed in "Trusted Root Certification Authorities -> Certificates".

   Detailed instructions:   
   https://wiki.strongswan.org/projects/strongswan/wiki/Win7Certs

   **Note:** Ubuntu 18.04 users may encounter the error "The password you entered is incorrect" when trying to import the generated `.p12` file into Windows. See [Known issues](#known-issues).

1. On the Windows computer, add a new IKEv2 VPN connection:   
   https://wiki.strongswan.org/projects/strongswan/wiki/Win7Config

   **Note:** If you specified the server's DNS name (instead of its IP address) during IKEv2 setup, you must enter the DNS name in the **Internet address** field.

1. (Optional but recommended) Enable stronger ciphers for IKEv2 with a one-time registry change. Download and import the `.reg` file below, or run the following from an <a href="http://www.winhelponline.com/blog/open-elevated-command-prompt-windows/" target="_blank">elevated command prompt</a>. Read more <a href="https://wiki.strongswan.org/projects/strongswan/wiki/WindowsClients#AES-256-CBC-and-MODP2048" target="_blank">here</a>.

   - For Windows 7, 8.x and 10 ([download .reg file](https://dl.ls20.com/reg-files/v1/Enable_Stronger_Ciphers_for_IKEv2_on_Windows.reg))

     ```console
     REG ADD HKLM\SYSTEM\CurrentControlSet\Services\RasMan\Parameters /v NegotiateDH2048_AES256 /t REG_DWORD /d 0x1 /f
     ```

1. Start the new VPN connection, and enjoy your IKEv2 VPN!   
   https://wiki.strongswan.org/projects/strongswan/wiki/Win7Connect

Once successfully connected, you can verify that your traffic is being routed properly by <a href="https://www.google.com/search?q=my+ip" target="_blank">looking up your IP address on Google</a>. It should say "Your public IP address is `Your VPN Server IP`".

### OS X (macOS)

First, securely transfer the generated `.mobileconfig` file to your Mac, then double-click and follow the prompts to import as a macOS profile. When finished, check to make sure "IKEv2 VPN configuration" is listed under System Preferences -> Profiles.

1. Open System Preferences and go to the Network section.
1. Select the VPN connection with `Your VPN Server IP` (or DNS name).
1. Check the **Show VPN status in menu bar** checkbox.
1. Click **Connect**.

(Optional feature) You can choose to enable <a href="https://developer.apple.com/documentation/networkextension/personal_vpn/vpn_on_demand_rules" target="_blank">VPN On Demand</a>. This is an "always-on" feature that can automatically connect to the VPN while on Wi-Fi. To enable, check the **Connect on demand** checkbox for the VPN connection, and click **Apply**.

<details>
<summary>
If you manually set up IKEv2 without using the helper script, click here for instructions.
</summary>

First, securely transfer the generated `.p12` file to your Mac, then double-click to import into the **login** keychain in **Keychain Access**. Next, double-click on the imported `IKEv2 VPN CA` certificate, expand **Trust** and select **Always Trust** from the **IP Security (IPsec)** drop-down menu. Close the dialog using the red "X" on the top-left corner. When prompted, use Touch ID or enter your password and click "Update Settings".

When finished, check to make sure both the new client certificate and `IKEv2 VPN CA` are listed under the **Certificates** category of **login** keychain.

1. Open System Preferences and go to the Network section.
1. Click the **+** button in the lower-left corner of the window.
1. Select **VPN** from the **Interface** drop-down menu.
1. Select **IKEv2** from the **VPN Type** drop-down menu.
1. Enter anything you like for the **Service Name**.
1. Click **Create**.
1. Enter `Your VPN Server IP` (or DNS name) for the **Server Address**.   
   **Note:** If you specified the server's DNS name (instead of its IP address) during IKEv2 setup, you must enter the DNS name in the **Server Address** and **Remote ID** fields.
1. Enter `Your VPN Server IP` (or DNS name) for the **Remote ID**.
1. Enter `Your VPN client name` in the **Local ID** field.   
   **Note:** This must match exactly the client name you specified during IKEv2 setup. Same as the first part of your `.p12` filename.
1. Click the **Authentication Settings...** button.
1. Select **None** from the **Authentication Settings** drop-down menu.
1. Select the **Certificate** radio button, then select the new client certificate.
1. Click **OK**.
1. Check the **Show VPN status in menu bar** checkbox.
1. Click **Apply** to save the VPN connection information.
1. Click **Connect**.
</details>

Once successfully connected, you can verify that your traffic is being routed properly by <a href="https://www.google.com/search?q=my+ip" target="_blank">looking up your IP address on Google</a>. It should say "Your public IP address is `Your VPN Server IP`".

### iOS

First, securely transfer the generated `.mobileconfig` file to your iOS device, then import it as an iOS profile. To transfer the file, you may use:

1. AirDrop, or
1. Upload to your device using "File Sharing" in iTunes, then open the "Files" app on your iOS device, move the uploaded file to the "On My iPhone" folder. After that, tap the file and go to "Settings" to import, or
1. Host the file on a secure website of yours, then download and import it in Mobile Safari.

When finished, check to make sure "IKEv2 VPN configuration" is listed under Settings -> General -> Profile(s).

1. Go to Settings -> General -> VPN.
1. Select the VPN connection with `Your VPN Server IP` (or DNS name).
1. Slide the **VPN** switch ON.

(Optional feature) You can choose to enable <a href="https://developer.apple.com/documentation/networkextension/personal_vpn/vpn_on_demand_rules" target="_blank">VPN On Demand</a>. This is an "always-on" feature that can automatically connect to the VPN while on Wi-Fi. To enable, tap the "i" icon on the right of the VPN connection, and enable **Connect On Demand**.

<details>
<summary>
If you manually set up IKEv2 without using the helper script, click here for instructions.
</summary>

First, securely transfer the generated `ikev2vpnca.cer` and `.p12` files to your iOS device, then import them one by one as iOS profiles. To transfer the files, you may use:

1. AirDrop, or
1. Upload to your device using "File Sharing" in iTunes, then open the "Files" app on your iOS device, move the uploaded files to the "On My iPhone" folder. After that, tap each file and go to "Settings" to import, or
1. Host the files on a secure website of yours, then download and import them in Mobile Safari.

When finished, check to make sure both the new client certificate and `IKEv2 VPN CA` are listed under Settings -> General -> Profiles.

1. Go to Settings -> General -> VPN.
1. Tap **Add VPN Configuration...**.
1. Tap **Type**. Select **IKEv2** and go back.
1. Tap **Description** and enter anything you like.
1. Tap **Server** and enter `Your VPN Server IP` (or DNS name).   
   **Note:** If you specified the server's DNS name (instead of its IP address) during IKEv2 setup, you must enter the DNS name in the **Server** and **Remote ID** fields.
1. Tap **Remote ID** and enter `Your VPN Server IP` (or DNS name).
1. Enter `Your VPN client name` in the **Local ID** field.   
   **Note:** This must match exactly the client name you specified during IKEv2 setup. Same as the first part of your `.p12` filename.
1. Tap **User Authentication**. Select **None** and go back.
1. Make sure the **Use Certificate** switch is ON.
1. Tap **Certificate**. Select the new client certificate and go back.
1. Tap **Done**.
1. Slide the **VPN** switch ON.
</details>

Once successfully connected, you can verify that your traffic is being routed properly by <a href="https://www.google.com/search?q=my+ip" target="_blank">looking up your IP address on Google</a>. It should say "Your public IP address is `Your VPN Server IP`".

### Android

1. Securely transfer the generated `.sswan` file to your Android device.
1. Install <a href="https://play.google.com/store/apps/details?id=org.strongswan.android" target="_blank">strongSwan VPN Client</a> from **Google Play**.
1. Launch the strongSwan VPN client.
1. Tap the "more options" menu on top right, then tap **Import VPN profile**.
1. Choose the `.sswan` file you transferred from the VPN server.   
   **Note:** To find the `.sswan` file, tap the three-line menu button, then browse to the location you saved the file.
1. On the "Import VPN profile" screen, tap **IMPORT CERTIFICATE FROM VPN PROFILE**, and follow the prompts.
1. On the "Choose certificate" screen, select the new client certificate, then tap **Select**.
1. Tap **IMPORT**.
1. Tap the new VPN profile to connect.

(Optional feature) You can choose to enable the "Always-on VPN" feature on Android. Launch the **Settings** app, go to Network & internet -> Advanced -> VPN, click the gear icon on the right of "strongSwan VPN Client", then enable the "Always-on VPN" and "Block connections without VPN" options.

<details>
<summary>
If you manually set up IKEv2 without using the helper script, click here for instructions.
</summary>

**Android 10 and newer:**

1. Securely transfer the generated `.p12` file to your Android device.
1. Install <a href="https://play.google.com/store/apps/details?id=org.strongswan.android" target="_blank">strongSwan VPN Client</a> from **Google Play**.
1. Launch the **Settings** application.
1. Go to Security -> Advanced -> Encryption & credentials.
1. Tap **Install certificates from storage (or SD card)**.
1. Choose the `.p12` file you transferred from the VPN server, and follow the prompts.   
   **Note:** To find the `.p12` file, tap the three-line menu button, then browse to the location you saved the file.
1. Launch the strongSwan VPN client and tap **Add VPN Profile**.
1. Enter `Your VPN Server IP` (or DNS name) in the **Server** field.   
   **Note:** If you specified the server's DNS name (instead of its IP address) during IKEv2 setup, you must enter the DNS name in the **Server** field.
1. Select **IKEv2 Certificate** from the **VPN Type** drop-down menu.
1. Tap **Select user certificate**, select the new client certificate and confirm.
1. **(Important)** Tap **Show advanced settings**. Scroll down, find and enable the **Use RSA/PSS signatures** option.
1. Save the new VPN connection, then tap to connect.

**Android 4 to 9:**

1. Securely transfer the generated `.p12` file to your Android device.
1. Install <a href="https://play.google.com/store/apps/details?id=org.strongswan.android" target="_blank">strongSwan VPN Client</a> from **Google Play**.
1. Launch the strongSwan VPN client and tap **Add VPN Profile**.
1. Enter `Your VPN Server IP` (or DNS name) in the **Server** field.   
   **Note:** If you specified the server's DNS name (instead of its IP address) during IKEv2 setup, you must enter the DNS name in the **Server** field.
1. Select **IKEv2 Certificate** from the **VPN Type** drop-down menu.
1. Tap **Select user certificate**, then tap **Install certificate**.
1. Choose the `.p12` file you transferred from the VPN server, and follow the prompts.   
   **Note:** To find the `.p12` file, tap the three-line menu button, then browse to the location you saved the file.
1. **(Important)** Tap **Show advanced settings**. Scroll down, find and enable the **Use RSA/PSS signatures** option.
1. Save the new VPN connection, then tap to connect.
</details>

Once successfully connected, you can verify that your traffic is being routed properly by <a href="https://www.google.com/search?q=my+ip" target="_blank">looking up your IP address on Google</a>. It should say "Your public IP address is `Your VPN Server IP`".

## Manage client certificates

### List existing clients

If you want to list the names of existing IKEv2 clients, run the [helper script](#using-helper-scripts) with the `--listclients` option.

<details>
<summary>
Click here to view detailed usage information for the IKEv2 helper script.
</summary>

```
Usage: bash ikev2.sh [options]

Options:
  --auto                        run IKEv2 setup in auto mode using default options (for initial IKEv2 setup only)
  --addclient [client name]     add a new IKEv2 client using default options (after IKEv2 setup)
  --exportclient [client name]  export an existing IKEv2 client using default options (after IKEv2 setup)
  --listclients                 list the names of existing IKEv2 clients (after IKEv2 setup)
  -h, --help                    show this help message and exit

To customize IKEv2 or client options, run this script without arguments.
```
</details>

### Add a client certificate

To generate certificates for additional IKEv2 clients, just run the [helper script](#using-helper-scripts) again. Refer to the usage information above. Or you may refer to step 4 in [this section](#manually-set-up-ikev2-on-the-vpn-server).

### Export configuration for an existing client

By default, the [IKEv2 helper script](#using-helper-scripts) exports client configuration after running. If later you want to export configuration for an existing client, run the helper script again and select the appropriate option. Refer to the usage information above.

### Revoke a client certificate

In certain circumstances, you may need to revoke a previously generated VPN client certificate. This can be done using `crlutil`. See example steps below, commands must be run as `root`.

1. Check the database, and identify the nickname of the client certificate you want to revoke.

   ```bash
   certutil -L -d sql:/etc/ipsec.d
   ```

   ```
   Certificate Nickname                               Trust Attributes
                                                      SSL,S/MIME,JAR/XPI

   IKEv2 VPN CA                                       CTu,u,u
   ($PUBLIC_IP)                                       u,u,u
   vpnclient-to-revoke                                u,u,u
   ```

   In this example, we will revoke the certificate with nickname `vpnclient-to-revoke`, issued by `IKEv2 VPN CA`.

1. Find the serial number of this client certificate.

   ```bash
   certutil -L -d sql:/etc/ipsec.d -n "vpnclient-to-revoke"
   ```

   ```
   Certificate:
       Data:
           Version: 3 (0x2)
           Serial Number:
               00:cd:69:ff:74
   ... ...
   ```

   From the output, we see that the serial number is `CD69FF74` in hexadecimal, which is `3446275956` in decimal. It will be used in the next steps.

1. Create a new Certificate Revocation List (CRL). You only need to do this once for each CA.

   ```bash
   if ! crlutil -L -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" 2>/dev/null; then
     crlutil -G -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" -c /dev/null
   fi
   ```

   ```
   CRL Info:
   :
       Version: 2 (0x1)
       Signature Algorithm: PKCS #1 SHA-256 With RSA Encryption
       Issuer: "O=IKEv2 VPN,CN=IKEv2 VPN CA"
       This Update: Sat Jun 06 22:00:00 2020
       CRL Extensions:
   ```

1. Add the client certificate you want to revoke to the CRL. Here we specify the certificate's serial number in decimal, and the revocation time in GeneralizedTime format (YYYYMMDDhhmmssZ) in UTC.

   ```bash
   crlutil -M -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" <<EOF
   addcert 3446275956 20200606220100Z
   EOF
   ```

   ```
   CRL Info:
   :
       Version: 2 (0x1)
       Signature Algorithm: PKCS #1 SHA-256 With RSA Encryption
       Issuer: "O=IKEv2 VPN,CN=IKEv2 VPN CA"
       This Update: Sat Jun 06 22:02:00 2020
       Entry 1 (0x1):
           Serial Number:
               00:cd:69:ff:74
           Revocation Date: Sat Jun 06 22:01:00 2020
       CRL Extensions:
   ```

   **Note:** If you want to remove a certificate from the CRL, replace `addcert 3446275956 20200606220100Z` above with `rmcert 3446275956`. For other `crlutil` usage, read <a href="https://developer.mozilla.org/en-US/docs/Mozilla/Projects/NSS/tools/NSS_Tools_crlutil" target="_blank">here</a>.

1. Finally, let Libreswan re-read the updated CRL.

   ```bash
   ipsec crls
   ```

## Manually set up IKEv2 on the VPN server

As an alternative to using the [helper script](#using-helper-scripts), advanced users can manually set up IKEv2. The following example shows how to manually configure IKEv2 with Libreswan. Commands below must be run as `root`.

1. Find the VPN server's public IP, save it to a variable and check.

   ```bash
   PUBLIC_IP=$(dig @resolver1.opendns.com -t A -4 myip.opendns.com +short)
   [ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(wget -t 3 -T 15 -qO- http://ipv4.icanhazip.com)
   printf '%s\n' "$PUBLIC_IP"
   ```

   Check to make sure the output matches the server's public IP. This variable is required in the steps below.

   **Note:** Alternatively, you may specify the server's DNS name here. e.g. `PUBLIC_IP=myvpn.example.com`.

1. Add a new IKEv2 connection:

   ```bash
   if ! grep -qs '^include /etc/ipsec\.d/\*\.conf$' /etc/ipsec.conf; then
     echo >> /etc/ipsec.conf
     echo 'include /etc/ipsec.d/*.conf' >> /etc/ipsec.conf
   fi
   ```

   ```bash
   cat > /etc/ipsec.d/ikev2.conf <<EOF

   conn ikev2-cp
     left=%defaultroute
     leftcert=$PUBLIC_IP
     leftid=@$PUBLIC_IP
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
     fragmentation=yes
     ike=aes256-sha2,aes128-sha2,aes256-sha1,aes128-sha1,aes256-sha2;modp1024,aes128-sha1;modp1024
     phase2alg=aes_gcm-null,aes128-sha1,aes256-sha1,aes128-sha2,aes256-sha2
     ikelifetime=24h
     salifetime=24h
   EOF
   ```

   We need to add a few more lines to that file. First check your Libreswan version, then run one of the following commands:

   ```bash
   ipsec --version
   ```

   For Libreswan 3.23 and newer:

   ```bash
   cat >> /etc/ipsec.d/ikev2.conf <<EOF
     modecfgdns="8.8.8.8 8.8.4.4"
     encapsulation=yes
     mobike=no
   EOF
   ```

   **Note:** The <a href="https://wiki.strongswan.org/projects/strongswan/wiki/MobIke" target="_blank">MOBIKE</a> IKEv2 extension allows VPN clients to change network attachment points, e.g. switch between mobile data and Wi-Fi and keep the IPsec tunnel up on the new IP. If your server (or Docker host) is **NOT** running Ubuntu Linux, and you wish to enable MOBIKE support, replace `mobike=no` with `mobike=yes` in the command above. **DO NOT** enable this option on Ubuntu systems or Raspberry Pis.

   For Libreswan 3.19-3.22:

   ```bash
   cat >> /etc/ipsec.d/ikev2.conf <<EOF
     modecfgdns1=8.8.8.8
     modecfgdns2=8.8.4.4
     encapsulation=yes
   EOF
   ```

   For Libreswan 3.18 and older:

   ```bash
   cat >> /etc/ipsec.d/ikev2.conf <<EOF
     modecfgdns1=8.8.8.8
     modecfgdns2=8.8.4.4
     forceencaps=yes
   EOF
   ```

1. Generate Certificate Authority (CA) and VPN server certificates.

   **Note:** Specify the certificate validity period (in months) with "-v". e.g. "-v 120".

   Generate CA certificate:

   ```bash
   certutil -z <(head -c 1024 /dev/urandom) \
     -S -x -n "IKEv2 VPN CA" \
     -s "O=IKEv2 VPN,CN=IKEv2 VPN CA" \
     -k rsa -g 4096 -v 120 \
     -d sql:/etc/ipsec.d -t "CT,," -2
   ```

   ```
   Generating key.  This may take a few moments...

   Is this a CA certificate [y/N]?
   y
   Enter the path length constraint, enter to skip [<0 for unlimited path]: >
   Is this a critical extension [y/N]?
   N
   ```

   Generate VPN server certificate:

   **Note:** If you specified the server's DNS name (instead of its IP address) in step 1 above, you must replace `--extSAN "ip:$PUBLIC_IP,dns:$PUBLIC_IP"` in the command below with `--extSAN "dns:$PUBLIC_IP"`.

   ```bash
   certutil -z <(head -c 1024 /dev/urandom) \
     -S -c "IKEv2 VPN CA" -n "$PUBLIC_IP" \
     -s "O=IKEv2 VPN,CN=$PUBLIC_IP" \
     -k rsa -g 4096 -v 120 \
     -d sql:/etc/ipsec.d -t ",," \
     --keyUsage digitalSignature,keyEncipherment \
     --extKeyUsage serverAuth \
     --extSAN "ip:$PUBLIC_IP,dns:$PUBLIC_IP"
   ```

   ```
   Generating key.  This may take a few moments...
   ```

1. Generate client certificate(s), then export the `.p12` file that contains the client certificate, private key, and CA certificate.

   **Note:** You may repeat this step to generate certificates for additional VPN clients, but make sure to replace every `vpnclient` with `vpnclient2`, etc. To connect multiple VPN clients simultaneously, you must generate a unique certificate for each.

   Generate client certificate:

   ```bash
   certutil -z <(head -c 1024 /dev/urandom) \
     -S -c "IKEv2 VPN CA" -n "vpnclient" \
     -s "O=IKEv2 VPN,CN=vpnclient" \
     -k rsa -g 4096 -v 120 \
     -d sql:/etc/ipsec.d -t ",," \
     --keyUsage digitalSignature,keyEncipherment \
     --extKeyUsage serverAuth,clientAuth -8 "vpnclient"
   ```

   ```
   Generating key.  This may take a few moments...
   ```

   Export `.p12` file:

   ```bash
   pk12util -d sql:/etc/ipsec.d -n "vpnclient" -o vpnclient.p12
   ```

   ```
   Enter password for PKCS12 file:
   Re-enter password:
   pk12util: PKCS12 EXPORT SUCCESSFUL
   ```

   Enter a secure password to protect the exported `.p12` file (when importing into an iOS or macOS device, this password cannot be empty).

1. (For iOS clients) Export the CA certificate as `ikev2vpnca.cer`:

   ```bash
   certutil -L -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" -a -o ikev2vpnca.cer
   ```

1. The database should now contain:

   ```bash
   certutil -L -d sql:/etc/ipsec.d
   ```

   ```
   Certificate Nickname                               Trust Attributes
                                                      SSL,S/MIME,JAR/XPI

   IKEv2 VPN CA                                       CTu,u,u
   ($PUBLIC_IP)                                       u,u,u
   vpnclient                                          u,u,u
   ```

   **Note:** To display a certificate, use `certutil -L -d sql:/etc/ipsec.d -n "Nickname"`. To revoke a client certificate, follow [these steps](#revoke-a-client-certificate). For other `certutil` usage, read <a href="https://developer.mozilla.org/en-US/docs/Mozilla/Projects/NSS/tools/NSS_Tools_certutil" target="_blank">here</a>.

1. **(Important) Restart the IPsec service**:

   ```bash
   service ipsec restart
   ```

Before continuing, you **must** restart the IPsec service. The IKEv2 setup on the VPN server is now complete. Follow instructions to [configure VPN clients](#configure-ikev2-vpn-clients).

## Known issues

1. The built-in VPN client in Windows may not support IKEv2 fragmentation (this feature <a href="https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-ikee/74df968a-7125-431d-9c98-4ea929e548dc" target="_blank">requires</a> Windows 10 v1803 or newer). On some networks, this can cause the connection to fail or have other issues. You may instead try the <a href="clients.md" target="_blank">IPsec/L2TP</a> or <a href="clients-xauth.md" target="_blank">IPsec/XAuth</a> mode.
1. Ubuntu 18.04 users may encounter the error "The password you entered is incorrect" when trying to import the generated `.p12` file into Windows. This is due to a bug in `NSS`. Read more <a href="https://github.com/hwdsl2/setup-ipsec-vpn/issues/414#issuecomment-460495258" target="_blank">here</a>.
   <details>
   <summary>
   Workaround for the NSS bug on Ubuntu 18.04
   </summary>

   **Note:** This workaround should only be used on Ubuntu 18.04 systems running on the `x86_64` architecture. As of 2021-01-21, the IKEv2 helper script was updated to automatically apply this workaround.

   First, install newer versions of `libnss3` related packages:

   ```
   wget https://mirrors.kernel.org/ubuntu/pool/main/n/nss/libnss3_3.49.1-1ubuntu1.5_amd64.deb
   wget https://mirrors.kernel.org/ubuntu/pool/main/n/nss/libnss3-dev_3.49.1-1ubuntu1.5_amd64.deb
   wget https://mirrors.kernel.org/ubuntu/pool/universe/n/nss/libnss3-tools_3.49.1-1ubuntu1.5_amd64.deb
   apt-get -y update
   apt-get -y install "./libnss3_3.49.1-1ubuntu1.5_amd64.deb" \
     "./libnss3-dev_3.49.1-1ubuntu1.5_amd64.deb" \
     "./libnss3-tools_3.49.1-1ubuntu1.5_amd64.deb"
   ```

   After that, [export configuration for the IKEv2 client](#export-configuration-for-an-existing-client) again.
   </details>
1. If using the strongSwan Android VPN client, you must <a href="../README.md#upgrade-libreswan" target="_blank">upgrade Libreswan</a> on your server to version 3.26 or above.

## Remove IKEv2

If you want to remove IKEv2 from the VPN server, but keep the [IPsec/L2TP](clients.md) and [IPsec/XAuth ("Cisco IPsec")](clients-xauth.md) modes, run the [helper script](#using-helper-scripts) again and select the "Remove IKEv2" option. Note that this will delete all IKEv2 configuration including certificates, and **cannot be undone**!

<details>
<summary>
Alternatively, you can manually remove IKEv2. Click here for instructions.
</summary>

To manually remove IKEv2 from the VPN server, but keep the [IPsec/L2TP](clients.md) and [IPsec/XAuth ("Cisco IPsec")](clients-xauth.md) modes, follow these steps. Commands must be run as `root`. Note that this will delete all IKEv2 configuration including certificates, and **cannot be undone**!

1. Rename (or delete) the IKEv2 config file:

   ```bash
   mv /etc/ipsec.d/ikev2.conf /etc/ipsec.d/ikev2.conf.bak
   ```

   **Note:** If you used an older version (before 2020-05-31) of the IKEv2 helper script or instructions, file `/etc/ipsec.d/ikev2.conf` may not exist. In this case, please instead remove the `conn ikev2-cp` section from file `/etc/ipsec.conf`.

1. **(Important) Restart the IPsec service**:

   ```bash
   service ipsec restart
   ```

1. List certificates in the IPsec database:

   ```bash
   certutil -L -d sql:/etc/ipsec.d
   ```

   Example output:

   ```
   Certificate Nickname                               Trust Attributes
                                                      SSL,S/MIME,JAR/XPI

   IKEv2 VPN CA                                       CTu,u,u
   ($PUBLIC_IP)                                       u,u,u
   vpnclient                                          u,u,u
   ```

1. Delete certificates. Replace "Nickname" below with each certificate's nickname. Repeat for each certificate. When finished, list certificates in the IPsec database again, and confirm that the list is empty.

   ```bash
   certutil -D -d sql:/etc/ipsec.d -n "Nickname"
   ```
</details>

## References

* https://libreswan.org/wiki/VPN_server_for_remote_clients_using_IKEv2
* https://libreswan.org/wiki/HOWTO:_Using_NSS_with_libreswan
* https://libreswan.org/man/ipsec.conf.5.html
* https://wiki.strongswan.org/projects/strongswan/wiki/WindowsClients
* https://wiki.strongswan.org/projects/strongswan/wiki/AndroidVpnClient
* https://developer.mozilla.org/en-US/docs/Mozilla/Projects/NSS/tools/NSS_Tools_certutil
* https://developer.mozilla.org/en-US/docs/Mozilla/Projects/NSS/tools/NSS_Tools_crlutil
