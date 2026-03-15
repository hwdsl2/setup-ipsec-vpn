[English](README.md) | [简体中文](README-zh.md) | [繁體中文](README-zh-Hant.md) | [日本語](README-ja.md) | [Русский](README-ru.md)

# IPsec VPN 伺服器一鍵安裝腳本

[![Build Status](https://github.com/hwdsl2/setup-ipsec-vpn/actions/workflows/main.yml/badge.svg)](https://github.com/hwdsl2/setup-ipsec-vpn/actions/workflows/main.yml) [![GitHub Stars](docs/images/badges/github-stars.svg)](https://github.com/hwdsl2/setup-ipsec-vpn/stargazers) [![Docker Stars](docs/images/badges/docker-stars.svg)](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh-Hant.md) [![Docker Pulls](docs/images/badges/docker-pulls.svg)](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh-Hant.md)

使用 Linux 腳本一鍵快速架設自己的 IPsec VPN 伺服器。支援 IPsec/L2TP、Cisco IPsec 和 IKEv2 協議。

IPsec VPN 可以加密你的網路流量，以防止在透過網際網路傳送時，你和 VPN 伺服器之間的任何人對你的資料進行未經授權的存取。在使用不安全的網路時，這一點特別有用，例如在咖啡廳、機場或旅館房間。

我們將使用 [Libreswan](https://libreswan.org/) 作為 IPsec 伺服器，以及 [xl2tpd](https://github.com/xelerance/xl2tpd) 作為 L2TP 提供者。

**[&raquo; :book: Book: Privacy Tools in the Age of AI](docs/vpn-book-zh-Hant.md) &nbsp;[架設自己的 VPN 伺服器](docs/vpn-book-zh-Hant.md)**

## 快速開始

首先，在你的 Linux 伺服器\* 上安裝 Ubuntu、Debian 或 CentOS。

使用以下命令快速架設 IPsec VPN 伺服器：

```bash
wget https://get.vpnsetup.net -O vpn.sh && sudo sh vpn.sh
```

你的 VPN 登入憑證將會自動隨機生成，並在安裝完成後顯示。

**可選：** 在同一台伺服器上安裝 [WireGuard](https://github.com/hwdsl2/wireguard-install/blob/master/README-zh-Hant.md) 和/或 [OpenVPN](https://github.com/hwdsl2/openvpn-install/blob/master/README-zh-Hant.md)。

<details>
<summary>
查看腳本的範例輸出（終端記錄）。
</summary>

**註：** 此終端記錄僅用於示範目的。該記錄中的 VPN 憑據 **無效**。

<p align="center"><img src="docs/images/script-demo.svg"></p>
</details>
<details>
<summary>
如果無法下載，請點這裡。
</summary>

你也可以使用 `curl` 下載：

```bash
curl -fsSL https://get.vpnsetup.net -o vpn.sh && sudo sh vpn.sh
```

或者，你也可以使用這些連結：

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/vpnsetup.sh
```

如果無法下載，打開 [vpnsetup.sh](vpnsetup.sh)，然後點擊右側的 `Raw` 按鈕。按快捷鍵 `Ctrl/Cmd+A` 全選，`Ctrl/Cmd+C` 複製，然後貼上到你喜歡的編輯器。
</details>

另外，你也可以使用預先建構的 [Docker 映像](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh-Hant.md)。如需了解其他選項以及客戶端設定，請繼續閱讀以下部分。

\* 一個雲端伺服器、虛擬專用伺服器 (VPS) 或專用伺服器。

## 功能特性

- 全自動的 IPsec VPN 伺服器設定，無需使用者輸入
- 支援具有強大且快速加密演算法（例如 AES-GCM）的 IKEv2 模式
- 生成 VPN 設定檔以自動設定 iOS、macOS 和 Android 裝置
- 支援 Windows、macOS、iOS、Android、Chrome OS 和 Linux 客戶端
- 包含輔助腳本以管理 VPN 使用者和憑證

## 系統需求

一個雲端伺服器、虛擬專用伺服器 (VPS) 或專用伺服器，安裝以下作業系統之一：

- Ubuntu 24.04 或 22.04
- Debian 13、12 或 11
- CentOS Stream 10 或 9
- Rocky Linux 或 AlmaLinux
- Oracle Linux
- Amazon Linux 2

<details>
<summary>
其他受支援的 Linux 發行版。
</summary>

- Raspberry Pi OS (Raspbian)
- Kali Linux
- Alpine Linux
- Red Hat Enterprise Linux (RHEL)
</details>

這也包括公共雲服務中的 Linux 虛擬機，例如 [DigitalOcean](https://blog.ls20.com/digitalocean)、[Vultr](https://blog.ls20.com/vultr)、[Linode](https://blog.ls20.com/linode)、[OVH](https://www.ovhcloud.com/en/vps/) 和 [Microsoft Azure](https://azure.microsoft.com)。公共雲使用者也可以使用[使用者資料](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#vpnsetup)部署。

使用以下按鈕快速部署：

[![Deploy to Linode](docs/images/linode-deploy-button.png)](https://cloud.linode.com/stackscripts/37239) &nbsp;[![Deploy to AWS](docs/images/aws-deploy-button.png)](aws/README-zh.md) &nbsp;[![Deploy to Azure](docs/images/azure-deploy-button.png)](azure/README-zh.md)

[**&raquo; 我想建立並使用自己的 VPN，但沒有可用的伺服器**](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#gettingavps)

對於有外部防火牆的伺服器（例如 [EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html)/[GCE](https://cloud.google.com/vpc/docs/firewalls)），請為 VPN 開啟 UDP 連接埠 500 和 4500。

另外，你也可以使用預先建構的 [Docker 映像](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh-Hant.md)。進階使用者可以在 [Raspberry Pi](https://www.raspberrypi.com) 上安裝。[[1]](https://elasticbyte.net/posts/setting-up-a-native-cisco-ipsec-vpn-server-using-a-raspberry-pi/) [[2]](https://www.stewright.me/2018/07/create-a-raspberry-pi-vpn-server-using-l2tpipsec/)

:warning: **不要** 在你的 PC 或 Mac 上執行這些腳本！它們只能用在伺服器上！

## 安裝說明

首先，更新你的伺服器：執行 `sudo apt-get update && sudo apt-get dist-upgrade` (Ubuntu/Debian) 或 `sudo yum update` 並重新啟動。此步驟為可選，但建議執行。

要安裝 VPN，請從以下選項中選擇一個：

**選項 1：** 使用腳本隨機生成的 VPN 登入憑證（完成後會顯示）。

```bash
wget https://get.vpnsetup.net -O vpn.sh && sudo sh vpn.sh
```

**選項 2：** 編輯腳本並提供你自己的 VPN 登入憑證。

```bash
wget https://get.vpnsetup.net -O vpn.sh
nano -w vpn.sh
[替換為你自己的值： YOUR_IPSEC_PSK, YOUR_USERNAME 和 YOUR_PASSWORD]
sudo sh vpn.sh
```

**註：** 一個安全的 IPsec PSK 應至少包含 20 個隨機字元。

**選項 3：** 將你自己的 VPN 登入憑證定義為環境變數。

```bash
# 所有變數值必須用 '單引號' 括起來
# *不要* 在值中使用這些字元：  \ " '
wget https://get.vpnsetup.net -O vpn.sh
sudo VPN_IPSEC_PSK='你的IPsec預共享金鑰' \
VPN_USER='你的VPN使用者名稱' \
VPN_PASSWORD='你的VPN密碼' \
sh vpn.sh
```

你可以選擇在同一台伺服器上安裝 [WireGuard](https://github.com/hwdsl2/wireguard-install/blob/master/README-zh-Hant.md) 和/或 [OpenVPN](https://github.com/hwdsl2/openvpn-install/blob/master/README-zh-Hant.md)。如果你的伺服器執行 CentOS Stream、Rocky Linux 或 AlmaLinux，請先安裝 OpenVPN/WireGuard，然後再安裝 IPsec VPN。

<details>
<summary>
如果無法下載，請點這裡。
</summary>

你也可以使用 `curl` 下載。例如：

```bash
curl -fL https://get.vpnsetup.net -o vpn.sh
sudo sh vpn.sh
```

或者，你也可以使用這些連結：

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/vpnsetup.sh
```

如果無法下載，打開 [vpnsetup.sh](vpnsetup.sh)，然後點擊右側的 `Raw` 按鈕。按快捷鍵 `Ctrl/Cmd+A` 全選，`Ctrl/Cmd+C` 複製，然後貼上到你喜歡的編輯器。
</details>
<details>
<summary>
我需要安裝較舊版本的 Libreswan 版本 4。
</summary>

一般建議使用最新的 [Libreswan](https://libreswan.org/) 版本 5，它是本專案的預設版本。不過，如果你想要安裝較舊版本的 Libreswan 版本 4：

```bash
wget https://get.vpnsetup.net -O vpn.sh
sudo VPN_SWAN_VER=4.15 sh vpn.sh
```

**註：** 如果 Libreswan 版本 5 已經安裝，你可能需要先[解除安裝 VPN](docs/uninstall-zh.md)，然後再安裝 Libreswan 版本 4。或者，你也可以下載[升級腳本](#升級libreswan)，編輯它並指定 `SWAN_VER=4.15`，然後執行腳本。
</details>

## 自訂 VPN 選項

### 使用其他 DNS 伺服器

在 VPN 已連線時，客戶端預設設定為使用 [Google Public DNS](https://developers.google.com/speed/public-dns/)。在安裝 VPN 時，你可以為所有 VPN 模式指定其他 DNS 伺服器。此為可選設定。示例如下：

```bash
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 sh vpn.sh
```

使用 `VPN_DNS_SRV1` 指定主要 DNS 伺服器，使用 `VPN_DNS_SRV2` 指定次要 DNS 伺服器（可選）。

以下是一些常見的公共 DNS 提供商列表，供你參考。

| 提供商 | 主 DNS | 輔助 DNS | 註解 |
| ----- | ------ | ------- | ---- |
| [Google Public DNS](https://developers.google.com/speed/public-dns) | 8.8.8.8 | 8.8.4.4 | 本專案預設 |
| [Cloudflare](https://1.1.1.1/dns/) | 1.1.1.1 | 1.0.0.1 | 另見：[Cloudflare for families](https://1.1.1.1/family/) |
| [Quad9](https://www.quad9.net) | 9.9.9.9 | 149.112.112.112 | 阻擋惡意網域 |
| [OpenDNS](https://www.opendns.com/home-internet-security/) | 208.67.222.222 | 208.67.220.220 | 阻擋網路釣魚網域，可設定。 |
| [CleanBrowsing](https://cleanbrowsing.org/filters/) | 185.228.168.9 | 185.228.169.9 | 提供[網域過濾器](https://cleanbrowsing.org/filters/) |
| [NextDNS](https://nextdns.io/?from=bg25bwmp) | 依需求選擇 | 依需求選擇 | 廣告攔截，提供免費方案。[了解更多](https://nextdns.io/?from=bg25bwmp)。 |
| [Control D](https://controld.com/free-dns) | 依需求選擇 | 依需求選擇 | 廣告攔截，可自訂設定。[了解更多](https://controld.com/free-dns)。 |

如果你需要在安裝 VPN 之後更改 DNS 伺服器，請參見[進階用法](docs/advanced-usage-zh.md)。

**註：** 如果伺服器上已經設定 IKEv2，以上變數對 IKEv2 模式無效。在此情況下，如需自訂 IKEv2 選項（例如 DNS 伺服器），你可以先 [移除 IKEv2](docs/ikev2-howto-zh.md#移除-ikev2)，然後執行 `sudo ikev2.sh` 重新設定。

### 自訂 IKEv2 選項

在安裝 VPN 時，進階使用者可以自訂 IKEv2 選項。此為可選設定。

<details open>
<summary>
選項 1：在安裝 VPN 時跳過 IKEv2，然後使用自訂選項設定 IKEv2。
</summary>

在安裝 VPN 時，你可以跳過 IKEv2，只安裝 IPsec/L2TP 和 IPsec/XAuth（"Cisco IPsec"）模式：

```bash
sudo VPN_SKIP_IKEV2=yes sh vpn.sh
```

（可選）如果要為 VPN 客戶端指定其他 DNS 伺服器，你可以定義 `VPN_DNS_SRV1` 和 `VPN_DNS_SRV2`（可選）。更多資訊請參見[使用其他 DNS 伺服器](#使用其他-dns-伺服器)。

然後執行 IKEv2 輔助腳本，以互動方式使用自訂選項設定 IKEv2：

```bash
sudo ikev2.sh
```

你可以自訂以下選項：VPN 伺服器的網域名稱、第一個客戶端的名稱與憑證有效期限、VPN 客戶端的 DNS 伺服器，以及是否對客戶端設定檔進行密碼保護。

**註：** 如果伺服器上已經設定 IKEv2，則 `VPN_SKIP_IKEV2` 變數無效。在此情況下，如需自訂 IKEv2 選項，你可以先 [移除 IKEv2](docs/ikev2-howto-zh.md#移除-ikev2)，然後執行 `sudo ikev2.sh` 重新設定。
</details>
<details>
<summary>
選項 2：使用環境變數自訂 IKEv2 選項。
</summary>

在安裝 VPN 時，你可以指定一個網域名稱作為 IKEv2 伺服器位址。此為可選設定。該網域名稱必須是完整網域名稱 (FQDN)。示例如下：

```bash
sudo VPN_DNS_NAME='vpn.example.com' sh vpn.sh
```

同樣地，你也可以指定第一個 IKEv2 客戶端的名稱。如果未指定，則使用預設值 `vpnclient`。

```bash
sudo VPN_CLIENT_NAME='your_client_name' sh vpn.sh
```

在 VPN 已連線時，客戶端預設設定為使用 [Google Public DNS](https://developers.google.com/speed/public-dns/)。你可以為所有 VPN 模式指定其他 DNS 伺服器。示例如下：

```bash
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 sh vpn.sh
```

預設情況下，匯入 IKEv2 客戶端設定時不需要密碼。你可以選擇使用隨機密碼保護客戶端設定檔。

```bash
sudo VPN_PROTECT_CONFIG=yes sh vpn.sh
```
</details>
<details>
<summary>
供參考：IKEv1 和 IKEv2 參數列表。
</summary>

| IKEv1 參數\* |預設值 |自訂（環境變數）\*\* |
| ------------ | ---- | ----------------- |
|伺服器位址（DNS 網域名稱）| - |不能，但你可以使用 DNS 網域名稱進行連線 |
|伺服器位址（公網 IP）|自動偵測 | VPN_PUBLIC_IP |
| IPsec 預共享金鑰 |自動生成 | VPN_IPSEC_PSK |
| VPN 使用者名稱 | vpnuser | VPN_USER |
| VPN 密碼 |自動生成 | VPN_PASSWORD |
|客戶端的 DNS 伺服器 |Google Public DNS | VPN_DNS_SRV1, VPN_DNS_SRV2 |
|跳過 IKEv2 安裝 |no | VPN_SKIP_IKEV2=yes |

\* 這些 IKEv1 參數適用於 IPsec/L2TP 和 IPsec/XAuth ("Cisco IPsec") 模式。   
\*\* 在執行 vpn(setup).sh 時將這些定義為環境變數。

| IKEv2 參數\* |預設值 |自訂（環境變數）\*\* |自訂（互動式）\*\*\* |
| ----------- | ---- | ------------------ | ----------------- |
|伺服器位址（DNS 網域名稱）| - | VPN_DNS_NAME | ✅ |
|伺服器位址（公網 IP）|自動偵測 | VPN_PUBLIC_IP | ✅ |
|第一個客戶端的名稱 | vpnclient | VPN_CLIENT_NAME | ✅ |
|客戶端的 DNS 伺服器 |Google Public DNS | VPN_DNS_SRV1, VPN_DNS_SRV2 | ✅ |
|保護客戶端設定檔 |no | VPN_PROTECT_CONFIG=yes | ✅ |
|啟用/停用 MOBIKE |如果系統支援則啟用 | ❌ | ✅ |
|客戶端憑證有效期限 | 10 年（120 個月）| VPN_CLIENT_VALIDITY\*\*\*\* | ✅ |
| CA 和伺服器憑證有效期限 | 10 年（120 個月）| ❌ | ❌ |
| CA 憑證名稱 | IKEv2 VPN CA | ❌ | ❌ |
|憑證金鑰長度 | 3072 bits | ❌ | ❌ |

\* 這些 IKEv2 參數適用於 IKEv2 模式。   
\*\* 在執行 vpn(setup).sh 時，或在自動模式下設定 IKEv2 時 (`sudo ikev2.sh --auto`) 將這些定義為環境變數。   
\*\*\* 可以在互動式設定 IKEv2 期間自訂 (`sudo ikev2.sh`)。參見上面的選項 1。   
\*\*\*\* 使用 `VPN_CLIENT_VALIDITY` 定義客戶端憑證的有效期限（單位：月）。它必須是 1 到 120 之間的整數。

除了這些參數，高級使用者還可以在安裝時 [自訂 VPN 子網](docs/advanced-usage-zh.md#自定义-vpn-子网)。
</details>

## 下一步

*其他語言版本: [English](README.md#next-steps), [简体中文](README-zh.md#下一步), [繁體中文](README-zh-Hant.md#下一步), [日本語](README-ja.md#次のステップ), [Русский](README-ru.md#следующие-шаги)。*

設定你的電腦或其他裝置使用 VPN。請參見以下連結（簡體中文）：

**[設定 IKEv2 VPN 客戶端（推薦）](docs/ikev2-howto-zh.md)**

**[設定 IPsec/L2TP VPN 客戶端](docs/clients-zh.md)**

**[設定 IPsec/XAuth ("Cisco IPsec") VPN 客戶端](docs/clients-xauth-zh.md)**

**閱讀 [:book: VPN book](docs/vpn-book-zh-Hant.md) 以存取 [額外內容](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-X8X5FVFZC)。**

開始使用自己的專屬 VPN! :sparkles::tada::rocket::sparkles:

## 重要提示

**Windows 使用者** 對於 IPsec/L2TP 模式，在首次連線之前需要 [修改登錄檔](docs/clients-zh.md#windows-错误-809)，以解決 VPN 伺服器或客戶端與 NAT（例如家用路由器）的相容問題。

同一個 VPN 帳戶可以在你的多個裝置上使用。但由於 IPsec/L2TP 的限制，如果需要連線到同一個 NAT（例如家用路由器）後面的多個裝置，你必須使用 [IKEv2](docs/ikev2-howto-zh.md) 或 [IPsec/XAuth](docs/clients-xauth-zh.md) 模式。要查看或變更 VPN 使用者帳戶，請參見 [管理 VPN 使用者](docs/manage-users-zh.md)。

對於有外部防火牆的伺服器（例如 [EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html)/[GCE](https://cloud.google.com/vpc/docs/firewalls)），請為 VPN 開啟 UDP 連接埠 500 和 4500。阿里雲使用者請參見 [#433](https://github.com/hwdsl2/setup-ipsec-vpn/issues/433)。

在 VPN 已連線時，客戶端設定為使用 [Google Public DNS](https://developers.google.com/speed/public-dns/)。如果偏好其他的網域解析服務，請參見 [進階用法](docs/advanced-usage-zh.md)。

使用核心支援有助於提升 IPsec/L2TP 效能。它在所有 [支援的系統](#系統需求) 上可用。Ubuntu 系統需要安裝 `linux-modules-extra-$(uname -r)` 軟體套件並執行 `service xl2tpd restart`。

這些腳本在變更現有設定檔之前會先建立備份，並使用 `.old-日期-時間` 作為檔名後綴。

## 升級Libreswan

使用以下命令更新你的 VPN 伺服器上的 [Libreswan](https://libreswan.org)（[更新日誌](https://github.com/libreswan/libreswan/blob/main/CHANGES) | [通知清單](https://lists.libreswan.org)）。

```bash
wget https://get.vpnsetup.net/upg -O vpnup.sh && sudo sh vpnup.sh
```

<details>
<summary>
如果無法下載，請點這裡。
</summary>

你也可以使用 `curl` 下載：

```bash
curl -fsSL https://get.vpnsetup.net/upg -o vpnup.sh && sudo sh vpnup.sh
```

或者，你也可以使用這些連結：

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/extras/vpnupgrade.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/extras/vpnupgrade.sh
```

如果無法下載，打開 [vpnupgrade.sh](extras/vpnupgrade.sh)，然後點擊右側的 `Raw` 按鈕。按快捷鍵 `Ctrl/Cmd+A` 全選，`Ctrl/Cmd+C` 複製，然後貼上到你喜歡的編輯器。
</details>

目前支援的 Libreswan 最新版本是 `5.3`。查看已安裝版本：`ipsec --version`。

**註：** `xl2tpd` 可以使用系統的套件管理器進行更新，例如 Ubuntu/Debian 上的 `apt-get`。

## 管理 VPN 使用者

請參見 [管理 VPN 使用者](docs/manage-users-zh.md) （簡體中文）。

- [使用輔助腳本管理 VPN 使用者](docs/manage-users-zh.md#使用辅助脚本管理-vpn-用户)
- [查看 VPN 使用者](docs/manage-users-zh.md#查看-vpn-用户)
- [查看或變更 IPsec PSK](docs/manage-users-zh.md#查看或更改-ipsec-psk)
- [手動管理 VPN 使用者](docs/manage-users-zh.md#手动管理-vpn-用户)

## 進階用法

請參見 [進階用法](docs/advanced-usage-zh.md) （簡體中文）。

- [使用其他 DNS 伺服器](docs/advanced-usage-zh.md#使用其他的-dns-服务器)
- [網域名稱與變更伺服器 IP](docs/advanced-usage-zh.md#域名和更改服务器-ip)
- [僅限 IKEv2 的 VPN](docs/advanced-usage-zh.md#仅限-ikev2-的-vpn)
- [VPN 內網 IP 與流量](docs/advanced-usage-zh.md#vpn-内网-ip-和流量)
- [指定 VPN 伺服器的公有 IP](docs/advanced-usage-zh.md#指定-vpn-服务器的公有-ip)
- [自訂 VPN 子網](docs/advanced-usage-zh.md#自定义-vpn-子网)
- [轉發連接埠到 VPN 客戶端](docs/advanced-usage-zh.md#转发端口到-vpn-客户端)
- [VPN 分流](docs/advanced-usage-zh.md#vpn-分流)
- [存取 VPN 伺服器的網段](docs/advanced-usage-zh.md#访问-vpn-服务器的网段)
- [VPN 伺服器網段存取 VPN 客戶端](docs/advanced-usage-zh.md#vpn-服务器网段访问-vpn-客户端)
- [變更 IPTables 規則](docs/advanced-usage-zh.md#更改-iptables-规则)
- [部署 Google BBR 壅塞控制](docs/advanced-usage-zh.md#部署-google-bbr-拥塞控制)

## 移除 VPN

要移除 IPsec VPN，執行[輔助腳本](extras/vpnuninstall.sh)：

**警告：** 此輔助腳本將從你的伺服器中刪除 IPsec VPN。所有 VPN 設定將被**永久刪除**，並且 Libreswan 和 xl2tpd 將被移除。此操作**無法復原**！

```bash
wget https://get.vpnsetup.net/unst -O unst.sh && sudo bash unst.sh
```

<details>
<summary>
如果無法下載，請點這裡。
</summary>

你也可以使用 `curl` 下載：

```bash
curl -fsSL https://get.vpnsetup.net/unst -o unst.sh && sudo bash unst.sh
```

或者，你也可以使用這些連結：

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/extras/vpnuninstall.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/extras/vpnuninstall.sh
```
</details>

更多資訊請參見 [移除 VPN](docs/uninstall-zh.md)。

## 問題與回饋

- 如果你對本專案有建議，請提交一個 [改進建議](https://github.com/hwdsl2/setup-ipsec-vpn/issues/new/choose)，或歡迎提交 [Pull request](https://github.com/hwdsl2/setup-ipsec-vpn/pulls)。
- 如果你發現可重現的程式漏洞，請為 [IPsec VPN](https://github.com/libreswan/libreswan/issues?q=is%3Aissue) 或 [VPN 腳本](https://github.com/hwdsl2/setup-ipsec-vpn/issues/new/choose) 提交錯誤回報。
- 有問題想提問？請先搜尋 [既有的 issues](https://github.com/hwdsl2/setup-ipsec-vpn/issues?q=is%3Aissue) 以及 [這個 Gist](https://gist.github.com/hwdsl2/9030462#comments) 和 [我的部落格](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#disqus_thread) 上已有的留言。
- VPN 相關問題可在 [Libreswan](https://lists.libreswan.org) 或 [strongSwan](https://lists.strongswan.org) 郵件列表提問，或參考以下網站：[[1]](https://libreswan.org/wiki/Main_Page) [[2]](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/sec-securing_virtual_private_networks) [[3]](https://wiki.strongswan.org/projects/strongswan/wiki/UserDocumentation) [[4]](https://wiki.gentoo.org/wiki/IPsec_L2TP_VPN_server) [[5]](https://wiki.archlinux.org/index.php/Openswan_L2TP/IPsec_VPN_client_setup)。

## 授權條款

版權所有 (C) 2014-2025 [Lin Song](https://github.com/hwdsl2) [![View my profile on LinkedIn](https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png)](https://www.linkedin.com/in/linsongui)   
基於 [Thomas Sarlandie 的工作](https://github.com/sarfata/voodooprivacy)（版權所有 2012）

[![Creative Commons License](https://i.creativecommons.org/l/by-sa/3.0/88x31.png)](http://creativecommons.org/licenses/by-sa/3.0/)   
此專案採用 [Creative Commons 姓名標示-相同方式分享 3.0](http://creativecommons.org/licenses/by-sa/3.0/) 授權條款。   
必須署名：請在任何衍生作品中包含我的名字，並且讓我知道你是如何改進它的！
