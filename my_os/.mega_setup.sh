#!/bin/bash

set -euo pipefail

MY_RED='\033[38;2;226;44;60m'
MY_ORANGE='\033[38;2;238;103;72m'
MY_YELLOW='\033[38;2;255;216;94m'
MY_GREEN='\033[38;2;82;238;163m'
DEFAULT='\033[0m'

echo "==> Starting Setup"
echo "==> Checking Distro"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    if [[ "$DISTRO" = "fedora" ]]; then
        echo -e "${MY_GREEN}Verified this machine is running Fedora${DEFAULT}"
    else
        echo -e "${MY_RED}Error: This machine is not running Fedora${DEFAULT}"
        echo "This setup is specific to Fedora."
        exit 1
    fi
else
    echo -e "${MY_RED}Error: Failed to detect Linux distribution${DEFAULT}"
    exit 1
fi

echo "==> Setup complete!"