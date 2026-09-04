#!/usr/bin/env bash

# Xorg may replace the core keymap when a keyboard is hot-plugged. Reapply the
# user's modifier map whenever the XInput device hierarchy changes.

set -u

readonly keymap="${HOME}/.Xmodmap"
readonly runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"

# i3 reloads must not leave multiple watchers behind.
exec 9>"${runtime_dir}/i3-keyboard-map-${UID}.lock"
flock --nonblock 9 || exit 0

apply_keymap() {
    xmodmap "$keymap"
}

apply_keymap

# Restart the monitor if the XInput connection is ever interrupted.
while true; do
    xinput test-xi2 --root 2>/dev/null |
        while IFS= read -r line; do
            if [[ "$line" == *HierarchyChanged* ]]; then
                # Give Xorg a moment to finish attaching the new slave device.
                sleep 0.25
                apply_keymap
            fi
        done
    sleep 1
done
