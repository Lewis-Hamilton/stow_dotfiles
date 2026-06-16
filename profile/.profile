# Force a dark GTK theme so GTK + Electron apps (e.g. 1Password) render dark.
export GTK_THEME=Adwaita:dark

# Machine-local environment & secrets (NOT tracked in dotfiles).
# Create ~/.config/shell/secrets.env only on machines that need it (e.g. work).
[ -r "$HOME/.config/shell/secrets.env" ] && . "$HOME/.config/shell/secrets.env"
