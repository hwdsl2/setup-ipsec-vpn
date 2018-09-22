# 如何配置 IKEv2 VPN: Windows 7 和更新版本

*其他语言版本: [English](ikev2-howto.md), [简体中文](ikev2-howto-zh.md).*

---

**重要提示：** 本指南仅适用于**高级用户**。其他用户请使用 <a href="clients-zh.md" target="_blank">IPsec/L2TP</a> 或者 <a href="clients-xauth-zh.md" target="_blank">IPsec/XAuth</a>。

---

Windows 7 和更新版本支持 IKEv2 协议标准，通过 Microsoft 的 Agile VPN 功能来实现。因特网密钥交换 （英语：Internet Key Exchange，简称 IKE 或 IKEv2）是一种网络协议，归属于 IPsec 协议族之下，用以创建安全关联 (Security Association, SA)。与 IKE 版本 1 相比较，IKEv2 的<a href="https://en.wikipedia.org/wiki/Internet_Key_Exchange#Improvements_with_IKEv2" target="_blank">功能改进</a>包括比如通过 MOBIKE 实现 Standard Mobility 支持，以及更高的可靠性。另外，IKEv2 支持同时连接在同一个 NAT（比如家用路由器）后面的多个设备到 VPN 服务器。

Libreswan 支持通过使用 RSA 签名算法的 X.509 Machine Certificates 来对 IKEv2 客户端进行身份验证。该方法无需 IPsec PSK, 用户名或密码。下面举例说明如何在 Libreswan 上配置 IKEv2。以下命令必须用 `root` 账户运行。

在继续之前，请确保你已经成功 <a href="https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/README-zh.md" target="_blank">搭建自己的 VPN 服务器</a>。

1. 获取 VPN 服务器的公共 IP 地址，将它保存到变量并检查。

   ```bash
   $ PUBLIC_IP=$(wget -t 3 -T 15 -qO- http://ipv4.icanhazip.com)
   $ echo "$PUBLIC_IP"
   （检查显示的公共 IP）
   ```

   **注：** 另外，在这里你也可以指定 VPN 服务器的域名。例如： `PUBLIC_IP=myvpn.example.com`。

1. 在 `/etc/ipsec.conf` 文件中添加一个新的 IKEv2 连接:

   ```bash
   $ cat >> /etc/ipsec.conf <<EOF

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
     fragmentation=yes
     ike=3des-sha1,3des-sha2,aes-sha1,aes-sha1;modp1024,aes-sha2,aes-sha2;modp1024
     phase2alg=3des-sha1,3des-sha2,aes-sha1,aes-sha2
   EOF
   ```

   还需要在该文件中添加一些行。首先查看你的 Libreswan 版本，然后运行以下命令之一：

   ```bash
   $ ipsec --version
   ```

   如果是 Libreswan 3.23 或更新版本：

   ```bash
   $ cat >> /etc/ipsec.conf <<EOF
     modecfgdns="8.8.8.8, 8.8.4.4"
     encapsulation=yes
   EOF
   ```

   如果是 Libreswan 3.19-3.22：

   ```bash
   $ cat >> /etc/ipsec.conf <<EOF
     modecfgdns1=8.8.8.8
     modecfgdns2=8.8.4.4
     encapsulation=yes
   EOF
   ```

   如果是 Libreswan 3.18 或更早版本：

   ```bash
   $ cat >> /etc/ipsec.conf <<EOF
     modecfgdns1=8.8.8.8
     modecfgdns2=8.8.4.4
     forceencaps=yes
   EOF
   ```

1. 生成 Certificate Authority (CA) 和 VPN 服务器证书：

   **注：** 使用 "-v" 参数指定证书的有效期（单位：月），例如 "-v 36"。另外，如果你在上面的第一步使用了服务器的域名而不是 IP 地址，则需要将以下命令中的 `--extSAN "ip:$PUBLIC_IP,dns:$PUBLIC_IP"` 换成 `--extSAN "dns:$PUBLIC_IP"`。

   ```bash
   $ certutil -z <(head -c 1024 /dev/urandom) \
     -S -x -n "Example CA" \
     -s "O=Example,CN=Example CA" \
     -k rsa -g 4096 -v 36 \
     -d sql:/etc/ipsec.d -t "CT,," -2

     Generating key.  This may take a few moments...

     Is this a CA certificate [y/N]?
     y
     Enter the path length constraint, enter to skip [<0 for unlimited path]: >
     Is this a critical extension [y/N]?
     N
   ```

   ```bash
   $ certutil -z <(head -c 1024 /dev/urandom) \
     -S -c "Example CA" -n "$PUBLIC_IP" \
     -s "O=Example,CN=$PUBLIC_IP" \
     -k rsa -g 4096 -v 36 \
     -d sql:/etc/ipsec.d -t ",," \
     --keyUsage digitalSignature,keyEncipherment \
     --extKeyUsage serverAuth \
     --extSAN "ip:$PUBLIC_IP,dns:$PUBLIC_IP"

     Generating key.  This may take a few moments...
   ```

1. 生成客户端证书，并且导出 `.p12` 文件。该文件包含客户端证书，私钥以及 CA 证书：

   ```bash
   $ certutil -z <(head -c 1024 /dev/urandom) \
     -S -c "Example CA" -n "vpnclient" \
     -s "O=Example,CN=vpnclient" \
     -k rsa -g 4096 -v 36 \
     -d sql:/etc/ipsec.d -t ",," \
     --keyUsage digitalSignature,keyEncipherment \
     --extKeyUsage serverAuth,clientAuth -8 "vpnclient"

     Generating key.  This may take a few moments...
   ```

   ```bash
   $ pk12util -o vpnclient.p12 -n "vpnclient" -d sql:/etc/ipsec.d

     Enter password for PKCS12 file:
     Re-enter password:
     pk12util: PKCS12 EXPORT SUCCESSFUL
   ```

   你可以重复本步骤来为更多的客户端生成证书。将所有的 `vpnclient` 换成 `vpnclient2`，等等。

   **注：** 如需同时连接多个客户端，则必须为每个客户端生成唯一的证书。

1. 证书数据库现在应该包含以下内容：

   ```bash
   $ certutil -L -d sql:/etc/ipsec.d

     Certificate Nickname                               Trust Attributes
                                                        SSL,S/MIME,JAR/XPI

     Example CA                                         CTu,u,u
     ($PUBLIC_IP)                                       u,u,u
     vpnclient                                          u,u,u
   ```

   **注：** 如需显示证书内容，可使用 `certutil -L -d sql:/etc/ipsec.d -n "Nickname"`。要删除一个证书，将 `-L` 换成 `-D`。更多的 `certutil` 使用说明请看 <a href="http://manpages.ubuntu.com/manpages/xenial/en/man1/certutil.1.html" target="_blank">这里</a>。

1. 重启 IPsec 服务：

   ```bash
   $ service ipsec restart
   ```

1. 将文件 `vpnclient.p12` 安全地传送到 VPN 客户端设备。下一步：

   #### Windows 7, 8.x 和 10

   1. 将 `.p12` 文件导入到 "计算机账户" 证书存储。在导入证书后，你必须确保将客户端证书放在 "个人 -> 证书" 目录中，并且将 CA 证书放在 "受信任的根证书颁发机构 -> 证书" 目录中。

      详细的操作步骤：   
      https://wiki.strongswan.org/projects/strongswan/wiki/Win7Certs

   1. 在 Windows 计算机上添加一个新的 IKEv2 VPN 连接：   
      https://wiki.strongswan.org/projects/strongswan/wiki/Win7Config

   1. 启用新的 VPN 连接，并且开始使用 IKEv2 VPN！   
      https://wiki.strongswan.org/projects/strongswan/wiki/Win7Connect

   1. （可选步骤） 如需启用更安全的加密方式，你可以添加 <a href="https://wiki.strongswan.org/projects/strongswan/wiki/WindowsClients#AES-256-CBC-and-MODP2048" target="_blank">这个注册表键</a> 并重启。

1. 连接成功后，你可以到 <a href="https://www.ipchicken.com" target="_blank">这里</a> 检测你的 IP 地址，应该显示为`你的 VPN 服务器 IP`。

## 已知问题

Windows 自带的 VPN 客户端不支持 IKEv2 fragmentation。在有些网络上，这可能会导致连接错误或其它连接问题。你可以尝试 <a href="clients-zh.md#故障排除" target="_blank">修改注册表</a>，或者换用 <a href="clients-zh.md" target="_blank">IPsec/L2TP</a> 或 <a href="clients-xauth-zh.md" target="_blank">IPsec/XAuth</a> 模式连接。

## 参考链接

* https://libreswan.org/wiki/VPN_server_for_remote_clients_using_IKEv2
* https://libreswan.org/wiki/HOWTO:_Using_NSS_with_libreswan
* https://libreswan.org/man/ipsec.conf.5.html
* https://wiki.strongswan.org/projects/strongswan/wiki/WindowsClients
