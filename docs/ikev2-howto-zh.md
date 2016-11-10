# 如何配置 IKEv2 VPN: Windows 7 和更新版本

*其他语言版本: [English](ikev2-howto.md), [简体中文](ikev2-howto-zh.md).*

---

**重要提示：** 本指南仅适用于**高级用户**。其他用户请使用 <a href="clients-zh.md" target="_blank">IPsec/L2TP</a> 或者 <a href="clients-xauth-zh.md" target="_blank">IPsec/XAuth</a>。

---

Windows 7 和更新版本支持 IKEv2 协议标准，通过 Microsoft 的 Agile VPN 功能来实现。因特网密钥交换 （英语：Internet Key Exchange，简称 IKE 或 IKEv2）是一种网络协议，归属于 IPsec 协议族之下，用以创建安全关联 (Security Association, SA)。与 IKE 版本 1 相比较，IKEv2 带来许多<a href="https://en.wikipedia.org/wiki/Internet_Key_Exchange#Improvements_with_IKEv2" target="_blank">功能改进</a>，比如通过 MOBIKE 实现 Standard Mobility 支持，以及更高的可靠性。

Libreswan 支持通过使用 RSA 签名算法的 X.509 Machine Certificates 来对 IKEv2 客户端进行身份验证。该方法无需 IPsec PSK, 用户名或密码。它可以用于以下系统：

- Windows 7, 8.x 和 10
- Windows Phone 8.1 及以上
- strongSwan Android VPN 客户端
- <a href="https://github.com/gaomd/docker-ikev2-vpn-server">iOS (iPhone/iPad) 和 OS X (macOS)</a> <-- 请参见

下面举例说明如何在 Libreswan 上配置 IKEv2。以下命令必须用 `root` 账户运行。

在继续之前，请确保你已经成功地 <a href="https://github.com/hwdsl2/setup-ipsec-vpn" target="_blank">搭建自己的 VPN 服务器</a>。

1. 获取服务器的公共和私有 IP 地址，并确保它们的值非空。注意，这两个 IP 地址可以相同。

   ```bash
   $ PUBLIC_IP=$(wget -t 3 -T 15 -qO- http://ipv4.icanhazip.com)
   $ PRIVATE_IP=$(ip -4 route get 1 | awk '{print $NF;exit}')
   $ echo "$PUBLIC_IP"
   (Your public IP is displayed)
   $ echo "$PRIVATE_IP"
   (Your private IP is displayed)
   ```

1. 在 `/etc/ipsec.conf` 文件中添加一个新的 IKEv2 连接:

   ```bash
   $ cat >> /etc/ipsec.conf <<EOF

   conn ikev2-cp
     left=$PRIVATE_IP
     leftcert=$PUBLIC_IP
     leftid=@$PUBLIC_IP
     leftsendcert=always
     leftsubnet=0.0.0.0/0
     leftrsasigkey=%cert
     right=%any
     rightaddresspool=192.168.43.10-192.168.43.250
     rightca=%same
     rightrsasigkey=%cert
     modecfgdns1=8.8.8.8
     modecfgdns2=8.8.4.4
     narrowing=yes
     dpddelay=30
     dpdtimeout=120
     dpdaction=clear
     auto=add
     ikev2=insist
     rekey=no
     fragmentation=yes
     forceencaps=yes
     ike=3des-sha1,aes-sha1,aes256-sha2_512,aes256-sha2_256
     phase2alg=3des-sha1,aes-sha1,aes256-sha2_512,aes256-sha2_256
   EOF
   ```

1. 生成 Certificate Authority (CA) 和 VPN 服务器证书：   
   注： 使用 "-v" 参数指定证书的有效期（单位：月），例如 "-v 36"。

   ```bash
   $ certutil -S -x -n "Example CA" -s "O=Example,CN=Example CA" -k rsa -g 4096 -v 36 -d sql:/etc/ipsec.d -t "CT,," -2

   A random seed must be generated that will be used in the
   creation of your key.  One of the easiest ways to create a
   random seed is to use the timing of keystrokes on a keyboard.

   To begin, type keys on the keyboard until this progress meter
   is full.  DO NOT USE THE AUTOREPEAT FUNCTION ON YOUR KEYBOARD!

   Continue typing until the progress meter is full:

   |************************************************************|

   Finished.  Press enter to continue:

   Generating key.  This may take a few moments...

   Is this a CA certificate [y/N]?
   y
   Enter the path length constraint, enter to skip [<0 for unlimited path]: >
   Is this a critical extension [y/N]?
   N

   $ certutil -S -c "Example CA" -n "$PUBLIC_IP" -s "O=Example,CN=$PUBLIC_IP" -k rsa -g 4096 -v 36 -d sql:/etc/ipsec.d -t ",," -1 -6 -8 "$PUBLIC_IP"

   A random seed must be generated that will be used in the
   creation of your key.  One of the easiest ways to create a
   random seed is to use the timing of keystrokes on a keyboard.

   To begin, type keys on the keyboard until this progress meter
   is full.  DO NOT USE THE AUTOREPEAT FUNCTION ON YOUR KEYBOARD!

   Continue typing until the progress meter is full:

   |************************************************************|

   Finished.  Press enter to continue:

   Generating key.  This may take a few moments...

                   0 - Digital Signature
                   1 - Non-repudiation
                   2 - Key encipherment
                   3 - Data encipherment
                   4 - Key agreement
                   5 - Cert signing key
                   6 - CRL signing key
                   Other to finish
    > 0
                   0 - Digital Signature
                   1 - Non-repudiation
                   2 - Key encipherment
                   3 - Data encipherment
                   4 - Key agreement
                   5 - Cert signing key
                   6 - CRL signing key
                   Other to finish
    > 2
                   0 - Digital Signature
                   1 - Non-repudiation
                   2 - Key encipherment
                   3 - Data encipherment
                   4 - Key agreement
                   5 - Cert signing key
                   6 - CRL signing key
                   Other to finish
    > 8
   Is this a critical extension [y/N]?
   N
                   0 - Server Auth
                   1 - Client Auth
                   2 - Code Signing
                   3 - Email Protection
                   4 - Timestamp
                   5 - OCSP Responder
                   6 - Step-up
                   7 - Microsoft Trust List Signing
                   Other to finish
    > 0
                   0 - Server Auth
                   1 - Client Auth
                   2 - Code Signing
                   3 - Email Protection
                   4 - Timestamp
                   5 - OCSP Responder
                   6 - Step-up
                   7 - Microsoft Trust List Signing
                   Other to finish
    > 8
   Is this a critical extension [y/N]?
   N
   ```

1. 生成客户端证书，并且导出 `.p12` 文件。该文件包含客户端证书，私钥以及 CA 证书：

   ```bash
   $ certutil -S -c "Example CA" -n "vpnclient" -s "O=Example,CN=vpnclient" -k rsa -g 4096 -v 36 -d sql:/etc/ipsec.d -t ",," -1 -6 -8 "vpnclient"

   -- repeat same extensions as above --

   $ pk12util -o vpnclient.p12 -n "vpnclient" -d sql:/etc/ipsec.d

   Enter password for PKCS12 file:
   Re-enter password:
   pk12util: PKCS12 EXPORT SUCCESSFUL
   ```

   可以重复该步骤来为更多的客户端生成证书，但必须把所有的 `vpnclient` 换成 `vpnclient2`，等等。

1. 证书数据库现在应该包含以下内容：

   ```bash
   $ certutil -L -d sql:/etc/ipsec.d

   Certificate Nickname                               Trust Attributes
                                                      SSL,S/MIME,JAR/XPI

   Example CA                                         CTu,u,u
   ($PUBLIC_IP)                                       u,u,u
   vpnclient                                          u,u,u
   ```

   注：如需删除证书，可运行命令 `certutil -D -d sql:/etc/ipsec.d -n "Certificate Nickname"`。

1. 重启 IPsec 服务：

   ```bash
   $ service ipsec restart
   ```

1. 文件 `vpnclient.p12` 应该被安全地传送到 VPN 客户端设备。下一步：

   #### Windows 7, 8.x 和 10

   将 `.p12` 文件导入到 Computer 证书存储。在导入 CA 证书后，它必须被放入 "Trusted Root Certification Authorities" 目录的 "Certificates" 子目录中。

   详细的操作步骤：  
   https://wiki.strongswan.org/projects/strongswan/wiki/Win7Certs

   在 Windows 计算机上添加一个新的 IKEv2 VPN 连接：

   https://wiki.strongswan.org/projects/strongswan/wiki/Win7Config

   启用新的 IKEv2 VPN 连接，并且开始使用自己的专属 VPN！

   https://wiki.strongswan.org/projects/strongswan/wiki/Win7Connect

   #### Windows Phone 8.1 及以上

   首先导入 `.p12` 文件，然后参照 <a href="https://technet.microsoft.com/en-us/windows/dn673608.aspx" target="_blank">这些说明</a> 配置一个基于证书的 IKEv2 VPN。

   #### Android 4.x 和更新版本

   请参见： https://wiki.strongswan.org/projects/strongswan/wiki/AndroidVpnClient

   连接成功后，你可以到 <a href="https://www.ipchicken.com" target="_blank">这里</a> 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

## 已知问题

Windows 7 和更新版本自带的 VPN 客户端不支持 IKEv2 fragmentation。在有些网络上，这可能会导致连接错误 "Error 809"，或者可能在连接后无法打开任何网站。如果出现这些问题，请首先尝试 <a href="clients-zh.md#故障排除" target="_blank">这个解决方案</a>。如果仍然无法解决，请使用 <a href="clients-zh.md" target="_blank">IPsec/L2TP</a> 或者 <a href="clients-xauth-zh.md" target="_blank">IPsec/XAuth</a> 模式连接。

## 参考链接

* https://libreswan.org/wiki/VPN_server_for_remote_clients_using_IKEv2
* https://libreswan.org/wiki/HOWTO:_Using_NSS_with_libreswan
* https://libreswan.org/man/ipsec.conf.5.html
* https://wiki.strongswan.org/projects/strongswan/wiki/Windows7
