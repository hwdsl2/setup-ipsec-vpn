[English](ikev2-howto.md) | [中文](ikev2-howto-zh.md)

# Guide: How to Set Up and Use IKEv2 VPN

* [Introduction](#introduction)
* [Configure IKEv2 VPN clients](#configure-ikev2-vpn-clients)
* [IKEv2 troubleshooting](#ikev2-troubleshooting)
* [Manage IKEv2 clients](#manage-ikev2-clients)
* [Change IKEv2 server address](#change-ikev2-server-address)
* [Update IKEv2 helper script](#update-ikev2-helper-script)
* [Set up IKEv2 using helper script](#set-up-ikev2-using-helper-script)
* [Manually set up IKEv2](#manually-set-up-ikev2)
* [Remove IKEv2](#remove-ikev2)

## Introduction

Modern operating systems support the IKEv2 standard. Internet Key Exchange (IKE or IKEv2) is the protocol used to set up a Security Association (SA) in the IPsec protocol suite. Compared to IKE version 1, IKEv2 contains [improvements](https://en.wikipedia.org/wiki/Internet_Key_Exchange#Improvements_with_IKEv2) such as Standard Mobility support through MOBIKE, and improved reliability.

Libreswan can authenticate IKEv2 clients on the basis of X.509 Machine Certificates using RSA signatures. This method does not require an IPsec PSK, username or password. It can be used with Windows, macOS, iOS, Android, Chrome OS, Linux and RouterOS.

By default, IKEv2 is automatically set up when running the VPN setup script. If you want to learn more about setting up IKEv2, see [Set up IKEv2 using helper script](#set-up-ikev2-using-helper-script). Docker users, see [Configure and use IKEv2 VPN](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README.md#configure-and-use-ikev2-vpn).

## Configure IKEv2 VPN clients

**Note:** To add or export IKEv2 clients, run `sudo ikev2.sh`. Use `-h` to show usage. Client config files can be safely deleted after import.

* [Windows 7, 8, 10 and 11](#windows-7-8-10-and-11)
* [OS X (macOS)](#os-x-macos)
* [iOS (iPhone/iPad)](#ios)
* [Android](#android)
* [Chrome OS (Chromebook)](#chrome-os)
* [Linux](#linux)
* [Mikrotik RouterOS](#routeros)

<details>
<summary>
Learn how to change the IKEv2 server address.
</summary>

In certain circumstances, you may need to change the IKEv2 server address. For example, to switch to use a DNS name, or after server IP changes. Learn more in [this section](#change-ikev2-server-address).
</details>

### Windows 7, 8, 10 and 11

#### Auto-import configuration

[**Screencast:** IKEv2 Auto Import Configuration on Windows](https://ko-fi.com/post/IKEv2-Auto-Import-Configuration-on-Windows-8-10-a-K3K1DQCHW)

**Windows 8, 10 and 11** users can automatically import IKEv2 configuration:

1. Securely transfer the generated `.p12` file to your computer.
1. Right-click on [ikev2_config_import.cmd](https://github.com/hwdsl2/vpn-extras/releases/latest/download/ikev2_config_import.cmd) and save this helper script to the **same folder** as the `.p12` file.
1. Right-click on the saved script, select **Properties**. Click on **Unblock** at the bottom, then click on **OK**.
1. Right-click on the saved script, select **Run as administrator** and follow the prompts.

To connect to the VPN: Click on the wireless/network icon in your system tray, select the new VPN entry, and click **Connect**. Once connected, you can verify that your traffic is being routed properly by [looking up your IP address on Google](https://www.google.com/search?q=my+ip). It should say "Your public IP address is `Your VPN Server IP`".

If you get an error when trying to connect, see [Troubleshooting](#ikev2-troubleshooting).

#### Manually import configuration

[[Supporters] **Screencast:** IKEv2 Manually Import Configuration on Windows](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-O5O7FVF8J)

Alternatively, **Windows 7, 8, 10 and 11** users can manually import IKEv2 configuration:

1. Securely transfer the generated `.p12` file to your computer, then import it into the certificate store.

   To import the `.p12` file, run the following from an [elevated command prompt](http://www.winhelponline.com/blog/open-elevated-command-prompt-windows/):

   ```console
   # Import .p12 file (replace with your own value)
   certutil -f -importpfx "\path\to\your\file.p12" NoExport
   ```

   **Note:** If there is no password for client config files, press Enter to continue, or if manually importing the `.p12` file, leave the password field blank.

   Alternatively, you can [manually import the .p12 file](https://wiki.strongswan.org/projects/strongswan/wiki/Win7Certs/9). Make sure that the client cert is placed in "Personal -> Certificates", and the CA cert is placed in "Trusted Root Certification Authorities -> Certificates".

1. On the Windows computer, add a new IKEv2 VPN connection.

   For **Windows 8, 10 and 11**, it is recommended to create the VPN connection using the following commands from a command prompt, for improved security and performance.

   ```console
   # Create VPN connection (replace server address with your own value)
   powershell -command ^"Add-VpnConnection -ServerAddress 'Your VPN Server IP (or DNS name)' ^
     -Name 'My IKEv2 VPN' -TunnelType IKEv2 -AuthenticationMethod MachineCertificate ^
     -EncryptionLevel Required -PassThru^"
   # Set IPsec configuration
   powershell -command ^"Set-VpnConnectionIPsecConfiguration -ConnectionName 'My IKEv2 VPN' ^
     -AuthenticationTransformConstants GCMAES128 -CipherTransformConstants GCMAES128 ^
     -EncryptionMethod AES256 -IntegrityCheckMethod SHA256 -PfsGroup None ^
     -DHGroup Group14 -PassThru -Force^"
   ```

   **Windows 7** does not support these commands, you can [manually create the VPN connection](https://wiki.strongswan.org/projects/strongswan/wiki/Win7Config/8).

   **Note:** The server address you specify must **exactly match** the server address in the output of the IKEv2 helper script. For example, if you specified the server's DNS name during IKEv2 setup, you must enter the DNS name in the **Internet address** field.

1. **This step is required if you manually created the VPN connection.**

   Enable stronger ciphers for IKEv2 with a one-time registry change. Download and import the `.reg` file below, or run the following from an elevated command prompt. Read more [here](https://docs.strongswan.org/docs/5.9/interop/windowsClients.html).

   - For Windows 7, 8, 10 and 11 ([download .reg file](https://github.com/hwdsl2/vpn-extras/releases/download/v1.0.0/Enable_Stronger_Ciphers_for_IKEv2_on_Windows.reg))

     ```console
     REG ADD HKLM\SYSTEM\CurrentControlSet\Services\RasMan\Parameters /v NegotiateDH2048_AES256 /t REG_DWORD /d 0x1 /f
     ```

To connect to the VPN: Click on the wireless/network icon in your system tray, select the new VPN entry, and click **Connect**. Once connected, you can verify that your traffic is being routed properly by [looking up your IP address on Google](https://www.google.com/search?q=my+ip). It should say "Your public IP address is `Your VPN Server IP`".

If you get an error when trying to connect, see [Troubleshooting](#ikev2-troubleshooting).

<details>
<summary>
Remove the IKEv2 VPN connection.
</summary>

Using the following steps, you can remove the VPN connection and optionally restore the computer to the status before IKEv2 configuration import.

1. Remove the added VPN connection in Windows Settings - Network - VPN. Windows 7 users can remove the VPN connection in Network and Sharing Center - Change adapter settings.

1. (Optional) Remove IKEv2 certificates.

   1. Press Win+R, or search for `mmc` in the Start Menu. Open *Microsoft Management Console*.

   1. Open `File - Add/Remove Snap-In`. Select to add `Certificates` and in the window that opens, select `Computer account -> Local Computer`. Click on `Finish -> OK` to save the settings.

   1. Go to `Certificates - Personal - Certificates` and delete the IKEv2 client certificate. The name of the certificate is the same as the IKEv2 client name you specified (default: `vpnclient`). The certificate was issued by `IKEv2 VPN CA`.

   1. Go to `Certificates - Trusted Root Certification Authorities - Certificates` and delete the IKEv2 VPN CA certificate. The certificate was issued to `IKEv2 VPN CA` by `IKEv2 VPN CA`. Before deleting, make sure that there are no other certificate(s) issued by `IKEv2 VPN CA` in `Certificates - Personal - Certificates`.

1. (Optional. For users who manually created the VPN connection) Restore registry settings. Note that you should backup the registry before editing.

   1. Press Win+R, or search for `regedit` in the Start Menu. Open *Registry Editor*.

   1. Go to `HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Rasman\Parameters` and delete the item with name `NegotiateDH2048_AES256`, if it exists.
</details>

### OS X (macOS)

[[Supporters] **Screencast:** IKEv2 Import Configuration and Connect on macOS](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-O5O7FVF8J)

First, securely transfer the generated `.mobileconfig` file to your Mac, then double-click and follow the prompts to import as a macOS profile. If your Mac runs macOS Big Sur or newer, open System Preferences and go to the Profiles section to finish importing. For macOS Ventura and newer, open System Settings and search for Profiles. When finished, check to make sure "IKEv2 VPN" is listed under System Preferences -> Profiles.

To connect to the VPN:

1. Open System Preferences and go to the Network section.
1. Select the VPN connection with `Your VPN Server IP` (or DNS name).
1. Check the **Show VPN status in menu bar** checkbox. For macOS Ventura and newer, this setting can be configured in System Settings -> Control Center -> Menu Bar Only section.
1. Click **Connect**, or slide the VPN switch ON.

(Optional feature) Enable **VPN On Demand** to automatically start a VPN connection when your Mac is on Wi-Fi. To enable, check the **Connect on demand** checkbox for the VPN connection, and click **Apply**. To find this setting on macOS Ventura and newer, click on the "i" icon on the right of the VPN connection.

You can customize VPN On Demand rules to exclude certain Wi-Fi networks (such as your home network). For more information, see the chapter "Guide: Customize IKEv2 VPN On Demand rules for macOS and iOS" in [:book: Book: Set Up Your Own IPsec VPN, OpenVPN and WireGuard Server](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-O5O7FVF8J).

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

Once connected, you can verify that your traffic is being routed properly by [looking up your IP address on Google](https://www.google.com/search?q=my+ip). It should say "Your public IP address is `Your VPN Server IP`".

If you get an error when trying to connect, see [Troubleshooting](#ikev2-troubleshooting).

**Note:** macOS 14 (Sonoma) has a minor issue that may cause IKEv2 VPN to disconnect and reconnect once every 24-48 minutes. Other macOS versions are not affected. For more details and a workaround, see [macOS Sonoma clients reconnect](#macos-sonoma-clients-reconnect).

<details>
<summary>
Remove the IKEv2 VPN connection.
</summary>

To remove the IKEv2 VPN connection, open System Preferences -> Profiles and remove the IKEv2 VPN profile you added.
</details>

### iOS

[[Supporters] **Screencast:** IKEv2 Import Configuration and Connect on iOS (iPhone & iPad)](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-O5O7FVF8J)

First, securely transfer the generated `.mobileconfig` file to your iOS device, then import it as an iOS profile. To transfer the file, you may use:

1. AirDrop, or
1. Upload to your device (any App folder) using [File Sharing](https://support.apple.com/en-us/HT210598), then open the "Files" App on your iOS device, move the uploaded file to the "On My iPhone" folder. After that, tap the file and go to the "Settings" App to import, or
1. Host the file on a secure website of yours, then download and import it in Mobile Safari.

When finished, check to make sure "IKEv2 VPN" is listed under Settings -> General -> VPN & Device Management or Profile(s).

To connect to the VPN:

1. Go to Settings -> VPN. Select the VPN connection with `Your VPN Server IP` (or DNS name).
1. Slide the **VPN** switch ON.

(Optional feature) Enable **VPN On Demand** to automatically start a VPN connection when your iOS device is on Wi-Fi. To enable, tap the "i" icon on the right of the VPN connection, and enable **Connect On Demand**.

You can customize VPN On Demand rules to exclude certain Wi-Fi networks (such as your home network). For more information, see the chapter "Guide: Customize IKEv2 VPN On Demand rules for macOS and iOS" in [:book: Book: Set Up Your Own IPsec VPN, OpenVPN and WireGuard Server](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-O5O7FVF8J).

<details>
<summary>
Customize VPN On Demand rules: Connect on Wi-Fi and cellular networks.
</summary>

The default VPN On Demand configuration only starts a VPN connection on Wi-Fi networks, but not on cellular networks. If you want the VPN to connect on both Wi-Fi and cellular networks:

1. Edit `/opt/src/ikev2.sh` on the VPN server. Find the lines:
   ```
     <dict>
       <key>InterfaceTypeMatch</key>
       <string>Cellular</string>
       <key>Action</key>
       <string>Disconnect</string>
     </dict>
   ```
   and replace "Disconnect" with "Connect":
   ```
     <dict>
       <key>InterfaceTypeMatch</key>
       <string>Cellular</string>
       <key>Action</key>
       <string>Connect</string>
     </dict>
   ```
2. Save the file, then run `sudo ikev2.sh` to export updated client config files for your iOS device(s).
3. Remove the previously imported VPN profile from your iOS device(s), then import the new `.mobileconfig` file(s) from step 2.
</details>
<details>
<summary>
If you manually set up IKEv2 without using the helper script, click here for instructions.
</summary>

First, securely transfer the generated `ca.cer` and `.p12` files to your iOS device, then import them one by one as iOS profiles. To transfer the files, you may use:

1. AirDrop, or
1. Upload to your device (any App folder) using [File Sharing](https://support.apple.com/en-us/HT210598), then open the "Files" App on your iOS device, move the uploaded files to the "On My iPhone" folder. After that, tap each file and go to the "Settings" App to import, or
1. Host the files on a secure website of yours, then download and import them in Mobile Safari.

When finished, check to make sure both the new client certificate and `IKEv2 VPN CA` are listed under Settings -> General -> VPN & Device Management or Profile(s).

1. Go to Settings -> General -> VPN & Device Management -> VPN.
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

Once connected, you can verify that your traffic is being routed properly by [looking up your IP address on Google](https://www.google.com/search?q=my+ip). It should say "Your public IP address is `Your VPN Server IP`".

If you get an error when trying to connect, see [Troubleshooting](#ikev2-troubleshooting).

<details>
<summary>
Remove the IKEv2 VPN connection.
</summary>

To remove the IKEv2 VPN connection, open Settings -> General -> VPN & Device Management or Profile(s) and remove the IKEv2 VPN profile you added.
</details>

### Android

#### Using strongSwan VPN client

[[Supporters] **Screencast:** Connect using Android strongSwan VPN Client](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-O5O7FVF8J)

Android users can connect using strongSwan VPN client (recommended).

1. Securely transfer the generated `.sswan` file to your Android device.
1. Install strongSwan VPN Client from [**Google Play**](https://play.google.com/store/apps/details?id=org.strongswan.android), [**F-Droid**](https://f-droid.org/en/packages/org.strongswan.android/) or [**strongSwan download server**](https://download.strongswan.org/Android/).
1. Launch the strongSwan VPN client.
1. Tap the "more options" menu on top right, then tap **Import VPN profile**.
1. Choose the `.sswan` file you transferred from the VPN server.   
   **Note:** To find the `.sswan` file, tap the three-line menu button, then browse to the location you saved the file.
1. On the "Import VPN profile" screen, tap **IMPORT CERTIFICATE FROM VPN PROFILE**, and follow the prompts.
1. On the "Choose certificate" screen, select the new client certificate, then tap **Select**.
1. Tap **IMPORT**.
1. Tap the new VPN profile to connect.

(Optional feature) You can choose to enable the "Always-on VPN" feature on Android. Launch the **Settings** app, go to Network & internet -> Advanced -> VPN, click the gear icon on the right of "strongSwan VPN Client", then enable the **Always-on VPN** and **Block connections without VPN** options.

<details>
<summary>
If your device runs Android 6.0 or older, click here for additional instructions.
</summary>

If your device runs Android 6.0 (Marshmallow) or older, in order to connect using the strongSwan VPN client, you must make the following change on the VPN server: Edit `/etc/ipsec.d/ikev2.conf` on the server. Append `authby=rsa-sha1` to the end of the `conn ikev2-cp` section, indented by two spaces. Save the file and run `service ipsec restart`.
</details>
<details>
<summary>
If you manually set up IKEv2 without using the helper script, click here for instructions.
</summary>

**Android 10 and newer:**

1. Securely transfer the generated `.p12` file to your Android device.
1. Install strongSwan VPN Client from [**Google Play**](https://play.google.com/store/apps/details?id=org.strongswan.android), [**F-Droid**](https://f-droid.org/en/packages/org.strongswan.android/) or [**strongSwan download server**](https://download.strongswan.org/Android/).
1. Launch the **Settings** application.
1. Go to Security -> Advanced -> Encryption & credentials.
1. Tap **Install a certificate**.
1. Tap **VPN & app user certificate**.
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
1. Install strongSwan VPN Client from [**Google Play**](https://play.google.com/store/apps/details?id=org.strongswan.android), [**F-Droid**](https://f-droid.org/en/packages/org.strongswan.android/) or [**strongSwan download server**](https://download.strongswan.org/Android/).
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

Once connected, you can verify that your traffic is being routed properly by [looking up your IP address on Google](https://www.google.com/search?q=my+ip). It should say "Your public IP address is `Your VPN Server IP`".

If you get an error when trying to connect, see [Troubleshooting](#ikev2-troubleshooting).

#### Using native IKEv2 client

[[Supporters] **Screencast:** Connect using Native VPN Client on Android 11+](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-O5O7FVF8J)

Android 11+ users can also connect using the native IKEv2 client.

1. Securely transfer the generated `.p12` file to your Android device.
1. Launch the **Settings** application.
1. Go to Security -> Advanced -> Encryption & credentials.
1. Tap **Install a certificate**.
1. Tap **VPN & app user certificate**.
1. Choose the `.p12` file you transferred from the VPN server.   
   **Note:** To find the `.p12` file, tap the three-line menu button, then browse to the location you saved the file.
1. Enter a name for the certificate, then tap **OK**.
1. Go to Settings -> Network & internet -> VPN, then tap the "+" button.
1. Enter a name for the VPN profile.
1. Select **IKEv2/IPSec RSA** from the **Type** drop-down menu.
1. Enter `Your VPN Server IP` (or DNS name) in the **Server address** field.   
   **Note:** This must **exactly match** the server address in the output of the IKEv2 helper script.
1. Enter anything (e.g. `empty`) in the **IPSec identifier** field.   
   **Note:** This field should not be required. It is a bug in Android.
1. Select the certificate you imported from the **IPSec user certificate** drop-down menu.
1. Select the certificate you imported from the **IPSec CA certificate** drop-down menu.
1. Select **(receive from server)** from the **IPSec server certificate** drop-down menu.
1. Tap **Save**. Then tap the new VPN connection and tap **Connect**.

Once connected, you can verify that your traffic is being routed properly by [looking up your IP address on Google](https://www.google.com/search?q=my+ip). It should say "Your public IP address is `Your VPN Server IP`".

If you get an error when trying to connect, see [Troubleshooting](#ikev2-troubleshooting).

### Chrome OS

First, on your VPN server, export the CA certificate as `ca.cer`:

```bash
sudo certutil -L -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" -a -o ca.cer
```

Securely transfer the generated `.p12` and `ca.cer` files to your Chrome OS device.

Install user and CA certificates:

1. Open a new tab in Google Chrome.
1. In the address bar, enter **chrome://settings/certificates**
1. **(Important)** Click **Import and Bind**, not **Import**.
1. In the box that opens, choose the `.p12` file you transferred from the VPN server and select **Open**.
1. Click **OK** if the certificate does not have a password. Otherwise, enter the certificate's password.
1. Click the **Authorities** tab. Then click **Import**.
1. In the box that opens, select **All files** in the drop-down menu at the bottom left.
1. Choose the `ca.cer` file you transferred from the VPN server and select **Open**.
1. Keep the default options and click **OK**.

Add a new VPN connection:

1. Go to Settings -> Network.
1. Click **Add connection**, then click **Add built-in VPN**.
1. Enter anything you like for the **Service name**.
1. Select **IPsec (IKEv2)** in the **Provider type** drop-down menu.
1. Enter `Your VPN Server IP` (or DNS name) for the **Server hostname**.
1. Select **User certificate** in the **Authentication type** drop-down menu.
1. Select **IKEv2 VPN CA [IKEv2 VPN CA]** in the **Server CA certificate** drop-down menu.
1. Select **IKEv2 VPN CA [client name]** in the **User certificate** drop-down menu.
1. Leave other fields blank.
1. Enable **Save identity and password**.
1. Click **Connect**.

Once connected, you will see a VPN icon overlay on the network status icon. You can verify that your traffic is being routed properly by [looking up your IP address on Google](https://www.google.com/search?q=my+ip). It should say "Your public IP address is `Your VPN Server IP`".

(Optional feature) You can choose to enable the "Always-on VPN" feature on Chrome OS. To manage this setting, go to Settings -> Network, then click **VPN**.

If you get an error when trying to connect, see [Troubleshooting](#ikev2-troubleshooting).

### Linux

Before configuring Linux VPN clients, you must make the following change on the VPN server: Edit `/etc/ipsec.d/ikev2.conf` on the server. Append `authby=rsa-sha1` to the end of the `conn ikev2-cp` section, indented by two spaces. Save the file and run `service ipsec restart`.

To configure your Linux computer to connect to IKEv2 as a VPN client, first install the strongSwan plugin for NetworkManager:

```bash
# Ubuntu and Debian
sudo apt-get update
sudo apt-get install network-manager-strongswan

# Arch Linux
sudo pacman -Syu  # upgrade all packages
sudo pacman -S networkmanager-strongswan

# Fedora
sudo yum install NetworkManager-strongswan-gnome

# CentOS
sudo yum install epel-release
sudo yum --enablerepo=epel install NetworkManager-strongswan-gnome
```

Next, securely transfer the generated `.p12` file from the VPN server to your Linux computer. After that, extract the CA certificate, client certificate and private key. Replace `vpnclient.p12` in the example below with the name of your `.p12` file.

```bash
# Example: Extract CA certificate, client certificate and private key.
#          You may delete the .p12 file when finished.
# Note: You may need to enter the import password, which can be found
#       in the output of the IKEv2 helper script. If the output does not
#       contain an import password, press Enter to continue.
# Note: If using OpenSSL 3.x (run "openssl version" to check),
#       append "-legacy" to the 3 commands below.
openssl pkcs12 -in vpnclient.p12 -cacerts -nokeys -out ca.cer
openssl pkcs12 -in vpnclient.p12 -clcerts -nokeys -out client.cer
openssl pkcs12 -in vpnclient.p12 -nocerts -nodes  -out client.key
rm vpnclient.p12

# (Important) Protect certificate and private key files
# Note: This step is optional, but strongly recommended.
sudo chown root:root ca.cer client.cer client.key
sudo chmod 600 ca.cer client.cer client.key
```

You can then set up and enable the VPN connection:

1. Go to Settings -> Network -> VPN. Click the **+** button.
1. Select **IPsec/IKEv2 (strongswan)**.
1. Enter anything you like in the **Name** field.
1. In the **Gateway (Server)** section, enter `Your VPN Server IP` (or DNS name) for the **Address**.
1. Select the `ca.cer` file for the **Certificate**.
1. In the **Client** section, select **Certificate(/private key)** in the **Authentication** drop-down menu.
1. Select **Certificate/private key** in the **Certificate** drop-down menu (if exists).
1. Select the `client.cer` file for the **Certificate (file)**.
1. Select the `client.key` file for the **Private key**.
1. In the **Options** section, check the **Request an inner IP address** checkbox.
1. In the **Cipher proposals (Algorithms)** section, check the **Enable custom proposals** checkbox.
1. Leave the **IKE** field blank.
1. Enter `aes128gcm16` in the **ESP** field.
1. Click **Add** to save the VPN connection information.
1. Turn the **VPN** switch ON.

Alternatively, you may connect using the command line. See [#1399](https://github.com/hwdsl2/setup-ipsec-vpn/issues/1399) and [#1007](https://github.com/hwdsl2/setup-ipsec-vpn/issues/1007) for example steps. If you encounter error `Could not find source connection`, edit `/etc/netplan/01-netcfg.yaml` and replace `renderer: networkd` with `renderer: NetworkManager`, then run `sudo netplan apply`. To connect to the VPN, run `sudo nmcli c up VPN`. To disconnect: `sudo nmcli c down VPN`.

Once connected, you can verify that your traffic is being routed properly by [looking up your IP address on Google](https://www.google.com/search?q=my+ip). It should say "Your public IP address is `Your VPN Server IP`".

If you get an error when trying to connect, see [Troubleshooting](#ikev2-troubleshooting).

### RouterOS

**Note:** These steps were contributed by [@Unix-User](https://github.com/Unix-User). It is recommended to run terminal commands via an SSH connection, e.g. via Putty.

1. Securely transfer the generated `.p12` file to your computer.

   <details>
   <summary>
   Click to see screencast.
   </summary>

   ![routeros get certificate](images/routeros-get-cert.gif)
   </details>

2. In WinBox, go to System > certificates > import. Import the `.p12` certificate file twice (yes, import the same file two times!). Verify in your certificates panel. You will see 2 files, the one that is marked KT is the key.

   <details>
   <summary>
   Click to see screencast.
   </summary>

   ![routeros import certificate](images/routeros-import-cert.gif)
   </details>

   Or you can use terminal instead (empty passphrase):

   ```bash
   [admin@MikroTik] > /certificate/import file-name=mikrotik.p12
   passphrase:

     certificates-imported: 2
     private-keys-imported: 0
            files-imported: 1
       decryption-failures: 0
     keys-with-no-certificate: 0

   [admin@MikroTik] > /certificate/import file-name=mikrotik.p12
   passphrase:

        certificates-imported: 0
        private-keys-imported: 1
               files-imported: 1
          decryption-failures: 0
     keys-with-no-certificate: 0

   ```

3. Run these commands in terminal. Replace the following with your own values.
`YOUR_VPN_SERVER_IP_OR_DNS_NAME` is your VPN server IP or DNS name.
`IMPORTED_CERTIFICATE` is the name of the certificate from step 2 above, e.g. `vpnclient.p12_0`
(the one flagged with KT - Priv. Key Trusted - if not flagged as KT, import certificate again).
`THESE_ADDRESSES_GO_THROUGH_VPN` are the local network addresses that you want to browse through the VPN.
Assuming that your local network behind RouterOS is `192.168.0.0/24`, you can use `192.168.0.0/24`
for the entire network, or use `192.168.0.10` for just one device, and so on.

   ```bash
   /ip firewall address-list add address=THESE_ADDRESSES_GO_THROUGH_VPN list=local
   /ip ipsec mode-config add name=ike2-rw responder=no src-address-list=local
   /ip ipsec policy group add name=ike2-rw
   /ip ipsec profile add name=ike2-rw
   /ip ipsec peer add address=YOUR_VPN_SERVER_IP_OR_DNS_NAME exchange-mode=ike2 \
       name=ike2-rw-client profile=ike2-rw
   /ip ipsec proposal add name=ike2-rw pfs-group=none
   /ip ipsec identity add auth-method=digital-signature certificate=IMPORTED_CERTIFICATE \
       generate-policy=port-strict mode-config=ike2-rw \
       peer=ike2-rw-client policy-template-group=ike2-rw
   /ip ipsec policy add group=ike2-rw proposal=ike2-rw template=yes
   ```
4. For more information, see [#1112](https://github.com/hwdsl2/setup-ipsec-vpn/issues/1112#issuecomment-1059628623).

> tested on   
> mar/02/2022 12:52:57 by RouterOS 6.48   
> RouterBOARD 941-2nD

## IKEv2 troubleshooting

*Read this in other languages: [English](ikev2-howto.md#ikev2-troubleshooting), [中文](ikev2-howto-zh.md#ikev2-故障排除).*

**See also:** [Check logs and VPN status](clients.md#check-logs-and-vpn-status), [IKEv1 troubleshooting](clients.md#ikev1-troubleshooting) and [Advanced usage](advanced-usage.md).

* [Cannot connect to the VPN server](#cannot-connect-to-the-vpn-server)
* [Ubuntu 20.04 cannot import client config](#ubuntu-2004-cannot-import-client-config)
* [macOS Sonoma clients reconnect](#macos-sonoma-clients-reconnect)
* [Unable to connect multiple IKEv2 clients](#unable-to-connect-multiple-ikev2-clients)
* [IKE authentication credentials are unacceptable](#ike-authentication-credentials-are-unacceptable)
* [Policy match error](#policy-match-error)
* [Parameter is incorrect](#parameter-is-incorrect)
* [Cannot open websites after connecting to IKEv2](#cannot-open-websites-after-connecting-to-ikev2)
* [Windows 10 connecting](#windows-10-connecting)
* [Other known issues](#other-known-issues)

### Cannot connect to the VPN server

First, make sure that the VPN server address specified on your VPN client device **exactly matches** the server address in the output of the IKEv2 helper script. For example, you cannot use a DNS name to connect if it was not specified when setting up IKEv2. To change the IKEv2 server address, read [this section](#change-ikev2-server-address).

For servers with an external firewall (e.g. [EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html)/[GCE](https://cloud.google.com/vpc/docs/firewalls)), open UDP ports 500 and 4500 for the VPN. Aliyun users, see [#433](https://github.com/hwdsl2/setup-ipsec-vpn/issues/433).

[Check logs and VPN status](clients.md#check-logs-and-vpn-status) for errors. If you encounter retransmission related errors and are unable to connect, there may be network issues between the VPN client and server. If you are connecting from mainland China, consider switching to alternative solutions other than IPsec VPN.

### Ubuntu 20.04 cannot import client config

If you installed the IPsec VPN before 2024-04-10, and your VPN server runs Ubuntu Linux version 20.04, you may have encountered an issue where newly generated client configuration files (`.mobileconfig`) fail to import on iOS or macOS device(s) with errors like "incorrect password". This could be caused by updates to libnss3 related packages on Ubuntu 20.04, which required some changes ([25670f3](https://github.com/hwdsl2/setup-ipsec-vpn/commit/25670f3)) in the IKEv2 script.

To fix this issue, first update the IKEv2 script on your server to the latest version using [these instructions](#update-ikev2-helper-script). After that, run `sudo ikev2.sh` and select "export" to re-create the client configuration files.

### macOS Sonoma clients reconnect

macOS 14 (Sonoma) has [a minor issue](https://github.com/hwdsl2/setup-ipsec-vpn/issues/1486) that may cause IKEv2 VPN to disconnect and reconnect once every 24-48 minutes. Other macOS versions are not affected. First [check your macOS version](https://support.apple.com/en-us/HT201260). To work around this issue, follow the steps below.

**Note:** If you installed IPsec VPN after December 10, 2023, no action is required because the following fixes are already included.

1. Edit `/etc/ipsec.d/ikev2.conf` on the VPN server. Find the line:
   ```
     ike=aes256-sha2,aes128-sha2,aes256-sha1,aes128-sha1
   ```
   and replace it with the following:
   ```
     ike=aes_gcm_c_256-hmac_sha2_256-ecp_256,aes256-sha2,aes128-sha2,aes256-sha1,aes128-sha1
   ```
   **Note:** Docker users should first [open a Bash shell inside the container](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/docs/advanced-usage.md#bash-shell-inside-container).
1. Save the file and run `service ipsec restart`. Docker users: After step 4 below, `exit` the container and run `docker restart ipsec-vpn-server`.
1. Edit `/opt/src/ikev2.sh` on the VPN server. Find and replace the following sections with these new values:
   ```
     <key>ChildSecurityAssociationParameters</key>
     <dict>
       <key>DiffieHellmanGroup</key>
       <integer>19</integer>
       <key>EncryptionAlgorithm</key>
       <string>AES-256-GCM</string>
       <key>LifeTimeInMinutes</key>
       <integer>1410</integer>
     </dict>
   ```
   ```
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
   ```
1. Run `sudo ikev2.sh` to export (or add) updated client config files for each macOS device you have.
1. Remove the previously imported IKEv2 profile (if any) from your macOS device(s), then import the updated `.mobileconfig` file(s). See [Configure IKEv2 VPN clients](#configure-ikev2-vpn-clients). Docker users, see [Configure and use IKEv2 VPN](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README.md#configure-and-use-ikev2-vpn).

### Unable to connect multiple IKEv2 clients

To connect multiple IKEv2 clients from behind the same NAT (e.g. home router) at the same time, you will need to generate a unique certificate for each client. Otherwise, you could encounter the issue where a later connected client affects the VPN connection of an existing client, which may lose Internet access.

To generate certificates for additional IKEv2 clients, run the helper script with the `--addclient` option. To customize client options, run the script without arguments.

```bash
sudo ikev2.sh --addclient [client name]
```

### IKE authentication credentials are unacceptable

If you encounter this error, make sure that the VPN server address specified on your VPN client device **exactly matches** the server address in the output of the IKEv2 helper script. For example, you cannot use a DNS name to connect if it was not specified when setting up IKEv2. To change the IKEv2 server address, read [this section](#change-ikev2-server-address).

### Policy match error

To fix this error, you will need to enable stronger ciphers for IKEv2 with a one-time registry change. Download and import the `.reg` file below, or run the following from an elevated command prompt.

- For Windows 7, 8, 10 and 11 ([download .reg file](https://github.com/hwdsl2/vpn-extras/releases/download/v1.0.0/Enable_Stronger_Ciphers_for_IKEv2_on_Windows.reg))

```console
REG ADD HKLM\SYSTEM\CurrentControlSet\Services\RasMan\Parameters /v NegotiateDH2048_AES256 /t REG_DWORD /d 0x1 /f
```

### Parameter is incorrect

If you encounter "Error 87: The parameter is incorrect" when trying to connect using IKEv2 mode, try the solutions in [this issue](https://github.com/trailofbits/algo/issues/1051), more specifically, step 2 "reset device manager adapters".

### Cannot open websites after connecting to IKEv2

If your VPN client device cannot open websites after successfully connecting to IKEv2, try the following fixes:

1. Some cloud providers, such as [Google Cloud](https://cloud.google.com), [set a lower MTU by default](https://cloud.google.com/network-connectivity/docs/vpn/concepts/mtu-considerations). This could cause network issues with IKEv2 VPN clients. To fix, try setting the MTU to 1500 on the VPN server:

   ```bash
   # Replace ens4 with the network interface name on your server
   sudo ifconfig ens4 mtu 1500
   ```

   This setting **does not** persist after a reboot. To change the MTU size permanently, refer to relevant articles on the web.

1. If your Android or Linux VPN client can connect using IKEv2 mode, but cannot open websites, try the fix in [Android/Linux MTU/MSS issues](clients.md#androidlinux-mtumss-issues).

1. Windows VPN clients may not use the DNS servers specified by IKEv2 after connecting, if the client's configured DNS servers on the Internet adapter are from the local network segment. This can be fixed by manually entering DNS servers such as Google Public DNS (8.8.8.8, 8.8.4.4) in network interface properties -> TCP/IPv4. For more information, see [Windows DNS leaks and IPv6](clients.md#windows-dns-leaks-and-ipv6).

### Windows 10 connecting

If using Windows 10 and the VPN is stuck on "connecting" for more than a few minutes, try these steps:

1. Right-click on the wireless/network icon in your system tray.
1. Select **Open Network & Internet settings**, then on the page that opens, click **VPN** on the left.
1. Select the new VPN entry, then click **Connect**.

### Other known issues

The built-in VPN client in Windows may not support IKEv2 fragmentation (this feature [requires](https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-ikee/74df968a-7125-431d-9c98-4ea929e548dc) Windows 10 v1803 or newer). On some networks, this can cause the connection to fail or have other issues. You may instead try the [IPsec/L2TP](clients.md) or [IPsec/XAuth](clients-xauth.md) mode.

## Manage IKEv2 clients

* [List existing clients](#list-existing-clients)
* [Add a client certificate](#add-a-client-certificate)
* [Export configuration for an existing client](#export-configuration-for-an-existing-client)
* [Delete a client certificate](#delete-a-client-certificate)
* [Revoke a client certificate](#revoke-a-client-certificate)

### List existing clients

To list the names of existing IKEv2 clients, run the helper script with the `--listclients` option. Use option `-h` to show usage.

```bash
sudo ikev2.sh --listclients
```

### Add a client certificate

To generate certificates for additional IKEv2 clients, run the helper script with the `--addclient` option. To customize client options, run the script without arguments.

```bash
sudo ikev2.sh --addclient [client name]
```

Alternatively, you may manually add a client certificate. Refer to step 4 in [this section](#manually-set-up-ikev2).

### Export configuration for an existing client

By default, the IKEv2 helper script exports client configuration after running. If later you want to export an existing client, you may use:

```bash
sudo ikev2.sh --exportclient [client name]
```

### Delete a client certificate

**Important:** Deleting a client certificate from the IPsec database **WILL NOT** prevent VPN client(s) from connecting using that certificate! For this use case, you **MUST** [revoke the client certificate](#revoke-a-client-certificate) instead of deleting it.

<details>
<summary>
First, read the important note above. Then click here for instructions.
</summary>

**Warning:** The client certificate and private key will be **permanently deleted**. This **cannot be undone**!

To delete an existing client:

```bash
sudo ikev2.sh --deleteclient [client name]
```

<details>
<summary>
Alternatively, you can manually delete a client certificate.
</summary>

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

1. Delete the client certificate and private key. Replace "Nickname" below with the nickname of the client certificate you want to delete, e.g. `vpnclient`.

   ```bash
   certutil -F -d sql:/etc/ipsec.d -n "Nickname"
   certutil -D -d sql:/etc/ipsec.d -n "Nickname" 2>/dev/null
   ```

1. (Optional) Delete the previously generated client configuration files (`.p12`, `.mobileconfig` and `.sswan` files) for this VPN client, if any.
</details>
</details>

### Revoke a client certificate

In certain circumstances, you may need to revoke a previously generated VPN client certificate.

To revoke an existing client:

```bash
sudo ikev2.sh --revokeclient [client name]
```

<details>
<summary>
Alternatively, you can manually revoke a client certificate.
</summary>

Alternatively, you can manually revoke a client certificate. This can be done using `crlutil`. See example steps below, commands must be run as `root`.

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

   **Note:** If you want to remove a certificate from the CRL, replace `addcert 3446275956 20200606220100Z` above with `rmcert 3446275956`. For other `crlutil` usage, read [here](https://firefox-source-docs.mozilla.org/security/nss/legacy/tools/nss_tools_crlutil/index.html).

1. Finally, let Libreswan re-read the updated CRL.

   ```bash
   ipsec crls
   ```
</details>

## Change IKEv2 server address

In certain circumstances, you may need to change the IKEv2 server address after setup. For example, to switch to use a DNS name, or after server IP changes. Note that the server address you specify on VPN client devices must **exactly match** the server address in the output of the IKEv2 helper script. Otherwise, devices may be unable to connect.

To change the server address, run the [helper script](../extras/ikev2changeaddr.sh) and follow the prompts.

```bash
wget https://get.vpnsetup.net/ikev2addr -O ikev2addr.sh
sudo bash ikev2addr.sh
```

**Important:** After running this script, you must manually update the server address (and remote ID, if applicable) on any existing IKEv2 client devices. For iOS clients, you'll need to run `sudo ikev2.sh` to export the updated client config file and import it to the iOS device.

## Update IKEv2 helper script

The IKEv2 helper script is updated from time to time for bug fixes and improvements ([commit log](https://github.com/hwdsl2/setup-ipsec-vpn/commits/master/extras/ikev2setup.sh)). When a newer version is available, you may optionally update the IKEv2 helper script on your server. Note that these commands will overwrite any existing `ikev2.sh`.

```bash
wget https://get.vpnsetup.net/ikev2 -O /opt/src/ikev2.sh
chmod +x /opt/src/ikev2.sh && ln -s /opt/src/ikev2.sh /usr/bin 2>/dev/null
```

## Set up IKEv2 using helper script

**Note:** By default, IKEv2 is automatically set up when running the VPN setup script. You may skip this section and continue to [configure IKEv2 VPN clients](#configure-ikev2-vpn-clients).

**Important:** Before continuing, you should have successfully [set up your own VPN server](https://github.com/hwdsl2/setup-ipsec-vpn). Docker users, see [Configure and use IKEv2 VPN](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README.md#configure-and-use-ikev2-vpn).

Use this [helper script](../extras/ikev2setup.sh) to automatically set up IKEv2 on the VPN server:

```bash
# Set up IKEv2 using default options
sudo ikev2.sh --auto
# Alternatively, you may customize IKEv2 options
sudo ikev2.sh
```

**Note:** If IKEv2 is already set up, but you want to customize IKEv2 options, first [remove IKEv2](#remove-ikev2), then set it up again using `sudo ikev2.sh`.

When finished, continue to [configure IKEv2 VPN clients](#configure-ikev2-vpn-clients). Advanced users can optionally enable [IKEv2-only mode](advanced-usage.md#ikev2-only-vpn).

<details>
<summary>
Error: "sudo: ikev2.sh: command not found".
</summary>

This is normal if you used an older version of the VPN setup script. First, download the IKEv2 helper script:

```bash
wget https://get.vpnsetup.net/ikev2 -O /opt/src/ikev2.sh
chmod +x /opt/src/ikev2.sh && ln -s /opt/src/ikev2.sh /usr/bin
```

Then run the script using the instructions above.
</details>
<details>
<summary>
You may optionally specify a DNS name, client name and/or custom DNS servers.
</summary>

When running IKEv2 setup in auto mode, advanced users can optionally specify a DNS name for the IKEv2 server address. The DNS name must be a fully qualified domain name (FQDN). Example:

```bash
sudo VPN_DNS_NAME='vpn.example.com' ikev2.sh --auto
```

Similarly, you may specify a name for the first IKEv2 client. The default is `vpnclient` if not specified.

```bash
sudo VPN_CLIENT_NAME='your_client_name' ikev2.sh --auto
```

By default, IKEv2 clients are set to use [Google Public DNS](https://developers.google.com/speed/public-dns/) when the VPN is active. You may specify custom DNS server(s) for IKEv2. Example:

```bash
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 ikev2.sh --auto
```

By default, no password is required when importing IKEv2 client configuration. You can choose to protect client config files using a random password.

```bash
sudo VPN_PROTECT_CONFIG=yes ikev2.sh --auto
```
</details>
<details>
<summary>
View usage information for the IKEv2 script.
</summary>

```
Usage: bash ikev2.sh [options]

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
```
</details>

## Manually set up IKEv2

As an alternative to using the [helper script](#set-up-ikev2-using-helper-script), advanced users can manually set up IKEv2 on the VPN server. Before continuing, it is recommended to [update Libreswan](../README.md#upgrade-libreswan) to the latest version.

The following example shows how to manually configure IKEv2 with Libreswan. Commands below must be run as `root`.

<details>
<summary>
View example steps for manually configuring IKEv2 with Libreswan.
</summary>

1. Find the VPN server's public IP, save it to a variable and check.

   ```bash
   PUBLIC_IP=$(dig @resolver1.opendns.com -t A -4 myip.opendns.com +short)
   [ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(wget -t 2 -T 10 -qO- http://ipv4.icanhazip.com)
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

   **Note:** If you specified the server's DNS name (instead of its IP address) in step 1 above, you must replace `leftid=$PUBLIC_IP` in the command below with `leftid=@$PUBLIC_IP`.

   ```bash
   cat > /etc/ipsec.d/ikev2.conf <<EOF

   conn ikev2-cp
     left=%defaultroute
     leftcert=$PUBLIC_IP
     leftid=$PUBLIC_IP
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

   **Note:** The MOBIKE IKEv2 extension allows VPN clients to change network attachment points, e.g. switch between mobile data and Wi-Fi and keep the IPsec tunnel up on the new IP. If your server (or Docker host) is **NOT** running Ubuntu Linux, and you wish to enable MOBIKE support, replace `mobike=no` with `mobike=yes` in the command above. **DO NOT** enable this option on Ubuntu systems or Raspberry Pis.

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
     -k rsa -g 3072 -v 120 \
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
     -k rsa -g 3072 -v 120 \
     -d sql:/etc/ipsec.d -t ",," \
     --keyUsage digitalSignature,keyEncipherment \
     --extKeyUsage serverAuth \
     --extSAN "ip:$PUBLIC_IP,dns:$PUBLIC_IP"
   ```

   ```
   Generating key.  This may take a few moments...
   ```

1. Generate client certificate(s), then export the `.p12` file that contains the client certificate, private key, and CA certificate.

   **Note:** You may repeat this step to generate certificates for additional VPN clients, but make sure to replace every `vpnclient` with `vpnclient2`, etc. To connect multiple IKEv2 clients from behind the same NAT (e.g. home router) at the same time, you will need to generate a unique certificate for each client.

   Generate client certificate:

   ```bash
   certutil -z <(head -c 1024 /dev/urandom) \
     -S -c "IKEv2 VPN CA" -n "vpnclient" \
     -s "O=IKEv2 VPN,CN=vpnclient" \
     -k rsa -g 3072 -v 120 \
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

1. (For iOS clients) Export the CA certificate as `ca.cer`:

   ```bash
   certutil -L -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" -a -o ca.cer
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

   **Note:** To display a certificate, use `certutil -L -d sql:/etc/ipsec.d -n "Nickname"`. To revoke a client certificate, follow [these steps](#revoke-a-client-certificate). For other `certutil` usage, read [here](https://firefox-source-docs.mozilla.org/security/nss/legacy/tools/nss_tools_certutil/index.html).

1. **(Important) Restart the IPsec service**:

   ```bash
   service ipsec restart
   ```

Before continuing, you **must** restart the IPsec service. The IKEv2 setup on the VPN server is now complete. Follow instructions to [configure VPN clients](#configure-ikev2-vpn-clients).
</details>

## Remove IKEv2

If you want to remove IKEv2 from the VPN server, but keep the [IPsec/L2TP](clients.md) and [IPsec/XAuth ("Cisco IPsec")](clients-xauth.md) modes (if installed), run the helper script. **Warning:** All IKEv2 configuration including certificates and keys will be **permanently deleted**. This **cannot be undone**!

```bash
sudo ikev2.sh --removeikev2
```

After removing IKEv2, if you want to set it up again, refer to [this section](#set-up-ikev2-using-helper-script).

<details>
<summary>
Alternatively, you can manually remove IKEv2.
</summary>

To manually remove IKEv2 from the VPN server, but keep the [IPsec/L2TP](clients.md) and [IPsec/XAuth ("Cisco IPsec")](clients-xauth.md) modes, follow these steps. Commands must be run as `root`.

**Warning:** All IKEv2 configuration including certificates and keys will be **permanently deleted**. This **cannot be undone**!

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

1. Delete the Certificate Revocation List (CRL), if any:

   ```bash
   crlutil -D -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" 2>/dev/null
   ```

1. Delete certificates and keys. Replace "Nickname" below with each certificate's nickname. Repeat these commands for each certificate. When finished, list certificates in the IPsec database again, and confirm that the list is empty.

   ```bash
   certutil -F -d sql:/etc/ipsec.d -n "Nickname"
   certutil -D -d sql:/etc/ipsec.d -n "Nickname" 2>/dev/null
   ```
</details>

## References

* https://libreswan.org/wiki/VPN_server_for_remote_clients_using_IKEv2
* https://libreswan.org/wiki/HOWTO:_Using_NSS_with_libreswan
* https://libreswan.org/man/ipsec.conf.5.html
* https://docs.strongswan.org/docs/5.9/interop/windowsClients.html
* https://docs.strongswan.org/docs/5.9/os/androidVpnClient.html
* https://firefox-source-docs.mozilla.org/security/nss/legacy/tools/nss_tools_certutil/index.html
* https://firefox-source-docs.mozilla.org/security/nss/legacy/tools/nss_tools_crlutil/index.html

## License

Copyright (C) 2016-2024 [Lin Song](https://github.com/hwdsl2) [![View my profile on LinkedIn](https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png)](https://www.linkedin.com/in/linsongui)   

[![Creative Commons License](https://i.creativecommons.org/l/by-sa/3.0/88x31.png)](http://creativecommons.org/licenses/by-sa/3.0/)   
This work is licensed under the [Creative Commons Attribution-ShareAlike 3.0 Unported License](http://creativecommons.org/licenses/by-sa/3.0/)  
Attribution required: please include my name in any derivative and let me know how you have improved it!
