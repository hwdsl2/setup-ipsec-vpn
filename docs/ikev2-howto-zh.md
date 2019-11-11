# 分步指南：如何配置 IKEv2 VPN

*其他语言版本: [English](ikev2-howto.md), [简体中文](ikev2-howto-zh.md).*

**重要提示：** 本指南仅适用于**高级用户**。其他用户请使用 [IPsec/L2TP](clients-zh.md) 或者 [IPsec/XAuth](clients-xauth-zh.md) 模式。

---
* [导言](#导言)
* [在 VPN 服务器上配置 IKEv2](#在-vpn-服务器上配置-ikev2)
* [配置 IKEv2 VPN 客户端](#配置-ikev2-vpn-客户端)
* [已知问题](#已知问题)
* [参考链接](#参考链接)

## 导言

现代操作系统（比如 Windows 7 和更新版本）支持 IKEv2 协议标准。因特网密钥交换 （英语：Internet Key Exchange，简称 IKE 或 IKEv2）是一种网络协议，归属于 IPsec 协议族之下，用以创建安全关联 (Security Association, SA)。与 IKE 版本 1 相比较，IKEv2 的 <a href="https://en.wikipedia.org/wiki/Internet_Key_Exchange#Improvements_with_IKEv2" target="_blank">功能改进</a> 包括比如通过 MOBIKE 实现 Standard Mobility 支持，以及更高的可靠性。

Libreswan 支持通过使用 RSA 签名算法的 X.509 Machine Certificates 来对 IKEv2 客户端进行身份验证。该方法无需 IPsec PSK, 用户名或密码。它可以用于以下系统：

- Windows 7, 8.x 和 10
- OS X (macOS)
- Android 4.x 和更新版本（使用 strongSwan VPN 客户端）
- iOS (iPhone/iPad)

## 在 VPN 服务器上配置 IKEv2

**重要：** 作为使用本指南的先决条件，在继续之前，你必须确保你已经成功地 <a href="../README-zh.md" target="_blank">搭建自己的 VPN 服务器</a>，并且（可选但推荐）将 Libreswan <a href="../README-zh.md#升级libreswan" target="_blank">升级</a> 到最新版本。

下面举例说明如何在 Libreswan 上配置 IKEv2。以下命令必须用 `root` 账户运行。

1. 获取 VPN 服务器的公共 IP 地址，将它保存到变量并检查。

   ```bash
   PUBLIC_IP=$(dig @resolver1.opendns.com -t A -4 myip.opendns.com +short)
   [ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(wget -t 3 -T 15 -qO- http://ipv4.icanhazip.com)
   printf '%s\n' "$PUBLIC_IP"
   ```

   检查并确保以上命令的输出与服务器的公共 IP 一致。该变量将在以下步骤中使用。

   **注：** 另外，在这里你也可以指定 VPN 服务器的域名。例如： `PUBLIC_IP=myvpn.example.com`。

1. 在 `/etc/ipsec.conf` 文件中添加一个新的 IKEv2 连接：

   ```bash
   cat >> /etc/ipsec.conf <<EOF

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
     ike-frag=yes
     ike=aes256-sha2,aes128-sha2,aes256-sha1,aes128-sha1,aes256-sha2;modp1024,aes128-sha1;modp1024
     phase2alg=aes_gcm-null,aes128-sha1,aes256-sha1,aes128-sha2,aes256-sha2
   EOF
   ```

   还需要在该文件中添加一些行。首先查看你的 Libreswan 版本，然后运行以下命令之一：

   ```bash
   ipsec --version
   ```

   如果是 Libreswan 3.23 或更新版本：

   ```bash
   cat >> /etc/ipsec.conf <<EOF
     modecfgdns="8.8.8.8 8.8.4.4"
     encapsulation=yes
     mobike=no
   EOF
   ```

   **注：** 如果你的服务器运行 Debian 或者 CentOS/RHEL，并且你想要启用 MOBIKE 支持，可以将上面命令中的 `mobike=no` 换成 `mobike=yes`。**不要**在 Ubuntu 系统上启用该选项。

   如果是 Libreswan 3.19-3.22：

   ```bash
   cat >> /etc/ipsec.conf <<EOF
     modecfgdns1=8.8.8.8
     modecfgdns2=8.8.4.4
     encapsulation=yes
   EOF
   ```

   如果是 Libreswan 3.18 或更早版本：

   ```bash
   cat >> /etc/ipsec.conf <<EOF
     modecfgdns1=8.8.8.8
     modecfgdns2=8.8.4.4
     forceencaps=yes
   EOF
   ```

1. 生成 Certificate Authority (CA) 和 VPN 服务器证书：

   **注：** 使用 "-v" 参数指定证书的有效期（单位：月），例如 "-v 120"。

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

   **注：** 如果你在上面的第一步指定了服务器的域名（而不是 IP 地址），则必须将以下命令中的 `--extSAN "ip:$PUBLIC_IP,dns:$PUBLIC_IP"` 换成 `--extSAN "dns:$PUBLIC_IP"`。

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

1. 生成客户端证书，然后导出 `.p12` 文件，该文件包含客户端证书，私钥以及 CA 证书：

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

   ```bash
   pk12util -o vpnclient.p12 -n "vpnclient" -d sql:/etc/ipsec.d
   ```

   ```
   Enter password for PKCS12 file:
   Re-enter password:
   pk12util: PKCS12 EXPORT SUCCESSFUL
   ```

   指定一个安全的密码以保护导出的 `.p12` 文件（在导入到 iOS 或 macOS 设备时，该密码不能为空）。你可以重复本步骤来为更多的客户端生成证书，但必须将所有的 `vpnclient` 换成比如 `vpnclient2`，等等。

   **注：** 如需同时连接多个客户端，则必须为每个客户端生成唯一的证书。

1. （适用于 iOS 客户端） 导出 CA 证书到 `vpnca.cer`：

   ```bash
   certutil -L -d sql:/etc/ipsec.d -n "IKEv2 VPN CA" -a -o vpnca.cer
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

   **注：** 如需显示证书内容，可使用 `certutil -L -d sql:/etc/ipsec.d -n "Nickname"`。要删除一个证书，将 `-L` 换成 `-D`。更多的 `certutil` 使用说明请看 <a href="http://manpages.ubuntu.com/manpages/xenial/en/man1/certutil.1.html" target="_blank">这里</a>。

1. **（重要）重启 IPsec 服务**：

   ```bash
   service ipsec restart
   ```

VPN 服务器上的 IKEv2 配置到此已完成。按照下面的步骤配置你的 VPN 客户端。

## 配置 IKEv2 VPN 客户端

**注：** 如果你在上面的第一步指定了服务器的域名（而不是 IP 地址），则必须在 **服务器地址** 和 **远程 ID** 字段中输入该域名。

* [Windows 7, 8.x 和 10](#windows-7-8x-和-10)
* [OS X (macOS)](#os-x-macos)
* [Android 10 和更新版本](#android-10-和更新版本)
* [Android 4.x to 9.x](#android-4x-to-9x)
* [iOS (iPhone/iPad)](#ios)

### Windows 7, 8.x 和 10

1. 将文件 `vpnclient.p12` 安全地传送到你的计算机，然后导入到 "计算机账户" 证书存储。在导入证书后，你必须确保将客户端证书放在 "个人 -> 证书" 目录中，并且将 CA 证书放在 "受信任的根证书颁发机构 -> 证书" 目录中。

   详细的操作步骤：   
   https://wiki.strongswan.org/projects/strongswan/wiki/Win7Certs

1. 在 Windows 计算机上添加一个新的 IKEv2 VPN 连接：   
   https://wiki.strongswan.org/projects/strongswan/wiki/Win7Config

1. 启用新的 VPN 连接，并且开始使用 IKEv2 VPN！   
   https://wiki.strongswan.org/projects/strongswan/wiki/Win7Connect

1. （可选步骤） 如需启用更强的加密算法，你可以添加注册表键 `NegotiateDH2048_AES256` 并重启。更多信息请看 <a href="https://wiki.strongswan.org/projects/strongswan/wiki/WindowsClients#AES-256-CBC-and-MODP2048" target="_blank">这里</a>。

### OS X (macOS)

首先，将文件 `vpnclient.p12` 安全地传送到你的 Mac，然后双击以导入到 **钥匙串访问** 中的 **登录** 钥匙串。下一步，双击导入的 `IKEv2 VPN CA` 证书，展开 **信任** 并从 **IP 安全 (IPsec)** 下拉菜单中选择 **始终信任**。在完成之后，检查并确保 `vpnclient` 和 `IKEv2 VPN CA` 都显示在 **登录** 钥匙串 的 **证书** 类别中。

1. 打开系统偏好设置并转到网络部分。
1. 在窗口左下角单击 **+** 按钮。
1. 从 **接口** 下拉菜单选择 **VPN**。
1. 从 **VPN 类型** 下拉菜单选择 **IKEv2**。
1. 在 **服务名称** 字段中输入任意内容。
1. 单击 **创建**。
1. 在 **服务器地址** 字段中输入 `你的 VPN 服务器 IP` （或者域名）。
1. 在 **远程 ID** 字段中输入 `你的 VPN 服务器 IP` （或者域名）。
1. 保持 **本地 ID** 字段空白。
1. 单击 **鉴定设置...** 按钮。
1. 从 **鉴定设置** 下拉菜单中选择 **无**。
1. 选择 **证书** 单选按钮，然后选择 **vpnclient** 证书。
1. 单击 **好**。
1. 选中 **在菜单栏中显示 VPN 状态** 复选框。
1. 单击 **应用** 保存VPN连接信息。
1. 单击 **连接**。

### Android 10 和更新版本

1. 将文件 `vpnclient.p12` 安全地传送到你的 Android 设备。
1. 从 **Google Play** 安装 <a href="https://play.google.com/store/apps/details?id=org.strongswan.android" target="_blank">strongSwan VPN 客户端</a>。
1. 启动 **设置** 应用程序。
1. 进入 安全 -> 高级 -> 加密与凭据。
1. 单击 **从存储设备（或 SD 卡）安装**。
1. 选择你从服务器复制过来的 `.p12` 文件，并按提示操作。   
   **注：** 要查找 `.p12` 文件，单击左上角的抽拉式菜单，然后单击你的设备名称。
1. 启动 strongSwan VPN 客户端，然后单击 **Add VPN Profile**。
1. 在 **Server** 字段中输入 `你的 VPN 服务器 IP` （或者域名）。
1. 在 **VPN Type** 下拉菜单选择 **IKEv2 Certificate**。
1. 单击 **Select user certificate**，选择你的新 VPN 客户端证书并确认。
1. 保存新的 VPN 连接，然后单击它以开始连接。

### Android 4.x to 9.x

1. 将文件 `vpnclient.p12` 安全地传送到你的 Android 设备。
1. 从 **Google Play** 安装 <a href="https://play.google.com/store/apps/details?id=org.strongswan.android" target="_blank">strongSwan VPN 客户端</a>。
1. 启动 strongSwan VPN 客户端，然后单击 **Add VPN Profile**。
1. 在 **Server** 字段中输入 `你的 VPN 服务器 IP` （或者域名）。
1. 在 **VPN Type** 下拉菜单选择 **IKEv2 Certificate**。
1. 单击 **Select user certificate**，然后单击 **Install certificate**。
1. 选择你从服务器复制过来的 `.p12` 文件，并按提示操作。   
   **注：** 要查找 `.p12` 文件，单击左上角的抽拉式菜单，然后单击你的设备名称。
1. 保存新的 VPN 连接，然后单击它以开始连接。

### iOS

首先，将文件 `vpnca.cer` 和 `vpnclient.p12` 安全地传送到你的 iOS 设备，并且逐个导入为 iOS 配置描述文件。要传送文件，你可以使用：

1. AirDrop （隔空投送），或者
1. 将文件上传到设备，在 "文件" 应用程序中单击它们，然后到 "设置" 中导入，或者
1. 将文件放在一个你的安全的托管网站上，然后在 Mobile Safari 中下载并导入它们。

在完成之后，检查并确保 `vpnclient` 和 `IKEv2 VPN CA` 都显示在设置 -> 通用 -> 描述文件中。

1. 进入设置 -> 通用 -> VPN。
1. 单击 **添加VPN配置...**。
1. 单击 **类型** 。选择 **IKEv2** 并返回。
1. 在 **描述** 字段中输入任意内容。
1. 在 **服务器** 字段中输入 `你的 VPN 服务器 IP` （或者域名）。
1. 在 **远程 ID** 字段中输入 `你的 VPN 服务器 IP` （或者域名）。
1. 保持 **本地 ID** 字段空白。
1. 单击 **用户鉴定** 。选择 **无** 并返回。
1. 启用 **使用证书** 选项。
1. 单击 **证书** 。选择 **vpnclient** 并返回。
1. 单击右上角的 **完成**。
1. 启用 **VPN** 连接。

连接成功后，你可以到 <a href="https://www.ipchicken.com" target="_blank">这里</a> 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

## 已知问题

1. Windows 自带的 VPN 客户端可能不支持 IKEv2 fragmentation。在有些网络上，这可能会导致连接错误或其它连接问题。你可以尝试换用 <a href="clients-zh.md" target="_blank">IPsec/L2TP</a> 或 <a href="clients-xauth-zh.md" target="_blank">IPsec/XAuth</a> 模式。
1. 如果你使用 strongSwan Android VPN 客户端，则必须将服务器上的 Libreswan <a href="../README-zh.md#升级libreswan" target="_blank">升级</a> 到版本 3.26 或以上。
1. 如果你的 VPN 客户端可以连接但是无法打开任何网站，可以尝试编辑服务器上的 `/etc/ipsec.conf`。找到 `conn ikev2-cp` 部分的 `phase2alg=` 一行并删除 `aes_gcm-null,`。保存文件并运行 `service ipsec restart`。
1. Ubuntu 18.04 和 CentOS 用户在尝试将生成的 `.p12` 文件导入到 Windows 时可能会遇到错误 "输入的密码不正确"。这是由 `NSS` 中的一个问题导致的。更多信息请看 <a href="https://github.com/hwdsl2/setup-ipsec-vpn/issues/414#issuecomment-460430354" target="_blank">这里</a>。
1. 目前还不支持同时连接在同一个 NAT （比如家用路由器）后面的多个 IKEv2 客户端。对于这个用例，请换用 <a href="clients-xauth-zh.md" target="_blank">IPsec/XAuth</a> 模式。

## 参考链接

* https://libreswan.org/wiki/VPN_server_for_remote_clients_using_IKEv2
* https://libreswan.org/wiki/HOWTO:_Using_NSS_with_libreswan
* https://libreswan.org/man/ipsec.conf.5.html
* https://wiki.strongswan.org/projects/strongswan/wiki/WindowsClients
* https://wiki.strongswan.org/projects/strongswan/wiki/AndroidVpnClient
