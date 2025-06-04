[English](README.md) | [中文](README-zh.md) | [日本語](README-ja.md)

# IPsec VPN サーバー自動セットアップスクリプト

[![Build Status](https://github.com/hwdsl2/setup-ipsec-vpn/actions/workflows/main.yml/badge.svg)](https://github.com/hwdsl2/setup-ipsec-vpn/actions/workflows/main.yml) [![GitHub Stars](docs/images/badges/github-stars.svg)](https://github.com/hwdsl2/setup-ipsec-vpn/stargazers) [![Docker Stars](docs/images/badges/docker-stars.svg)](https://github.com/hwdsl2/docker-ipsec-vpn-server) [![Docker Pulls](docs/images/badges/docker-pulls.svg)](https://github.com/hwdsl2/docker-ipsec-vpn-server)

数分で自分のIPsec VPNサーバーをセットアップし、IPsec/L2TP、Cisco IPsec、IKEv2をサポートします。

IPsec VPNはネットワークトラフィックを暗号化し、インターネット経由でデータが送信される際に、VPNサーバーとあなたの間の誰もがデータを盗聴できないようにします。これは、コーヒーショップ、空港、ホテルの部屋などの安全でないネットワークを使用する際に特に有用です。

IPsecサーバーとして[Libreswan](https://libreswan.org/)を使用し、L2TPプロバイダーとして[xl2tpd](https://github.com/xelerance/xl2tpd)を使用します。

**[&raquo; :book: 本: VPNサーバーの構築方法](docs/vpn-book.md)** [[日本語](https://books2read.com/vpnguideja?store=amazon) | [English](https://books2read.com/vpnguide?store=amazon) | [中文](https://books2read.com/vpnguidezh) | [Español](https://books2read.com/vpnguidees?store=amazon) | [Deutsch](https://books2read.com/vpnguidede?store=amazon) | [Français](https://books2read.com/vpnguidefr?store=amazon) | [Italiano](https://books2read.com/vpnguideit?store=amazon)]

## クイックスタート

まず、Ubuntu、Debian、またはCentOSをインストールしたLinuxサーバー\*を準備します。

このワンライナーを使用してIPsec VPNサーバーをセットアップします：

```bash
wget https://get.vpnsetup.net -O vpn.sh && sudo sh vpn.sh
```

VPNログイン情報はランダムに生成され、完了時に表示されます。

**オプション:** 同じサーバーに[WireGuard](https://github.com/hwdsl2/wireguard-install)および/または[OpenVPN](https://github.com/hwdsl2/openvpn-install)をインストールします。

<details>
<summary>
スクリプトの動作を確認する（ターミナル記録）。
</summary>

**注:** この記録はデモ目的のみです。この記録のVPN資格情報は**無効**です。

<p align="center"><img src="docs/images/script-demo.svg"></p>
</details>
<details>
<summary>
ダウンロードできない場合はこちらをクリックしてください。
</summary>

`curl`を使用してダウンロードすることもできます：

```bash
curl -fsSL https://get.vpnsetup.net -o vpn.sh && sudo sh vpn.sh
```

代替セットアップURL：

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/vpnsetup.sh
```

ダウンロードできない場合は、[vpnsetup.sh](vpnsetup.sh)を開き、右側の`Raw`ボタンをクリックします。`Ctrl/Cmd+A`を押してすべて選択し、`Ctrl/Cmd+C`を押してコピーし、お気に入りのエディタに貼り付けます。
</details>

事前構築された[Dockerイメージ](https://github.com/hwdsl2/docker-ipsec-vpn-server)も利用可能です。他のオプションやクライアントのセットアップについては、以下のセクションを参照してください。

\* クラウドサーバー、仮想プライベートサーバー（VPS）、または専用サーバー。

## 機能

- 完全自動化されたIPsec VPNサーバーのセットアップ、ユーザー入力不要
- 強力で高速な暗号（例：AES-GCM）をサポートするIKEv2をサポート
- iOS、macOS、Androidデバイスを自動設定するVPNプロファイルを生成
- Windows、macOS、iOS、Android、Chrome OS、LinuxをVPNクライアントとしてサポート
- VPNユーザーと証明書を管理するためのヘルパースクリプトを含む

## 要件

以下のいずれかのインストールを備えたクラウドサーバー、仮想プライベートサーバー（VPS）、または専用サーバー：

- Ubuntu 24.04または22.04
- Debian 12または11
- CentOS Stream 10または9
- Rocky LinuxまたはAlmaLinux
- Oracle Linux
- Amazon Linux 2

<details>
<summary>
他のサポートされているLinuxディストリビューション。
</summary>

- Raspberry Pi OS（Raspbian）
- Kali Linux
- Alpine Linux
- Red Hat Enterprise Linux（RHEL）
</details>

これは、[DigitalOcean](https://blog.ls20.com/digitalocean)、[Vultr](https://blog.ls20.com/vultr)、[Linode](https://blog.ls20.com/linode)、[OVH](https://www.ovhcloud.com/en/vps/)、および[Microsoft Azure](https://azure.microsoft.com)などのパブリッククラウドのLinux VMも含まれます。パブリッククラウドユーザーは、[ユーザーデータ](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#vpnsetup)を使用してデプロイすることもできます。

クイックデプロイ：

[![Deploy to Linode](docs/images/linode-deploy-button.png)](https://cloud.linode.com/stackscripts/37239) &nbsp;[![Deploy to AWS](docs/images/aws-deploy-button.png)](aws/README.md) &nbsp;[![Deploy to Azure](docs/images/azure-deploy-button.png)](azure/README.md)

[**&raquo; 自分のVPNを運用したいが、そのためのサーバーがない**](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#gettingavps)

外部ファイアウォールを持つサーバー（例：[EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html)/[GCE](https://cloud.google.com/vpc/docs/firewalls)）の場合、VPNのUDPポート500および4500を開きます。

事前構築された[Dockerイメージ](https://github.com/hwdsl2/docker-ipsec-vpn-server)も利用可能です。上級ユーザーは[Raspberry Pi](https://www.raspberrypi.com)にインストールできます。[[1]](https://elasticbyte.net/posts/setting-up-a-native-cisco-ipsec-vpn-server-using-a-raspberry-pi/) [[2]](https://www.stewright.me/2018/07/create-a-raspberry-pi-vpn-server-using-l2tpipsec/)

:warning: これらのスクリプトをPCやMacで実行しないでください！これらはサーバーでのみ使用する必要があります！

## インストール

まず、サーバーを更新します：`sudo apt-get update && sudo apt-get dist-upgrade`（Ubuntu/Debian）または`sudo yum update`を実行し、再起動します。これはオプションですが、推奨されます。

VPNをインストールするには、次のオプションのいずれかを選択してください：

**オプション1:** スクリプトにランダムなVPN資格情報を生成させる（完了時に表示されます）。

```bash
wget https://get.vpnsetup.net -O vpn.sh && sudo sh vpn.sh
```

**オプション2:** スクリプトを編集し、自分のVPN資格情報を提供する。

```bash
wget https://get.vpnsetup.net -O vpn.sh
nano -w vpn.sh
[自分の値に置き換える：YOUR_IPSEC_PSK、YOUR_USERNAME、およびYOUR_PASSWORD]
sudo sh vpn.sh
```

**注:** 安全なIPsec PSKは少なくとも20のランダムな文字で構成されるべきです。

**オプション3:** 環境変数として自分のVPN資格情報を定義する。

```bash
# すべての値は 'シングルクォート' で囲む必要があります
# これらの特殊文字を値に使用しないでください： \ " '
wget https://get.vpnsetup.net -O vpn.sh
sudo VPN_IPSEC_PSK='your_ipsec_pre_shared_key' \
VPN_USER='your_vpn_username' \
VPN_PASSWORD='your_vpn_password' \
sh vpn.sh
```

同じサーバーに[WireGuard](https://github.com/hwdsl2/wireguard-install)および/または[OpenVPN](https://github.com/hwdsl2/openvpn-install)をインストールすることもできます。サーバーがCentOS Stream、Rocky Linux、またはAlmaLinuxを実行している場合、最初にOpenVPN/WireGuardをインストールし、その後IPsec VPNをインストールします。

<details>
<summary>
ダウンロードできない場合はこちらをクリックしてください。
</summary>

`curl`を使用してダウンロードすることもできます。例えば：

```bash
curl -fL https://get.vpnsetup.net -o vpn.sh
sudo sh vpn.sh
```

代替セットアップURL：

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/vpnsetup.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/vpnsetup.sh
```

ダウンロードできない場合は、[vpnsetup.sh](vpnsetup.sh)を開き、右側の`Raw`ボタンをクリックします。`Ctrl/Cmd+A`を押してすべて選択し、`Ctrl/Cmd+C`を押してコピーし、お気に入りのエディタに貼り付けます。
</details>
<details>
<summary>
古いLibreswanバージョン4をインストールしたい。
</summary>

一般的には、最新の[Libreswan](https://libreswan.org/)バージョン5を使用することをお勧めします。これはこのプロジェクトのデフォルトバージョンです。ただし、古いLibreswanバージョン4をインストールしたい場合：

```bash
wget https://get.vpnsetup.net -O vpn.sh
sudo VPN_SWAN_VER=4.15 sh vpn.sh
```

**注:** Libreswanバージョン5がすでにインストールされている場合、最初に[VPNをアンインストール](docs/uninstall.md)してからLibreswanバージョン4をインストールする必要があるかもしれません。あるいは、[アップデートスクリプト](#upgrade-libreswan)をダウンロードし、`SWAN_VER=4.15`を指定して編集し、スクリプトを実行します。
</details>

## VPNオプションのカスタマイズ

### 代替DNSサーバーの使用

デフォルトでは、VPNがアクティブなときにクライアントは[Google Public DNS](https://developers.google.com/speed/public-dns/)を使用するように設定されています。VPNをインストールする際に、すべてのVPNモードに対してカスタムDNSサーバーを指定することができます。例：

```bash
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 sh vpn.sh
```

`VPN_DNS_SRV1`を使用してプライマリDNSサーバーを指定し、`VPN_DNS_SRV2`を使用してセカンダリDNSサーバーを指定します（オプション）。

以下は、参考のためのいくつかの人気のあるパブリックDNSプロバイダーのリストです。

| プロバイダー | プライマリDNS | セカンダリDNS | 注記 |
| -------- | ----------- | ------------- | ----- |
| [Google Public DNS](https://developers.google.com/speed/public-dns) | 8.8.8.8 | 8.8.4.4 | このプロジェクトのデフォルト |
| [Cloudflare](https://1.1.1.1/dns/) | 1.1.1.1 | 1.0.0.1 | 参照：[Cloudflare for families](https://1.1.1.1/family/) |
| [Quad9](https://www.quad9.net) | 9.9.9.9 | 149.112.112.112 | 悪意のあるドメインをブロック |
| [OpenDNS](https://www.opendns.com/home-internet-security/) | 208.67.222.222 | 208.67.220.220 | フィッシングドメインをブロック、設定可能。 |
| [CleanBrowsing](https://cleanbrowsing.org/filters/) | 185.228.168.9 | 185.228.169.9 | [ドメインフィルター](https://cleanbrowsing.org/filters/)利用可能 |
| [NextDNS](https://nextdns.io/?from=bg25bwmp) | さまざま | さまざま | 広告ブロック、無料プラン利用可能。[詳細はこちら](https://nextdns.io/?from=bg25bwmp)。 |
| [Control D](https://controld.com/free-dns) | さまざま | さまざま | 広告ブロック、設定可能。[詳細はこちら](https://controld.com/free-dns)。 |

VPNセットアップ後にDNSサーバーを変更する必要がある場合は、[高度な使用法](docs/advanced-usage.md)を参照してください。

**注:** サーバーにIKEv2がすでに設定されている場合、上記の変数はIKEv2モードには影響しません。その場合、DNSサーバーなどのIKEv2オプションをカスタマイズするには、まず[IKEv2を削除](docs/ikev2-howto.md#remove-ikev2)し、`sudo ikev2.sh`を使用して再設定します。

### IKEv2オプションのカスタマイズ

VPNをインストールする際に、上級ユーザーはオプションでIKEv2オプションをカスタマイズできます。

<details open>
<summary>
オプション1: VPNセットアップ時にIKEv2をスキップし、カスタムオプションを使用してIKEv2を設定します。
</summary>

VPNをインストールする際に、IKEv2をスキップし、IPsec/L2TPおよびIPsec/XAuth（"Cisco IPsec"）モードのみをインストールできます：

```bash
sudo VPN_SKIP_IKEV2=yes sh vpn.sh
```

（オプション）VPNクライアントにカスタムDNSサーバーを指定する場合は、`VPN_DNS_SRV1`およびオプションで`VPN_DNS_SRV2`を定義します。詳細については、[代替DNSサーバーの使用](#use-alternative-dns-servers)を参照してください。

その後、IKEv2ヘルパースクリプトを実行して、カスタムオプションを使用して対話的にIKEv2を設定します：

```bash
sudo ikev2.sh
```

次のオプションをカスタマイズできます：VPNサーバーのDNS名、最初のクライアントの名前と有効期間、VPNクライアントのDNSサーバー、およびクライアント構成ファイルをパスワードで保護するかどうか。

**注:** サーバーにIKEv2がすでに設定されている場合、`VPN_SKIP_IKEV2`変数は影響しません。その場合、IKEv2オプションをカスタマイズするには、まず[IKEv2を削除](docs/ikev2-howto.md#remove-ikev2)し、`sudo ikev2.sh`を使用して再設定します。
</details>
<details>
<summary>
オプション2: 環境変数を使用してIKEv2オプションをカスタマイズします。
</summary>

VPNをインストールする際に、オプションでIKEv2サーバーアドレスのDNS名を指定できます。DNS名は完全修飾ドメイン名（FQDN）である必要があります。例：

```bash
sudo VPN_DNS_NAME='vpn.example.com' sh vpn.sh
```

同様に、最初のIKEv2クライアントの名前を指定できます。指定しない場合、デフォルトは`vpnclient`です。

```bash
sudo VPN_CLIENT_NAME='your_client_name' sh vpn.sh
```

デフォルトでは、VPNがアクティブなときにクライアントは[Google Public DNS](https://developers.google.com/speed/public-dns/)を使用するように設定されています。すべてのVPNモードに対してカスタムDNSサーバーを指定できます。例：

```bash
sudo VPN_DNS_SRV1=1.1.1.1 VPN_DNS_SRV2=1.0.0.1 sh vpn.sh
```

デフォルトでは、IKEv2クライアント構成のインポート時にパスワードは必要ありません。ランダムなパスワードを使用してクライアント構成ファイルを保護することを選択できます。

```bash
sudo VPN_PROTECT_CONFIG=yes sh vpn.sh
```
</details>
<details>
<summary>
参考のために：IKEv1およびIKEv2パラメータのリスト。
</summary>

| IKEv1パラメータ\* | デフォルト値 | カスタマイズ（環境変数）\*\* |
| ------------ | ---- | ----------------- |
| サーバーアドレス（DNS名）| - | いいえ、ただしDNS名を使用して接続できます |
| サーバーアドレス（パブリックIP）| 自動検出 | VPN_PUBLIC_IP |
| IPsec事前共有キー | 自動生成 | VPN_IPSEC_PSK |
| VPNユーザー名 | vpnuser | VPN_USER |
| VPNパスワード | 自動生成 | VPN_PASSWORD |
| クライアントのDNSサーバー | Google Public DNS | VPN_DNS_SRV1、VPN_DNS_SRV2 |
| IKEv2セットアップをスキップ | いいえ | VPN_SKIP_IKEV2=yes |

\* これらのIKEv1パラメータは、IPsec/L2TPおよびIPsec/XAuth（"Cisco IPsec"）モード用です。   
\*\* vpn（setup）.shを実行する際に、これらを環境変数として定義します。

| IKEv2パラメータ\* | デフォルト値 | カスタマイズ（環境変数）\*\* | カスタマイズ（対話型）\*\*\* |
| ----------- | ---- | ------------------ | ----------------- |
| サーバーアドレス（DNS名）| - | VPN_DNS_NAME | ✅ |
| サーバーアドレス（パブリックIP）| 自動検出 | VPN_PUBLIC_IP | ✅ |
| 最初のクライアントの名前 | vpnclient | VPN_CLIENT_NAME | ✅ |
| クライアントのDNSサーバー | Google Public DNS | VPN_DNS_SRV1、VPN_DNS_SRV2 | ✅ |
| クライアント構成ファイルを保護する | いいえ | VPN_PROTECT_CONFIG=yes | ✅ |
| MOBIKEの有効/無効 | サポートされている場合は有効 | ❌ | ✅ |
| クライアント証明書の有効期間 | 10年（120ヶ月）| VPN_CLIENT_VALIDITY\*\*\*\* | ✅ |
| CAおよびサーバー証明書の有効期間 | 10年（120ヶ月）| ❌ | ❌ |
| CA証明書名 | IKEv2 VPN CA | ❌ | ❌ |
| 証明書キーサイズ | 3072ビット | ❌ | ❌ |

\* これらのIKEv2パラメータは、IKEv2モード用です。   
\*\* vpn（setup）.shを実行する際、または自動モードでIKEv2を設定する際に、これらを環境変数として定義します（`sudo ikev2.sh --auto`）。   
\*\*\* 対話型IKEv2セットアップ中にカスタマイズできます（`sudo ikev2.sh`）。上記のオプション1を参照してください。   
\*\*\*\* `VPN_CLIENT_VALIDITY`を使用して、クライアント証明書の有効期間を月単位で指定します。1から120の間の整数である必要があります。

これらのパラメータに加えて、上級ユーザーはVPNセットアップ中に[VPNサブネットをカスタマイズ](docs/advanced-usage.md#customize-vpn-subnets)することもできます。
</details>

## 次のステップ

*他の言語で読む：[English](README.md#next-steps)、[中文](README-zh.md#下一步)、[日本語](README-ja.md#次のステップ)。*

コンピュータやデバイスをVPNに接続します。詳細は以下のリンク（英語）をご覧ください。

**[IKEv2 VPNクライアントの設定（推奨）](docs/ikev2-howto.md)**

**[IPsec/L2TP VPNクライアントの設定](docs/clients.md)**

**[IPsec/XAuth（"Cisco IPsec"）VPNクライアントの設定](docs/clients-xauth.md)**

**:book: [VPN本](docs/vpn-book.md)を読んで[追加コンテンツ](https://ko-fi.com/post/Support-this-project-and-get-access-to-supporter-o-O5O7FVF8J)にアクセスしてください。**

自分のVPNを楽しんでください！ :sparkles::tada::rocket::sparkles:

## 重要な注意事項

**Windowsユーザー**：IPsec/L2TPモードの場合、VPNサーバーまたはクライアントがNAT（例：家庭用ルーター）の背後にある場合、[一度だけレジストリを変更](docs/clients.md#windows-error-809)する必要があります。

同じVPNアカウントを複数のデバイスで使用できます。ただし、IPsec/L2TPの制限により、同じNAT（例：家庭用ルーター）の背後から複数のデバイスを接続する場合は、[IKEv2](docs/ikev2-howto.md)または[IPsec/XAuth](docs/clients-xauth.md)モードを使用する必要があります。VPNユーザーアカウントを表示または更新するには、[VPNユーザーの管理](docs/manage-users.md)を参照してください。

外部ファイアウォールを持つサーバー（例：[EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html)/[GCE](https://cloud.google.com/vpc/docs/firewalls)）の場合、VPNのUDPポート500および4500を開きます。Aliyunユーザーは、[＃433](https://github.com/hwdsl2/setup-ipsec-vpn/issues/433)を参照してください。

クライアントは、VPNがアクティブなときに[Google Public DNS](https://developers.google.com/speed/public-dns/)を使用するように設定されています。別のDNSプロバイダーを好む場合は、[高度な使用法](docs/advanced-usage.md)を参照してください。

カーネルサポートを使用すると、IPsec/L2TPのパフォーマンスが向上する可能性があります。これは[すべてのサポートされているOS](#requirements)で利用可能です。Ubuntuユーザーは`linux-modules-extra-$(uname -r)`パッケージをインストールし、`service xl2tpd restart`を実行する必要があります。

スクリプトは、変更を加える前に既存の構成ファイルをバックアップし、`.old-date-time`サフィックスを付けます。

## Libreswanのアップグレード

このワンライナーを使用して、VPNサーバー上の[Libreswan](https://libreswan.org)（[変更ログ](https://github.com/libreswan/libreswan/blob/main/CHANGES) | [アナウンス](https://lists.libreswan.org)）を更新します。

```bash
wget https://get.vpnsetup.net/upg -O vpnup.sh && sudo sh vpnup.sh
```

<details>
<summary>
ダウンロードできない場合はこちらをクリックしてください。
</summary>

`curl`を使用してダウンロードすることもできます：

```bash
curl -fsSL https://get.vpnsetup.net/upg -o vpnup.sh && sudo sh vpnup.sh
```

代替アップデートURL：

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/extras/vpnupgrade.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/extras/vpnupgrade.sh
```

ダウンロードできない場合は、[vpnupgrade.sh](extras/vpnupgrade.sh)を開き、右側の`Raw`ボタンをクリックします。`Ctrl/Cmd+A`を押してすべて選択し、`Ctrl/Cmd+C`を押してコピーし、お気に入りのエディタに貼り付けます。
</details>

最新のサポートされているLibreswanバージョンは`5.2`です。インストールされているバージョンを確認します：`ipsec --version`。

**注:** `xl2tpd`は、Ubuntu/Debianの`apt-get`などのシステムのパッケージマネージャーを使用して更新できます。

## VPNユーザーの管理

[VPNユーザーの管理](docs/manage-users.md)（英語）を参照してください。

- [ヘルパースクリプトを使用してVPNユーザーを管理する](docs/manage-users.md#manage-vpn-users-using-helper-scripts)
- [VPNユーザーを表示する](docs/manage-users.md#view-vpn-users)
- [IPsec PSKを表示または更新する](docs/manage-users.md#view-or-update-the-ipsec-psk)
- [VPNユーザーを手動で管理する](docs/manage-users.md#manually-manage-vpn-users)

## 高度な使用法

[高度な使用法](docs/advanced-usage.md)（英語）を参照してください。

- [代替DNSサーバーの使用](docs/advanced-usage.md#use-alternative-dns-servers)
- [DNS名とサーバーIPの変更](docs/advanced-usage.md#dns-name-and-server-ip-changes)
- [IKEv2専用VPN](docs/advanced-usage.md#ikev2-only-vpn)
- [内部VPN IPとトラフィック](docs/advanced-usage.md#internal-vpn-ips-and-traffic)
- [VPNサーバーのパブリックIPを指定する](docs/advanced-usage.md#specify-vpn-servers-public-ip)
- [VPNサブネットのカスタマイズ](docs/advanced-usage.md#customize-vpn-subnets)
- [VPNクライアントへのポートフォワーディング](docs/advanced-usage.md#port-forwarding-to-vpn-clients)
- [スプリットトンネリング](docs/advanced-usage.md#split-tunneling)
- [VPNサーバーのサブネットにアクセスする](docs/advanced-usage.md#access-vpn-servers-subnet)
- [サーバーのサブネットからVPNクライアントにアクセスする](docs/advanced-usage.md#access-vpn-clients-from-servers-subnet)
- [IPTablesルールの変更](docs/advanced-usage.md#modify-iptables-rules)
- [Google BBR輻輳制御の展開](docs/advanced-usage.md#deploy-google-bbr-congestion-control)

## VPNのアンインストール

IPsec VPNをアンインストールするには、[ヘルパースクリプト](extras/vpnuninstall.sh)を実行します：

**警告:** このヘルパースクリプトは、サーバーからIPsec VPNを削除します。すべてのVPN構成は**永久に削除**され、Libreswanおよびxl2tpdは削除されます。これは**元に戻すことはできません**！

```bash
wget https://get.vpnsetup.net/unst -O unst.sh && sudo bash unst.sh
```

<details>
<summary>
ダウンロードできない場合はこちらをクリックしてください。
</summary>

`curl`を使用してダウンロードすることもできます：

```bash
curl -fsSL https://get.vpnsetup.net/unst -o unst.sh && sudo bash unst.sh
```

代替スクリプトURL：

```bash
https://github.com/hwdsl2/setup-ipsec-vpn/raw/master/extras/vpnuninstall.sh
https://gitlab.com/hwdsl2/setup-ipsec-vpn/-/raw/master/extras/vpnuninstall.sh
```
</details>

詳細については、[VPNのアンインストール](docs/uninstall.md)を参照してください。

## フィードバックと質問

- このプロジェクトに提案がありますか？[改善リクエスト](https://github.com/hwdsl2/setup-ipsec-vpn/issues/new/choose)を開いてください。[プルリクエスト](https://github.com/hwdsl2/setup-ipsec-vpn/pulls)も歓迎します。
- 再現可能なバグを見つけた場合、[IPsec VPN](https://github.com/libreswan/libreswan/issues?q=is%3Aissue)または[VPNスクリプト](https://github.com/hwdsl2/setup-ipsec-vpn/issues/new/choose)のバグレポートを開いてください。
- 質問がありますか？まず、[既存の問題](https://github.com/hwdsl2/setup-ipsec-vpn/issues?q=is%3Aissue)と、この[Gist](https://gist.github.com/hwdsl2/9030462#comments)および[私のブログ](https://blog.ls20.com/ipsec-l2tp-vpn-auto-setup-for-ubuntu-12-04-on-amazon-ec2/#disqus_thread)のコメントを検索してください。
- VPNに関連する質問は、[Libreswan](https://lists.libreswan.org)または[strongSwan](https://lists.strongswan.org)のメーリングリストで質問するか、次のウィキを参照してください：[[1]](https://libreswan.org/wiki/Main_Page) [[2]](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/sec-securing_virtual_private_networks) [[3]](https://wiki.strongswan.org/projects/strongswan/wiki/UserDocumentation) [[4]](https://wiki.gentoo.org/wiki/IPsec_L2TP_VPN_server) [[5]](https://wiki.archlinux.org/index.php/Openswan_L2TP/IPsec_VPN_client_setup)。

## ライセンス

著作権 (C) 2014-2025 [Lin Song](https://github.com/hwdsl2) [![View my profile on LinkedIn](https://static.licdn.com/scds/common/u/img/webpromo/btn_viewmy_160x25.png)](https://www.linkedin.com/in/linsongui)   
[Thomas Sarlandieの作品](https://github.com/sarfata/voodooprivacy)に基づく（著作権2012）

[![Creative Commons License](https://i.creativecommons.org/l/by-sa/3.0/88x31.png)](http://creativecommons.org/licenses/by-sa/3.0/)   
この作品は[クリエイティブ・コモンズ表示-継承3.0非移植ライセンス](http://creativecommons.org/licenses/by-sa/3.0/)の下でライセンスされています。  
帰属が必要です：私の名前を派生物に含め、改善方法を教えてください！
