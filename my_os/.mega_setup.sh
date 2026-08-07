#!/bin/bash

set -euo pipefail

MY_RED='\033[38;2;226;44;60m'
MY_ORANGE='\033[38;2;238;103;72m'
MY_YELLOW='\033[38;2;255;216;94m'
MY_GREEN='\033[38;2;82;238;163m'
DEFAULT='\033[0m'
FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
FONT_NAME="JetBrainsMonoNerdFontMono-SemiBold.ttf"
FONT_URL="https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/patched-fonts/JetBrainsMono/Ligatures/$FONT_NAME"
# Resolve through the stow symlink so this works from the repo or from ~
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
PACKAGES_FILE="$SCRIPT_DIR/dnf_packages.txt"
FLATPAK_FILE="$SCRIPT_DIR/flatpak_packages.txt"
MISSING_PACKAGES=()
MISSING_FLATPAKS=()
SKIP_UPGRADE=false

usage() {
    cat <<EOF
Usage: ${0##*/} [options]

Options:
  -s, --skip-upgrade    Skip the 'dnf upgrade --refresh' step
  -h, --help            Show this help and exit
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--skip-upgrade)
            SKIP_UPGRADE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

success_output() {
    echo -e "$MY_GREEN:) $1$DEFAULT"
}

failed_output() {
    echo -e "${MY_RED}Error: $1$DEFAULT"
}

warning_output() {
    echo -e "$MY_YELLOW:( $1$DEFAULT"
}

echo "── Starting Setup ──────────────────────────────────────────────────────────────────────────────────"

if [[ $EUID -eq 0 ]]; then
    # Running as sudo breaks the file paths
    failed_output "Do not run this script as root or with sudo"
    exit 1
fi

sudo -v

while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KP_PID=$!

trap 'kill $SUDO_KP_PID 2>/dev/null || true' EXIT

echo "── Checking Distro ───────────────────────────────────────────────────────────────────── Step 1/5 ──"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    if [[ "$DISTRO" = "fedora" ]]; then
        success_output "Verified this machine is running Fedora"
    else
        failed_output "This machine is not running Fedora"
        echo "This setup is specific to Fedora."
        exit 1
    fi
else
    failed_output "Failed to detect Linux distribution"
    exit 1
fi

echo "── Checking Font ─────────────────────────────────────────────────────────────────────── Step 2/5 ──"

FONT_LIST=$(fc-list : family style)

if grep -qi "JetBrainsMono.*SemiBold" <<< "$FONT_LIST"; then
    success_output "Verified font is installed"
else
    warning_output "JetBrainsMono Nerd Font Mono-SemiBold is not installed"
    echo "==> Installing Font"

    if mkdir -p "$FONT_DIR" && \
        curl -fLo "$FONT_DIR/$FONT_NAME" "$FONT_URL" && \
        fc-cache -f "$FONT_DIR"; then
            success_output "Successfully installed font"
        else
            failed_output "Failed to install Font"
            exit 1
        fi
fi

echo "── Checking DNF Packages ─────────────────────────────────────────────────────────────── Step 3/5 ──"
echo "── Checking DNF Packages - 3.1/3.3 ────────────────────────────────── Updating installed packages ──"

if [[ "$SKIP_UPGRADE" == true ]]; then
    warning_output "Skipping package update (--skip-upgrade)"
elif sudo dnf upgrade --refresh -y; then
    success_output "Successfully updated existing packages"
else
    failed_output "Failed to update existing packages"
    exit 1
fi

echo "── Checking DNF Packages - 3.2/3.3 ──────────────────────────────── Checking for missing packages ──"

while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    pkg=$(echo "$pkg" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [[ -z "$pkg" ]] && continue

    if dnf list --installed "$pkg" &>/dev/null; then
        success_output "Verified install - $pkg"
    else
        warning_output "── Not installed - $pkg"
        MISSING_PACKAGES+=("$pkg")
    fi
done < "$PACKAGES_FILE"

echo "── Checking DNF Packages - 3.3/3.3 ────────────────────────────────── Installing missing packages ──"

echo "── Checking Flatpak Packages ─────────────────────────────────────────────────────────── Step 4/5 ──"
echo "── Checking Flatpak Packages - 4.1/4.3 ───────────────────────────────── Verifying flathub remote ──"

# Fedora only preconfigures its own remote, so anything from flathub fails to
# install without this. --if-not-exists makes it a no-op on later runs.
if sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
    success_output "Verified flathub remote is configured"
else
    failed_output "Failed to add flathub remote"
    exit 1
fi

echo "── Checking Flatpak Packages - 4.2/4.3 ────────────────────────────── Updating installed flatpaks ──"

# Split by scope on purpose: a --system update run as a normal user blocks on a
# polkit prompt, so that half goes through the already-cached sudo instead.
if [[ "$SKIP_UPGRADE" == true ]]; then
    warning_output "Skipping flatpak update (--skip-upgrade)"
elif sudo flatpak update -y --system && flatpak update -y --user; then
    success_output "Successfully updated existing flatpaks"
else
    failed_output "Failed to update existing flatpaks"
    exit 1
fi

echo "── Checking Flatpak Packages - 4.3/4.3 ──────────────────────────── Checking for missing flatpaks ──"

while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [[ -z "$line" ]] && continue

    # "<app id> <display name>" - app ids never contain spaces, so split on the
    # first one and keep the rest as the name. The name is optional.
    app=${line%%[[:space:]]*}
    name=${line#"$app"}
    name=$(echo "$name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [[ -z "$name" ]] && name="$app"

    # flatpak info looks in both the system and user installations
    if flatpak info "$app" &>/dev/null; then
        success_output "Verified install - $name"
    else
        warning_output "── Not installed - $name"
        MISSING_FLATPAKS+=("$app")
    fi
done < "$FLATPAK_FILE"

echo "── Checking Display Manager ──────────────────────────────────────────────────────────── Step 5/5 ──"
echo "── Checking Display Manager - 5.1/5.2 ─────────────────────────────────── Checking Lightdm Status ──"


# lightdm comes in as a hard dependency of light-locker, but ships disabled.
# is-enabled prints nothing and fails when the unit does not exist, which is
# the case until the packages above are actually installed.
LIGHTDM_STATE=$(systemctl is-enabled lightdm.service 2>/dev/null || true)

if [[ "$LIGHTDM_STATE" == "masked" ]]; then
    failed_output "lightdm is masked"
    echo "Unmask it with 'sudo systemctl unmask lightdm.service' and re-run."
    exit 1
else
    if [[ "$LIGHTDM_STATE" == "enabled" ]]; then
        success_output "Verified lightdm is enabled"
    else
        echo "==> Enabling lightdm (currently $LIGHTDM_STATE)"
        if sudo systemctl enable lightdm.service; then
            success_output "Successfully enabled lightdm"
        else
            failed_output "Failed to enable lightdm"
            exit 1
        fi
    fi

echo "── Checking Display Manager - 5.2/5.2 ────────────────────────────────────── Checking Boot Target ──"

    # Enabling lightdm alone is inert: the display manager is only started as
    # part of graphical.target, and a minimal install boots to multi-user.
    if [[ "$(systemctl get-default)" == "graphical.target" ]]; then
        success_output "Verified default boot target is graphical"
    else
        echo "==> Setting default boot target to graphical"
        if sudo systemctl set-default graphical.target; then
            success_output "Successfully set default boot target to graphical"
        else
            failed_output "Failed to set default boot target"
            exit 1
        fi
    fi
fi

echo "── Setup complete! ─────────────────────────────────────────────────────────────────────────────────"