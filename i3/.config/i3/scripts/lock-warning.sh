#!/usr/bin/env bash

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/lock-settings.sh"

warning_text=${WARNING_MESSAGE//\{seconds\}/$WARNING_SECONDS}

printf -v message \
    "<span size='180%%'>%s</span>" \
    "$warning_text"
        
# xss-lock terminates this process as soon as it sees user activity. Rofi is
# used as the process itself so there is no terminal window underneath it.
exec rofi \
    -e "$message" \
    -markup \
    -theme-str '
        * {
            background-color: transparent;
            text-color: #ffffff;
        }
        
        window {
            fullscreen: true;
            transparency: "real";
            background-color: #000000b8;
            border: 0px;
            border-radius: 0px;
        }
        
        error-message {
            expand: true;
            padding: 0px;
            background-color: transparent;
            text-color: #ffffff;
        }
        
        textbox {
            expand: true;
            horizontal-align: 0.5;
            vertical-align: 0.5;
            background-color: transparent;
            text-color: #ffffff;
        }
    ' 
