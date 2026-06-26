#!/usr/bin/env bash

options="⏻ Shutdown\n Restart\n"

# Get choice from rofi
chosen=$(echo -e "$options" | rofi -dmenu -i -p "Power Menu:" -theme-str 'window {width: 15em;} listview {lines: 2;}')

# Execute command based on choice
case "$chosen" in
    *Shutdown) systemctl poweroff ;;
    *Reboot) systemctl reboot ;;
esac
