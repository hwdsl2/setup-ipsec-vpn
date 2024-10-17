[English](ikev2-howto.md) | [中文](ikev2-howto-zh.md)

# IKEv2 VPN 配置和使用指南

* [导言](#导言)
* [配置 IKEv2 VPN 客户端](#配置-ikev2-vpn-客户端)
* [IKEv2 故障排除](#ikev2-故障排除)
* [管理 IKEv2 客户端](#管理-ikev2-客户端)
* [更改 IKEv2 服务器地址](#更改-ikev2-服务器地址)
* [更新 IKEv2 辅助脚本](#更新-ikev2-辅助脚本)
* [使用辅助脚本配置 IKEv2](#使用辅助脚本配置-ikev2)
* [手动配置 IKEv2](#手动配置-ikev2)
* [移除 IKEv2](#移除-ikev2)

## 导言

现代操作系统支持 IKEv2 协议标准。因特网密钥交换（英语：Internet Key Exchange，简称 IKE 或 IKEv2）是一种网络协议，归属于 IPsec 协议族之下，用以创建安全关联 (Security Association, SA)。与 IKE 版本 1 相比较，IKEv2 的 [功能改进](https://en.wikipedia.org/wiki/Internet_Key_Exchange#Improvements_with_IKEv2) 包括比如通过 MOBIKE 实现 Standard Mobility 支持，以及更高的可靠性。

Libreswan 支持通过使用 RSA 签名算法的 X.509 Machine Certificates 来对 IKEv2 客户端进行身份验证。该方法无需 IPsec PSK, 用户名或密码。它可以用于 Windows, macOS, iOS, Android, Chrome OS, Linux 和 RouterOS。

默认情况下，运行 VPN 安装脚本时会自动配置 IKEv2。如果你想了解有关配置 IKEv2 的更多信息，请参见 [使用辅助脚本配置 IKEv2](#使用辅助脚本配置-ikev2)。Docker 用户请看 [配置并使用 IKEv2 VPN](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md#配置并使用-ikev2-vpn)。

## 配置 IKEv2 VPN 客户端

**注：** 如果要添加或者导出 IKEv2 客户端，运行 `sudo ikev2.sh`。使用 `-h` 显示使用信息。客户端配置文件可以在导入后安全删除。

* [Windows 7, 8, 10 和 11](#windows-7-8-10-和-11)
* [OS X (macOS)](#os-x-macos)
* [iOS (iPhone/iPad)](#ios)
* [Android](#android)
* [Chrome OS (Chromebook)](#chrome-os)
* [Linux](#linux)
* [Mikrotik RouterOS](#routeros)

<details>
<summary>
了解如何更改 IKEv2 服务器地址。
</summary>

在某些情况下，你可能需要更改 IKEv2 服务器地址，例如切换为使用域名，或者在服务器的 IP 更改之后。要了解更多信息，参见 [这一小节](#更改-ikev2-服务器地址)。
</details>

### Windows 7, 8, 10 和 11

#### 自动导入配置

[**屏幕录影：** 在 Windows 上自动导入 IKEv2 配置](https://ko-fi.com/post/IKEv2-Auto-Import-Configuration-on-Windows-8-10-a-K3K1DQCHW)

**Windows 8, 10 和 11** 用户可以自动导入 IKEv2 配置：

1. 将生成的 `.p12` 文件安全地传送到你的计算机。
1. 右键单击 [ikev2_config_import.cmd](https://github.com/hwdsl2/vpn-extras/releases/latest/download/ikev2_config_import.cmd) 并保存这个辅助脚本到与 `.p12` 文件 **相同的文件夹**。
1. 右键单击保存的脚本，选择 **属性**。单击对话框下方的 **解除锁定**，然后单击 **确定**。
1. 右键单击保存的脚本，选择 **以管理员身份运行** 并按提示操作。

要连接到 VPN：单击系统托盘中的无线/网络图标，选择新的 VPN 连接，然后单击 **连接**。连接成功后，你可以到 [这里](https://www.ipchicken.com) 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

如果在连接过程中遇到错误，请参见 [故障排除](#ikev2-故障排除)。

#### 手动导入配置

[[支持者] **屏幕录影：** 在 Windows 上手动导入 IKEv2 配置](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-X8X5FVFZC)

或者，**Windows 7, 8, 10 和 11** 用户可以手动导入 IKEv2 配置：

1. 将生成的 `.p12` 文件安全地传送到你的计算机，然后导入到证书存储。

   要导入 `.p12` 文件，打开 [提升权限命令提示符](http://www.cnblogs.com/xxcanghai/p/4610054.html) 并运行以下命令：

   ```console
   # 导入 .p12 文件（换成你自己的值）
   certutil -f -importpfx "\path\to\your\file.p12" NoExport
   ```

   **注：** 如果客户端配置文件没有密码，请按回车键继续，或者在手动导入 `.p12` 文件时保持密码字段空白。

   或者，你也可以 [手动导入 .p12 文件](https://wiki.strongswan.org/projects/strongswan/wiki/Win7Certs/9)。在导入证书后，确保将客户端证书放在 "个人 -> 证书" 目录中，并且将 CA 证书放在 "受信任的根证书颁发机构 -> 证书" 目录中。

1. 在 Windows 计算机上添加一个新的 IKEv2 VPN 连接。

   对于 **Windows 8, 10 和 11**，推荐从命令提示符运行以下命令创建 VPN 连接，以达到更佳的安全性和性能。

   ```console
   # 创建 VPN 连接（将服务器地址换成你自己的值）
   powershell -command ^"Add-VpnConnection -ServerAddress '你的 VPN 服务器 IP（或者域名）' ^
     -Name 'My IKEv2 VPN' -TunnelType IKEv2 -AuthenticationMethod MachineCertificate ^
     -EncryptionLevel Required -PassThru^"
   # 设置 IPsec 参数
   powershell -command ^"Set-VpnConnectionIPsecConfiguration -ConnectionName 'My IKEv2 VPN' ^
     -AuthenticationTransformConstants GCMAES128 -CipherTransformConstants GCMAES128 ^
     -EncryptionMethod AES256 -IntegrityCheckMethod SHA256 -PfsGroup None ^
     -DHGroup Group14 -PassThru -Force^"
   ```

   **Windows 7** 不支持这些命令，你可以 [手动创建 VPN 连接](https://wiki.strongswan.org/projects/strongswan/wiki/Win7Config/8)。

   **注：** 你输入的服务器地址必须与 IKEv2 辅助脚本输出中的服务器地址 **完全一致**。例如，如果你在配置 IKEv2 时指定了服务器的域名，则必须在 **Internet地址** 字段中输入该域名。

1. **此步骤为必须，如果你手动创建了 VPN 连接。**

   为 IKEv2 启用更强的加密算法，通过修改一次注册表来实现。请下载并导入下面的 `.reg` 文件，或者打开提升权限命令提示符并运行以下命令。更多信息请看 [这里](https://docs.strongswan.org/docs/5.9/interop/windowsClients.html)。

   - 适用于 Windows 7, 8, 10 和 11 ([下载 .reg 文件](https://github.com/hwdsl2/vpn-extras/releases/download/v1.0.0/Enable_Stronger_Ciphers_for_IKEv2_on_Windows.reg))

     ```console
     REG ADD HKLM\SYSTEM\CurrentControlSet\Services\RasMan\Parameters /v NegotiateDH2048_AES256 /t REG_DWORD /d 0x1 /f
     ```

要连接到 VPN：单击系统托盘中的无线/网络图标，选择新的 VPN 连接，然后单击 **连接**。连接成功后，你可以到 [这里](https://www.ipchicken.com) 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

如果在连接过程中遇到错误，请参见 [故障排除](#ikev2-故障排除)。

<details>
<summary>
删除 IKEv2 VPN 连接。
</summary>

通过以下的步骤，可以删除添加的 VPN 连接，并将计算机恢复到导入 IKEv2 配置之前的状态（可选）。

1. 在系统设置 - 网络 - VPN 中删除添加的 VPN 连接。Windows 7 用户可以在网络和共享中心 - 更改适配器设置中删除 VPN 连接。

1. （可选）删除 IKEv2 证书。

   1. 按 Win+R 或在开始菜单中搜索 `mmc` 打开 *Microsoft Management Console*。

   1. 在 `File - Add/Remove Snap-In` 的窗口中，选择添加 `Certificates` 并在弹出的窗口中选择 `Computer account -> Local Computer`。点击 `Finish -> OK` 以保存设置。

   1. 在 `Certificates - Personal - Certificates` 中删除 IKEv2 客户端证书。该证书的名称与你指定的 IKEv2 客户端名称一致，默认为 `vpnclient`，该证书由 `IKEv2 VPN CA` 颁发。

   1. 在 `Certificates - Trusted Root Certification Authorities - Certificates` 中删除 IKEv2 VPN CA 证书。该证书是由 `IKEv2 VPN CA` 颁发的，颁发给 `IKEv2 VPN CA` 的证书。需要注意，删除这一步的证书时，`Certificates - Personal - Certificates` 中应不存在其他由 `IKEv2 VPN CA` 颁发的证书。

1. （可选，适用于手动创建了 VPN 连接的用户）还原注册表配置。注意，在编辑注册表前应备份。

   1. 按 Win+R 或在开始菜单中搜索 `regedit` 打开 *Registry Editor*。

   1. 在 `HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Rasman\Parameters` 中删除名为 `NegotiateDH2048_AES256` 的项目，如果它存在。
</details>

### OS X (macOS)

[[支持者] **屏幕录影：** 在 macOS 上导入 IKEv2 配置并连接](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-X8X5FVFZC)

首先，将生成的 `.mobileconfig` 文件安全地传送到你的 Mac，然后双击并按提示操作，以导入为 macOS 配置描述文件。如果你的 Mac 运行 macOS Big Sur 或更新版本，打开系统偏好设置并转到描述文件部分以完成导入。对于 macOS Ventura 和更新版本，打开系统设置并搜索描述文件。在完成之后，检查并确保 "IKEv2 VPN" 显示在系统偏好设置 -> 描述文件中。

要连接到 VPN：

1. 打开系统偏好设置并转到网络部分。
1. 选择与 `你的 VPN 服务器 IP`（或者域名）对应的 VPN 连接。
1. 选中 **在菜单栏中显示 VPN 状态** 复选框。对于 macOS Ventura 和更新版本，你可以到系统设置 -> 控制中心 -> 仅菜单栏部分配置该选项。
1. 单击 **连接**，或启用 VPN 连接。

（可选功能）启用 **VPN On Demand（按需连接）** 以在你的 Mac 连接到 Wi-Fi 时自动启动 VPN 连接。要启用它，选中 VPN 连接的 **按需连接** 复选框，然后单击 **应用**。对于 macOS Ventura 和更新版本，首先单击 VPN 连接右边的 "i" 图标，然后配置该选项。

你可以自定义按需连接规则，以排除某些 Wi-Fi 网络（例如你的家庭网络）。有关更多详细信息，请参阅 [:book: Book: 搭建自己的 IPsec VPN, OpenVPN 和 WireGuard 服务器](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-X8X5FVFZC) 中的 "指南：为 macOS 和 iOS 自定义 IKEv2 VPN On Demand 规则" 一章。

<details>
<summary>
如果你手动配置 IKEv2 而不是使用辅助脚本，点这里查看步骤。
</summary>

首先，将生成的 `.p12` 文件安全地传送到你的 Mac，然后双击以导入到 **钥匙串访问** 中的 **登录** 钥匙串。下一步，双击导入的 `IKEv2 VPN CA` 证书，展开 **信任** 并从 **IP 安全 (IPsec)** 下拉菜单中选择 **始终信任**。单击左上角的红色 "X" 关闭窗口。根据提示使用触控 ID，或者输入密码并单击 "更新设置"。

在完成之后，检查并确保新的客户端证书和 `IKEv2 VPN CA` 都显示在 **登录** 钥匙串 的 **证书** 类别中。

1. 打开系统偏好设置并转到网络部分。
1. 在窗口左下角单击 **+** 按钮。
1. 从 **接口** 下拉菜单选择 **VPN**。
1. 从 **VPN 类型** 下拉菜单选择 **IKEv2**。
1. 在 **服务名称** 字段中输入任意内容。
1. 单击 **创建**。
1. 在 **服务器地址** 字段中输入 `你的 VPN 服务器 IP` （或者域名）。   
   **注：** 如果你在配置 IKEv2 时指定了服务器的域名（而不是 IP 地址），则必须在 **服务器地址** 和 **远程 ID** 字段中输入该域名。
1. 在 **远程 ID** 字段中输入 `你的 VPN 服务器 IP` （或者域名）。
1. 在 **本地 ID** 字段中输入 `你的 VPN 客户端名称`。   
   **注：** 该名称必须和你在 IKEv2 配置过程中指定的客户端名称一致。它与你的 `.p12` 文件名的第一部分相同。
1. 单击 **认证设置** 按钮。
1. 从 **认证设置** 下拉菜单中选择 **无**。
1. 选择 **证书** 单选按钮，然后选择新的客户端证书。
1. 单击 **好**。
1. 选中 **在菜单栏中显示 VPN 状态** 复选框。
1. 单击 **应用** 保存 VPN 连接信息。
1. 单击 **连接**。
</details>

连接成功后，你可以到 [这里](https://www.ipchicken.com) 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

如果在连接过程中遇到错误，请参见 [故障排除](#ikev2-故障排除)。

**注：** macOS 14 (Sonoma) 存在一个小问题，可能会导致 IKEv2 VPN 每 24-48 分钟断开并重新连接一次。其他 macOS 版本不受影响。有关详细信息和解决方法，请参阅 [macOS Sonoma 客户端重新连接](#macos-sonoma-客户端重新连接)。

<details>
<summary>
删除 IKEv2 VPN 连接。
</summary>

要删除 IKEv2 VPN 连接，打开系统偏好设置 -> 描述文件并移除你添加的 IKEv2 VPN 描述文件。
</details>

### iOS

[[支持者] **屏幕录影：** 在 iOS (iPhone & iPad) 上导入 IKEv2 配置并连接](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-X8X5FVFZC)

首先，将生成的 `.mobileconfig` 文件安全地传送到你的 iOS 设备，并且导入为 iOS 配置描述文件。要传送文件，你可以使用：

1. AirDrop（隔空投送），或者
1. 使用 [文件共享](https://support.apple.com/zh-cn/HT210598) 功能上传到设备（任何 App 目录），然后打开 iOS 设备上的 "文件" App，将上传的文件移动到 "On My iPhone" 目录下。然后单击它并到 "设置" App 中导入，或者
1. 将文件放在一个你的安全的托管网站上，然后在 Mobile Safari 中下载并导入它们。

在完成之后，检查并确保 "IKEv2 VPN" 显示在设置 -> 通用 -> VPN 与设备管理（或者描述文件）中。

要连接到 VPN：

1. 进入设置 -> VPN。选择与 `你的 VPN 服务器 IP`（或者域名）对应的 VPN 连接。
1. 启用 **VPN** 连接。

（可选功能）启用 **VPN On Demand（按需连接）** 以在你的 iOS 设备连接到 Wi-Fi 时自动启动 VPN 连接。要启用它，单击 VPN 连接右边的 "i" 图标，然后启用 **按需连接**。

你可以自定义按需连接规则，以排除某些 Wi-Fi 网络（例如你的家庭网络）。有关更多详细信息，请参阅 [:book: Book: 搭建自己的 IPsec VPN, OpenVPN 和 WireGuard 服务器](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-X8X5FVFZC) 中的 "指南：为 macOS 和 iOS 自定义 IKEv2 VPN On Demand 规则" 一章。

<details>
<summary>
自定义按需连接规则：在 Wi-Fi 和蜂窝网络上连接。
</summary>

默认的 VPN On Demand 配置仅在 Wi-Fi 网络上启动 VPN 连接，而不会在蜂窝网络上启动 VPN 连接。如果你希望 VPN 在 Wi-Fi 和蜂窝网络上都启动连接：

1. 编辑 VPN 服务器上的 `/opt/src/ikev2.sh`。找到以下行：
   ```
     <dict>
       <key>InterfaceTypeMatch</key>
       <string>Cellular</string>
       <key>Action</key>
       <string>Disconnect</string>
     </dict>
   ```
   并将 "Disconnect" 替换为 "Connect"：
   ```
     <dict>
       <key>InterfaceTypeMatch</key>
       <string>Cellular</string>
       <key>Action</key>
       <string>Connect</string>
     </dict>
   ```
2. 保存文件，然后运行 `sudo ikev2.sh` 为你的 iOS 设备导出更新后的客户端配置文件。
3. 从你的 iOS 设备中移除之前导入的 VPN 配置文件，然后导入步骤 2 中生成的新 `.mobileconfig` 文件。
</details>
<details>
<summary>
如果你手动配置 IKEv2 而不是使用辅助脚本，点这里查看步骤。
</summary>

首先，将生成的 `ca.cer` 和 `.p12` 文件安全地传送到你的 iOS 设备，并且逐个导入为 iOS 配置描述文件。要传送文件，你可以使用：

1. AirDrop（隔空投送），或者
1. 使用 [文件共享](https://support.apple.com/zh-cn/HT210598) 功能上传到设备（任何 App 目录），然后打开 iOS 设备上的 "文件" App，将上传的文件移动到 "On My iPhone" 目录下。然后逐个单击它们并到 "设置" App 中导入，或者
1. 将文件放在一个你的安全的托管网站上，然后在 Mobile Safari 中下载并导入它们。

在完成之后，检查并确保新的客户端证书和 `IKEv2 VPN CA` 都显示在设置 -> 通用 -> VPN 与设备管理（或者描述文件）中。

1. 进入设置 -> 通用 -> VPN 与设备管理 -> VPN。
1. 单击 **添加VPN配置...**。
1. 单击 **类型** 。选择 **IKEv2** 并返回。
1. 在 **描述** 字段中输入任意内容。
1. 在 **服务器** 字段中输入 `你的 VPN 服务器 IP` （或者域名）。   
   **注：** 如果你在配置 IKEv2 时指定了服务器的域名（而不是 IP 地址），则必须在 **服务器** 和 **远程 ID** 字段中输入该域名。
1. 在 **远程 ID** 字段中输入 `你的 VPN 服务器 IP` （或者域名）。
1. 在 **本地 ID** 字段中输入 `你的 VPN 客户端名称`。   
   **注：** 该名称必须和你在 IKEv2 配置过程中指定的客户端名称一致。它与你的 `.p12` 文件名的第一部分相同。
1. 单击 **用户鉴定** 。选择 **无** 并返回。
1. 启用 **使用证书** 选项。
1. 单击 **证书** 。选择新的客户端证书并返回。
1. 单击右上角的 **完成**。
1. 启用 **VPN** 连接。
</details>

连接成功后，你可以到 [这里](https://www.ipchicken.com) 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

如果在连接过程中遇到错误，请参见 [故障排除](#ikev2-故障排除)。

<details>
<summary>
删除 IKEv2 VPN 连接。
</summary>

要删除 IKEv2 VPN 连接，打开设置 -> 通用 -> VPN 与设备管理（或者描述文件）并移除你添加的 IKEv2 VPN 描述文件。
</details>

### Android

#### 使用 strongSwan VPN 客户端

[[支持者] **屏幕录影：** 使用 Android strongSwan VPN 客户端连接](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-X8X5FVFZC)

Android 用户可以使用 strongSwan VPN 客户端连接（推荐）。

1. 将生成的 `.sswan` 文件安全地传送到你的 Android 设备。
1. 从 [**Google Play**](https://play.google.com/store/apps/details?id=org.strongswan.android)，[**F-Droid**](https://f-droid.org/en/packages/org.strongswan.android/) 或 [**strongSwan 下载网站**](https://download.strongswan.org/Android/)下载并安装 strongSwan VPN 客户端。
1. 启动 strongSwan VPN 客户端。
1. 单击右上角的 "更多选项" 菜单，然后单击 **导入VPN配置**。
1. 选择你从服务器传送过来的 `.sswan` 文件。   
   **注：** 要查找 `.sswan` 文件，单击左上角的抽拉式菜单，然后浏览到你保存文件的目录。
1. 在 "导入VPN配置" 屏幕上，单击 **从VPN配置导入证书**，并按提示操作。
1. 在 "选择证书" 屏幕上，选择新的客户端证书并单击 **选择**。
1. 单击 **导入**。
1. 单击新的 VPN 配置文件以开始连接。

（可选功能）你可以选择启用 Android 上的 "始终开启的 VPN" 功能。启动 **设置** App，进入 网络和互联网 -> 高级 -> VPN，单击 "strongSwan VPN 客户端" 右边的设置图标，然后启用 **始终开启的 VPN** 以及 **屏蔽未使用 VPN 的所有连接** 选项。

<details>
<summary>
如果你的设备运行 Android 6.0 或更早版本，点这里查看额外的步骤。
</summary>

如果你的设备运行 Android 6.0 (Marshmallow) 或更早版本，要使用 strongSwan VPN 客户端连接，你必须更改 VPN 服务器上的以下设置：编辑服务器上的 `/etc/ipsec.d/ikev2.conf`。在 `conn ikev2-cp` 小节的末尾添加 `authby=rsa-sha1`，开头必须空两格。保存文件并运行 `service ipsec restart`。
</details>
<details>
<summary>
如果你手动配置 IKEv2 而不是使用辅助脚本，点这里查看步骤。
</summary>

**Android 10 和更新版本:**

1. 将生成的 `.p12` 文件安全地传送到你的 Android 设备。
1. 从 [**Google Play**](https://play.google.com/store/apps/details?id=org.strongswan.android)，[**F-Droid**](https://f-droid.org/en/packages/org.strongswan.android/) 或 [**strongSwan 下载网站**](https://download.strongswan.org/Android/)下载并安装 strongSwan VPN 客户端。
1. 启动 **设置** App。
1. 进入 安全 -> 高级 -> 加密与凭据。
1. 单击 **安装证书**。
1. 单击 **VPN 和应用用户证书**。
1. 选择你从服务器传送过来的 `.p12` 文件，并按提示操作。   
   **注：** 要查找 `.p12` 文件，单击左上角的抽拉式菜单，然后浏览到你保存文件的目录。
1. 启动 strongSwan VPN 客户端，然后单击 **添加VPN配置**。
1. 在 **服务器地址** 字段中输入 `你的 VPN 服务器 IP` （或者域名）。   
   **注：** 如果你在配置 IKEv2 时指定了服务器的域名（而不是 IP 地址），则必须在 **服务器地址** 字段中输入该域名。
1. 在 **VPN 类型** 下拉菜单选择 **IKEv2 证书**。
1. 单击 **选择用户证书**，选择新的客户端证书并单击 **选择**。
1. **（重要）** 单击 **显示高级设置**。向下滚动，找到并启用 **Use RSA/PSS signatures** 选项。
1. 保存新的 VPN 连接，然后单击它以开始连接。

**Android 4 to 9:**

1. 将生成的 `.p12` 文件安全地传送到你的 Android 设备。
1. 从 [**Google Play**](https://play.google.com/store/apps/details?id=org.strongswan.android)，[**F-Droid**](https://f-droid.org/en/packages/org.strongswan.android/) 或 [**strongSwan 下载网站**](https://download.strongswan.org/Android/)下载并安装 strongSwan VPN 客户端。
1. 启动 strongSwan VPN 客户端，然后单击 **添加VPN配置**。
1. 在 **服务器地址** 字段中输入 `你的 VPN 服务器 IP` （或者域名）。   
   **注：** 如果你在配置 IKEv2 时指定了服务器的域名（而不是 IP 地址），则必须在 **服务器地址** 字段中输入该域名。
1. 在 **VPN 类型** 下拉菜单选择 **IKEv2 证书**。
1. 单击 **选择用户证书**，然后单击 **安装证书**。
1. 选择你从服务器传送过来的 `.p12` 文件，并按提示操作。   
   **注：** 要查找 `.p12` 文件，单击左上角的抽拉式菜单，然后浏览到你保存文件的目录。
1. **（重要）** 单击 **显示高级设置**。向下滚动，找到并启用 **Use RSA/PSS signatures** 选项。
1. 保存新的 VPN 连接，然后单击它以开始连接。
</details>

连接成功后，你可以到 [这里](https://www.ipchicken.com) 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

如果在连接过程中遇到错误，请参见 [故障排除](#ikev2-故障排除)。

#### 使用系统自带的 IKEv2 客户端

[[支持者] **屏幕录影：** 使用 Android 11+ 系统自带的 VPN 客户端连接](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-X8X5FVFZC)

Android 11+ 用户也可以使用系统自带的 IKEv2 客户端连接。

1. 将生成的 `.p12` 文件安全地传送到你的 Android 设备。
1. 启动 **设置** App。
1. 进入 安全 -> 高级 -> 加密与凭据。
1. 单击 **安装证书**。
1. 单击 **VPN 和应用用户证书**。
1. 选择你从服务器传送过来的 `.p12` 文件。   
   **注：** 要查找 `.p12` 文件，单击左上角的抽拉式菜单，然后浏览到你保存文件的目录。
1. 为证书输入名称，然后单击 **确定**。
1. 进入 设置 -> 网络和互联网 -> VPN，然后单击 "+" 按钮。
1. 为 VPN 配置文件输入名称。
1. 在 **类型** 下拉菜单选择 **IKEv2/IPSec RSA**。
1. 在 **服务器地址** 字段中输入 `你的 VPN 服务器 IP` （或者域名）。   
   **注：** 它必须与 IKEv2 辅助脚本输出中的服务器地址 **完全一致**。
1. 在 **IPSec 标识符** 字段中输入任意内容（例如 `empty`）。   
   **注：** 该字段不应该为必填。它是 Android 的一个 bug。
1. 在 **IPSec 用户证书** 下拉菜单选择你导入的证书。
1. 在 **IPSec CA 证书** 下拉菜单选择你导入的证书。
1. 在 **IPSec 服务器证书** 下拉菜单选择 **(来自服务器)**。
1. 单击 **保存**。然后单击新的 VPN 连接并单击 **连接**。

连接成功后，你可以到 [这里](https://www.ipchicken.com) 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

如果在连接过程中遇到错误，请参见 [故障排除](#ikev2-故障排除)。

### Chrome OS

首先，在 VPN 服务器上导出 CA 证书到 `ca.cer`：

```bash
sudo certutil -L -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" -a -o ca.cer
```

将生成的 `.p12` 文件和 `ca.cer` 文件安全地传送到你的 Chrome OS 设备。

安装用户证书和 CA 证书：

1. 在 Google Chrome 中打开新标签页。
1. 在地址栏中输入 **chrome://settings/certificates**
1. **（重要）** 单击 **导入并绑定** 而不是 **导入**。
1. 在对话框中选择你从服务器传送过来的 `.p12` 文件并选择 **打开**。
1. 如果证书没有密码，单击 **确定**。否则输入该证书的密码。
1. 单击上面的 **授权机构** 选项卡，然后单击 **导入**。
1. 在对话框中左下角的下拉菜单选择 **所有文件**。
1. 选择你从服务器传送过来的 `ca.cer` 文件并选择 **打开**。
1. 保持默认选项并单击 **确定**。

添加 VPN 连接：

1. 进入设置 -> 网络。
1. 单击 **添加连接**，然后单击 **添加内置 VPN**。
1. 在 **服务名称** 字段中输入任意内容。
1. 在 **提供商类型** 下拉菜单选择 **IPsec (IKEv2)**。
1. 在 **服务器主机名** 字段中输入 `你的 VPN 服务器 IP`（或者域名）。
1. 在 **身份验证类型** 下拉菜单选择 **用户证书**。
1. 在 **服务器 CA 证书** 下拉菜单选择 **IKEv2 VPN CA [IKEv2 VPN CA]**。
1. 在 **用户证书** 下拉菜单选择 **IKEv2 VPN CA [客户端名称]**。
1. 保持其他字段空白。
1. 启用 **保存身份信息和密码**。
1. 单击 **连接**。

连接成功后，网络状态图标上会出现 VPN 指示。你可以到 [这里](https://www.ipchicken.com) 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

（可选功能）你可以选择启用 Chrome OS 上的 "始终开启的 VPN" 功能。要管理该设置，进入设置 -> 网络，然后单击 **VPN**。

如果在连接过程中遇到错误，请参见 [故障排除](#ikev2-故障排除)。

### Linux

在配置 Linux 客户端之前，你必须更改 VPN 服务器上的以下设置：编辑服务器上的 `/etc/ipsec.d/ikev2.conf`。在 `conn ikev2-cp` 小节的末尾添加 `authby=rsa-sha1`，开头必须空两格。保存文件并运行 `service ipsec restart`。

要配置你的 Linux 计算机以作为客户端连接到 IKEv2，首先安装 NetworkManager 的 strongSwan 插件：

```bash
# Ubuntu and Debian
sudo apt-get update
sudo apt-get install network-manager-strongswan

# Arch Linux
sudo pacman -Syu  # 升级所有软件包
sudo pacman -S networkmanager-strongswan

# Fedora
sudo yum install NetworkManager-strongswan-gnome

# CentOS
sudo yum install epel-release
sudo yum --enablerepo=epel install NetworkManager-strongswan-gnome
```

下一步，将生成的 `.p12` 文件安全地从 VPN 服务器传送到你的 Linux 计算机。然后提取 CA 证书，客户端证书和私钥。将下面示例中的 `vpnclient.p12` 换成你的 `.p12` 文件名。

```bash
# 示例：提取 CA 证书，客户端证书和私钥。在完成后可以删除 .p12 文件。
# 注：你可能需要输入 import password，它可以在 IKEv2 辅助脚本的输出中找到。
#    如果在脚本的输出中没有 import password，请按回车键继续。
# 注：如果使用 OpenSSL 3.x (运行 "openssl version" 进行检查)，
#    请将 "-legacy" 附加到下面的 3 个命令。
openssl pkcs12 -in vpnclient.p12 -cacerts -nokeys -out ca.cer
openssl pkcs12 -in vpnclient.p12 -clcerts -nokeys -out client.cer
openssl pkcs12 -in vpnclient.p12 -nocerts -nodes  -out client.key
rm vpnclient.p12

# （重要）保护证书和私钥文件
# 注：这一步是可选的，但强烈推荐。
sudo chown root:root ca.cer client.cer client.key
sudo chmod 600 ca.cer client.cer client.key
```

然后你可以创建并启用 VPN 连接：

1. 进入 Settings -> Network -> VPN。单击 **+** 按钮。
1. 选择 **IPsec/IKEv2 (strongswan)**。
1. 在 **Name** 字段中输入任意内容。
1. 在 **Gateway (Server)** 部分的 **Address** 字段中输入 `你的 VPN 服务器 IP`（或者域名）。
1. 为 **Certificate** 字段选择 `ca.cer` 文件。
1. 在 **Client** 部分的 **Authentication** 下拉菜单选择 **Certificate(/private key)**。
1. 在 **Certificate** 下拉菜单（如果存在）选择 **Certificate/private key**。
1. 为 **Certificate (file)** 字段选择 `client.cer` 文件。
1. 为 **Private key** 字段选择 `client.key` 文件。
1. 在 **Options** 部分，选中 **Request an inner IP address** 复选框。
1. 在 **Cipher proposals (Algorithms)** 部分，选中 **Enable custom proposals** 复选框。
1. 保持 **IKE** 字段空白。
1. 在 **ESP** 字段中输入 `aes128gcm16`.
1. 单击 **Add** 保存 VPN 连接信息。
1. 启用 **VPN** 连接。

另外，你也可以使用命令行连接。示例步骤请参见 [#1399](https://github.com/hwdsl2/setup-ipsec-vpn/issues/1399) 和 [#1007](https://github.com/hwdsl2/setup-ipsec-vpn/issues/1007)。如果你遇到错误 `Could not find source connection`，编辑 `/etc/netplan/01-netcfg.yaml` 并将 `renderer: networkd` 替换为 `renderer: NetworkManager`，然后运行 `sudo netplan apply`。要连接到 VPN，运行 `sudo nmcli c up VPN`。要断开连接：`sudo nmcli c down VPN`。

连接成功后，你可以到 [这里](https://www.ipchicken.com) 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

如果在连接过程中遇到错误，请参见 [故障排除](#ikev2-故障排除)。

### RouterOS

**注：** 这些步骤由 [@Unix-User](https://github.com/Unix-User) 提供。建议通过 SSH 连接运行终端命令，例如通过 Putty。

1. 将生成的 `.p12` 文件安全地传送到你的计算机。

   <details>
   <summary>
   单击查看屏幕录影。
   </summary>

   ![routeros get certificate](images/routeros-get-cert.gif)
   </details>

2. 在 WinBox 中，转到 System > certificates > import. 将 `.p12` 证书文件导入两次（是的，导入同一个文件两次）。检查你的 certificates panel。你应该看到 2 个文件，其中标注 KT 的是密钥。

   <details>
   <summary>
   单击查看屏幕录影。
   </summary>

   ![routeros import certificate](images/routeros-import-cert.gif)
   </details>

   或者，你也可以使用终端命令 (empty passphrase):

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

3. 在 terminal 中运行以下命令。将以下内容替换为你自己的值。
`YOUR_VPN_SERVER_IP_OR_DNS_NAME` 是你的 VPN 服务器 IP 或域名。
`IMPORTED_CERTIFICATE` 是上面第 2 步中的证书名称，例如 `vpnclient.p12_0`
（标记为 KT 的行 - Priv. Key Trusted - 如果未标记为 KT，请再次导入证书）。
`THESE_ADDRESSES_GO_THROUGH_VPN` 是你想要通过 VPN 浏览因特网的本地网络地址。
假设 RouterOS 后面的本地网络是 `192.168.0.0/24`，你可以使用 `192.168.0.0/24`
来指定整个网络，或者使用 `192.168.0.10` 来指定仅用于一个设备，依此类推。

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
4. 更多信息请参见 [#1112](https://github.com/hwdsl2/setup-ipsec-vpn/issues/1112#issuecomment-1059628623)。

> 已在以下系统测试   
> mar/02/2022 12:52:57 by RouterOS 6.48   
> RouterBOARD 941-2nD

## IKEv2 故障排除

*其他语言版本: [English](ikev2-howto.md#ikev2-troubleshooting), [中文](ikev2-howto-zh.md#ikev2-故障排除)。*

**另见：** [检查日志及 VPN 状态](clients-zh.md#检查日志及-vpn-状态)，[IKEv1 故障排除](clients-zh.md#ikev1-故障排除) 和 [高级用法](advanced-usage-zh.md)。

* [无法连接到 VPN 服务器](#无法连接到-vpn-服务器)
* [Ubuntu 20.04 无法导入客户端配置](#ubuntu-2004-无法导入客户端配置)
* [macOS Sonoma 客户端重新连接](#macos-sonoma-客户端重新连接)
* [无法连接多个 IKEv2 客户端](#无法连接多个-ikev2-客户端)
* [IKE 身份验证凭证不可接受](#ike-身份验证凭证不可接受)
* [参数错误 policy match error](#参数错误-policy-match-error)
* [参数错误 parameter is incorrect](#参数错误-parameter-is-incorrect)
* [连接 IKEv2 后不能打开网站](#连接-ikev2-后不能打开网站)
* [Windows 10 正在连接](#windows-10-正在连接)
* [其它已知问题](#其它已知问题)

### 无法连接到 VPN 服务器

首先，请确保你的 VPN 客户端设备上指定的 VPN 服务器地址与 IKEv2 辅助脚本输出中的服务器地址**完全一致**。例如，如果在配置 IKEv2 时未指定域名，则不可以使用域名进行连接。要更改 IKEv2 服务器地址，参见[这一小节](#更改-ikev2-服务器地址)。

对于有外部防火墙的服务器（比如 [EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html)/[GCE](https://cloud.google.com/vpc/docs/firewalls)），请为 VPN 打开 UDP 端口 500 和 4500。阿里云用户请参见 [#433](https://github.com/hwdsl2/setup-ipsec-vpn/issues/433)。

[检查日志及 VPN 状态](clients-zh.md#检查日志及-vpn-状态)是否有错误。如果你遇到 retransmission 相关错误并且无法连接，说明 VPN 客户端和服务器之间的网络可能有问题。如果你从中国大陆进行连接，请考虑改用 IPsec VPN 以外的其他解决方案。

### Ubuntu 20.04 无法导入客户端配置

如果你在 2024-04-10 之前安装了 IPsec VPN，并且你的 VPN 服务器运行的是 Ubuntu Linux 版本 20.04，那么你可能会遇到无法在 iOS 或 macOS 设备上导入新生成的客户端配置文件 (`.mobileconfig`) 的问题，例如提示密码不正确。这可能是由 Ubuntu 20.04 上 libnss3 相关软件包的更新引起的，需要对 IKEv2 脚本进行一些更改 ([25670f3](https://github.com/hwdsl2/setup-ipsec-vpn/commit/25670f3))。

要解决此问题，请首先按照[这些步骤](#更新-ikev2-辅助脚本)将服务器上的 IKEv2 脚本更新到最新版本。然后运行 `sudo ikev2.sh` 并选择 "export" 以重新创建客户端配置文件。

### macOS Sonoma 客户端重新连接

macOS 14 (Sonoma) 存在[一个小问题](https://github.com/hwdsl2/setup-ipsec-vpn/issues/1486)，可能会导致 IKEv2 VPN 每 24-48 分钟断开并重新连接一次。其他 macOS 版本不受影响。首先[检查你的 macOS 版本](https://support.apple.com/zh-cn/HT201260)。要解决此问题，请按以下步骤操作。

**注：** 如果你在 2023 年 12 月 10 日之后安装了 IPsec VPN，则无需执行任何操作，因为已经包含以下修复。

1. 编辑 VPN 服务器上的 `/etc/ipsec.d/ikev2.conf`。找到这一行：
   ```
     ike=aes256-sha2,aes128-sha2,aes256-sha1,aes128-sha1
   ```
   并将它替换为以下内容：
   ```
     ike=aes_gcm_c_256-hmac_sha2_256-ecp_256,aes256-sha2,aes128-sha2,aes256-sha1,aes128-sha1
   ```
   **注：** Docker 用户需要首先[在容器中运行 Bash shell](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/docs/advanced-usage-zh.md#在容器中运行-bash-shell)。
1. 保存文件并运行 `service ipsec restart`。Docker 用户：在下面的第 4 步之后退出 (`exit`) 容器并运行 `docker restart ipsec-vpn-server`。
1. 编辑 VPN 服务器上的 `/opt/src/ikev2.sh`。找到以下部分并将其替换为这些新值：
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
1. 运行 `sudo ikev2.sh` 为你的每个 macOS 设备导出（或添加）更新后的客户端配置文件。
1. 从你的 macOS 设备中移除之前导入的 IKEv2 配置文件（如果有），然后导入更新后的 `.mobileconfig` 文件。请参阅[配置 IKEv2 VPN 客户端](#配置-ikev2-vpn-客户端)。Docker 用户请看[配置并使用 IKEv2 VPN](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md#配置并使用-ikev2-vpn)。

### 无法连接多个 IKEv2 客户端

如果要同时连接在同一个 NAT（比如家用路由器）后面的多个 IKEv2 客户端，你需要为每个客户端生成唯一的证书。否则，你可能会遇到稍后连接的客户端影响现有客户端的 VPN 连接，从而导致无法访问 Internet 的问题。

要为其它的 IKEv2 客户端生成证书，运行辅助脚本并添加 `--addclient` 选项。要自定义客户端选项，可以在不添加参数的情况下运行脚本。

```bash
sudo ikev2.sh --addclient [client name]
```

### IKE 身份验证凭证不可接受

如果遇到此错误，请确保你的 VPN 客户端设备上指定的 VPN 服务器地址与 IKEv2 辅助脚本输出中的服务器地址**完全一致**。例如，如果在配置 IKEv2 时未指定域名，则不可以使用域名进行连接。要更改 IKEv2 服务器地址，参见[这一小节](#更改-ikev2-服务器地址)。

### 参数错误 policy match error

要解决此错误，你需要为 IKEv2 启用更强的加密算法，通过修改一次注册表来实现。请下载并导入下面的 `.reg` 文件，或者打开提升权限命令提示符并运行以下命令。

- 适用于 Windows 7, 8, 10 和 11 ([下载 .reg 文件](https://github.com/hwdsl2/vpn-extras/releases/download/v1.0.0/Enable_Stronger_Ciphers_for_IKEv2_on_Windows.reg))

```console
REG ADD HKLM\SYSTEM\CurrentControlSet\Services\RasMan\Parameters /v NegotiateDH2048_AES256 /t REG_DWORD /d 0x1 /f
```

### 参数错误 parameter is incorrect

如果你在尝试使用 IKEv2 模式连接时遇到 "错误 87：参数错误 The parameter is incorrect"，请尝试 [这个 Issue](https://github.com/trailofbits/algo/issues/1051) 中的解决方案，更具体地说，第 2 步 "reset device manager adapters"。

### 连接 IKEv2 后不能打开网站

如果你的 VPN 客户端设备在成功连接到 IKEv2 后无法打开网站，请尝试以下解决方案：

1. 某些云服务提供商，比如 [Google Cloud](https://cloud.google.com)，[默认设置较低的 MTU](https://cloud.google.com/network-connectivity/docs/vpn/concepts/mtu-considerations)。这可能会导致 IKEv2 VPN 客户端的网络问题。要解决此问题，尝试在 VPN 服务器上将 MTU 设置为 1500：

   ```bash
   # 将 ens4 替换为你的服务器上的网络接口名称
   sudo ifconfig ens4 mtu 1500
   ```

   此设置 **不会** 在重启后保持。要永久更改 MTU 大小，请参阅网络上的相关文章。

1. 如果你的 Android 或 Linux VPN 客户端可以连接到 IKEv2 但是无法打开网站，请尝试 [Android/Linux MTU/MSS 问题](clients-zh.md#androidlinux-mtumss-问题) 中的解决方案。

1. Windows VPN 客户端在连接后可能不使用 IKEv2 指定的 DNS 服务器，如果该客户端的因特网适配器的 DNS 服务器在本地网段上。要解决此问题，可以在网络连接属性 -> TCP/IPv4 中手动输入 DNS 服务器，例如 Google Public DNS (8.8.8.8, 8.8.4.4)。更多信息请参见 [Windows DNS 泄漏和 IPv6](clients-zh.md#windows-dns-泄漏和-ipv6)。

### Windows 10 正在连接

如果你使用 Windows 10 并且 VPN 卡在 "正在连接" 状态超过几分钟，尝试以下步骤：

1. 右键单击系统托盘中的无线/网络图标。
1. 选择 **打开"网络和 Internet"设置**，然后在打开的页面中单击左侧的 **VPN**。
1. 选择新的 VPN 连接，然后单击 **连接**。

### 其它已知问题

Windows 自带的 VPN 客户端可能不支持 IKEv2 fragmentation（该功能[需要](https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-ikee/74df968a-7125-431d-9c98-4ea929e548dc) Windows 10 v1803 或更新版本）。在有些网络上，这可能会导致连接错误或其它连接问题。你可以尝试换用 [IPsec/L2TP](clients-zh.md) 或 [IPsec/XAuth](clients-xauth-zh.md) 模式。

## 管理 IKEv2 客户端

* [列出已有的客户端](#列出已有的客户端)
* [添加客户端证书](#添加客户端证书)
* [导出已有的客户端的配置](#导出已有的客户端的配置)
* [删除客户端证书](#删除客户端证书)
* [吊销客户端证书](#吊销客户端证书)

### 列出已有的客户端

要列出已有的 IKEv2 客户端的名称，运行辅助脚本并添加 `--listclients` 选项。使用参数 `-h` 显示使用信息。

```bash
sudo ikev2.sh --listclients
```

### 添加客户端证书

要为其它的 IKEv2 客户端生成证书，运行辅助脚本并添加 `--addclient` 选项。要自定义客户端选项，可以在不添加参数的情况下运行脚本。

```bash
sudo ikev2.sh --addclient [client name]
```

另外，你也可以手动添加客户端证书。参见 [这一小节](#手动配置-ikev2) 的第 4 步。

### 导出已有的客户端的配置

在默认情况下，IKEv2 辅助脚本在运行后会导出客户端配置。如果之后你想要导出一个已有的客户端，可以运行：

```bash
sudo ikev2.sh --exportclient [client name]
```

### 删除客户端证书

**重要：** 从 IPsec 数据库中删除一个客户端证书 **并不能** 阻止 VPN 客户端使用该证书连接！对于此用例，你 **必须** [吊销该客户端证书](#吊销客户端证书)，而不是删除证书。

<details>
<summary>
首先，请阅读上面的重要说明。然后点这里查看详情。
</summary>

**警告：** 这将**永久删除**客户端证书和私钥。此操作**不可撤销**！

如果要删除一个现有的客户端：

```bash
sudo ikev2.sh --deleteclient [client name]
```

<details>
<summary>
或者，你也可以手动删除一个客户端证书。
</summary>

1. 列出 IPsec 证书数据库中的证书：

   ```bash
   certutil -L -d sql:/etc/ipsec.d
   ```

   示例输出：

   ```
   Certificate Nickname                               Trust Attributes
                                                      SSL,S/MIME,JAR/XPI

   IKEv2 VPN CA                                       CTu,u,u
   ($PUBLIC_IP)                                       u,u,u
   vpnclient                                          u,u,u
   ```

1. 删除客户端证书和私钥。将下面的 "Nickname" 替换为你想要删除的客户端证书的昵称，例如 `vpnclient`。

   ```bash
   certutil -F -d sql:/etc/ipsec.d -n "Nickname"
   certutil -D -d sql:/etc/ipsec.d -n "Nickname" 2>/dev/null
   ```

1. （可选步骤）删除之前为该客户端生成的配置文件（`.p12`, `.mobileconfig` 和 `.sswan` 文件），如果存在。
</details>
</details>

### 吊销客户端证书

在某些情况下，你可能需要吊销一个之前生成的 VPN 客户端证书。

如果要吊销一个现有的客户端：

```bash
sudo ikev2.sh --revokeclient [client name]
```

<details>
<summary>
另外，你也可以手动吊销客户端证书。
</summary>

另外，你也可以手动吊销客户端证书。这可以通过 `crlutil` 实现。下面举例说明，这些命令必须用 `root` 账户运行。

1. 检查证书数据库，并且找到想要吊销的客户端证书的昵称。

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

   在这个例子中，我们将要吊销昵称为 `vpnclient-to-revoke` 的客户端证书。它是由 `IKEv2 VPN CA` 签发的。

1. 找到该客户端证书的序列号。

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

   根据上面的输出，我们知道该序列号为十六进制的 `CD69FF74`，也就是十进制的 `3446275956`。它将在以下步骤中使用。

1. 创建一个新的证书吊销列表 (CRL)。该步骤对于每个 CA 只需运行一次。

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

1. 将你想要吊销的客户端证书添加到 CRL。在这里我们指定该证书的（十进制）序列号，以及吊销时间（UTC时间，格式：GeneralizedTime (YYYYMMDDhhmmssZ)）。

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

   **注：** 如果需要从 CRL 删除一个证书，可以将上面的 `addcert 3446275956 20200606220100Z` 替换为 `rmcert 3446275956`。关于 `crlutil` 的其它用法参见 [这里](https://firefox-source-docs.mozilla.org/security/nss/legacy/tools/nss_tools_crlutil/index.html)。

1. 最后，让 Libreswan 重新读取已更新的 CRL。

   ```bash
   ipsec crls
   ```
</details>

## 更改 IKEv2 服务器地址

在某些情况下，你可能需要在配置之后更改 IKEv2 服务器地址。例如切换为使用域名，或者在服务器的 IP 更改之后。请注意，你在 VPN 客户端指定的服务器地址必须与 IKEv2 辅助脚本输出中的服务器地址 **完全一致**，否则客户端可能无法连接。

要更改服务器地址，运行 [辅助脚本](../extras/ikev2changeaddr.sh) 并按提示操作。

```bash
wget https://get.vpnsetup.net/ikev2addr -O ikev2addr.sh
sudo bash ikev2addr.sh
```

**重要：** 运行此脚本后，你必须手动更新任何现有 IKEv2 客户端设备上的服务器地址以及 Remote ID（如果适用）。对于 iOS 客户端，你需要运行 `sudo ikev2.sh` 以导出更新后的客户端配置文件并导入 iOS 设备。

## 更新 IKEv2 辅助脚本

IKEv2 辅助脚本会不时更新，以进行错误修复和改进（[更新日志](https://github.com/hwdsl2/setup-ipsec-vpn/commits/master/extras/ikev2setup.sh)）。 当有新版本可用时，你可以更新服务器上的 IKEv2 辅助脚本。这是可选的。请注意，这些命令将覆盖任何现有的 `ikev2.sh`。

```bash
wget https://get.vpnsetup.net/ikev2 -O /opt/src/ikev2.sh
chmod +x /opt/src/ikev2.sh && ln -s /opt/src/ikev2.sh /usr/bin 2>/dev/null
```

## 使用辅助脚本配置 IKEv2

**注：** 默认情况下，运行 VPN 安装脚本时会自动配置 IKEv2。你可以跳过此部分并转到 [配置 IKEv2 VPN 客户端](#配置-ikev2-vpn-客户端)。

**重要：** 在继续之前，你应该已经成功地 [搭建自己的 VPN 服务器](../README-zh.md)。Docker 用户请看 [配置并使用 IKEv2 VPN](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md#配置并使用-ikev2-vpn)。

使用这个 [辅助脚本](../extras/ikev2setup.sh) 来自动地在 VPN 服务器上配置 IKEv2：

```bash
# 使用默认选项配置 IKEv2
sudo ikev2.sh --auto
# 或者你也可以自定义 IKEv2 选项
sudo ikev2.sh
```

**注：** 如果已配置 IKEv2，但是你想要自定义 IKEv2 选项，首先 [移除 IKEv2](#移除-ikev2)，然后运行 `sudo ikev2.sh` 重新配置。

在完成之后，请转到 [配置 IKEv2 VPN 客户端](#配置-ikev2-vpn-客户端)。高级用户可以启用 [仅限 IKEv2 模式](advanced-usage-zh.md#仅限-ikev2-的-vpn)。这是可选的。

<details>
<summary>
错误："sudo: ikev2.sh: command not found".
</summary>

如果你使用了较早版本的 VPN 安装脚本，这是正常的。首先下载 IKEv2 辅助脚本：

```bash
wget https://get.vpnsetup.net/ikev2 -O /opt/src/ikev2.sh
chmod +x /opt/src/ikev2.sh && ln -s /opt/src/ikev2.sh /usr/bin
```

然后按照上面的说明运行脚本。
</details>
<details>
<summary>
你可以指定一个域名，客户端名称和/或另外的 DNS 服务器。这是可选的。
</summary>

在使用自动模式安装 IKEv2 时，高级用户可以指定一个域名作为 IKEv2 服务器地址。这是可选的。该域名必须是一个全称域名(FQDN)。示例如下：

```bash
sudo VPN_DNS_NAME='vpn.example.com' ikev2.sh --auto
```

类似地，你可以指定第一个 IKEv2 客户端的名称。如果未指定，则使用默认值 `vpnclient`。

```bash
sudo VPN_CLIENT_NAME='your_client_name' ikev2.sh --auto
```

在 VPN 已连接时，IKEv2 客户端默认配置为使用 [Google Public DNS](https://developers.google.com/speed/public-dns/)。你可以为 IKEv2 指定另外的 DNS 服务器。示例如下：

```bash
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 ikev2.sh --auto
```

默认情况下，导入 IKEv2 客户端配置时不需要密码。你可以选择使用随机密码保护客户端配置文件。

```bash
sudo VPN_PROTECT_CONFIG=yes ikev2.sh --auto
```
</details>
<details>
<summary>
查看 IKEv2 脚本的使用信息。
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

## 手动配置 IKEv2

除了使用 [辅助脚本](#使用辅助脚本配置-ikev2) 之外，高级用户也可以手动在 VPN 服务器上配置 IKEv2。在继续之前，推荐 [升级 Libreswan](../README-zh.md#升级libreswan) 到最新版本。

下面举例说明如何手动在 Libreswan 上配置 IKEv2。以下命令必须用 `root` 账户运行。

<details>
<summary>
查看手动在 Libreswan 上配置 IKEv2 的示例步骤。
</summary>

1. 获取 VPN 服务器的公共 IP 地址，将它保存到变量并检查。

   ```bash
   PUBLIC_IP=$(dig @resolver1.opendns.com -t A -4 myip.opendns.com +short)
   [ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(wget -t 2 -T 10 -qO- http://ipv4.icanhazip.com)
   printf '%s\n' "$PUBLIC_IP"
   ```

   检查并确保以上命令的输出与服务器的公共 IP 一致。该变量将在以下步骤中使用。

   **注：** 另外，在这里你也可以指定 VPN 服务器的域名。例如： `PUBLIC_IP=myvpn.example.com`。

1. 添加一个新的 IKEv2 连接：

   ```bash
   if ! grep -qs '^include /etc/ipsec\.d/\*\.conf$' /etc/ipsec.conf; then
     echo >> /etc/ipsec.conf
     echo 'include /etc/ipsec.d/*.conf' >> /etc/ipsec.conf
   fi
   ```

   **注：** 如果你在上面的第一步指定了服务器的域名（而不是 IP 地址），则必须将以下命令中的 `leftid=$PUBLIC_IP` 换成 `leftid=@$PUBLIC_IP`。

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

   还需要在该文件中添加一些行。首先查看你的 Libreswan 版本，然后运行以下命令之一：

   ```bash
   ipsec --version
   ```

   如果是 Libreswan 3.23 或更新版本：

   ```bash
   cat >> /etc/ipsec.d/ikev2.conf <<EOF
     modecfgdns="8.8.8.8 8.8.4.4"
     encapsulation=yes
     mobike=no
   EOF
   ```

   **注：** MOBIKE IKEv2 协议扩展允许 VPN 客户端更改网络连接点，例如在移动数据和 Wi-Fi 之间切换，并使 VPN 保持连接。如果你的服务器（或者 Docker 主机）的操作系统 **不是** Ubuntu Linux，并且你想要启用 MOBIKE 支持，可以将上面命令中的 `mobike=no` 换成 `mobike=yes`。**不要** 在 Ubuntu 系统或者 Raspberry Pi 上启用该选项。

   如果是 Libreswan 3.19-3.22：

   ```bash
   cat >> /etc/ipsec.d/ikev2.conf <<EOF
     modecfgdns1=8.8.8.8
     modecfgdns2=8.8.4.4
     encapsulation=yes
   EOF
   ```

   如果是 Libreswan 3.18 或更早版本：

   ```bash
   cat >> /etc/ipsec.d/ikev2.conf <<EOF
     modecfgdns1=8.8.8.8
     modecfgdns2=8.8.4.4
     forceencaps=yes
   EOF
   ```

1. 生成 Certificate Authority (CA) 和 VPN 服务器证书。

   **注：** 使用 "-v" 参数指定证书的有效期（单位：月），例如 "-v 120"。

   生成 CA 证书：

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

   生成 VPN 服务器证书：

   **注：** 如果你在上面的第一步指定了服务器的域名（而不是 IP 地址），则必须将以下命令中的 `--extSAN "ip:$PUBLIC_IP,dns:$PUBLIC_IP"` 换成 `--extSAN "dns:$PUBLIC_IP"`。

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

1. 生成客户端证书，然后导出 `.p12` 文件，该文件包含客户端证书，私钥以及 CA 证书。

   **注：** 你可以重复本步骤来为其它的客户端生成证书，但必须将所有的 `vpnclient` 换成比如 `vpnclient2`，等等。如果要同时连接在同一个 NAT（比如家用路由器）后面的多个 IKEv2 客户端，你需要为每个客户端生成唯一的证书。

   生成客户端证书：

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

   导出 `.p12` 文件：

   ```bash
   pk12util -d sql:/etc/ipsec.d -n "vpnclient" -o vpnclient.p12
   ```

   ```
   Enter password for PKCS12 file:
   Re-enter password:
   pk12util: PKCS12 EXPORT SUCCESSFUL
   ```

   指定一个安全的密码以保护导出的 `.p12` 文件（在导入到 iOS 或 macOS 设备时，该密码不能为空）。

1. （适用于 iOS 客户端） 导出 CA 证书到 `ca.cer`：

   ```bash
   certutil -L -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" -a -o ca.cer
   ```

1. 证书数据库现在应该包含以下内容：

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

   **注：** 如需显示证书内容，可使用 `certutil -L -d sql:/etc/ipsec.d -n "Nickname"`。要吊销客户端证书，请转到[这一节](#吊销客户端证书)。关于 `certutil` 的其它用法参见 [这里](https://firefox-source-docs.mozilla.org/security/nss/legacy/tools/nss_tools_certutil/index.html)。

1. **（重要）重启 IPsec 服务**：

   ```bash
   service ipsec restart
   ```

在继续之前，你**必须**重启 IPsec 服务。VPN 服务器上的 IKEv2 配置到此已完成。下一步：[配置 VPN 客户端](#配置-ikev2-vpn-客户端)。
</details>

## 移除 IKEv2

如果你想要从 VPN 服务器移除 IKEv2，但是保留 [IPsec/L2TP](clients-zh.md) 和 [IPsec/XAuth ("Cisco IPsec")](clients-xauth-zh.md) 模式（如果已安装），可以运行辅助脚本。**警告：** 这将**永久删除**所有的 IKEv2 配置（包括证书和密钥），并且**不可撤销**！

```bash
sudo ikev2.sh --removeikev2
```

在移除 IKEv2 之后，如果你想要重新配置 IKEv2，参见 [这一小节](#使用辅助脚本配置-ikev2)。

<details>
<summary>
另外，你也可以手动移除 IKEv2。
</summary>

要手动从 VPN 服务器移除 IKEv2，但是保留 [IPsec/L2TP](clients-zh.md) 和 [IPsec/XAuth ("Cisco IPsec")](clients-xauth-zh.md) 模式，按照以下步骤操作。这些命令必须用 `root` 账户运行。

**警告：** 这将**永久删除**所有的 IKEv2 配置（包括证书和密钥），并且**不可撤销**！

1. 重命名（或者删除）IKEv2 配置文件：

   ```bash
   mv /etc/ipsec.d/ikev2.conf /etc/ipsec.d/ikev2.conf.bak
   ```

   **注：** 如果你使用了较旧版本（2020-05-31 之前）的 IKEv2 辅助脚本或者配置说明，文件 `/etc/ipsec.d/ikev2.conf` 可能不存在。在该情况下，请移除文件 `/etc/ipsec.conf` 中的 `conn ikev2-cp` 部分。

1. **（重要）重启 IPsec 服务**：

   ```bash
   service ipsec restart
   ```

1. 列出 IPsec 证书数据库中的证书：

   ```bash
   certutil -L -d sql:/etc/ipsec.d
   ```

   示例输出：

   ```
   Certificate Nickname                               Trust Attributes
                                                      SSL,S/MIME,JAR/XPI

   IKEv2 VPN CA                                       CTu,u,u
   ($PUBLIC_IP)                                       u,u,u
   vpnclient                                          u,u,u
   ```

1. 删除证书吊销列表 (CRL)，如果存在：

   ```bash
   crlutil -D -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" 2>/dev/null
   ```

1. 删除证书和密钥。将下面的 "Nickname" 替换为每个证书的昵称。为每个证书重复这些命令。在完成后，再次列出 IPsec 证书数据库中的证书，并确认列表为空。

   ```bash
   certutil -F -d sql:/etc/ipsec.d -n "Nickname"
   certutil -D -d sql:/etc/ipsec.d -n "Nickname" 2>/dev/null
   ```
</details>

## 参考链接

* https://libreswan.org/wiki/VPN_server_for_remote_clients_using_IKEv2
* https://libreswan.org/wiki/HOWTO:_Using_NSS_with_libreswan
* https://libreswan.org/man/ipsec.conf.5.html
* https://docs.strongswan.org/docs/5.9/interop/windowsClients.html
* https://docs.strongswan.org/docs/5.9/os/androidVpnClient.html
* https://firefox-source-docs.mozilla.org/security/nss/legacy/tools/nss_tools_certutil/index.html
* https://firefox-source-docs.mozilla.org/security/nss/legacy/tools/nss_tools_crlutil/index.html

## 授权协议

版权所有 (C) 2016-2024 [Lin Song](https://github.com/hwdsl2) [![View my profile on LinkedIn](https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png)](https://www.linkedin.com/in/linsongui)   

[![Creative Commons License](https://i.creativecommons.org/l/by-sa/3.0/88x31.png)](http://creativecommons.org/licenses/by-sa/3.0/)   
这个项目是以 [知识共享署名-相同方式共享3.0](http://creativecommons.org/licenses/by-sa/3.0/) 许可协议授权。   
必须署名： 请包括我的名字在任何衍生产品，并且让我知道你是如何改善它的！
