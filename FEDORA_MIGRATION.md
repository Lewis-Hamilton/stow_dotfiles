# Fedora i3 Migration Notes

Notes for wiping this machine and rebuilding the same i3 setup on a fresh
Fedora install. These dotfiles originated on Fedora i3 (e.g. the `dnf-updates`
i3blocks script), so this is a return to their native target, not a port.

## Fedora platform differences you'll hit first

- **Get the i3 environment**: either install the **Fedora i3 Spin** (ships i3 +
  lightdm preconfigured) or add i3 to Workstation (`sudo dnf install i3 i3status`)
  and pick the session at the login screen. The Spin is closest to "same setup."
- **Enable extra repos immediately**: **RPM Fusion** (free + nonfree) for
  codecs/drivers, and **Flathub** for flatpak (the `flatpak-updates` block uses
  it). Some tools live in **COPR**.
- **SELinux is enforcing** by default (Ubuntu's AppArmor is laxer about home
  scripts). The i3blocks scripts run from `$HOME` so they're fine, but if
  something silently fails, check `sudo ausearch -m avc -ts recent`.
- **PAM is managed by `authselect`**, not Ubuntu's `pam-auth-update`. Matters for
  fingerprint + 1Password below — don't hand-edit `/etc/pam.d` the same way.
- **Audio**: Fedora is PipeWire by default, so the `wpctl`/`pactl` volume binds
  work unchanged.

## Specific concerns

### Fingerprint reader
- `sudo dnf install fprintd fprintd-pam`
- No GNOME settings GUI on i3, so enroll from CLI: `fprintd-enroll`
- Enable in PAM: `sudo authselect enable-feature with-fingerprint`
- **Biggest caveat: hardware support.** Many newer Goodix/Synaptics sensors have
  no `libfprint` driver. Verify the exact sensor (`lsusb`) is supported *before*
  counting on it.

### 1Password unlock via local password / fingerprint
Most likely thing to silently break on i3, for two reasons:
1. It relies on **polkit**, and **i3 does not start a polkit authentication
   agent** (GNOME does it for you). Launch one in the i3 config:
   ```
   exec --no-startup-id /usr/libexec/polkit-gnome-authentication-agent-1
   ```
   (`dnf install polkit-gnome`). Without this, "unlock with system
   authentication" just fails.
2. It uses the **kernel keyring + gnome-keyring**. There's a commented-out
   `gnome-keyring-daemon` exec in the i3 config (around lines 243/245) — on
   Fedora i3 you'll likely need to start it so 1Password (and SSH keys) can store
   secrets. Fingerprint unlock then works *through* fprintd + polkit.
- Install 1Password from its **official RPM repo**, not flatpak, for the
  system-auth + browser integration to work.

### Lock screen
- `i3lock` is in Fedora repos; `i3lock-color` is in COPR. `xss-lock` is packaged.
  The suspend-lock setup ports directly.
- Two fragile bits in the current config:
  - The lock bind uses a **relative path** `Downloads/lockscreen.png` — make it
    absolute.
  - The wallpaper `/usr/share/backgrounds/speed.png` is a custom file you must
    drop back in place.

### Playwright on Fedora
- Known friction: `npx playwright install-deps` **only supports Debian/Ubuntu**
  and errors on Fedora. The browsers themselves run fine; install the system libs
  manually via dnf:
  `nss atk at-spi2-atk cups-libs libdrm gtk3 alsa-lib libXcomposite libXdamage
  libxkbcommon` (etc.).
- Budget time to get the dep list right the first time. Headed mode under i3/X11
  works normally.

### Env files from dev projects
- `.env` files are gitignored, so `git clone` won't bring them back. They migrate
  **only if copied manually** (or via Syncthing, which is already running —
  consider adding project dirs / a secrets folder to a Syncthing share *before*
  wiping).
- Same goes for: `~/.ssh` keys (the git signing key!), `~/.aws`, `~/.config/gh`,
  GPG keyring, `~/.npmrc` tokens, `direnv` `.envrc` files, local DB volumes/certs.
  None of these are in the dotfiles repo by design.

## Programs from these dotfiles — Fedora availability

All in Fedora repos / RPM Fusion (names mostly identical): `picom`, `rofi`,
`feh`, `flameshot`, `dunst`, `brightnessctl`, `syncthing`, `dex` (the
`dex-autostart`), `autorandr`, `arandr`, `xmodmap` (in `xorg-x11-server-utils`),
`rxvt-unicode` (urxvt). The `dnf-updates` i3blocks script is already
Fedora-native, so it starts working again.

**Fonts**: `JetBrainsMono NFM` (Nerd Font Mono) is **not** in Fedora repos —
reinstall it manually into `~/.local/share/fonts`, or via a Nerd Fonts COPR.

**HiDPI**: the 4K scaling problem is identical on Fedora i3, so the
`Xft.dpi`/`Xcursor.size` work in `xresources/.Xresources` **carries over** —
don't drop it.

## Recommended: capture a bootstrap before wiping

Turn "set up the same" into a repeatable script so a fresh Fedora install is:
install git+stow -> clone -> stow -> run bootstrap.

- A **`packages.txt`** (dnf list) + **`flatpaks.txt`** committed to the repo.
- A short **`bootstrap.sh`** that enables RPM Fusion/Flathub, installs the lists,
  installs the Nerd Font, and `stow`s every package.
- Decide the **canonical branch**: `i3-config-cleanup` is the clean
  Fedora-targeted line; `ubuntu-laptop` only adds the DPI tweaks — which you'll
  *want* on the 4K Fedora box too, so consider merging those DPI commits back
  into the main config rather than stranding them on `ubuntu-laptop`.
- Add the **polkit-agent + gnome-keyring** exec lines to the i3 config so the
  1Password/fingerprint path works on first boot.
