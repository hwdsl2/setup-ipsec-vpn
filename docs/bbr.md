[English](bbr.md) | [中文](bbr-zh.md)

# Advanced usage: Deploy Google BBR congestion control algorithm

Google BBR is a congestion control algorithm that could significantly increase server throughput and reduce latency.

Google BBR has been built into Linux kernel 4.9 and higher, but needs to be manually turned on.

To learn more about the Google BBR algorithm, see this [official blog](https://cloud.google.com/blog/products/networking/tcp-bbr-congestion-control-comes-to-gcp-your-internet-just-got-faster) or this [official repository](https://github.com/google/bbr).

## Prepare

You can check the current Linux kernel version with the command `uname -r`. When the version is greater than or equal to 4.9, you can deploy BBR directly by referring to the [instructions below](#deploy-google-bbr).

Generally speaking, the kernel versions of Ubuntu 18.04+, Debian 10+, CentOS 8+ and RHEL 8+ are greater than 4.9. But for CentOS 7 or Amazon Linux 2, you need to update the kernel in the following ways before deploying Google BBR.

### Amazon Linux 2

Amazon Linux 2 provides newer versions of the verified Linux kernel, which can be installed from the Extras repository.

1. Install `kernel-ng` from the Extras repository
   ```bash
   sudo amazon-linux-extras install kernel-ng
   ```
2. Update packages
   ```bash
   sudo yum update
   ```
3. Restart the system
   ```bash
   sudo reboot
   ```
4. Check the Linux kernel version
   ```bash
   uname -r
   ```

### CentOS 7

When using CentOS 7, a newer Linux kernel provided by the ELRepo Project needs to be installed. More information about the Linux kernels provided by the ELRepo Project can be found at [this page](http://elrepo.org/tiki/kernel-ml).

Refer to the installation instructions below.

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

## Deploy Google BBR

In this section, we will start Google BBR by modifying the configuration file.

1. Backup `/etc/sysctl.conf`
   ```bash
   sudo cp /etc/sysctl.conf /etc/sysctl.conf.backup
   ```
2. Modify `/etc/sysctl.conf`
   ```bash
   sudo vim /etc/sysctl.conf
   ```
   Add the following lines to the file
   ```
   net.core.default_qdisc = fq
   net.ipv4.tcp_congestion_control = bbr
   ```
3. Enable Google BBR   
   First, check your server's kernel version using `uname -r`.   
   For kernel versions >= 4.20, apply `sysctl` settings:
   ```bash
   sudo sysctl -p
   ```
   For kernel versions < 4.20, you must reboot the server:
   ```bash
   sudo reboot
   ```
4. Check Google BBR status
   ```bash
   sudo sysctl net.ipv4.tcp_available_congestion_control
   # net.ipv4.tcp_available_congestion_control = reno cubic bbr
   sudo sysctl -n net.ipv4.tcp_congestion_control
   # bbr
   lsmod | grep bbr
   # tcp_bbr  16384  0
   ```

## Document author

Copyright (C) 2022 [Leo Liu](https://github.com/optimusleobear)   
Translated by [Lin Song](https://github.com/hwdsl2)
