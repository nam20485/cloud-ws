# **Hetzner RAID 10 Automated Setup Guide**

This guide provides a comprehensive, step-by-step walkthrough for automatically provisioning a Hetzner dedicated server and configuring it with a high-performance RAID 10 array. By leveraging Infrastructure as Code (IaC) tools like Terraform and Ansible, we can create a repeatable, reliable, and fast deployment process, minimizing manual configuration and the potential for human error.

## **Prerequisites**

Before we begin, ensure you have the following set up. Each of these components is essential for the automation process to work correctly.

* **A Hetzner Cloud Account:** You will need an active account to provision resources. The creation process is manual and cannot be automated.  
* **A Hetzner API Token:** This token acts as a password, allowing Terraform to authenticate with your Hetzner account and manage resources on your behalf. You can generate one in the Hetzner Cloud Console under your project's "Security" \-\> "API tokens" section. For this guide, you will need a token with **Read & Write** permissions.  
* **Terraform Installed:** Terraform is the tool we will use to define and provision the server itself. If you don't have it installed, you can download it from the [official Terraform website](https://www.terraform.io/downloads.html).  
* **Ansible Installed:** Ansible is our configuration management tool, which we will use to run commands on the newly created server to set up the RAID array. You can find installation instructions in the [official Ansible documentation](https://docs.ansible.com/ansible/latest/installation_guide/index.html).  
* **An SSH Key Pair:** An SSH key provides secure access to your server. You will need to add your public SSH key to your Hetzner Cloud project and have the corresponding private key on your local machine. This is more secure than using passwords.

## **Step 1: Provision the Server with Terraform**

In this step, we'll write a Terraform configuration file to define the server we want, and then use the Terraform CLI to create that server in your Hetzner account.

1. **Create a Project Directory:** On your local machine, create a new directory for your project files and navigate into it. This keeps your configuration organized.  
2. **Define the Infrastructure:** Create a file named main.tf. This file is the core of our Terraform setup, where we declare the provider and the resources we want to create.  
3. **Store Your Secret Token:** Create a file named terraform.tfvars. This file is used to store sensitive data like your API token. Terraform automatically loads variables from this file, so you don't have to hardcode secrets directly into your main configuration. Add the following, replacing the placeholder with your actual token:  
   hcloud\_token \= "YOUR\_HETZNER\_API\_TOKEN"

4. **Initialize Terraform:** Open your terminal in the project directory and run:  
   terraform init

   This command initializes your Terraform workspace by downloading the necessary provider plugins (in this case, the hcloud provider for Hetzner). You only need to run this once per project.  
5. **Review the Execution Plan:** Before making any changes, it's a best practice to preview what Terraform will do. Run:  
   terraform plan

   This command shows you an execution plan, detailing which resources will be created, modified, or destroyed. **Always review this plan carefully** to ensure it matches your intentions.  
6. **Apply the Configuration:** Once you are satisfied with the plan, apply it to create the server:  
   terraform apply

   Terraform will ask for confirmation before proceeding. Type yes to approve. It will then connect to the Hetzner API and provision the server as defined in your main.tf file. When it's finished, it will output the server's public IP address, which you will need for the next step.

## **Step 2: Configure RAID 10 with Ansible**

With our server up and running, we'll now use Ansible to log in and run the necessary commands to configure the software RAID 10 array.

1. **Create an Inventory File:** Create a file named inventory.ini. This file tells Ansible which servers to connect to. Add the IP address that Terraform provided in the previous step.  
2. **Create an Ansible Playbook:** Create a file named playbook.yml. A playbook is a YAML file that contains a list of tasks for Ansible to execute sequentially on the target server.  
3. **Run the Playbook:** Now, execute the playbook using the following command:  
   ansible-playbook \-i inventory.ini playbook.yml

   Ansible will read your inventory file, connect to the server via SSH using your key, and execute the tasks in the playbook one by one. This includes installing the mdadm RAID management utility, creating the RAID 10 array across the four specified drives, formatting it with an ext4 filesystem, and mounting it.

## **Step 3: Verify the RAID Array**

The automation is complete, but it's always wise to manually verify that everything is working as expected.

1. **Connect to the Server:** Use SSH to log into your new server as the root user:  
   ssh root@\<your\_server\_ip\>

2. **Check the RAID Status:** To see the status of your newly created RAID array, run:  
   cat /proc/mdstat

   The output should show a /dev/md0 device that is active raid10 with four devices listed. A status of \[UUUU\] indicates that all four drives are online and working correctly.  
3. **Check the Filesystem Mount:** To confirm that the RAID array is formatted and mounted correctly, check the system's mounted filesystems:  
   df \-h

   You should see /dev/md0 listed, mounted at /mnt/raid10, with the correct total size (approximately twice the size of a single drive, since RAID 10 uses half the total capacity for mirroring).

Congratulations\! You have successfully provisioned a Hetzner dedicated server and configured a high-performance, redundant RAID 10 array using a fully automated workflow. You can now use this powerful server for your development and hosting needs.