# Force a dark GTK theme so GTK + Electron apps (e.g. 1Password) render dark.
export GTK_THEME=Adwaita:dark

# Hand SSH agent duty to gnome-keyring so key passphrases are stored in the
# login keyring and unlocked by PAM. Must be exported here: xinitrc-common
# sources this file (line 20) before deciding whether to start its own
# ssh-agent (line 55), which it only does when SSH_AUTH_SOCK is unset.
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/keyring/ssh"