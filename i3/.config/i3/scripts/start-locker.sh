#!/usr/bin/env bash

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

. "$script_dir/lock-settings.sh"

if [[ ! $AUTO_LOCK_SECONDS =~ ^[0-9]+$ ]] ||
   [[ ! $WARNING_SECONDS =~ ^[0-9]+$ ]] ||
   (( AUTO_LOCK_SECONDS <= WARNING_SECONDS )); then
    printf 'start-locker: warning must be shorter than lock timeout\n' >&2
    exit 1
fi

warning_after_seconds=$((AUTO_LOCK_SECONDS - WARNING_SECONDS))
monitor_off_seconds=$((AUTO_LOCK_SECONDS + 300))

# X11 signals inactivity after the first value. xss-lock treats the second
# value as the notifier duration and starts i3lock when that cycle expires.
xset s "$warning_after_seconds" "$WARNING_SECONDS"

# Do not let DPMS power off the monitors at the same moment as the lock. Wait
# another five minutes so the warning and lock transition remain visible.
xset dpms 0 0 "$monitor_off_seconds"

# i3 can restart without ending its previous children, so ensure there is only
# one idle watcher before replacing this shell with the new instance.
pkill -x xss-lock || true
exec xss-lock \
    -n "$script_dir/lock-warning.sh" \
    --transfer-sleep-lock \
    -- i3lock -n -c 000000 
