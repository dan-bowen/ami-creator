# Amify

Amify is a simple command-line wrapper around several tedious steps when it comes to creating 
custom AMIs with Ansible.

1. Create a temporary EC2 instance
1. Upload and run a `pre-ansible.sh` script
1. Run Ansible against the instance
1. Create the AMI
1. Terminate the instance

```
$ amify --help

NAME
        amify

DESCRIPTION

        amify is a command line tool to build custom AMIs using Ansible.

OPTIONS

        --version   Display the version of this tool.

AVAILABLE COMMANDS

    init                Create a new project
    create              Create a custom AMI start to finish
    pre-ansible         Run a script on the instance before running Ansible
    ansible             Run Ansible on the instance
    ssh                 SSH to the instance
    finalize            Create AMI from the instance
    terminate           Terminate the instance
    list-amis           List AMIs
    list-instances      List running instances
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

There are several options for creating these resources:

1. Use existing resources.
1. Manuall create new ones.
1. Use [cloudformation.yml](./cloudformation.yml) to create a separate `amify` stack for you.

## Installation

### Pre-requisites

- [Ansible](http://docs.ansible.com/ansible/latest/intro_installation.html)
- [AWS CLI tools](https://aws.amazon.com/cli/)
  
  I suggest a creating [separate profile](http://docs.aws.amazon.com/cli/latest/userguide/cli-multiple-profiles.html) 
  reserved for `amify` to use. The [cloudformation.yml](./cloudformation.yml) will create a separate user with 
  all the permissions you need. You'll need to manually create the access key and `aws` profile for this user.
  
  Alternatively, you can attach the `amify-user` policy created by [cloudformation.yml](./cloudformation.yml) 
  to an existing user or group.

### Venv

```
# Ensure you have virtualenv installed
$ pip install virtualenv

# initialize virtual env
$ virtualenv venv

# start virtualenv
$ source venv/bin/activate

# Install local module as symlink
$ pip install -e .

# check installation
$ which amify
```

## Creating an AMI

```
$ amify create
```

This should create a custom AMI from start to finish. If any of the intermediate steps fail, the instance will still be 
running so you can debug and tweak your instance. `amify` includes several commands 
to help with debugging a running instance.

```
$ amify ssh
$ amify pre-ansible
$ amify ansible
$ amify finalize
$ amify terminate
```

## Managing resources

Instances and AMIs are tagged so they are easily discoverable by `amify`. These commands will show you what 
resources are associated with `amify`,

List running instances.

```
$ amify list-instances
```

Terminate running instances.

```
$ amify terminate
```

List all AMIs.

```
$ amify list-amis
```

# Project Directory Structure

The `.amify` folder lives inside your Ansible directory structure.


```
.amify/
    project_name/      # Project folder, named in amify.yml
        pre-ansible.sh # Runs on the server prior to running Ansible
        ssh.cfg        # Temporary SSH config file
        session.yml    # Temporary session file
    amify.yml          # Amify configuration file
group_vars/
host_vars/
roles/
someproject.inventory.amify.{ project_name }.ini # Temporary inventory
someproject.playbook.amify.{ project_name }.yml  # Temporary playbook
someproject.playbook.yml                         # Original playbook
```

## Description of files

- `.amify/project/pre-ansible.sh`
  
  This script is copied to the intance and executed prior to running Ansible.
  
  - Modify as needed, add to source control.
  
- `.amify/project/session.yml`

  This holds temporary variables saved during a session such as the Instance ID and AMI ID.
  
  - Temporary, deleted on exit.
  
- `.amify/project/ssh.cfg`

  This is an [SSH config file](http://nerderati.com/2011/03/17/simplify-your-life-with-an-ssh-config-file/) 
  to help with SSH-ing to the temporary EC2 instance.
  
  - Temporary, deleted on exit.

- `.amify/amify.yml`
  
  Amify configuration file.
  
  - Modfiy as needed, add to source control.

- `someproject.playbook.amify.{ project_name }.ini`
  
  This is an [Ansible inventory file](http://docs.ansible.com/ansible/latest/intro_inventory.html) that 
  represents the temporary EC2 instance.

  - Temporary, deleted on exit.

- `someproject.playbook.amify.{ project_name }.yml`
  
  This is an Ansible playbook. It is mostly a direct copy of your existing Ansible playbook. The main difference 
  is the `hosts` variable is set to `amify`, e.g. `hosts: amify`, so that Amify can run the playbook against the 
  temporary EC2 instance.
  
  Amify does not modify your existing playbooks. You can modify your current playbooks at-will and Amify will pick
  up the changes.
  
  - Temporary, deleted on exit.

# @TODO

- `--incremental` option to build AMI incrementally based off the last AMI
