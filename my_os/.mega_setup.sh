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
ONEPASS_KEY_URL="https://downloads.1password.com/linux/keys/1password.asc"
ONEPASS_REPO_FILE="/etc/yum.repos.d/1password.repo"
# Overridable from the environment so an odd machine can be tuned without an edit
MIN_DISK_GIB=${MIN_DISK_GIB:-25}
MIN_FREE_GIB=${MIN_FREE_GIB:-10}
DEFAULT_DIRS=("$HOME/Documents" "$HOME/Code" "$HOME/Pictures" "$HOME/Videos" "$HOME/Downloads")
MISSING_PACKAGES=()
MISSING_FLATPAKS=()
SKIP_UPGRADE=false
SKIP_STORAGE_CHECK=false

usage() {
    cat <<EOF
Usage: ${0##*/} [options]

Options:
  -s, --skip-upgrade    Skip the 'dnf upgrade --refresh' step
  -S, --skip-storage-check
                        Run even if the machine is below the storage minimums
  -h, --help            Show this help and exit
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--skip-upgrade)
            SKIP_UPGRADE=true
            shift
            ;;
        -S|--skip-storage-check)
            SKIP_STORAGE_CHECK=true
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

gib() {
    awk -v bytes="$1" 'BEGIN { printf "%.1f", bytes / (1024 ^ 3) }'
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

echo "── Checking Distro ───────────────────────────────────────────────────────────────────── Step 1/8 ──"

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

echo "── Checking Storage ──────────────────────────────────────────────────────────────────── Step 2/8 ──"
echo "── Checking Storage - 2.1/2.2 ────────────────────────────────────── Checking filesystem capacity ──"

ROOT_FSTYPE=$(df --output=fstype / | tail -n 1 | tr -d '[:space:]')
ROOT_SIZE=$(df -B1 --output=size / | tail -n 1 | tr -d '[:space:]')
ROOT_AVAIL=$(df -B1 --output=avail / | tail -n 1 | tr -d '[:space:]')

# Total size is a static property of the machine, so it is the one threshold
# that means the same thing on a first run and on every run after it.
if [[ "$SKIP_STORAGE_CHECK" == true ]]; then
    warning_output "Skipping storage check (--skip-storage-check)"
elif (( ROOT_SIZE < MIN_DISK_GIB * 1024 ** 3 )); then
    failed_output "Root filesystem is $(gib "$ROOT_SIZE") GiB, less than the $MIN_DISK_GIB GiB minimum"
    exit 1
else
    success_output "Verified root filesystem is $(gib "$ROOT_SIZE") GiB, greater than the $MIN_DISK_GIB GiB minimum"

    if (( ROOT_AVAIL < MIN_FREE_GIB * 1024 ** 3 )); then
        warning_output "Only $(gib "$ROOT_AVAIL") GiB free, less than the $MIN_FREE_GIB GiB minimum"
        echo "Safe to ignore if most of the packages below are already installed."
    else
        success_output "Verified $(gib "$ROOT_AVAIL") GiB of free space, greater than the $MIN_FREE_GIB GiB minimum"
    fi
fi

echo "── Checking Storage - 2.2/2.2 ───────────────────────────────────────── Checking btrfs allocation ──"

if [[ "$SKIP_STORAGE_CHECK" == true ]]; then
    warning_output "Skipping btrfs allocation check (--skip-storage-check)"
elif [[ "$ROOT_FSTYPE" != "btrfs" ]]; then
    success_output "Root filesystem is $ROOT_FSTYPE, no allocation check needed"
else
    UNALLOCATED=$(btrfs filesystem usage -b / 2>/dev/null | awk '/Device unallocated:/ {print $3}')
    META_TOTAL=$(btrfs filesystem df -b / 2>/dev/null | awk -F'[=,]' '/^Metadata/ {print $3}')
    META_USED=$(btrfs filesystem df -b / 2>/dev/null | awk -F'[=,]' '/^Metadata/ {print $5}')

    if ! [[ "$UNALLOCATED" =~ ^[0-9]+$ && "$META_TOTAL" =~ ^[1-9][0-9]*$ && "$META_USED" =~ ^[0-9]+$ ]]; then
        warning_output "Could not read btrfs allocation, skipping this check"
    else
        META_PCT=$(( META_USED * 100 / META_TOTAL ))

        if (( UNALLOCATED < 1024 ** 3 && META_PCT > 85 )); then
            failed_output "btrfs is fully allocated and metadata is ${META_PCT}% full"
            echo "Only $(( UNALLOCATED / 1024 / 1024 )) MiB is unallocated"
            echo "Not enough space to continue"
            exit 1
        fi

        success_output "Verified btrfs allocation ($(gib "$UNALLOCATED") GiB unallocated, metadata ${META_PCT}%)"
    fi
fi

echo "── Checking Repositories ─────────────────────────────────────────────────────────────── Step 3/8 ──"

if [[ -f "$ONEPASS_REPO_FILE" ]]; then
    success_output "Verified 1Password repository is configured"
else
    warning_output "1Password repository is not configured"
    echo "==> Adding 1Password repository"

    # $basearch is expanded by dnf, not here, hence the escape.
    if sudo rpm --import "$ONEPASS_KEY_URL" && \
        sudo tee "$ONEPASS_REPO_FILE" >/dev/null <<EOF
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$ONEPASS_KEY_URL
EOF
    then
        success_output "Successfully added 1Password repository"
    else
        failed_output "Failed to add 1Password repository"
        exit 1
    fi
fi

echo "── Checking DNF Packages ─────────────────────────────────────────────────────────────── Step 4/8 ──"
echo "── Checking DNF Packages - 4.1/4.3 ────────────────────────────────── Updating installed packages ──"

if [[ "$SKIP_UPGRADE" == true ]]; then
    warning_output "Skipping package update (--skip-upgrade)"
elif sudo dnf upgrade --refresh -y; then
    success_output "Successfully updated existing packages"
else
    failed_output "Failed to update existing packages"
    exit 1
fi

echo "── Checking DNF Packages - 4.2/4.3 ──────────────────────────────── Checking for missing packages ──"

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

echo "── Checking DNF Packages - 4.3/4.3 ────────────────────────────────── Installing missing packages ──"

if [[ ${#MISSING_PACKAGES[@]} -eq 0 ]]; then
    success_output "No missing packages to install"
elif sudo dnf install -y "${MISSING_PACKAGES[@]}"; then
    success_output "Successfully installed ${#MISSING_PACKAGES[@]} missing packages"
else
    failed_output "Failed to install missing packages"
    exit 1
fi

echo "── Checking Flatpak Packages ─────────────────────────────────────────────────────────── Step 5/8 ──"
echo "── Checking Flatpak Packages - 5.1/5.4 ───────────────────────────────── Verifying flathub remote ──"

# Fedora only preconfigures its own remote, so anything from flathub fails to
# install without this. --if-not-exists makes it a no-op on later runs.
if sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
    success_output "Verified flathub remote is configured"
else
    failed_output "Failed to add flathub remote"
    exit 1
fi

echo "── Checking Flatpak Packages - 5.2/5.4 ────────────────────────────── Updating installed flatpaks ──"

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

echo "── Checking Flatpak Packages - 5.3/5.4 ──────────────────────────── Checking for missing flatpaks ──"

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

echo "── Checking Flatpak Packages - 5.4/5.4 ────────────────────────────── Installing missing flatpaks ──"

if [[ ${#MISSING_FLATPAKS[@]} -eq 0 ]]; then
    success_output "No missing flatpaks to install"
elif sudo flatpak install -y --system flathub "${MISSING_FLATPAKS[@]}"; then
    success_output "Successfully installed ${#MISSING_FLATPAKS[@]} missing flatpaks"
else
    failed_output "Failed to install missing flatpaks"
    exit 1
fi

echo "── Checking Display Manager ──────────────────────────────────────────────────────────── Step 6/8 ──"
echo "── Checking Display Manager - 6.1/6.2 ─────────────────────────────────── Checking Lightdm Status ──"


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

echo "── Checking Display Manager - 6.2/6.2 ────────────────────────────────────── Checking Boot Target ──"

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

echo "── Checking Font ─────────────────────────────────────────────────────────────────────── Step 7/8 ──"

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

echo "── Checking Default Folders ──────────────────────────────────────────────────────────── Step 8/8 ──"

for dir in "${DEFAULT_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        success_output "──── Verified folder exists - ${dir/#"$HOME"/\~}"
    elif mkdir -p "$dir"; then
        success_output "Successfully created folder - ${dir/#"$HOME"/\~}"
    else
        failed_output "Failed to create folder - ${dir/#"$HOME"/\~}"
        exit 1
    fi
done

echo "── Setup complete! ─────────────────────────────────────────────────────────────────────────────────"