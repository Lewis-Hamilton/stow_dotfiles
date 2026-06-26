#!/usr/bin/env bash
# Rename the focused workspace, preserving its number and icon.
# Name scheme is  number:<icon>[ label]   e.g.  "2:󰬻"  or  "2:󰬻 auth"
#   - the leading  N:   is i3's workspace number (keeps $mod+N bindings working)
#   - the first glyph after the colon is the icon (never contains a space)
#   - only the trailing label changes; result is  number:<icon> <new label>

set -euo pipefail

name=$(i3-msg -t get_workspaces | jq -r '.[] | select(.focused).name')

num="${name%%:*}"      # "2"          (everything before the first colon)
disp="${name#*:}"      # "󰬻 auth"     (everything after the first colon)
icon="${disp%% *}"     # "󰬻"          (icon = up to the first space; blank labels have none)

# Result becomes:  number:<icon> <typed name>
# -l caps the label length to keep workspace buttons from getting too wide.
exec i3-input -l 12 -F "rename workspace to \"${num}:${icon} %s\"" -P "Rename: "
