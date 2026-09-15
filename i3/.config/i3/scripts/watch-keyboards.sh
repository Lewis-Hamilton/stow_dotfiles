#!/usr/bin/env bash

# Xorg may replace the core keymap when a keyboard is hot-plugged. Poll device
# IDs so hotplug detection does not depend on xinput's piped stdout buffering.

set -u

readonly keymap="${HOME}/.Xmodmap"
readonly runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"

# i3 restarts must not leave multiple watchers behind.
exec 9>"${runtime_dir}/i3-keyboard-map-${UID}.lock"
flock --nonblock 9 || exit 0

apply_keymap() {
    xmodmap "$keymap"
}

# Wait for a stable device list before applying the map. Docks can attach
# several input devices in succession. Retry once on the next stable poll to
# cover a keymap reset that arrives just after device attachment.
last_devices=""
remaining_applies=2
apply_keymap
while true; do
    if devices=$(xinput list --id-only); then
        if [[ "$devices" != "$last_devices" ]]; then
            last_devices="$devices"
            remaining_applies=2
        elif (( remaining_applies > 0 )); then
            if apply_keymap; then
                remaining_applies=$((remaining_applies - 1))
            fi
        fi
    else
        # Reapply after the X connection recovers, even if the IDs are unchanged.
        remaining_applies=2
    fi
    sleep 1
done
