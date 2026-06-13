---
name: Bug report
about: Tell us about a problem you are experiencing
title: ''
labels: ''
assignees: ''

---

**Checklist**

- [ ] I read the [README](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/README.md)
- [ ] I read the [Important notes](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/README.md#important-notes)
- [ ] I followed instructions to [configure VPN clients](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/README.md#next-steps)
- [ ] I checked [IKEv1 troubleshooting](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/docs/clients.md#ikev1-troubleshooting), [IKEv2 troubleshooting](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/docs/ikev2-howto.md#ikev2-troubleshooting) and [VPN status](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/docs/clients.md#check-logs-and-vpn-status)
- [ ] I searched existing [Issues](https://github.com/hwdsl2/setup-ipsec-vpn/issues?q=is%3Aissue)
- [ ] This bug is about the VPN setup scripts, and not IPsec VPN itself

<!---
If you found a reproducible bug in IPsec VPN itself, open a bug report at https://github.com/libreswan/libreswan. Ask VPN-related questions on the [Libreswan](https://lists.libreswan.org) or [strongSwan](https://lists.strongswan.org) users mailing list, or search e.g. [Stack Overflow](https://stackoverflow.com/questions/tagged/vpn).

Before posting logs or configuration, remove VPN credentials, private keys, IPsec PSKs, passwords and other secrets.
--->

**Describe the issue**
A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:

1. ...
2. ...

**Expected behavior**
A clear and concise description of what you expected to happen.

**Logs**
[Check logs and VPN status](https://github.com/hwdsl2/setup-ipsec-vpn/blob/master/docs/clients.md#check-logs-and-vpn-status), and add relevant error logs to help explain the problem, if applicable.

Useful commands include:

```bash
ipsec status
ipsec trafficstatus
```

For connection issues, also include the relevant `pluto` and `xl2tpd` log lines from your server OS, with secrets removed.

**Server (please complete the following information)**
- OS and version: [e.g. Debian 13]
- Architecture: [e.g. x86_64, arm64]
- Hosting provider (if applicable): [e.g. GCP, AWS]
- External firewall/NAT: [e.g. UDP 500/4500 open, behind NAT, not applicable]
- Install method or command used

**Client (please complete the following information)**
- Device: [e.g. iPhone 15]
- OS and version: [e.g. iOS 18]
- VPN client app and version (if applicable): [e.g. strongSwan VPN Client 2.x]
- VPN mode: [IPsec/L2TP, IPsec/XAuth ("Cisco IPsec") or IKEv2]

**Additional context**
Add any other context about the problem here.
