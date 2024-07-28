[English](bbr.md) | [中文](bbr-zh.md)

# 高级用法：部署 Google BBR 拥塞控制算法

Google BBR是一种拥塞控制算法，它能够显著提升服务器吞吐率并降低延迟。

Google BBR已经被内置于Linux内核4.9及更高版本中，但是需要手动开启。

关于Google BBR算法，可以在这篇[官方博客](https://cloud.google.com/blog/products/networking/tcp-bbr-congestion-control-comes-to-gcp-your-internet-just-got-faster)或者这个[官方库](https://github.com/google/bbr)中找到更多信息。

## 准备

可以通过命令 `uname -r` 来查看当前Linux内核版本。版本大于等于4.9时，可以直接参照[下方的说明](#部署-google-bbr)部署BBR。

通常而言，Ubuntu 18.04+, Debian 10+，CentOS 8+及RHEL 8+的内核版本都大于4.9。但是对于Amazon Linux 2，需要通过以下的方式更新内核之后才能部署Google BBR。

### Amazon Linux 2

Amazon Linux 2提供过经过验证的新版Linux内核，并可以通过启用预置的Extras库安装。

1. 从Extras库安装 `kernel-ng`
   ```bash
   sudo amazon-linux-extras install kernel-ng
   ```
2. 更新包
   ```bash
   sudo yum update
   ```
3. 重启系统
   ```bash
   sudo reboot
   ```
4. 检查Linux内核版本
   ```bash
   uname -r
   ```

## 部署 Google BBR

在这个部分，我们将通过修改配置文件启动Google BBR。

1. 备份 `/etc/sysctl.conf`
   ```bash
   sudo cp /etc/sysctl.conf /etc/sysctl.conf.backup
   ```
2. 修改 `/etc/sysctl.conf`
   ```bash
   sudo vim /etc/sysctl.conf
   ```
   在文件中增加以下行
   ```
   net.core.default_qdisc = fq
   net.ipv4.tcp_congestion_control = bbr
   ```
3. 启用Google BBR   
   首先使用 `uname -r` 检查你的服务器的内核版本。   
   对于内核版本 >= 4.20，应用 `sysctl` 设置：
   ```bash
   sudo sysctl -p
   ```
   对于内核版本 < 4.20，你必须重启服务器：
   ```bash
   sudo reboot
   ```
4. 检查Google BBR状态
   ```bash
   sudo sysctl net.ipv4.tcp_available_congestion_control
   # net.ipv4.tcp_available_congestion_control = reno cubic bbr
   sudo sysctl -n net.ipv4.tcp_congestion_control
   # bbr
   lsmod | grep bbr
   # tcp_bbr  16384  0
   ```

## 文档作者

版权所有 (C) 2022 [Leo Liu](https://github.com/optimusleobear)
