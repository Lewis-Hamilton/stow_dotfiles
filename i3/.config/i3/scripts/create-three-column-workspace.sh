#!/usr/bin/env bash

set -euo pipefail

fail() {
    printf '%s\n' "$1" >&2
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "i3 three-column layout" "$1"
    fi
    exit 1
}

workspace_name="$({
    i3-msg -t get_workspaces |
        jq -er '.[] | select(.focused) | .name'
})"

tree="$(i3-msg -t get_tree)"
workspace_id="$({
    jq -er --arg workspace "$workspace_name" \
        '.. | objects | select(.type? == "workspace" and .name? == $workspace) | .id' \
        <<<"$tree"
})"

mark_prefix="threecol_${workspace_id}"
if jq -e --arg workspace "$workspace_name" --arg prefix "${mark_prefix}_" '
    [
        .. | objects
        | select(.type? == "workspace" and .name? == $workspace)
        | .. | objects | (.marks? // [])[]
        | select(startswith($prefix))
    ]
    | length > 0
' <<<"$tree" >/dev/null; then
    fail "This workspace already has a three-column layout."
fi

mapfile -t window_ids < <(
    jq -er --arg workspace "$workspace_name" '
        .. | objects
        | select(.type? == "workspace" and .name? == $workspace)
        | .. | objects
        | select(.window? != null and .floating? == "auto_off")
        | .id
    ' <<<"$tree"
)

((${#window_ids[@]} > 0)) || fail "Open at least one tiled window before creating the layout."

focused_id="$({
    jq -er --arg workspace "$workspace_name" '
        .. | objects
        | select(.type? == "workspace" and .name? == $workspace)
        | .. | objects
        | select(.window? != null and .floating? == "auto_off" and .focused? == true)
        | .id
    ' <<<"$tree" 2>/dev/null
})" || focused_id="${window_ids[0]}"

focused_index=0
for index in "${!window_ids[@]}"; do
    if [[ "${window_ids[$index]}" == "$focused_id" ]]; then
        focused_index=$index
        break
    fi
done

left_id=""
right_id=""

if ((${#window_ids[@]} == 2)); then
    other_index=$((1 - focused_index))
    if ((other_index < focused_index)); then
        left_id="${window_ids[$other_index]}"
    else
        right_id="${window_ids[$other_index]}"
    fi
elif ((${#window_ids[@]} >= 3)); then
    for id in "${window_ids[@]}"; do
        [[ "$id" == "$focused_id" ]] && continue
        if [[ -z "$left_id" ]]; then
            left_id="$id"
        else
            right_id="$id"
        fi
    done
fi

left_mark="${mark_prefix}_left"
center_mark="${mark_prefix}_center"
right_mark="${mark_prefix}_right"
left_placeholder="${left_mark}_placeholder"
center_placeholder="${center_mark}_placeholder"
right_placeholder="${right_mark}_placeholder"

layout_file="$(mktemp --tmpdir three-column-layout.XXXXXX.json)"
trap 'rm -f "$layout_file"' EXIT

jq -n \
    --arg left "$left_mark" \
    --arg center "$center_mark" \
    --arg right "$right_mark" \
    --arg left_placeholder "$left_placeholder" \
    --arg center_placeholder "$center_placeholder" \
    --arg right_placeholder "$right_placeholder" '
    {
        layout: "splith",
        type: "con",
        nodes: [
            {
                layout: "splith",
                marks: [$left],
                percent: 0.25,
                type: "con",
                nodes: [{
                    marks: [$left_placeholder],
                    name: "left 25% — next window",
                    type: "con",
                    swallows: [{class: "^.*$"}]
                }]
            },
            {
                layout: "tabbed",
                marks: [$center],
                percent: 0.5,
                type: "con",
                nodes: [{
                    marks: [$center_placeholder],
                    name: "center 50%",
                    type: "con",
                    swallows: [{class: "^$"}]
                }]
            },
            {
                layout: "splith",
                marks: [$right],
                percent: 0.25,
                type: "con",
                nodes: [{
                    marks: [$right_placeholder],
                    name: "right 25% — next window",
                    type: "con",
                    swallows: [{class: "^.*$"}]
                }]
            }
        ]
    }
' >"$layout_file"

# Remove any horizontal gap previously applied by the old centered-layout binding.
i3-msg -q "gaps horizontal current set 0"
i3-msg -q "append_layout $layout_file"

if [[ -n "$left_id" ]]; then
    i3-msg -q "[con_id=$left_id] move container to mark $left_mark"
    i3-msg -q "[con_mark=^${left_placeholder}$] kill"
fi

if [[ -n "$right_id" ]]; then
    i3-msg -q "[con_id=$right_id] move container to mark $right_mark"
    i3-msg -q "[con_mark=^${right_placeholder}$] kill"
fi

for id in "${window_ids[@]}"; do
    [[ "$id" == "$left_id" || "$id" == "$right_id" ]] && continue
    i3-msg -q "[con_id=$id] move container to mark $center_mark"
done

i3-msg -q "[con_mark=^${center_placeholder}$] kill"
i3-msg -q "[con_mark=^${center_mark}$] layout tabbed"
i3-msg -q "[con_mark=^${left_mark}$] resize set width 25 ppt"
i3-msg -q "[con_mark=^${center_mark}$] resize set width 50 ppt"
i3-msg -q "[con_mark=^${right_mark}$] resize set width 25 ppt"
i3-msg -q "[con_id=$focused_id] focus"
