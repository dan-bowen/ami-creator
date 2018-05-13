#!/usr/bin/env bash
set -euo pipefail

cd ../../
ansible-playbook ami-creator.sample-project-dev.playbook.yml \
    --inventory=ami-creator.sample-project-dev.inventory.ini \
    --ssh-common-args='-F ./ami-creator/sample-project-dev/ssh.cfg';
