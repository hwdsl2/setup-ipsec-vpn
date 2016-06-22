## 配置 IPsec/XAuth VPN 客户端

*Read this in other languages: [English](clients-xauth.md), [简体中文](clients-xauth-zh.md).*

*如需使用 IPsec/L2TP 模式连接，请参见： [配置 IPsec/L2TP VPN 客户端](clients-zh.md)*

在成功<a href="https://github.com/hwdsl2/setup-ipsec-vpn" target="_blank">搭建自己的VPN服务器</a>之后，你可以按照下面的步骤来配置你的设备。IPsec/XAuth 在 Android, iOS 和 OS X 上均受支持，无需安装额外的软件。Windows 用户可以使用免费的 <a href="https://www.shrew.net/download/vpn" target="_blank">Shrew Soft 客户端</a>。如果无法连接,请首先检查是否输入了正确的 VPN 登录信息。

`IPsec/XAuth` 模式也称为 `Cisco IPsec`。和 `IPsec/L2TP` 相比较，它通常能够更高效地传输数据。

---
* 平台名称
  * [Windows](#windows)
  * [OS X](#os-x)
  * [Android](#android)
  * [iOS](#ios)

### Windows ###

**注:** 你也可以使用 [IPsec/L2TP 模式](clients-zh.md) 连接，无需安装额外的软件。

1. 下载并安装免费的 <a href="https://www.shrew.net/download/vpn" target="_blank">Shrew Soft VPN 客户端</a>。
1. 单击开始菜单 -> 所有程序 -> ShrewSoft VPN Client -> VPN Access Manager
1. 单击工具栏中的 **Add (+)** 按钮。
1. 在 **Host Name or IP Address** 字段中输入`你的 VPN 服务器 IP`。
1. 单击 **Authentication** 选项卡，从 **Authentication Method** 下拉菜单中选择 **Mutual PSK + XAuth**。
1. 单击 **Credentials** 子选项卡，并在 **Pre Shared Key** 字段中输入`你的 VPN IPsec PSK`。
1. 单击 **Phase 1** 选项卡，从 **Exchange Type** 下拉菜单中选择 **main**。
1. 单击 **Save** 保存 VPN 连接的详细信息。
1. 选择新添加的 VPN 连接。单击工具栏中的 **Connect** 按钮。
1. 在 **Username** 字段中输入`你的 VPN 用户名`。
1. 在 **Password** 字段中输入`你的 VPN 密码`。
1. 单击 **Connect**。

VPN 连接成功后，会在 VPN Connect 状态窗口中显示 **tunnel enabled** 字样。最后你可以到<a href="https://www.whatismyip.com" target="_blank">这里</a>检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

**注：** 在首次连接之前需要<a href="https://documentation.meraki.com/MX-Z/Client_VPN/Troubleshooting_Client_VPN#Windows_Error_809" target="_blank">修改一次注册表</a>，以解决 VPN 服务器和客户端与 NAT （比如家用路由器）的兼容问题。请参照链接文章中的说明，或者打开<a href="http://windows.microsoft.com/zh-cn/windows/command-prompt-faq#1TC=windows-7" target="_blank">提升权限命令提示符</a>并运行以下命令。完成后必须重新启动计算机。
- 适用于 Windows Vista, 7, 8 和 10
  ```console
  REG ADD HKLM\SYSTEM\CurrentControlSet\Services\PolicyAgent /v AssumeUDPEncapsulationContextOnSendRule /t REG_DWORD /d 0x2 /f
  ```

- 仅限 Windows XP
  ```console
  REG ADD HKLM\SYSTEM\CurrentControlSet\Services\IPSec /v AssumeUDPEncapsulationContextOnSendRule /t REG_DWORD /d 0x2 /f
  ```

### OS X ###
1. 打开系统偏好设置并转到网络部分。
1. 在窗口左下角单击 **+** 按钮。
1. 从 **接口** 下拉菜单选择 **VPN**。
1. 从 **VPN类型** 下拉菜单选择 **Cisco IPSec**。
1. 在 **服务名称** 字段中输入任意内容。
1. 单击 **创建**。
1. 在 **服务器地址** 字段中输入`你的 VPN 服务器 IP`。
1. 在 **帐户名称** 字段中输入`你的 VPN 用户名`。
1. 在 **密码** 字段中输入`你的 VPN 密码`。
1. 单击 **鉴定设置** 按钮。
1. 在 **机器鉴定** 部分，选择 **共享的密钥** 单选按钮，然后输入`你的 VPN IPsec PSK`。
1. 保持 **群组名称** 字段空白。
1. 单击 **好**。
1. 选中 **在菜单栏中显示 VPN 状态** 复选框。
1. 单击 **应用** 保存VPN连接信息。

要连接到 VPN，你可以使用菜单栏中的 VPN 图标，或者在系统偏好设置的网络部分选择 VPN，并单击 **连接**。最后你可以到<a href="https://www.whatismyip.com" target="_blank">这里</a>检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

### Android ###
1. 启动 **设置** 应用程序。
1. 在 **无线和网络** 部分单击 **更多...**。
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

**注：** Android 6 (Marshmallow) 用户需要编辑 VPN 服务器上的 `/etc/ipsec.conf`，并在 `ike=` 和 `phase2alg=` 两行结尾添加 `,aes256-sha2_256` 字样。然后在它们下面添加一行 `sha2-truncbug=yes`。每行开头必须空两格。保存修改并运行 `service ipsec restart`。(<a href="https://libreswan.org/wiki/FAQ#Android_6.0_connection_comes_up_but_no_packet_flow" target="_blank">更多信息</a>)

VPN 连接成功后，会在通知栏显示图标。最后你可以到<a href="https://www.whatismyip.com" target="_blank">这里</a>检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

### iOS ###
1. 进入设置 -> 通用 -> VPN。
1. 单击 **添加VPN配置...**。
1. 单击 **类型** 。选择 **IPSec** 并返回。
1. 在 **描述** 字段中输入任意内容。
1. 在 **服务器** 字段中输入`你的 VPN 服务器 IP`。
1. 在 **帐户** 字段中输入`你的 VPN 用户名`。
1. 在 **密码** 字段中输入`你的 VPN 密码`。
1. 保持 **群组名称** 字段空白。
1. 在 **密钥** 字段中输入`你的 VPN IPsec PSK`。
1. 单击右上角的 **存储**。
1. 启用 **VPN** 连接。

VPN 连接成功后，会在通知栏显示图标。最后你可以到<a href="https://www.whatismyip.com" target="_blank">这里</a>检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

## 致谢

本文档是在 <a href="https://github.com/jlund/streisand" target="_blank">Streisand</a> 项目文档基础上翻译和修改。该项目由 Joshua Lund 和其他开发者维护。

## 授权协议

版权所有 (C) 2016 Lin Song   
基于 <a href="https://github.com/jlund/streisand/blob/master/playbooks/roles/l2tp-ipsec/templates/instructions.md.j2" target="_blank">Joshua Lund 的工作</a> (版权所有 2014-2016)

本程序为自由软件，在自由软件联盟发布的<a href="https://www.gnu.org/licenses/gpl.html" target="_blank"> GNU 通用公共许可协议</a>的约束下，你可以对其进行再发布及修改。协议版本为第三版或（随你）更新的版本。

我们希望发布的这款程序有用，但不保证，甚至不保证它有经济价值和适合特定用途。详情参见GNU通用公共许可协议。
