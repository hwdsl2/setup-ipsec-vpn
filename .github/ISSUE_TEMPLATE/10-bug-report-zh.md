---
name: 错误报告
about: 请使用这个模板来提交 bug
title: ''
labels: ''
assignees: ''

---

**任务列表**

- [ ] 我已阅读[自述文件](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/README-zh.md)
- [ ] 我已阅读[重要提示](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/README-zh.md#重要提示)
- [ ] 我已按照说明[配置 VPN 客户端](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/README-zh.md#下一步)
- [ ] 我检查了 [IKEv1 故障排除](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/docs/clients-zh.md#ikev1-故障排除)，[IKEv2 故障排除](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/docs/ikev2-howto-zh.md#ikev2-故障排除)以及 [VPN 状态](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/docs/clients-zh.md#检查日志及-vpn-状态)
- [ ] 我搜索了已有的 [Issues](https://github.com/hwdsl2/setup-ipsec-vpn/issues?q=is%3Aissue)
- [ ] 这个 bug 是关于 VPN 安装脚本，而不是 IPsec VPN 本身

<!---
如果你发现的是 IPsec VPN 本身的可重复 bug，请在 https://github.com/libreswan/libreswan 提交错误报告。VPN 的相关问题可在 [Libreswan](https://lists.libreswan.org) 或 [strongSwan](https://lists.strongswan.org) 用户邮件列表提问，或者搜索比如 [Stack Overflow](https://stackoverflow.com/questions/tagged/vpn) 等网站。

发布日志或配置前，请删除 VPN 凭据、私钥、IPsec PSK、密码和其它敏感信息。
--->

**问题描述**
使用清楚简明的语言描述这个 bug。

**重现步骤**
重现该 bug 的步骤：

1. ...
2. ...

**期待的正确结果**
简要地描述你期望的正确结果。

**日志**
[检查日志及 VPN 状态](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/docs/clients-zh.md#检查日志及-vpn-状态)，并添加相关错误日志以帮助解释该问题（如果适用）。

常用命令包括：

```bash
ipsec status
ipsec trafficstatus
```

对于连接问题，也请提供服务器操作系统中相关的 `pluto` 和 `xl2tpd` 日志行，并删除敏感信息。

**服务器信息（请填写以下信息）**
- 操作系统和版本: [比如 Debian 13]
- 架构: [比如 x86_64, arm64]
- 服务提供商（如果适用）: [比如 GCP, AWS]
- 外部防火墙/NAT: [比如 UDP 500/4500 已开放，位于 NAT 后，不适用]
- 安装方法或使用的命令

**客户端信息（请填写以下信息）**
- 设备: [比如 iPhone 15]
- 操作系统和版本: [比如 iOS 18]
- VPN 客户端应用及版本（如果适用）: [比如 strongSwan VPN Client 2.x]
- VPN 模式: [IPsec/L2TP, IPsec/XAuth ("Cisco IPsec") 或 IKEv2]

**其它信息**
添加关于该 bug 的其它信息。
