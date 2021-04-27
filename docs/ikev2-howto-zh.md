# IKEv2 VPN 配置和使用指南

*其他语言版本: [English](ikev2-howto.md), [简体中文](ikev2-howto-zh.md).*

**注：** 你也可以使用 [IPsec/L2TP](clients-zh.md) 或者 [IPsec/XAuth](clients-xauth-zh.md) 模式连接。

* [导言](#导言)
* [使用辅助脚本](#使用辅助脚本)
* [配置 IKEv2 VPN 客户端](#配置-ikev2-vpn-客户端)
* [管理客户端证书](#管理客户端证书)
* [手动在 VPN 服务器上配置 IKEv2](#手动在-vpn-服务器上配置-ikev2)
* [故障排除](#故障排除)
* [移除 IKEv2](#移除-ikev2)
* [参考链接](#参考链接)

## 导言

现代操作系统（比如 Windows 7 和更新版本）支持 IKEv2 协议标准。因特网密钥交换（英语：Internet Key Exchange，简称 IKE 或 IKEv2）是一种网络协议，归属于 IPsec 协议族之下，用以创建安全关联 (Security Association, SA)。与 IKE 版本 1 相比较，IKEv2 的 <a href="https://en.wikipedia.org/wiki/Internet_Key_Exchange#Improvements_with_IKEv2" target="_blank">功能改进</a> 包括比如通过 MOBIKE 实现 Standard Mobility 支持，以及更高的可靠性。

Libreswan 支持通过使用 RSA 签名算法的 X.509 Machine Certificates 来对 IKEv2 客户端进行身份验证。该方法无需 IPsec PSK, 用户名或密码。它可以用于以下系统：

- Windows 7, 8.x 和 10
- OS X (macOS)
- iOS (iPhone/iPad)
- Android 4.x 和更新版本（使用 strongSwan VPN 客户端）
- Linux

在按照本指南操作之后，你将可以选择三种模式中的任意一种连接到 VPN：IKEv2，以及已有的 [IPsec/L2TP](clients-zh.md) 和 [IPsec/XAuth ("Cisco IPsec")](clients-xauth-zh.md) 模式。

## 使用辅助脚本

**重要：** 在继续之前，你应该已经成功地 <a href="../README-zh.md" target="_blank">搭建自己的 VPN 服务器</a>，并且（可选但推荐）<a href="../README-zh.md#升级libreswan" target="_blank">升级 Libreswan</a>。**Docker 用户请看 <a href="https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md#配置并使用-ikev2-vpn" target="_blank">这里</a>**。

使用这个辅助脚本来自动地在 VPN 服务器上配置 IKEv2：

```
sudo bash /opt/src/ikev2.sh --auto
```

该 <a href="../extras/ikev2setup.sh" target="_blank">脚本</a> 必须使用 `bash` 而不是 `sh` 运行。以上命令使用自动模式和默认选项运行辅助脚本。如果你想要自定义 IKEv2 安装选项，请在运行脚本时去掉 `--auto` 参数。在完成之后，请转到 [配置 IKEv2 VPN 客户端](#配置-ikev2-vpn-客户端)。

<details>
<summary>
错误："bash: /opt/src/ikev2.sh: No such file or directory".
</summary>

如果你使用了较早版本的 VPN 安装脚本，这是正常的。请使用以下命令下载并运行 IKEv2 辅助脚本：

```
wget https://git.io/ikev2setup -O /opt/src/ikev2.sh && sudo bash /opt/src/ikev2.sh --auto
```
</details>
<details>
<summary>
你可以指定一个域名，客户端名称和/或另外的 DNS 服务器。这是可选的。点这里查看详情。
</summary>

在使用自动模式安装 IKEv2 时，高级用户可以指定一个域名作为 VPN 服务器的地址。这是可选的。该域名必须是一个全称域名(FQDN)。示例如下：

```
sudo VPN_DNS_NAME='vpn.example.com' bash /opt/src/ikev2.sh --auto
```

类似地，你可以指定第一个 IKEv2 客户端的名称。这是可选的。如果未指定，则使用默认值 `vpnclient`。

```
sudo VPN_CLIENT_NAME='your_client_name' bash /opt/src/ikev2.sh --auto
```

在 VPN 已连接时，IKEv2 客户端默认配置为使用 <a href="https://developers.google.com/speed/public-dns/" target="_blank">Google Public DNS</a>。在使用自动模式安装 IKEv2 时，你可以指定另外的 DNS 服务器。这是可选的。示例如下：

```
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 bash /opt/src/ikev2.sh --auto
```
</details>
<details>
<summary>
单击此处以查看 IKEv2 辅助脚本的使用信息。
</summary>

```
Usage: bash ikev2.sh [options]

Options:
  --auto                        run IKEv2 setup in auto mode using default options (for initial setup only)
  --addclient [client name]     add a new client using default options (after IKEv2 setup)
  --exportclient [client name]  export configuration for an existing client (after IKEv2 setup)
  --listclients                 list the names of existing clients (after IKEv2 setup)
  --removeikev2                 remove IKEv2 and delete all certificates and keys from the IPsec database
  -h, --help                    show this help message and exit

To customize IKEv2 or client options, run this script without arguments.
```
</details>

## 配置 IKEv2 VPN 客户端

*其他语言版本: [English](ikev2-howto.md#configure-ikev2-vpn-clients), [简体中文](ikev2-howto-zh.md#配置-ikev2-vpn-客户端).*

**注：** 客户端配置文件的密码可以在 IKEv2 辅助脚本的输出中找到。如果你想要添加或者导出 IKEv2 客户端，只需重新运行[辅助脚本](#使用辅助脚本)。使用参数 `-h` 显示使用信息。

* [Windows 7, 8.x 和 10](#windows-7-8x-和-10)
* [OS X (macOS)](#os-x-macos)
* [iOS (iPhone/iPad)](#ios)
* [Android](#android)
* [Linux](#linux)

### Windows 7, 8.x 和 10

1. 将生成的 `.p12` 文件安全地传送到你的计算机，然后导入到 "计算机账户" 证书存储。要导入 `.p12` 文件，打开 <a href="http://www.cnblogs.com/xxcanghai/p/4610054.html" target="_blank">提升权限命令提示符</a> 并运行以下命令：

   ```console
   # 导入 .p12 文件（换成你自己的值）
   certutil -f -importpfx ".p12文件的位置和名称" NoExport
   ```

   另外，你也可以手动导入 `.p12` 文件。详细步骤请看 <a href="https://wiki.strongswan.org/projects/strongswan/wiki/Win7Certs" target="_blank">这里</a>。在导入证书后，你必须确保将客户端证书放在 "个人 -> 证书" 目录中，并且将 CA 证书放在 "受信任的根证书颁发机构 -> 证书" 目录中。

   **注：** Ubuntu 18.04 用户在尝试导入 `.p12` 文件时可能会遇到错误 "输入的密码不正确"。参见 [故障排除](#故障排除)。

1. 在 Windows 计算机上添加一个新的 IKEv2 VPN 连接。对于 Windows 8.x 和 10，推荐从命令提示符运行以下命令创建 VPN 连接，以达到更佳的安全性和性能。Windows 7 不支持这些命令，你可以手动创建 VPN 连接（见下面）。

   ```console
   # 创建 VPN 连接（将服务器地址换成你自己的值）
   powershell -command "Add-VpnConnection -ServerAddress '你的 VPN 服务器 IP（或者域名）' -Name 'My IKEv2 VPN' -TunnelType IKEv2 -AuthenticationMethod MachineCertificate -EncryptionLevel Required -PassThru"
   # 设置 IPsec 参数
   powershell -command "Set-VpnConnectionIPsecConfiguration -ConnectionName 'My IKEv2 VPN' -AuthenticationTransformConstants GCMAES128 -CipherTransformConstants GCMAES128 -EncryptionMethod AES256 -IntegrityCheckMethod SHA256 -PfsGroup None -DHGroup Group14 -PassThru -Force"
   ```

   另外，你也可以手动创建 VPN 连接。详细步骤请看 <a href="https://wiki.strongswan.org/projects/strongswan/wiki/Win7Config" target="_blank">这里</a>。如果你在配置 IKEv2 时指定了服务器的域名（而不是 IP 地址），则必须在 **Internet地址** 字段中输入该域名。

1. （**此步骤为必须**，如果你手动创建了 VPN 连接）为 IKEv2 启用更强的加密算法，通过修改一次注册表来实现。请下载并导入下面的 `.reg` 文件，或者打开提升权限命令提示符并运行以下命令。更多信息请看 <a href="https://wiki.strongswan.org/projects/strongswan/wiki/WindowsClients#AES-256-CBC-and-MODP2048" target="_blank">这里</a>。

   - 适用于 Windows 7, 8.x 和 10 ([下载 .reg 文件](https://dl.ls20.com/reg-files/v1/Enable_Stronger_Ciphers_for_IKEv2_on_Windows.reg))

     ```console
     REG ADD HKLM\SYSTEM\CurrentControlSet\Services\RasMan\Parameters /v NegotiateDH2048_AES256 /t REG_DWORD /d 0x1 /f
     ```

要连接到 VPN：单击系统托盘中的无线/网络图标，选择新的 VPN 连接，然后单击 **连接**。连接成功后，你可以到 <a href="https://www.ipchicken.com" target="_blank">这里</a> 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

如果在连接过程中遇到错误，请参见 [故障排除](#故障排除)。

### OS X (macOS)

首先，将生成的 `.mobileconfig` 文件安全地传送到你的 Mac，然后双击并按提示操作，以导入为 macOS 配置描述文件。在完成之后，检查并确保 "IKEv2 VPN" 显示在系统偏好设置 -> 描述文件中。

要连接到 VPN：

1. 打开系统偏好设置并转到网络部分。
1. 选择与 `你的 VPN 服务器 IP`（或者域名）对应的 VPN 连接。
1. 选中 **在菜单栏中显示 VPN 状态** 复选框。
1. 单击 **连接**。

（可选功能）你可以选择启用 <a href="https://developer.apple.com/documentation/networkextension/personal_vpn/vpn_on_demand_rules" target="_blank">VPN On Demand（按需连接）</a> ，该功能在使用 Wi-Fi 网络时自动建立 VPN 连接。要启用它，选中 VPN 连接的 **按需连接** 复选框，然后单击 **应用**。

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
1. 单击 **应用** 保存VPN连接信息。
1. 单击 **连接**。
</details>

连接成功后，你可以到 <a href="https://www.ipchicken.com" target="_blank">这里</a> 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

如果在连接过程中遇到错误，请参见 [故障排除](#故障排除)。

### iOS

首先，将生成的 `.mobileconfig` 文件安全地传送到你的 iOS 设备，并且导入为 iOS 配置描述文件。要传送文件，你可以使用：

1. AirDrop（隔空投送），或者
1. 使用 iTunes 的 "文件共享" 功能上传到设备，然后打开 iOS 设备上的 "文件" 应用程序，将上传的文件移动到 "On My iPhone" 目录下。然后单击它并到 "设置" 应用程序中导入，或者
1. 将文件放在一个你的安全的托管网站上，然后在 Mobile Safari 中下载并导入它们。

在完成之后，检查并确保 "IKEv2 VPN" 显示在设置 -> 通用 -> 描述文件中。

要连接到 VPN：

1. 进入设置 -> 通用 -> VPN。
1. 选择与 `你的 VPN 服务器 IP`（或者域名）对应的 VPN 连接。
1. 启用 **VPN** 连接。

（可选功能）你可以选择启用 <a href="https://developer.apple.com/documentation/networkextension/personal_vpn/vpn_on_demand_rules" target="_blank">VPN On Demand（按需连接）</a> ，该功能在使用 Wi-Fi 网络时自动建立 VPN 连接。要启用它，单击 VPN 连接右边的 "i" 图标，然后启用 **按需连接**。

<details>
<summary>
如果你手动配置 IKEv2 而不是使用辅助脚本，点这里查看步骤。
</summary>

首先，将生成的 `ikev2vpnca.cer` 和 `.p12` 文件安全地传送到你的 iOS 设备，并且逐个导入为 iOS 配置描述文件。要传送文件，你可以使用：

1. AirDrop（隔空投送），或者
1. 使用 iTunes 的 "文件共享" 功能上传到设备，然后打开 iOS 设备上的 "文件" 应用程序，将上传的文件移动到 "On My iPhone" 目录下。然后逐个单击它们并到 "设置" 应用程序中导入，或者
1. 将文件放在一个你的安全的托管网站上，然后在 Mobile Safari 中下载并导入它们。

在完成之后，检查并确保新的客户端证书和 `IKEv2 VPN CA` 都显示在设置 -> 通用 -> 描述文件中。

1. 进入设置 -> 通用 -> VPN。
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

连接成功后，你可以到 <a href="https://www.ipchicken.com" target="_blank">这里</a> 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

如果在连接过程中遇到错误，请参见 [故障排除](#故障排除)。

### Android

1. 将生成的 `.sswan` 文件安全地传送到你的 Android 设备。
1. 从 **Google Play** 安装 <a href="https://play.google.com/store/apps/details?id=org.strongswan.android" target="_blank">strongSwan VPN 客户端</a>。
1. 启动 strongSwan VPN 客户端。
1. 单击右上角的 "更多选项" 菜单，然后单击 **导入VPN配置**。
1. 选择你从服务器传送过来的 `.sswan` 文件。   
   **注：** 要查找 `.sswan` 文件，单击左上角的抽拉式菜单，然后浏览到你保存文件的目录。
1. 在 "导入VPN配置" 屏幕上，单击 **从VPN配置导入证书**，并按提示操作。
1. 在 "选择证书" 屏幕上，选择新的客户端证书并单击 **选择**。
1. 单击 **导入**。
1. 单击新的 VPN 配置文件以开始连接。

<details>
<summary>
如果你的设备运行 Android 6.0 或更早版本，点这里查看额外的步骤。
</summary>

如果你的设备运行 Android 6.0 (Marshmallow) 或更早版本，要使用 strongSwan VPN 客户端连接，你必须更改 VPN 服务器上的以下设置：编辑服务器上的 `/etc/ipsec.d/ikev2.conf`。在 `conn ikev2-cp` 小节的末尾添加 `authby=rsa-sha1`，开头必须空两格。保存文件并运行 `service ipsec restart`。
</details>

（可选功能）你可以选择启用 Android 上的 "始终开启的 VPN" 功能。启动 **设置** 应用程序，进入 网络和互联网 -> 高级 -> VPN，单击 "strongSwan VPN 客户端" 右边的设置图标，然后启用 **始终开启的 VPN** 以及 **屏蔽未使用 VPN 的所有连接** 选项。

<details>
<summary>
如果你手动配置 IKEv2 而不是使用辅助脚本，点这里查看步骤。
</summary>

**Android 10 和更新版本:**

1. 将生成的 `.p12` 文件安全地传送到你的 Android 设备。
1. 从 **Google Play** 安装 <a href="https://play.google.com/store/apps/details?id=org.strongswan.android" target="_blank">strongSwan VPN 客户端</a>。
1. 启动 **设置** 应用程序。
1. 进入 安全 -> 高级 -> 加密与凭据。
1. 单击 **从存储设备（或 SD 卡）安装证书**。
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
1. 从 **Google Play** 安装 <a href="https://play.google.com/store/apps/details?id=org.strongswan.android" target="_blank">strongSwan VPN 客户端</a>。
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

连接成功后，你可以到 <a href="https://www.ipchicken.com" target="_blank">这里</a> 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

如果在连接过程中遇到错误，请参见 [故障排除](#故障排除)。

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
# 注：你将需要输入 import password，它可以在 IKEv2 辅助脚本的输出中找到。
openssl pkcs12 -in vpnclient.p12 -cacerts -nokeys -out ikev2vpnca.cer
openssl pkcs12 -in vpnclient.p12 -clcerts -nokeys -out vpnclient.cer
openssl pkcs12 -in vpnclient.p12 -nocerts -nodes  -out vpnclient.key
rm vpnclient.p12

# （重要）保护证书和私钥文件
# 注：这一步是可选的，但强烈推荐。
sudo chown root.root ikev2vpnca.cer vpnclient.cer vpnclient.key
sudo chmod 600 ikev2vpnca.cer vpnclient.cer vpnclient.key
```

然后你可以创建并启用 VPN 连接：

1. 进入 Settings -> Network -> VPN。单击 **+** 按钮。
1. 选择 **IPsec/IKEv2 (strongswan)**。
1. 在 **Name** 字段中输入任意内容。
1. 在 **Gateway (Server)** 部分的 **Address** 字段中输入 `你的 VPN 服务器 IP`（或者域名）。
1. 为 **Certificate** 字段选择 `ikev2vpnca.cer` 文件。
1. 在 **Client** 部分的 **Authentication** 下拉菜单选择 **Certificate(/private key)**。
1. 在 **Certificate** 下拉菜单（如果存在）选择 **Certificate/private key**。
1. 为 **Certificate (file)** 字段选择 `vpnclient.cer` 文件。 
1. 为 **Private key** 字段选择 `vpnclient.key` 文件。 
1. 在 **Options** 部分，选中 **Request an inner IP address** 复选框。
1. 在 **Cipher proposals (Algorithms)** 部分，选中 **Enable custom proposals** 复选框。
1. 保持 **IKE** 字段空白。
1. 在 **ESP** 字段中输入 `aes128gcm16`.
1. 单击 **Add** 保存 VPN 连接信息。
1. 启用 **VPN** 连接。

连接成功后，你可以到 <a href="https://www.ipchicken.com" target="_blank">这里</a> 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

如果在连接过程中遇到错误，请参见 [故障排除](#故障排除)。

## 管理客户端证书

### 列出已有的客户端

如果要列出已有的 IKEv2 客户端的名称，运行 [辅助脚本](#使用辅助脚本) 并添加 `--listclients` 选项。使用参数 `-h` 显示使用信息。

### 添加一个客户端证书

如果要为更多的 IKEv2 客户端生成证书，只需重新运行 [辅助脚本](#使用辅助脚本)。或者你可以看 [这一小节](#手动在-vpn-服务器上配置-ikev2) 的第 4 步。

### 导出一个已有的客户端的配置

在默认情况下，[IKEv2 辅助脚本](#使用辅助脚本) 在运行后会导出客户端配置。如果之后你想要为一个已有的客户端导出配置，重新运行辅助脚本并选择适当的选项。

### 删除一个客户端证书

**重要：** 从 IPsec 数据库中删除一个客户端证书 **并不能** 阻止 VPN 客户端使用该证书连接！对于此用例，你 **必须** [吊销该客户端证书](#吊销一个客户端证书)，而不是删除证书。

<details>
<summary>
首先，请阅读上面的重要说明。然后点这里查看详情。
</summary>

**重要：** 请先阅读上面的重要说明。如果你仍然想要删除证书，参见下面的步骤。此操作 **不可撤销**！

如果要删除一个客户端证书：

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

### 吊销一个客户端证书

在某些情况下，你可能需要吊销一个之前生成的 VPN 客户端证书。这可以通过 `crlutil` 实现。下面举例说明，这些命令必须用 `root` 账户运行。

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

   **注：** 如果需要从 CRL 删除一个证书，可以将上面的 `addcert 3446275956 20200606220100Z` 替换为 `rmcert 3446275956`。关于 `crlutil` 的其它用法参见 <a href="https://developer.mozilla.org/en-US/docs/Mozilla/Projects/NSS/tools/NSS_Tools_crlutil" target="_blank">这里</a>。

1. 最后，让 Libreswan 重新读取已更新的 CRL。

   ```bash
   ipsec crls
   ```

## 手动在 VPN 服务器上配置 IKEv2

除了使用 [辅助脚本](#使用辅助脚本) 之外，高级用户也可以手动配置 IKEv2。在继续之前，推荐 <a href="../README-zh.md#升级libreswan" target="_blank">升级 Libreswan</a> 到最新版本。

下面举例说明如何手动在 Libreswan 上配置 IKEv2。以下命令必须用 `root` 账户运行。

1. 获取 VPN 服务器的公共 IP 地址，将它保存到变量并检查。

   ```bash
   PUBLIC_IP=$(dig @resolver1.opendns.com -t A -4 myip.opendns.com +short)
   [ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(wget -t 3 -T 15 -qO- http://ipv4.icanhazip.com)
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

   **注：** <a href="https://wiki.strongswan.org/projects/strongswan/wiki/MobIke" target="_blank">MOBIKE</a>  IKEv2 协议扩展允许 VPN 客户端更改网络连接点，例如在移动数据和 Wi-Fi 之间切换，并使 VPN 保持连接。如果你的服务器（或者 Docker 主机）的操作系统 **不是** Ubuntu Linux，并且你想要启用 MOBIKE 支持，可以将上面命令中的 `mobike=no` 换成 `mobike=yes`。**不要** 在 Ubuntu 系统或者 Raspberry Pi 上启用该选项。

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
     -k rsa -v 120 \
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
     -k rsa -v 120 \
     -d sql:/etc/ipsec.d -t ",," \
     --keyUsage digitalSignature,keyEncipherment \
     --extKeyUsage serverAuth \
     --extSAN "ip:$PUBLIC_IP,dns:$PUBLIC_IP"
   ```

   ```
   Generating key.  This may take a few moments...
   ```

1. 生成客户端证书，然后导出 `.p12` 文件，该文件包含客户端证书，私钥以及 CA 证书。

   **注：** 你可以重复本步骤来为更多的客户端生成证书，但必须将所有的 `vpnclient` 换成比如 `vpnclient2`，等等。如需同时连接多个客户端，则必须为每个客户端生成唯一的证书。

   生成客户端证书：

   ```bash
   certutil -z <(head -c 1024 /dev/urandom) \
     -S -c "IKEv2 VPN CA" -n "vpnclient" \
     -s "O=IKEv2 VPN,CN=vpnclient" \
     -k rsa -v 120 \
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

1. （适用于 iOS 客户端） 导出 CA 证书到 `ikev2vpnca.cer`：

   ```bash
   certutil -L -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" -a -o ikev2vpnca.cer
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

   **注：** 如需显示证书内容，可使用 `certutil -L -d sql:/etc/ipsec.d -n "Nickname"`。要吊销一个客户端证书，请转到[这一节](#吊销一个客户端证书)。关于 `certutil` 的其它用法参见 <a href="https://developer.mozilla.org/en-US/docs/Mozilla/Projects/NSS/tools/NSS_Tools_certutil" target="_blank">这里</a>。

1. **（重要）重启 IPsec 服务**：

   ```bash
   service ipsec restart
   ```

在继续之前，你**必须**重启 IPsec 服务。VPN 服务器上的 IKEv2 配置到此已完成。下一步：[配置 VPN 客户端](#配置-ikev2-vpn-客户端)。

## 故障排除

*其他语言版本: [English](ikev2-howto.md#troubleshooting), [简体中文](ikev2-howto-zh.md#故障排除).*

### 在导入客户端配置文件时提示密码不正确

如果你忘记了客户端配置文件的密码，可以重新 [导出 IKEv2 客户端的配置](#导出一个已有的客户端的配置)。

Ubuntu 18.04 用户在尝试将生成的 `.p12` 文件导入到 Windows 时可能会遇到错误 "输入的密码不正确"。这是由 `NSS` 中的一个问题导致的。更多信息请看 <a href="https://github.com/hwdsl2/setup-ipsec-vpn/issues/414#issuecomment-460495258" target="_blank">这里</a>。在 2021-01-21 已更新 IKEv2 辅助脚本以自动应用以下解决方法。
<details>
<summary>
Ubuntu 18.04 上的 NSS 问题的解决方法
</summary>

**注：** 该解决方法仅适用于运行在 `x86_64` 架构下的 Ubuntu 18.04 系统。

首先安装更新版本的 `libnss3` 相关的软件包：

```
wget https://mirrors.kernel.org/ubuntu/pool/main/n/nss/libnss3_3.49.1-1ubuntu1.5_amd64.deb
wget https://mirrors.kernel.org/ubuntu/pool/main/n/nss/libnss3-dev_3.49.1-1ubuntu1.5_amd64.deb
wget https://mirrors.kernel.org/ubuntu/pool/universe/n/nss/libnss3-tools_3.49.1-1ubuntu1.5_amd64.deb
apt-get -y update
apt-get -y install "./libnss3_3.49.1-1ubuntu1.5_amd64.deb" \
 "./libnss3-dev_3.49.1-1ubuntu1.5_amd64.deb" \
 "./libnss3-tools_3.49.1-1ubuntu1.5_amd64.deb"
```

然后重新 [导出 IKEv2 客户端的配置](#导出一个已有的客户端的配置)。
</details>

### IKEv2 在一小时后断开连接

如果 IKEv2 连接在一小时（60 分钟）后自动断开，可以这样解决：编辑 VPN 服务器上的 `/etc/ipsec.d/ikev2.conf`（如果不存在，编辑 `/etc/ipsec.conf`）。在 `conn ikev2-cp` 一节的末尾添加以下行，开头必须空两格：

```
  ikelifetime=24h
  salifetime=24h
```

保存修改并运行 `service ipsec restart`。该解决方案已在 2021-01-20 添加到辅助脚本。

### 无法同时连接多个 IKEv2 客户端

如果要同时连接多个客户端，则必须为每个客户端 [生成唯一的证书](#添加一个客户端证书)。

如果你无法同时连接同一个 NAT （比如家用路由器）后面的多个 IKEv2 客户端，可以这样解决：编辑 VPN 服务器上的 `/etc/ipsec.d/ikev2.conf`，找到这一行 `leftid=@<your_server_ip>` 并去掉 `@`，也就是说将它替换为 `leftid=<your_server_ip>`。保存修改并运行 `service ipsec restart`。如果 `leftid` 是一个域名则不受影响，不要应用这个解决方案。该解决方案已在 2021-02-01 添加到辅助脚本。

### 其它已知问题

1. Windows 自带的 VPN 客户端可能不支持 IKEv2 fragmentation（该功能<a href="https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-ikee/74df968a-7125-431d-9c98-4ea929e548dc" target="_blank">需要</a> Windows 10 v1803 或更新版本）。在有些网络上，这可能会导致连接错误或其它连接问题。你可以尝试换用 <a href="clients-zh.md" target="_blank">IPsec/L2TP</a> 或 <a href="clients-xauth-zh.md" target="_blank">IPsec/XAuth</a> 模式。
1. 如果你使用 strongSwan Android VPN 客户端，则必须将服务器上的 Libreswan <a href="../README-zh.md#升级libreswan" target="_blank">升级</a>到版本 3.26 或以上。

### 更多故障排除信息

要查看更多故障排除信息，请看 <a href="clients-zh.md#故障排除" target="_blank">这里</a>。

## 移除 IKEv2

如果你想要从 VPN 服务器移除 IKEv2，但是保留 [IPsec/L2TP](clients-zh.md) 和 [IPsec/XAuth ("Cisco IPsec")](clients-xauth-zh.md) 模式（如果已安装），请重新运行 [辅助脚本](#使用辅助脚本) 并选择 "Remove IKEv2" 选项。请注意，这将删除所有的 IKEv2 配置（包括证书和密钥），并且**不可撤销**！

<details>
<summary>
另外，你也可以手动移除 IKEv2。点这里查看步骤。
</summary>

要手动从 VPN 服务器移除 IKEv2，但是保留 [IPsec/L2TP](clients-zh.md) 和 [IPsec/XAuth ("Cisco IPsec")](clients-xauth-zh.md) 模式，按照以下步骤操作。这些命令必须用 `root` 账户运行。请注意，这将删除所有的 IKEv2 配置（包括证书和密钥），并且**不可撤销**！

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
* https://wiki.strongswan.org/projects/strongswan/wiki/WindowsClients
* https://wiki.strongswan.org/projects/strongswan/wiki/AndroidVpnClient
* https://developer.mozilla.org/en-US/docs/Mozilla/Projects/NSS/tools/NSS_Tools_certutil
* https://developer.mozilla.org/en-US/docs/Mozilla/Projects/NSS/tools/NSS_Tools_crlutil

## 授权协议

版权所有 (C) 2016-2021 <a href="https://www.linkedin.com/in/linsongui" target="_blank">Lin Song</a>   

<a rel="license" href="http://creativecommons.org/licenses/by-sa/3.0/"><img alt="Creative Commons License" style="border-width:0" src="https://i.creativecommons.org/l/by-sa/3.0/88x31.png" /></a>   
这个项目是以 <a href="http://creativecommons.org/licenses/by-sa/3.0/" target="_blank">知识共享署名-相同方式共享3.0</a> 许可协议授权。   
必须署名： 请包括我的名字在任何衍生产品，并且让我知道你是如何改善它的！
