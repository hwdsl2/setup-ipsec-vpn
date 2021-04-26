# Deploy to Amazon EC2 using CloudFormation

*Read this in other languages: [English](README.md), [简体中文](README-zh.md).*

This template will create a fully-working IPsec VPN server on Amazon Elastic Compute Cloud (Amazon EC2). Please make sure to check the EC2 [pricing details](https://aws.amazon.com/ec2/pricing/on-demand/) before continuing. Using a `t2.micro` server instance for your deployment may qualify for the [AWS Free Tier](https://aws.amazon.com/free/).

Available customization parameters:

- Amazon EC2 instance type
> **Note**: It is possible that not all instance type options offered by this template are available in a specific AWS region. For example, you may not be able to deploy an `m5a.large` instance in `ap-east-1` (hypothetically). In that case, you might experience the following error during deployment: `The requested configuration is currently not supported. Please check the documentation for supported configurations`. Newly released regions are more prone to having this problem as there are less variety of instances. For more info about instance type availability, refer to [https://ec2instances.info](https://ec2instances.info).
- OS for your VPN server (Ubuntu 20.04/18.04, Debian 9, CentOS 8/7, Amazon Linux 2)
> **Note:** Before using the Debian 9 image on EC2, you need to first subscribe at the AWS Marketplace: [Debian 9](https://aws.amazon.com/marketplace/pp/B073HW9SP3).
- Your VPN username
- Your VPN password
- Your VPN IPsec PSK (pre-shared key)

> **Note:** DO NOT use these special characters within values: `\ " '`

Make sure to deploy this template with an **AWS Account Root User** or an **IAM Account** with **Administrator Access**.

Right-click this [**template link**](https://raw.githubusercontent.com/hwdsl2/setup-ipsec-vpn/master/aws/cloudformation-template-ipsec.json) and save as a file on your computer. Then upload it as the template source in the [stack creation wizard](https://console.aws.amazon.com/cloudformation/home#/stacks/new).

![Upload the template](upload-the-template.png)

At step 4, make sure to confirm that this template may create IAM resources.

![Confirm IAM](confirm-iam.png)

Click the icon below to start:

<a href="https://console.aws.amazon.com/cloudformation/home#/stacks/new" target="_blank"><img src="cloudformation-launch-stack-button.png" alt="Launch stack" height="34px"></a>

You may choose an AWS region using the selector to the right of your account information on the navigation bar. After you click "create stack" in the final step, please wait for the stack creation and VPN setup to complete, which may take up to 15 minutes. As soon as the stack's status changes to **"CREATE_COMPLETE"**, you are ready to connect to the VPN server. Click the **Outputs** tab to view your VPN login details. Then continue to [Next steps: Configure VPN Clients](../README.md#next-steps).

> **Note**: If you delete a CloudFormation stack deployed using this template, the key pair that was added during deployment won't be automatically cleaned up. To manage your key pairs, go to EC2 console -> Key Pairs.

## FAQs

<details>
<summary>
How to connect to the server via SSH after deployment?
</summary>

You need to know the username and the private key for your Amazon EC2 instance in order to login to it via SSH.

Each Linux server distribution on EC2 has its own default login username. Password login is disabled by default for new instances, and the use of private keys, or "key pairs", is enforced.

List of default usernames:
> **Reference:** [https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connection-prereqs.html](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connection-prereqs.html)

| Distribution | Default Login Username |
| --- | --- |
| Ubuntu (`Ubuntu *.04`) |  `ubuntu` |
| Debian (`Debian 9`) | `admin` |
| CentOS (`CenOS 7/8`) | `centos` |
| Amazon Linux 2 | `ec2-user` |

This template generates a key pair for you during deployment, and the private key will be available as text under the **Outputs** tab after the stack is successfully created.

You will need to save the private key from the **Outputs** tab to a file on your computer, if you want to access the VPN server via SSH.

> **Note:** You may need to format the private key by replacing all spaces with newlines, before saving to a file. The file will need to be set with [proper permissions](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connection-prereqs.html#connection-prereqs-private-key) before using.

![Show key](show-key.png)

To apply proper permissions to your private key file, run the following command under the directory where the file is located:
```bash
sudo chmod 400 key-file.pem
```

Example command to login to your EC2 instance using SSH:
```bash
$ ssh -i path/to/your/key-file.pem instance-username@instance-ip-address
```
</details>

## Author

Copyright (C) 2020-2021 [S. X. Liang](https://github.com/scottpedia)

## Screenshots

![Specify parameters](specify-parameters.png)
