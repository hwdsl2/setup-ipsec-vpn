## 配置 IPsec/L2TP VPN 客户端

*Read this in other languages: [English](clients.md), [简体中文](clients-zh.md).*

注： 本说明是在 <a href="https://github.com/jlund/streisand" target="_blank">Streisand</a> 项目文档的基础上修改。该项目由 <a href="https://github.com/jlund" target="_blank">Joshua Lund</a> 和其他志愿者维护。 授权协议： GPLv3

在成功<a href="https://github.com/hwdsl2/setup-ipsec-vpn" target="_blank">搭建自己的VPN服务器</a>之后，你可以按照下面的步骤来配置你的设备。IPsec/L2TP 在 Android, iOS, OS X 和 Windows 上均受支持，无需安装额外的软件。设置过程通常只需要几分钟。如果无法连接,请首先检查是否输入了正确的用户名和密码。

---
* 平台名称
  * [Windows](#windows)
  * [OS X](#osx)
  * [Android](#android)
  * [iOS](#ios)
  * [Chromebook](#chromebook)

<a name="windows"></a>
### Windows ###
1. 单击开始菜单，进入控制面板。
1. 单击 **网络与共享中心**。
1. 单击 **设置新的连接或网络**。
1. 选择 **连接到工作区**，然后单击**下一步**。
1. 单击 **使用我的Internet连接 (VPN)**。
1. 在 **Internet地址** 字段中输入`你的 VPN 服务器 IP`。
1. 在 **目标名称** 字段中输入任意内容。
1. 选中 **现在不连接；仅进行设置以便稍后连接** 复选框。
1. 单击 **下一步**。
1. 在 **用户名** 字段中输入`你的 VPN 用户名`。
1. 在 **密码** 字段中输入`你的 VPN 密码`。
1. 选中 **记住此密码** 复选框。
1. 单击 **连接**，然后单击 **关闭** 按钮。
1. 返回到控制面板中的 **网络和Internet** 部分，然后单击 **连接到网络** 选项。
1. 右键单击新的VPN连接，并选择 **属性**。
1. 单击 **选项** 选项卡，取消选中 **包含Windows登录域** 复选框。
1. 单击 <a href="https://github.com/hwdsl2/setup-ipsec-vpn/issues/7#issuecomment-210084875" target="_blank">**安全** 选项卡</a>，从 **VPN 类型** 下拉菜单中选择 **使用 IPsec 的第 2 层隧道协议 (L2TP/IPSec)**。在 **允许使用这些协议** 下，选中 `CHAP` 复选框，并且取消选中 `MS-CHAP v2`。
1. 单击 **高级设置** 按钮。
1. 单击 **使用预共享密钥作身份验证** 并在 **密钥** 字段中输入`你的 IPsec PSK`。
1. 单击 **确定** 关闭 **高级设置**。
1. 单击 **确定** 保存 VPN 连接的详细信息。
1. 在首次连接之前需要<a href="https://documentation.meraki.com/MX-Z/Client_VPN/Troubleshooting_Client_VPN#Windows_Error_809" target="_blank">修改一次注册表</a>，以解决 VPN 服务器和客户端与 NAT （比如家用路由器）的兼容问题。请按照链接文章中的说明进行操作，并在完成后重新启动计算机。

要连接到 VPN，只需在系统托盘中的无线/网络图标上单击右键，选择新的 VPN 连接，然后单击 **连接**。

<a name="osx"></a>
### OS X ###
1. 打开系统偏好设置并转到网络部分。
1. 在窗口左下角单击 **+** 按钮。
1. 从 **接口** 下拉菜单选择 **VPN**。
1. 从 **VPN类型** 下拉菜单选择 **IPSec 上的 L2TP**。
1. 在 **服务名称** 字段中输入任意内容。
1. 单击 **创建**。
1. 在 **服务器地址** 字段中输入`你的 VPN 服务器 IP`。
1. 在 **帐户名称** 字段中输入`你的 VPN 用户名`。
1. 单击 **鉴定设置** 按钮。
1. 在 **用户鉴定** 部分，选择 **密码** 单选按钮，然后输入`你的 VPN 密码`。
1. 在 **机器鉴定** 部分，选择 **共享的密钥** 单选按钮，然后输入`你的 IPsec PSK`。
1. 单击 **好**。
1. 选中 **在菜单栏中显示 VPN 状态** 复选框。
1. 单击 **高级** 按钮，并选中 **通过VPN连接发送所有通信** 复选框。
1. 单击 **TCP/IP** 选项卡，并确保在 **配置IPv6** 部分中选择 **仅本地**。
1. 单击 **好** 关闭高级设置，然后单击 **应用** 保存VPN连接信息。

要连接到 VPN，你可以使用菜单栏中的 VPN 图标，或者在系统偏好设置的网络部分选择 VPN，并单击 **连接**。

<a name="android"></a>
### Android ###
1. 启动 **设置** 应用程序。
1. 在 **无线和网络** 部分单击 **更多...**。
1. 单击 **VPN**。
1. 单击 **添加VPN配置文件**。
1. 在 **名称** 字段中输入任意内容。
1. 在 **类型** 下拉菜单选择 **L2TP/IPSec PSK**。
1. 在 **服务器地址** 字段中输入`你的 VPN 服务器 IP`。
1. 在 **IPSec 预共享密钥** 字段中输入`你的 IPsec PSK`。
1. 单击 **保存**。
1. 单击新的VPN连接。
1. 在 **用户名** 字段中输入`你的 VPN 用户名`。
1. 在 **密码** 字段中输入`你的 VPN 密码`。
1. 选中 **保存帐户信息** 复选框。
1. 单击 **连接**。

Android 6 (Marshmallow) 用户需要编辑 VPN 服务器上的 `/etc/ipsec.conf` 并在 `ike=` 和 `phase2alg=` 两行结尾添加 `,aes256-sha2_256` 。另外<a href="https://libreswan.org/wiki/FAQ#Android_6.0_connection_comes_up_but_no_packet_flow" target="_blank">增加一行</a> `sha2-truncbug=yes` 。每行开头必须空两格。保存修改并运行 `service ipsec restart` 。

VPN 连接成功后，会在通知栏显示图标。

<a name="ios"></a>
### iOS ###
1. 进入设置 -> 通用 -> VPN。
1. 单击 **添加VPN配置...**。
1. 单击 **类型** 。选择 **L2TP** 并返回。
1. 在 **描述** 字段中输入任意内容。
1. 在 **服务器** 字段中输入`你的 VPN 服务器 IP`。
1. 在 **帐户** 字段中输入`你的 VPN 用户名`。
1. 在 **密码** 字段中输入`你的 VPN 密码`。
1. 在 **密钥** 字段中输入`你的 IPsec PSK`。
1. 启用 **发送所有流量** 选项。
1. 单击右上角的 **存储**。
1. 启用 **VPN** 连接。

VPN 连接成功后，会在通知栏显示图标。

<a name="chromebook"></a>
### Chromebook ###
1. 如果你尚未登录 Chromebook，请先登录。
1. 单击状态区（其中显示帐户头像）。
1. 单击 **设置**。
1. 在 **互联网连接** 部分，单击**添加连接**。
1. 单击 **添加 OpenVPN / L2TP**。
1. 在 **服务器主机名** 字段中输入`你的 VPN 服务器 IP`。
1. 在 **服务名称** 字段中输入任意内容。
1. 在 **供应商类型** 下拉菜单选择 **L2TP/IPsec + 预共享密钥**。
1. 在 **预共享密钥** 字段中输入`你的 IPsec PSK`。
1. 在 **用户名** 字段中输入`你的 VPN 用户名`。
1. 在 **密码** 字段中输入`你的 VPN 密码`。
1. 单击 **连接**。

VPN 连接成功后，你会看到网络状态图标被 VPN 图标覆盖。
