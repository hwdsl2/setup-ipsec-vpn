[English](README.md) | [中文](README-zh.md)

# 在 Microsoft Azure 上部署

使用这个模板，你可以在 Microsoft Azure Cloud 上快速搭建一个 VPN 服务器 （[定价细节](https://azure.microsoft.com/zh-cn/pricing/details/virtual-machines/)）。

可根据偏好设置以下选项：

 - Username for VPN **and** SSH （用户名）
 - Password for VPN **and** SSH （密码）
 - IPsec Pre-Shared Key for VPN （IPsec 预共享密钥）
 - Operating System Image （操作系统镜像，Ubuntu 22.04 或 20.04）
 - Virtual Machine Size （虚拟机大小，默认值： Standard_B1s）

**注：** \*不要\* 在值中使用这些字符： `\ " '`

请单击以下按钮开始：

[![Deploy to Azure](../docs/images/azure-deploy-button.png)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fhwdsl2%2Fsetup-ipsec-vpn%2Fmaster%2Fazure%2Fazuredeploy.json)

在完成部署之后，Azure 会有提示。下一步：[配置 VPN 客户端](../README-zh.md#下一步)。

**注：** 在使用 SSH 连接到服务器时，请使用你在部署模板中指定的用户名和密码。如果要添加或者导出 IKEv2 客户端，运行 `sudo ikev2.sh`。如果你在输入正确的登录凭证后仍然无法使用 SSH 连接到服务器，请参见 [解决与 Azure Linux VM 的 SSH 连接失败、出错或被拒绝的问题](https://docs.microsoft.com/zh-cn/troubleshoot/azure/virtual-machines/troubleshoot-ssh-connection) 和/或 [无法 SSH 到 Azure Linux VM，因为权限太开放](https://docs.microsoft.com/zh-cn/troubleshoot/azure/virtual-machines/troubleshoot-ssh-permissions-too-open)。

## 作者

版权所有 (C) 2016 [Daniel Falkner](https://github.com/derdanu)   
版权所有 (C) 2017-2024 [Lin Song](https://github.com/hwdsl2)

## 屏幕截图

<details>
<summary>
单击查看屏幕截图。
</summary>

![Azure Custom Deployment](custom_deployment_screenshot.png)
</details>
