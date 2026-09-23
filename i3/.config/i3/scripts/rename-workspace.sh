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

# Keep the prompt compact and centered, with no empty results list below it.
if ! label=$(rofi -dmenu -p 'Rename:' -theme-str '
    window { location: center; anchor: center; width: 24em; border: 3px; border-color: #FFFFFF; }
    mainbox { children: [inputbar]; }
' < /dev/null); then
    exit 0
fi

# Cap the label length to keep workspace buttons from getting too wide.
label=${label:0:12}
target="${num}:${icon}"
if [[ -n $label ]]; then
    target+=" $label"
fi

# Quote the target for i3's command parser.
target=${target//\\/\\\\}
target=${target//\"/\\\"}
i3-msg "rename workspace to \"$target\""
