# AMI Creator

Automates creating custom AMIs using Ansible for provisioning.

1. Create a temporary EC2 instance
1. Upload and run a pre-provisioning script
1. Run Ansible against the instance
1. Create AMI
1. Terminate instance

Each of these steps can be run individually to allow for debugging and fine-tuning your instance 
before creating the final AMI.

```
$ ami-creator help

NAME
        ami-creator

DESCRIPTION

        ami-creator is a command line tool to build custom AMIs using Ansible for provisioning.

OPTIONS

        --version   Display the version of this tool.

AVAILABLE COMMANDS

    init                Create a new project
    create              Create a custom AMI start to finish
    pre-ansible         Run a script on the instance before running Ansible
    ansible             Run Ansible on the instance
    ssh                 SSH to the currently running instance
    finalize            Create AMI from currently running instance
    terminate           Terminate the currently running instance
    list-amis           List AMIs created on a per-session, per-project or global basis
    list-instances      List any instances that are running on a per-session, per-roject or global basis
```

# Getting started

## AWS resources

Performing actions in your AWS account requires several resources to exist prior to creating custom AMIs. Specifically:

- AWS CLI profile
- EC2 SSH Key
- EC2 SSH File, e.g. `~/.ssh/ami-creator.pem`
- EC2 Security Groups, e.g `sg-baf872c8`
- EC2 Subnet, e.g `subnet-7a742b20`
- EC2 IAM Instance Profile

You will be prompted for these values when creating a new project, so it is a good idea to set them up first.

You basically have three options for creating these resources:

1. Use existing resources.
1. Create new ones.
1. Use [cloudformation.json](./cloudformation.json) to create a separate `ami-creator` stack for you.

   [cloudformation.json](./cloudformation.json) has the added benefit of being completely separate from your existing resources. Don't 
   like `ami-creator`? Just delete the stack, and there will be no traces of it in your AWS account.

## Installation

Pre-requisites:

- [Ansible](http://docs.ansible.com/ansible/latest/intro_installation.html)

- [AWS CLI tools](https://aws.amazon.com/cli/)
  
  I highly suggest a creating 
  [separate profile](http://docs.aws.amazon.com/cli/latest/userguide/cli-multiple-profiles.html) reserved 
  for `ami-creator` to use. The [cloudformation.json](./cloudformation.json) will create this for you.

```
# checkout the git repo
$ git clone git@github.com:crucialwebstudio/ami-creator.git

# symlink ami-creator.sh to somewhere on your $PATH
$ ln -s /path/to/ami-creator.sh /usr/local/bin/ami-creator
```

Now you can call `ami-creator` from anywhere.

## Create `ami-creator` directory in your Ansible folder

```
$ cd /path/to/ansible
$ mkdir ami-creator
```

## Creating a project

Call `ami-creator init` from within the `ami-creator` directory.

```
$ cd /path/to/ansible/ami-creator
$ ami-creator init
```

This will prompt you for several project variables and save several files to a new project folder.

## Creating an AMI

```
$ cd /path/to/ansible/ami-creator/name-of-project
$ ami-creator create
```

This should start a new 'session' and a custom AMI from start to finish. If any of the steps fail, 
the instance will still be running so you can debug and tweak your instance. `ami-creator` includes several commands 
to help with debugging a 'session'.

```
$ ami-creator ssh
$ ami-creator pre-ansible
$ ami-creator ansible
$ ami-creator finalize
$ ami-creator terminate
```

# Viewing resources

Instances and AMIs are tagged so they are easily discoverable by `ami-creator`. These commands will show you what 
resources are associated with `ami-creator`,

## Listing Instances

```
$ ami-creator list-instances
```

AMI creator prompts you to terminate the temporary instance after a new AMI is successfully created. If you 
answered no or some other step of the process fails such that the instance is not terminated, this command will list 
any instances that were created by `ami-creator`.

You can manually terminate any running instances with 

```
$ ami-creator terminate
```

## Listing AMIs

```
$ ami-creator list-amis
```

AMIs are tagged so they are easily discoverable on a per-session, per-project, or global basis. This command will 
list them for you.

# Project Directory Structure

The `ami-creator` folder lives inside your Ansible directory structure. AMI Creator 
projects live in folders below that.


```
ami-creator/
    project-name/
        ansible.sh
        inventory.ini
        playbook.yml
        pre-ansible.sh
        project.cfg
        session.lock
        ssh.cfg
group_vars/
host_vars/
roles/
someproject.playbook.yml
```

## Description of files

- `ansible.sh`
  
  This is a wrapper around `ansible-playbook`.

  - Feel free to modify, but be careful to retain the existing parameters.

- `inventory.ini`
  
  This is an [Ansible inventory file](http://docs.ansible.com/ansible/latest/intro_inventory.html) that 
  represents the temporary EC2 instance.

  - Feel free to modify, but be careful to retain the `ami-creator` hostname.

- `playbook.yml`
  
  This playbook is copied from your existing Ansible directory. The main difference is the `hosts` variable 
  is set to `ami-creator`, e.g. `hosts: ami-creator`, so that AMI Creator can run the playbook against the 
  temporary EC2 instance.
  
  AMI Creator does not touch your existing playbooks. You can modify your current playbooks at-will and AMI 
  Creator will copy the changes to this file.
  
  - Do not modify
  
- `pre-ansible.sh`
  
  This script is copied to and executed on the temporary EC2 instance prior to running Ansible.
  
  - Feel free to modify.
  
- `project.cfg`
  
  The contains project configuration variables set during `ami-creator init`
  
  - Feel free to modify values. Do not add or modify variable names.
  
- `session.lock`

  This holds variables saved during a session such as the Instance ID and the AMI ID.
  
  - Do not modify.
  
- `ssh.cfg`
  This is an [SSH config file](http://nerderati.com/2011/03/17/simplify-your-life-with-an-ssh-config-file/) 
  to help with SSH-ing to the temporary EC2 instance.
  
  - Do not modify.

# F.A.Q.

1. Why did you create this tool?

   Creating custom AMIs is tedious. This started as an internal tool to help me automate the process and it currently
   "works for me". I'd love to have you try it out and let me know if you find it useful.

2. Why does the `ami-creator` folder have to exist within my Ansible folder?

   Technically, it doesn't, but this convention makes it easy for `ami-creator` to locate your playbooks, roles, 
   etc. Additionally, your playbooks are (hopefully) already under source control. I believe if you are using 
   a tool such as  `ami-creator` to create custom AMIs, the files it uses and creates are important enough to have 
   under source control as well. This enables code review, sharing with a team, etc.

3. Pure Bash, eh?

   This may get rewritten in Python at some point. For now it works pretty well and there are no dependencies.

