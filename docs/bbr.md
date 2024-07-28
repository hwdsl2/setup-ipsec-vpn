[English](bbr.md) | [中文](bbr-zh.md)

# Advanced usage: Deploy Google BBR congestion control algorithm

Google BBR is a congestion control algorithm that could significantly increase server throughput and reduce latency.

Google BBR has been built into Linux kernel 4.9 and higher, but needs to be manually turned on.

To learn more about the Google BBR algorithm, see this [official blog](https://cloud.google.com/blog/products/networking/tcp-bbr-congestion-control-comes-to-gcp-your-internet-just-got-faster) or this [official repository](https://github.com/google/bbr).

## Prepare

You can check the current Linux kernel version with the command `uname -r`. When the version is greater than or equal to 4.9, you can deploy BBR directly by referring to the [instructions below](#deploy-google-bbr).

Generally speaking, the kernel versions of Ubuntu 18.04+, Debian 10+, CentOS 8+ and RHEL 8+ are greater than 4.9. But for Amazon Linux 2, you need to update the kernel in the following ways before deploying Google BBR.

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
