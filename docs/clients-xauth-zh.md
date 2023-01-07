[English](clients-xauth.md) | [中文](clients-xauth-zh.md)

# 配置 IPsec/XAuth VPN 客户端

在成功 [搭建自己的 VPN 服务器](../README-zh.md) 之后，按照下面的步骤来配置你的设备。IPsec/XAuth ("Cisco IPsec") 在 Android, iOS 和 OS X 上均受支持，无需安装额外的软件。Windows 用户可以使用免费的 [Shrew Soft 客户端](https://www.shrew.net/download/vpn)。如果无法连接,请首先检查是否输入了正确的 VPN 登录凭证。

IPsec/XAuth 模式也称为 "Cisco IPsec"。该模式通常能够比 IPsec/L2TP **更高效**地传输数据（较低的额外开销）。

---
* 平台名称
  * [Windows](#windows)
  * [OS X (macOS)](#os-x)
  * [Android](#android)
  * [iOS (iPhone/iPad)](#ios)
  * [Linux](#linux)

## Windows

> 你也可以使用 [IKEv2](ikev2-howto-zh.md)（推荐）或者 [IPsec/L2TP](clients-zh.md) 模式连接。无需安装额外的软件。

1. 下载并安装免费的 [Shrew Soft VPN 客户端](https://www.shrew.net/download/vpn)。在安装时请选择 **Standard Edition**。   
   **注：** 该 VPN 客户端 **不支持** Windows 10/11。
1. 单击开始菜单 -> 所有程序 -> ShrewSoft VPN Client -> VPN Access Manager
1. 单击工具栏中的 **Add (+)** 按钮。
1. 在 **Host Name or IP Address** 字段中输入`你的 VPN 服务器 IP`。
1. 单击 **Authentication** 选项卡，从 **Authentication Method** 下拉菜单中选择 **Mutual PSK + XAuth**。
1. 在 **Local Identity** 子选项卡中，从 **Identification Type** 下拉菜单中选择 **IP Address**。
1. 单击 **Credentials** 子选项卡，并在 **Pre Shared Key** 字段中输入`你的 VPN IPsec PSK`。
1. 单击 **Phase 1** 选项卡，从 **Exchange Type** 下拉菜单中选择 **main**。
1. 单击 **Phase 2** 选项卡，从 **HMAC Algorithm** 下拉菜单中选择 **sha1**。
1. 单击 **Save** 保存 VPN 连接的详细信息。
1. 选择新添加的 VPN 连接。单击工具栏中的 **Connect** 按钮。
1. 在 **Username** 字段中输入`你的 VPN 用户名`。
1. 在 **Password** 字段中输入`你的 VPN 密码`。
1. 单击 **Connect**。

连接成功后，你会在 VPN Connect 状态窗口中看到 **tunnel enabled** 字样。单击 "Network" 选项卡，并确认 **Established - 1** 显示在 "Security Associations" 下面。最后你可以到 [这里](https://www.ipchicken.com) 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

如果在连接过程中遇到错误，请参见 [故障排除](clients-zh.md#ikev1-故障排除)。

## OS X

> 你也可以使用 [IKEv2](ikev2-howto-zh.md)（推荐）或者 [IPsec/L2TP](clients-zh.md) 模式连接。

1. 打开系统偏好设置并转到网络部分。
1. 在窗口左下角单击 **+** 按钮。
1. 从 **接口** 下拉菜单选择 **VPN**。
1. 从 **VPN类型** 下拉菜单选择 **Cisco IPSec**。
1. 在 **服务名称** 字段中输入任意内容。
1. 单击 **创建**。
1. 在 **服务器地址** 字段中输入`你的 VPN 服务器 IP`。
1. 在 **帐户名称** 字段中输入`你的 VPN 用户名`。
1. 在 **密码** 字段中输入`你的 VPN 密码`。
1. 单击 **认证设置** 按钮。
1. 在 **机器认证** 部分，选择 **共享的密钥** 单选按钮，然后输入`你的 VPN IPsec PSK`。
1. 保持 **群组名称** 字段空白。
1. 单击 **好**。
1. 选中 **在菜单栏中显示 VPN 状态** 复选框。
1. 单击 **应用** 保存VPN连接信息。

要连接到 VPN：使用菜单栏中的图标，或者打开系统偏好设置的网络部分，选择 VPN 并单击 **连接**。最后你可以到 [这里](https://www.ipchicken.com) 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

如果在连接过程中遇到错误，请参见 [故障排除](clients-zh.md#ikev1-故障排除)。

## Android

**重要：** Android 用户应该使用更安全的 [IKEv2 模式](ikev2-howto-zh.md) 连接（推荐）。Android 12+ 仅支持 IKEv2 模式。Android 系统自带的 VPN 客户端对 IPsec/L2TP 和 IPsec/XAuth ("Cisco IPsec") 模式使用安全性较低的 `modp1024` (DH group 2)。

如果你仍然想用 IPsec/XAuth 模式连接，你必须首先编辑 VPN 服务器上的 `/etc/ipsec.conf` 并在 `ike=...` 一行的末尾加上 `,aes256-sha2;modp1024,aes128-sha1;modp1024` 字样。保存文件并运行 `sudo service ipsec restart`。

Docker 用户：在 [你的 env 文件](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md#如何使用本镜像) 中添加 `VPN_ENABLE_MODP1024=yes`，然后重新创建 Docker 容器。

然后在你的 Android 设备上进行以下步骤：

1. 启动 **设置** 应用程序。
1. 单击 **网络和互联网**。或者，如果你使用 Android 7 或更早版本，在 **无线和网络** 部分单击 **更多...**。
1. 单击 **VPN**。
1. 单击 **添加VPN配置文件** 或窗口右上角的 **+**。
1. 在 **名称** 字段中输入任意内容。
1. 在 **类型** 下拉菜单选择 **IPSec Xauth PSK**。
1. 在 **服务器地址** 字段中输入`你的 VPN 服务器 IP`。
1. 保持 **IPSec 标识符** 字段空白。
1. 在 **IPSec 预共享密钥** 字段中输入`你的 VPN IPsec PSK`。
1. 单击 **保存**。
1. 单击新的VPN连接。
1. 在 **用户名** 字段中输入`你的 VPN 用户名`。
1. 在 **密码** 字段中输入`你的 VPN 密码`。
1. 选中 **保存帐户信息** 复选框。
1. 单击 **连接**。

连接成功后，会在通知栏显示图标。最后你可以到 [这里](https://www.ipchicken.com) 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

如果在连接过程中遇到错误，请参见 [故障排除](clients-zh.md#ikev1-故障排除)。

## iOS

> 你也可以使用 [IKEv2](ikev2-howto-zh.md)（推荐）或者 [IPsec/L2TP](clients-zh.md) 模式连接。

1. 进入设置 -> 通用 -> VPN。
1. 单击 **添加VPN配置...**。
1. 单击 **类型** 。选择 **IPSec** 并返回。
1. 在 **描述** 字段中输入任意内容。
1. 在 **服务器** 字段中输入`你的 VPN 服务器 IP`。
1. 在 **帐户** 字段中输入`你的 VPN 用户名`。
1. 在 **密码** 字段中输入`你的 VPN 密码`。
1. 保持 **群组名称** 字段空白。
1. 在 **密钥** 字段中输入`你的 VPN IPsec PSK`。
1. 单击右上角的 **完成**。
1. 启用 **VPN** 连接。

连接成功后，会在通知栏显示图标。最后你可以到 [这里](https://www.ipchicken.com) 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

如果在连接过程中遇到错误，请参见 [故障排除](clients-zh.md#ikev1-故障排除)。

## Linux

> 你也可以使用 [IKEv2](ikev2-howto-zh.md) 模式连接（推荐）。

### Fedora 和 CentOS

Fedora 28 （和更新版本）和 CentOS 8/7 用户可以使用 `yum` 安装 `NetworkManager-libreswan-gnome` 软件包，然后通过 GUI 配置 IPsec/XAuth VPN 客户端。

1. 进入 Settings -> Network -> VPN。单击 **+** 按钮。
1. 选择 **IPsec based VPN**。
1. 在 **Name** 字段中输入任意内容。
1. 在 **Gateway** 字段中输入`你的 VPN 服务器 IP`。
1. 在 **Type** 下拉菜单选择 **IKEv1 (XAUTH)**。
1. 在 **User name** 字段中输入`你的 VPN 用户名`。
1. 右键单击 **User password** 字段中的 **?**，选择 **Store the password only for this user**。
1. 在 **User password** 字段中输入`你的 VPN 密码`。
1. 保持 **Group name** 字段空白。
1. 右键单击 **Secret** 字段中的 **?**，选择 **Store the password only for this user**。
1. 在 **Secret** 字段中输入`你的 VPN IPsec PSK`。
1. 保持 **Remote ID** 字段空白。
1. 单击 **Add** 保存 VPN 连接信息。
1. 启用 **VPN** 连接。

连接成功后，你可以到 [这里](https://www.ipchicken.com) 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

### 其它 Linux

其它 Linux 版本用户可以使用 [IPsec/L2TP](clients-zh.md#linux) 模式连接。

## 授权协议

注： 这个协议仅适用于本文档。

版权所有 (C) 2016-2023 [Lin Song](https://github.com/hwdsl2) [![View my profile on LinkedIn](https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png)](https://www.linkedin.com/in/linsongui)   
受到 [Joshua Lund 的工作](https://github.com/StreisandEffect/streisand/blob/6aa6b6b2735dd829ca8c417d72eb2768a89b6639/playbooks/roles/l2tp-ipsec/templates/instructions.md.j2) 的启发

本程序为自由软件，在自由软件联盟发布的[ GNU 通用公共许可协议](https://www.gnu.org/licenses/gpl.html)的约束下，你可以对其进行再发布及修改。协议版本为第三版或（随你）更新的版本。

我们希望发布的这款程序有用，但不保证，甚至不保证它有经济价值和适合特定用途。详情参见GNU通用公共许可协议。
