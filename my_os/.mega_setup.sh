#!/bin/bash

set -euo pipefail

MY_RED='\033[38;2;226;44;60m'
MY_ORANGE='\033[38;2;238;103;72m'
MY_YELLOW='\033[38;2;255;216;94m'
MY_GREEN='\033[38;2;82;238;163m'
DEFAULT='\033[0m'

success_output() {
    echo -e $MY_GREEN$1$DEFAULT
}

failed_output() {
    echo -e $MY_RED$1$DEFAULT
}

echo "==> Starting Setup"
echo "==> Checking Distro"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    if [[ "$DISTRO" = "fedora" ]]; then
        success_output "Verified this machine is running Fedora"
    else
        failed_output "Error: This machine is not running Fedora"
        echo "This setup is specific to Fedora."
        exit 1
    fi
else
    failed_output "Error: Failed to detect Linux distribution"
    exit 1
fi

echo "==> Setup complete!"