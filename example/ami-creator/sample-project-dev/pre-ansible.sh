#!/usr/bin/env bash
set -euo pipefail

# @TODO handle other platforms

if apt-get -v &> /dev/null; then
    sudo apt-get -y update;
    sudo apt-get -y upgrade;
    sudo apt-get -y install python-simplejson;
    sudo apt-get -y update;
fi

if which yum &> /dev/null; then
    exit 1
fi
