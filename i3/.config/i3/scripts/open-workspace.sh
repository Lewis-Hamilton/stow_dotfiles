#!/usr/bin/env bash
# Switch to a numbered workspace and prompt for a name only when it is new.
set -euo pipefail

number=$1
default_name=$2
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

if i3-msg -t get_workspaces |
    jq -e --argjson number "$number" 'any(.[]; .num == $number)' > /dev/null; then
    existed=true 
else
    existed=false
fi

i3-msg "workspace number \"$default_name\"" > /dev/null

if [[ $existed == false ]]; then
    "$script_dir/rename-workspace.sh"
fi 
