# Deploy to Microsoft Azure

*Read this in other languages: [English](README.md), [简体中文](README-zh.md).*

This template will create a fully working VPN server on the Microsoft Azure Cloud (<a href="https://azure.microsoft.com/en-us/pricing/details/virtual-machines/" target="_blank">pricing details</a>).

Customizable with the following options:

 - Username for VPN **and** SSH
 - Password for VPN **and** SSH
 - IPsec Pre-Shared Key for VPN
 - Operating System Image (Ubuntu 20.04/18.04 or Debian 9)
 - Virtual Machine Size (Default: Standard_B1s)

**Note:** DO NOT use these special characters within values: `\ " '`

Press this button to start:

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fhwdsl2%2Fsetup-ipsec-vpn%2Fmaster%2Fazure%2Fazuredeploy.json" target="_blank">
    <img src="../docs/images/azure-deploy-button.png" alt="Deploy to Azure" />
</a><br><br>

When the deployment finishes, Azure displays a notification. Next steps: [Configure VPN Clients](../README.md#next-steps).

## Authors

Copyright (C) 2016 [Daniel Falkner](https://github.com/derdanu)   
Copyright (C) 2017-2021 [Lin Song](https://www.linkedin.com/in/linsongui)

## Screenshot

![Azure Custom Deployment](custom_deployment_screenshot.png)
