
#!/bin/bash

# Skip the watcher on machines without native or Flatpak Slack installed.
if ! command -v slack >/dev/null 2>&1; then
    if ! command -v flatpak >/dev/null 2>&1 \
        || ! flatpak info com.slack.Slack >/dev/null 2>&1; then
        exit 0
    fi
fi

set_slack_rule() {
    focused_class=$(
        i3-msg -t get_tree \
            | jq -r '.. | objects | select(.focused? == true) | .window_properties.class // empty' \
            | head -n 1
    )

    if [[ "${focused_class,,}" == "slack" ]]; then
        dunstctl rule slack_focused enable >/dev/null 2>&1
    else
        dunstctl rule slack_focused disable >/dev/null 2>&1
    fi
}

# Suppress Slack's Dunst popups only while a Slack window has keyboard focus.
# Keep one watcher alive across i3 restarts. A duplicate spawned by an i3
# reload still refreshes the rule once before exiting.
exec 9>"${XDG_RUNTIME_DIR}/slack-dunst-focus.lock"
if ! flock -n 9; then
    set_slack_rule
    exit 0
fi

# Dunst is launched through XDG autostart and may still be starting when i3
# launches this watcher.
until dunstctl rules >/dev/null 2>&1; do
    sleep 0.2
done

while true; do
    set_slack_rule
    i3-msg -t subscribe '["window"]' \
        | while IFS= read -r event; do
            if jq -e '.change == "focus"' >/dev/null 2>&1 <<<"${event}"; then
                set_slack_rule
            fi
        done
    sleep 0.2
done