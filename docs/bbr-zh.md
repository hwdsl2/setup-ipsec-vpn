# Google BBR

Google BBR是一种由Google开发的拥塞控制算法，它能够显著提升服务器吞吐率并降低延迟。

Google BBR已经被内置于Linux Kernel 4.9及更高版本中，但是需要手动开启。

关于Google BBR算法，可以在这篇[官方博客](https://cloud.google.com/blog/products/networking/tcp-bbr-congestion-control-comes-to-gcp-your-internet-just-got-faster)或者这个[官方库](https://github.com/google/bbr)中找到更多信息。

## 准备

可以通过命令 `uname -r` 来查看当前Linux Kernel版本。版本大于等于4.9时，可以直接参照[下方的说明](#部署google-bbr)部署BBR。

通常而言，Ubuntu 18.04+, Debian 10+，CentOS 8+及RHEL 8+的内核版本都大于4.9。但是对于CentOS 7或者Amazon Linux 2，需要通过以下的方式更新内核之后才能部署Google BBR。

### Amazon Linux 2

Amazon Linux 2提供过经过验证的新版Linux Kernel，并可以通过启用预置的Extras库安装。

1. 启用 `kernel-ng` Extras 库
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
4. 检查Linux Kernel版本
   ```bash
   uname -r
   ```

### CentOS 7

当使用CentOS 7时，需要安装由ELRepo Project提供的新版Linux Kernel。可以在[这个页面](http://elrepo.org/tiki/kernel-ml)找到有关ELRepo Project提供的Linux Kernel的更多信息。

以下的安装说明，因为缺少可供参考的中文文档，暂仅提供英文版。

1. Import ELRepo Project's public key.
   ```bash
   sudo rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
   ```
2. Install ELRepo for RHEL-7, SL-7 or CentOS-7.
   ```bash
   sudo yum install https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm
   ```
3. Install `kernel-ml`.
   ```bash
   sudo yum --enablerepo=elrepo-kernel install kernel-ml
   ```
4. Confirm the result.
   ```bash
   rpm -qa | grep kernel
   ```
   You should see `kernel-ml-xxx` in output.
5. Show all entries in the grub2 menu and setup `kernel-ml`.
   ```bash
   sudo egrep ^menuentry /etc/grub2.cfg | cut -f 2 -d \'
   ```
   **Indexing starts at `0`.** 
   For example, when the `kernel-ml` is located at `1`, use the command below to activate `kernel-ml`.
   ```bash
   sudo grub2-set-default 1
   ```
6. Reboot.
   ```bash
   sudo reboot
   ```
7. Check Linux kernel version.
   ```bash
   uname -r
   ```

## 部署Google BBR

在这个部分，我们将通过修改配置文件启动Google BBR。

1. 备份 `/etc/sysctl.conf`
   ```bash
   sudo cp /etc/sysctl.conf /etc/sysctl.conf.backup
   ```
2. 修改`/etc/sysctl.conf`
   ```bash
   sudo vim /etc/sysctl.conf
   ```
   在文件中增加以下行
   ```
   net.core.default_qdisc = fq
   net.ipv4.tcp_congestion_control = bbr
   ```
3. 启用Google BBR
   ```bash
   sudo sysctl -p
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