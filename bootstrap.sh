#!/usr/bin/env bash
#
# bootstrap.sh — rebuild this i3 setup on a fresh Fedora install.
#
# Usage (after installing git + cloning this repo):
#   sudo dnf install -y git stow
#   git clone git@github.com:Lewis-Hamilton/stow_dotfiles.git ~/stow_dotfiles
#   cd ~/stow_dotfiles && ./bootstrap.sh
#
# Idempotent: safe to re-run. Does NOT touch anything destructive.
# See FEDORA_MIGRATION.md for the reasoning behind each step.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }

if [ ! -r /etc/fedora-release ]; then
  warn "This doesn't look like Fedora. Continuing anyway, but package names assume Fedora."
fi

FEDORA_VER="$(rpm -E %fedora 2>/dev/null || echo "")"

# ---------------------------------------------------------------------------
log "Enabling RPM Fusion (free + nonfree)"
if [ -n "$FEDORA_VER" ]; then
  sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm" \
    || warn "RPM Fusion setup failed — continuing"
fi

# ---------------------------------------------------------------------------
log "Enabling Flathub"
flatpak remote-add --if-not-exists flathub \
  https://flathub.org/repo/flathub.flatpakrepo || warn "Could not add Flathub remote"

# ---------------------------------------------------------------------------
log "Installing dnf packages from packages.txt"
# Install one-by-one so a single unknown/renamed package name doesn't abort the
# whole run; collect and report any failures at the end.
PKG_FAILURES=()
while IFS= read -r line; do
  pkg="${line%%#*}"; pkg="$(echo "$pkg" | xargs)"   # strip comments + whitespace
  [ -z "$pkg" ] && continue
  if ! sudo dnf install -y "$pkg"; then
    warn "failed to install: $pkg"
    PKG_FAILURES+=("$pkg")
  fi
done < packages.txt

# ---------------------------------------------------------------------------
log "Installing flatpaks from flatpaks.txt"
while IFS= read -r line; do
  app="${line%%#*}"; app="$(echo "$app" | xargs)"
  [ -z "$app" ] && continue
  flatpak install -y --noninteractive flathub "$app" || warn "failed flatpak: $app"
done < flatpaks.txt

# ---------------------------------------------------------------------------
log "Installing JetBrainsMono Nerd Font"
# The i3 config + .Xresources expect 'JetBrainsMono NFM' (Nerd Font Mono),
# which is not in Fedora repos.
FONT_DIR="$HOME/.local/share/fonts/JetBrainsMono"
if [ -d "$FONT_DIR" ] && ls "$FONT_DIR"/*.ttf >/dev/null 2>&1; then
  echo "JetBrainsMono Nerd Font already present — skipping"
else
  tmp="$(mktemp -d)"
  if curl -fL --retry 3 -o "$tmp/JetBrainsMono.zip" \
      https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip; then
    mkdir -p "$FONT_DIR"
    unzip -o "$tmp/JetBrainsMono.zip" -d "$FONT_DIR" >/dev/null
    fc-cache -f "$HOME/.local/share/fonts"
  else
    warn "Font download failed — install JetBrainsMono Nerd Font manually"
  fi
  rm -rf "$tmp"
fi

# ---------------------------------------------------------------------------
log "Stowing dotfile packages"
# Every top-level directory is a stow package (.git is hidden so it's skipped).
for dir in */; do
  name="${dir%/}"
  stow -v -R -t "$HOME" "$name" || warn "stow failed for: $name (existing file conflict?)"
done

# ---------------------------------------------------------------------------
# Optional: 1Password (proprietary, from its own RPM repo). Uncomment to enable.
# log "Installing 1Password from official repo"
# sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc
# sudo sh -c 'echo -e "[1password]\nname=1Password Stable Channel\nbaseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://downloads.1password.com/linux/keys/1password.asc" > /etc/yum.repos.d/1password.repo'
# sudo dnf install -y 1password 1password-cli

# ---------------------------------------------------------------------------
log "Done."
if [ "${#PKG_FAILURES[@]}" -gt 0 ]; then
  warn "These packages failed to install (verify names with 'dnf provides'):"
  printf '  - %s\n' "${PKG_FAILURES[@]}"
fi

cat <<'NOTE'

Remaining manual steps (see FEDORA_MIGRATION.md):
  - Enroll fingerprint: fprintd-enroll  &&  sudo authselect enable-feature with-fingerprint
  - 1Password: uncomment the block above (or install its RPM repo) for system-auth unlock
  - Add a polkit agent + gnome-keyring to the i3 config so 1Password unlock works
  - Copy back un-tracked secrets: ~/.ssh, .env files, ~/.aws, tokens, etc.
  - Place custom wallpaper at /usr/share/backgrounds/speed.png
NOTE
