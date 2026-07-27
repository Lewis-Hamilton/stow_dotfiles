#!/bin/bash

set -euo pipefail

MY_RED='\033[38;2;226;44;60m'
MY_ORANGE='\033[38;2;238;103;72m'
MY_YELLOW='\033[38;2;255;216;94m'
MY_GREEN='\033[38;2;82;238;163m'
DEFAULT='\033[0m'
FONT_DIR="~/.local/share/fonts"
FONT_URL="https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/patched-fonts/JetBrainsMono/Ligatures/SemiBold/JetBrainsMonoNerdFont-SemiBold.ttf"

success_output() {
    echo -e $MY_GREEN$1$DEFAULT
}

failed_output() {
    echo -e $MY_RED$1$DEFAULT
}

warning_output() {
    echo -e $MY_YELLOW$1$DEFAULT
}

echo "── Starting Setup ──────────────────────────────────────────────────────────────────────────────────"

sudo -v

while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KP_PID=$!

trap 'kill $SUDO_KP_PID 2>/dev/null || true' EXIT

echo "── Checking Distro ───────────────────────────────────────────────────────────────────── Step 1/4 ──"

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

echo "── Checking Font ─────────────────────────────────────────────────────────────────────── Step 2/4 ──"

if fc-list : family style | grep -qi "JetBrainsMono.*SemiBold"; then
    success_output "Verified font is installed"    
else
    warning_output "JetBrainsMono Nerd Font Mono-SemiBold is not installed"
    echo "==> Installing Font"
    
    if mkdir -p "$FONT_DIR" && \
        curl -fLo "$FONT_DIR/$FONT_NAME" "$RAW_URL" && \
        fc-cache -f "$FONT_DIR"; then
            success_output "Successfully installed font"
        else
            failed_output "Error: Failed to install Font"
        fi
fi

echo "── Checking DNF Packages ───────────────────────────────────────────────────────────── Step 3/4 ──"
echo "── 3.1/3.? ────────────────────────────────────────────────────────── Updating installed packages ──"
if sudo dnf upgrade --refresh -y; then
    success_output "Successfully udpated existing packages"
else
    failed_output "Error: Failed to update existing packages"
    exit 1
fi

echo "── 3.2/3.? ─────────────────────────────────────────────────────────── Check for missing packages ──"


echo "── Checking Flatpak Packages ─────────────────────────────────────────────────────────── Step 4/4 ──"

echo "── Setup complete! ─────────────────────────────────────────────────────────────────────────────────"