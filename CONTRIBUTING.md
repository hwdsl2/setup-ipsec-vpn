# Contributing

Thanks for helping improve this project. This repository maintains the bare-metal IPsec VPN setup scripts; Docker image changes belong in [docker-ipsec-vpn-server](https://github.com/hwdsl2/docker-ipsec-vpn-server).

## Before You Start

- Search existing issues and pull requests.
- Keep changes focused and easy to review.
- For upstream Libreswan or xl2tpd behavior, check the upstream project first.
- Do not include IPsec PSKs, passwords, private keys, client profiles, certificates, or logs with secrets.

## Pull Requests

- Update `README.md` or docs when install behavior, options, service names, paths, or defaults change.
- Include the tested Linux distribution, version, architecture, hosting environment, and VPN mode.
- Note whether install, manage-users, IKEv2 helper, or uninstall paths were tested.

## Testing

Test the smallest relevant path before opening a PR, for example:

- Run ShellCheck when editing shell scripts.
- Test install or helper-script paths touched by the change.
- Check `ipsec status`, `ipsec trafficstatus`, and relevant `pluto`/`xl2tpd` logs for VPN changes.
- Verify client docs when changing configuration output or client profiles.
