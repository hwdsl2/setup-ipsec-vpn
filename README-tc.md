# IPsec VPN 伺服器一鍵安裝腳本
 
[![Build Status](https://img.shields.io/travis/hwdsl2/setup-ipsec-vpn.svg?maxAge=1200)](https://travis-ci.org/hwdsl2/setup-ipsec-vpn) [![GitHub Stars](https://img.shields.io/github/stars/hwdsl2/setup-ipsec-vpn.svg?maxAge=86400)](https://github.com/hwdsl2/setup-ipsec-vpn/stargazers) [![Docker Stars](https://img.shields.io/docker/stars/hwdsl2/ipsec-vpn-server.svg?maxAge=86400)](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md) [![Docker Pulls](https://img.shields.io/docker/pulls/hwdsl2/ipsec-vpn-server.svg?maxAge=86400)](https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md)
 
使用 Linux 腳本一鍵快速搭建自己的 IPsec VPN 伺服器。支援 IPsec/L2TP 和 Cisco IPsec 協議，可用於 Ubuntu/Debian/CentOS 系統。你只需提供自己的 VPN 登錄憑證，然後執行腳本。腳本會自動完成安裝。
 
IPsec VPN 可以加密你的網絡流量，以防止在通過互聯網傳送資料時，任何人對你和 VPN 伺服器之間的數據作未經授權的訪問。使用在咖啡廳，機場或旅館房間等等的不安全的網絡時，這VPN將能有效地加密你的資料。
 
我們將使用 <a href="https://libreswan.org/" target="_blank">Libreswan</a> 作為 IPsec 伺服器，以及 <a href="https://github.com/xelerance/xl2tpd" target="_blank">xl2tpd</a> 作為 L2TP 提供者。
 
<a href="https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md" target="_blank">**&raquo; 另見： Docker 上的 IPsec VPN 伺服器**</a>
 
*其他語言: [English](README.md), [繁體中文](README-tc.md), [简体中文](README-sc.md).*
 
#### 目錄
 
- [快速開始](#快速開始)
- [功能特性](#功能特性)
- [系統要求](#系統要求)
- [安裝說明](#安裝說明)
- [下一步](#下一步)
- [重要提示](#重要提示)
- [升級Libreswan](#升級libreswan)
- [問題和反饋](#問題和反饋)
- [卸載說明](#卸載說明)
- [另見](#另見)
- [授權協議](#授權協議)
 
## 快速開始
 
首先，在你的 Linux 伺服器[\*](#quick-start-note) 上安裝一個全新的 Ubuntu LTS, Debian 或者 CentOS 系統。
 
然後，使用以下指令快速搭建 IPsec VPN 伺服器：
 
```bash
wget https://git.io/vpnsetup -O vpnsetup.sh && sudo sh vpnsetup.sh
```
 
假如使用 CentOS，請將上面的地址換成 `https://git.io/vpnsetup-centos`。
 
腳本會隨機自動生成你的 VPN 登錄憑證，並在安裝完成後顯示在屏幕上。
 
如需了解其它安裝選項，以及如何設定 VPN 客戶端，請繼續閱讀以下部分。
 
<a name="quick-start-note"></a>
\* 一個專用伺服器或者虛擬專用伺服器 (VPS)。不支援 OpenVZ VPS 。
 
## 功能特性
 
- **新:** 增加支持更高效能的 `IPsec/XAuth ("Cisco IPsec")` 模式
- **新:** 現在亦可以使用預載 VPN 伺服器的 <a href="https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md" target="_blank">Docker 鏡像</a>
- 全自動的 IPsec VPN 伺服器配置，無需額外用戶輸入
- 封裝所有的 VPN 流量在 UDP 協議，不需要 ESP 協議支持
- 可直接作為 Amazon EC2 實例創建時的用戶數據使用
- 包含 `sysctl.conf` 優化設置，以達到更佳的傳輸性能
- 已測試平台： Ubuntu 18.04/16.04, Debian 9/8 和 CentOS 7/6
 
## 系統要求
 
使用這些映像之一的新創建的 <a href="https://aws.amazon.com/ec2/" target="_blank">Amazon EC2</a> ：
- <a href="https://cloud-images.ubuntu.com/locator/" target="_blank">Ubuntu 18.04 (Bionic) or 16.04 (Xenial)</a>
- <a href="https://wiki.debian.org/Cloud/AmazonEC2Image" target="_blank">Debian 10 (Buster)</a>[\*\*](#debian-10-note)<a href="https://wiki.debian.org/Cloud/AmazonEC2Image" target="_blank">, 9 (Stretch) or 8 (Jessie)</a>
- <a href="https://aws.amazon.com/marketplace/pp/B00O7WM7QW" target="_blank">CentOS 7 (x86_64) with Updates</a>
- <a href="https://aws.amazon.com/marketplace/pp/B00NQAYLWO" target="_blank">CentOS 6 (x86_64) with Updates</a>
- <a href="https://aws.amazon.com/partners/redhat/faqs/" target="_blank">Red Hat Enterprise Linux (RHEL) 7 or 6</a>
 
請參見 <a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#vpnsetup" target="_blank">詳細步驟</a> 以及 <a href="https://aws.amazon.com/cn/ec2/pricing/" target="_blank">EC2 定價細節</a>。
 
**-或者-**
 
一個全新專用伺服器，或者基於 KVM/Xen 的全新虛擬專用伺服器 (VPS)，並使用以上的操作系統。注意：不支援OpenVZ VPS ，OpenVZ VPS 用戶請另外嘗試 <a href="https://github.com/Nyr/openvpn-install" target="_blank">OpenVPN</a>。
 
同時包括各種公開雲服務中的 Linux 虛擬機，比如 <a href="https://blog.ls20.com/digitalocean" target="_blank">DigitalOcean</a>, <a href="https://blog.ls20.com/vultr" target="_blank">Vultr</a>, <a href="https://blog.ls20.com/linode" target="_blank">Linode</a>, <a href="https://cloud.google.com/compute/" target="_blank">Google Compute Engine</a>, <a href="https://aws.amazon.com/lightsail/" target="_blank">Amazon Lightsail</a>, <a href="https://azure.microsoft.com" target="_blank">Microsoft Azure</a>, <a href="https://www.ibm.com/cloud/virtual-servers" target="_blank">IBM Cloud</a>, <a href="https://www.ovh.com/world/vps/" target="_blank">OVH</a> 和 <a href="https://www.rackspace.com" target="_blank">Rackspace</a>。
 
<a href="azure/README-zh.md" target="_blank"><img src="docs/images/azure-deploy-button.png" alt="Deploy to Azure" /></a> <a href="http://dovpn.carlfriess.com/" target="_blank"><img src="docs/images/do-install-button.png" alt="Install on DigitalOcean" /></a> <a href="https://www.linode.com/stackscripts/view/37239" target="_blank"><img src="docs/images/linode-deploy-button.png" alt="Deploy to Linode" /></a>
 
<a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#gettingavps" target="_blank">**&raquo; 我想建立並使用自己的 VPN ，但是沒有可用的伺服器**</a>
 
進階用戶可以在一個 USD$35 的 <a href="https://www.raspberrypi.org" target="_blank">Raspberry Pi 3</a> 上搭建 VPN 伺服器。詳見以下教程： <a href="https://www.stewright.me/2018/07/create-a-raspberry-pi-vpn-server-using-l2tpipsec/" target="_blank">[1]</a> <a href="https://blog.elasticbyte.net/setting-up-a-native-cisco-ipsec-vpn-server-using-a-raspberry-pi/" target="_blank">[2]</a>。
 
<a name="debian-10-note"></a>
\*\* Debian 10 用戶需要使用標準的 Linux 內核（而不是 "cloud" 版本）。詳情請看 <a href="docs/clients-zh.md#debian-10-內核" target="_blank">這裏</a>。
 
:warning: **不要** 在你的 PC 或者 Mac 上運行這些腳本！它們只能用在伺服器上！
 
## 安裝說明
 
### Ubuntu & Debian
 
首先，建議先更新你的系統： 運行 `apt-get update && apt-get dist-upgrade` 並重啟。
 
下一步，安裝 VPN：請從以下選項中選擇一個：
 
**選項 1:** 使用腳本並隨機生成一組 VPN 登錄憑證 （完成執行後憑證會在屏幕上顯示）：
 
```bash
wget https://git.io/vpnsetup -O vpnsetup.sh && sudo sh vpnsetup.sh
```
 
**選項 2:** 修改腳本並輸入你自己的 VPN 登錄憑證：
 
```bash
wget https://git.io/vpnsetup -O vpnsetup.sh
nano -w vpnsetup.sh
[修改成你自創的資料： YOUR_IPSEC_PSK, YOUR_USERNAME 和 YOUR_PASSWORD]
sudo sh vpnsetup.sh
```
 
**註：** 一個安全的 IPsec PSK 應該至少包含 20 個隨機字符。
 
**選項 3:** 將你自己的 VPN 登錄憑證設定為環境變量(environment variables)：
 
```bash
# 所有變量值必須用 '單引號' 括起來
# *不要* 在值中使用這些字符：  \ " '
wget https://git.io/vpnsetup -O vpnsetup.sh && sudo \
VPN_IPSEC_PSK='你的IPsec預設共享密鑰' \
VPN_USER='你的VPN用戶名' \
VPN_PASSWORD='你的VPN密碼' \
sh vpnsetup.sh
```
 
**註：** 如果無法通過 `wget` 下載，你也可以打開 <a href="vpnsetup.sh" target="_blank">vpnsetup.sh</a> (或者 <a href="vpnsetup_centos.sh" target="_blank">vpnsetup_centos.sh</a>)，然後點擊右方的 **`Raw`** 按鈕。按快捷鍵 `Ctrl-A` 全選， `Ctrl-C` 複製，然後粘貼到自選的編輯器。
 
### CentOS & RHEL
 
首先，建議先更新你的系統： 運行 `yum update` 並重啟。
 
按照與上面相同的步驟，但將 `https://git.io/vpnsetup` 換成 `https://git.io/vpnsetup-centos`。
 
## 下一步
 
設定你的電腦或其它設備使用 VPN 。請參見：
 
<a href="docs/clients-zh.md" target="_blank">**配置 IPsec/L2TP VPN 客戶端**</a>
 
<a href="docs/clients-xauth-zh.md" target="_blank">**配置 IPsec/XAuth ("Cisco IPsec") VPN 客戶端**</a>
 
<a href="docs/ikev2-howto-zh.md" target="_blank">**詳細教學：如何配置 IKEv2 VPN**</a>
 
如果在連接過程中遇到錯誤，請參見 <a href="docs/clients-zh.md#故障排除" target="_blank">故障排除</a>。
 
開始使用自己的專屬 VPN 吧! :sparkles::tada::rocket::sparkles:
 
## 重要提示
 
*其他語言: [English](README.md#important-notes), [繁體中文](README-tc.md#重要提示), [简体中文](README-sc.md#重要提示).*
 
**Windows 用戶** 在首次連接之前或需要<a href="docs/clients-zh.md#windows-錯誤-809" target="_blank">修改註冊表</a>，以解決 VPN 伺服器和/或客戶端與 NAT（比如家用路由器）的兼容問題。
 
**Android 6 和 7 用戶**：如果你遇到連接問題，請嘗試 <a href="docs/clients-zh.md#android-6-和-7" target="_blank">這些步驟</a>。
 
同一個 VPN 賬戶可以在你的多個設備上使用。但是由於 IPsec/L2TP 的限制，如果需要同時連接在同一個 NAT （比如家用路由器）後面的多個設備到 VPN 伺服器，你只能使用 <a href="docs/clients-xauth-zh.md" target="_blank">IPsec/XAuth 模式</a>。
 
對於有外部防火墻的伺服器（比如 <a href="https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-network-security.html" target="_blank">EC2</a>/<a href="https://cloud.google.com/vpc/docs/firewalls" target="_blank">GCE</a>），請為 VPN 打開 UDP 端口 500 和 4500。阿里雲用戶請參見 [#433](https://github.com/hwdsl2/setup-ipsec-vpn/issues/433)。
 
如果需要添加，修改或者刪除 VPN 用戶賬戶，請參見 <a href="docs/manage-users-zh.md" target="_blank">管理 VPN 用戶</a>。該文檔包含輔助腳本，方便用家管理 VPN 用戶。
 
預設在 VPN 已連接時，客戶端會使用 <a href="https://developers.google.com/speed/public-dns/" target="_blank">Google Public DNS</a>。如希望其它的域名解析服務，請編輯 `/etc/ppp/options.xl2tpd` 和 `/etc/ipsec.conf` 並修改 `8.8.8.8` 和 `8.8.4.4` 成自選的DNS，然後重啟伺服器。進階用戶亦可在執行建立 VPN 腳本時定義 `VPN_DNS_SRV1` 和 `VPN_DNS_SRV2`。
 
有些系統亦有提供使用能提升 IPsec/L2TP 性能的內核 ，如 Ubuntu 18.04/16.04, Debian 9 和 CentOS 7/6。 Ubuntu 系統需要安裝 `linux-modules-extra-$(uname -r)`（或者 `linux-image-extra`），然後運行 `service xl2tpd restart`。
 
如果需要在安裝完畢後更改 IPTables 規則，請編輯 `/etc/iptables.rules` 和/或 `/etc/iptables/rules.v4` (Ubuntu/Debian)，或者 `/etc/sysconfig/iptables` (CentOS/RHEL)。然後重啟伺服器。
 
在使用 `IPsec/L2TP` 連接時，VPN 伺服器在虛擬網絡 `192.168.42.0/24` 內具有 IP `192.168.42.1`。
 
此腳本會在修改現有的配置文件之前先做備份，並使用 `.old-日期-時間` 為文件名後綴。
 
## 升級Libreswan
 
若要升級 <a href="https://libreswan.org" target="_blank">Libreswan</a> （<a href="https://github.com/libreswan/libreswan/blob/master/CHANGES" target="_blank">更新日志</a> | <a href="https://lists.libreswan.org/mailman/listinfo/swan-announce" target="_blank">通知列表</a> 請使用以下兩個腳本 <a href="extras/vpnupgrade.sh" target="_blank">vpnupgrade.sh</a> 和 <a href="extras/vpnupgrade_centos.sh" target="_blank">vpnupgrade_centos.sh</a>。請在運行前根據需要修改 `SWAN_VER` 到想安裝的版本。如想查看已安裝版本： `ipsec --version`.
 
```bash
# Ubuntu & Debian
wget https://git.io/vpnupgrade -O vpnupgrade.sh
# CentOS & RHEL
wget https://git.io/vpnupgrade-centos -O vpnupgrade.sh
```
 
## 問題和反饋
 
- 假如有問題想提問？請先搜索已有的留言，在 <a href="https://gist.github.com/hwdsl2/9030462#comments" target="_blank">這個 Gist</a> 以及 <a href="https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#disqus_thread" target="_blank">我的博客</a>。
- VPN 的相關問題亦可在 <a href="https://lists.libreswan.org/mailman/listinfo/swan" target="_blank">Libreswan</a> 或 <a href="https://lists.strongswan.org/mailman/listinfo/users" target="_blank">strongSwan</a> 郵件列表提問，或者參考這些網站： <a href="https://libreswan.org/wiki/Main_Page" target="_blank">[1]</a> <a href="https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/sec-securing_virtual_private_networks" target="_blank">[2]</a> <a href="https://wiki.strongswan.org/projects/strongswan/wiki/UserDocumentation" target="_blank">[3]</a> <a href="https://wiki.gentoo.org/wiki/IPsec_L2TP_VPN_server" target="_blank">[4]</a> <a href="https://wiki.archlinux.org/index.php/Openswan_L2TP/IPsec_VPN_client_setup" target="_blank">[5]</a>。
- 如果你發現了一個可重覆的程序漏洞，請提交一個 <a href="https://github.com/hwdsl2/setup-ipsec-vpn/issues?q=is%3Aissue" target="_blank">GitHub Issue</a>。
 
## 卸載說明
 
請參見 <a href="docs/uninstall-zh.md" target="_blank">卸載 VPN</a>。
 
## 另見
 
- <a href="https://github.com/hwdsl2/docker-ipsec-vpn-server/blob/master/README-zh.md" target="_blank">IPsec VPN Server on Docker</a>
- <a href="https://github.com/trailofbits/algo" target="_blank">Algo VPN</a>
- <a href="https://github.com/StreisandEffect/streisand" target="_blank">Streisand</a>
- <a href="https://github.com/Nyr/openvpn-install" target="_blank">OpenVPN Install</a>
 
## 授權協議
 
版權所有 (C) 2014-2019 <a href="https://www.linkedin.com/in/linsongui" target="_blank">Lin Song</a> <a href="https://www.linkedin.com/in/linsongui" target="_blank"><img src="https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png" width="160" height="25" border="0" alt="View my profile on LinkedIn"></a>   
基於 <a href="https://github.com/sarfata/voodooprivacy" target="_blank">Thomas Sarlandie 的工作</a> (版權所有 2012)
 
這個項目是以 <a href="http://creativecommons.org/licenses/by-sa/3.0/" target="_blank">知識共享署名-相同方式共享3.0</a> 許可協議授權。   
必須署名： 請包括我的名字在任何衍生產品，並且讓我知道你是如何改善它的！