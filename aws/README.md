# Deploy to AWS (Beta)

> **Note:** The AWS deployment template is still in **BETA** phase. You may encounter failures during the deployment. In that case, please let us know the issue.

This template will create a fully-working IPSec/L2TP VPN server on AWS (Amazon Web Service). Please make sure to check the [pricing details](https://aws.amazon.com/ec2/pricing/on-demand/) of Virtual Machine on EC2 before starting the launch sequence.

You can also use `t2.micro` instance as your server for your deployment, which is free of charge within the first year since your AWS account is registered. For more information on AWS free usage tier, go to [this page](https://aws.amazon.com/free/).

## Available Customization Parameters:

- AWS EC2 Instance Type
- OS for your VPN Server (Ubuntu16.04, Ubuntu18.04, Debian9-Stretch or Debian10-Buster)
> **Note:** To use Debian9 or Debian10 images on EC2, to need to subscribe them first at AWS marketplace. [**Debian9**](https://aws.amazon.com/marketplace/pp/B073HW9SP3) [**Debian10**](https://aws.amazon.com/marketplace/pp/B0859NK4HC)
- Your VPN username
- Your VPN password
- IPSec PSK (pre-shared key)

> When choosing your username and password, do not enter special characters like `" ' \`.

Make sure to do this with an **AWS ROOT ACCOUNT** or an **IAM ACCOUNT** with **ANDMINISTRATOR ACCESS**. 

Right-click the [**template link**](https://raw.githubusercontent.com/hwdsl2/setup-ipsec-vpn/master/aws/cloudformation-template-ipsec) and save it as a file on your computer. Then upload it as the template source in the stack creation wizard.

![Upload the file](upload-the-template.png)

At step 4, make sure to confirm that this template may create IAM resources.

![Confirm IAM](confirm-iam.png)

Click the icon below to initiate the launching sequence.

<a href="https://console.aws.amazon.com/cloudformation/home#/stacks/new"><img src="../docs/images/cloudformation-launch-stack-button.png" alt="Deploy to AWS" height="34px"></a>

Make sure the deployment is successful before going to [Next Step: Configure VPN Clients](https://git.io/vpnclients).

> **Note:** You need to wait for around 5 minutes after the stack is shown as **"CREATE_COMPLETE"**, before you can connect to the server with a VPN client. That's for the installation script to finish.

# FAQs

<details>
<summary>
How to connect to the server via ssh after deployment?
</summary>
  
AWS does not allow users to access the instances with an SSH password. Instead, users are instructed to create "key pairs", which are used as credentials to access the instances via SSH. 

The template here generates a key pair for you during the deployment, and that will be available as plain texts in the **"Output"** section after the stack is successfully created.

You need to note down that key file if you want to later access the VPN server via SSH. 

![](show-key.png)

</details>

## Author

Copyright (C) 2020 [S. X. Liang](https://github.com/scottpedia)

## Screenshots

<img src="specify-parameters.png" alt="Step 2">
