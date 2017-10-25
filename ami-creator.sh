#!/usr/bin/env bash

# http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -eEu -o pipefail
shopt -s extdebug
#IFS=$'\n\t'

# @TODO cloudformation for creating user (ami-creator), roles, policies, etc.
# @TODO one-line installer
# @TODO custom tab completion for commands and parameters

# define version
VERSION="ami-creator/0.1.0"

# Directory we are being called from
CALLING_DIR="$(pwd)"

# Directory of these scripts
if [[ -h "$0" ]]; then
    # we are being called via symlink
    ROOT_DIR="$(dirname "$(readlink "$0")")"
else
    # we are being called directly
    ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
fi

# define usage
USAGE="
Usage:

$(basename "$0") <command> [parameters]

To see help text, you can run:

  ami-creator help
  ami-creator <command> help
";

# just echo help message if no arguments are given
if [ "$#" == 0 ]; then
    echo "${USAGE}";
    exit 0;
fi

source "${ROOT_DIR}/ami-functions.sh"

# kick off the main script with all parameters
main ${@}
