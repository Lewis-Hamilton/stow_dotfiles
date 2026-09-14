#!/bin/bash
# Enable tapping and natural touchpad scrolling without affecting mouse-wheel
# scrolling.

command -v xinput >/dev/null 2>&1 || exit 0

xinput list --short 2>/dev/null \
    | sed -n 's/.*id=\([0-9][0-9]*\).*/\1/p' \
    | while IFS= read -r device_id; do
        # Tapping is exposed by libinput touchpads but not ordinary mice.
        if xinput list-props "${device_id}" 2>/dev/null \
            | grep -q 'libinput Tapping Enabled'; then
            xinput set-prop "${device_id}" 'libinput Tapping Enabled' 1 2>/dev/null
            xinput set-prop "${device_id}" 'libinput Natural Scrolling Enabled' 1 2>/dev/null
        fi
    done