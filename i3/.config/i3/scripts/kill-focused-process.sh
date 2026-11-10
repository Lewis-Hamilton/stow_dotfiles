#!/usr/bin/env bash
set -euo pipefail

# Resolve the focused X11 window, then kill only its owning process.
window_id=$(i3-msg -t get_tree | jq -er '.. | objects | select(.focused? == true) | .window // empty')
pid=$(xprop -id "$window_id" _NET_WM_PID | awk '/^_NET_WM_PID\(CARDINAL\) = [0-9]+$/ { print $3 }')

# Missing or invalid PIDs must never become process-group kill arguments.
[[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 1 )) || exit 1
kill -KILL -- "$pid"
