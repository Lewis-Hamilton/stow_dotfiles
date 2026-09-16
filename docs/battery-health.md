# Battery health history

At each graphical login, the battery health notification also appends a reading
to `~/.local/state/battery-health/history.tsv` (or
`$XDG_STATE_HOME/battery-health/history.tsv` when configured). The tab-separated
file records a timestamp with timezone, battery name, rounded health percentage,
full-charge capacity, design capacity, and capacity unit. History is retained
across reboots; health measures capacity degradation, not current charge level.

View the history with:

```bash
column -t -s $'\t' "${XDG_STATE_HOME:-$HOME/.local/state}/battery-health/history.tsv"
```

Running `~/.local/bin/notify-battery-health` manually also logs a reading and
shows a notification. Use `--print` to inspect health without writing history
or showing a notification. Logging begins with the next run; previous
notifications are not backfilled.
