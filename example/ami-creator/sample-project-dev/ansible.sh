#!/usr/bin/env bash
set -euo pipefail

ANSIBLE_ROLES_PATH=../../roles \
ansible-playbook ./playbook.yml \
    --inventory=./inventory.ini \
    --ssh-common-args='-F ./ssh.cfg';
