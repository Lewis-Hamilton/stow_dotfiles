# Dotfiles

GNU Stow packages and Fedora workstation setup for this account. Run
`~/.mega_setup.sh` after cloning and stowing `my_os` to install the normal
user-level setup.

## Battery health history

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

## Laptop suspend, then hibernate

The hibernation setup is a system-level addition and is not installed by the
Stow packages. It was added to prevent an `s2idle`-only laptop from exhausting
its battery during a long lid-close suspend.

Configured behavior:

- Closing the lid while undocked starts `suspend-then-hibernate`.
- The laptop hibernates after 12 hours on battery.
- The 12-hour countdown does not run while connected to AC power.
- Closing the lid while docked is ignored.

These instructions are for Fedora with systemd, a Btrfs root filesystem, and
an encrypted root volume. Do not copy the resume UUID or offset from another
computer: both values are machine-specific.

### 1. Check the target laptop

```bash
findmnt -no FSTYPE /
cat /sys/power/state
cat /sys/power/mem_sleep
free -h
df -h /
```

Continue only when the root filesystem is `btrfs`, `/sys/power/state` includes
`disk`, and there is enough free space for a swap file slightly larger than
installed RAM. If `mem_sleep` contains only `[s2idle]`, hibernation is
particularly useful for multi-day sleep.

### 2. Create persistent disk swap

This example rounds installed RAM up to GiB and adds 4 GiB. The swap file is
inside the encrypted root volume, so the hibernation image remains encrypted.

```bash
hibernate_mem_kib=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
hibernate_swap_gib=$(( (hibernate_mem_kib + 1048575) / 1048576 + 4 ))

sudo btrfs subvolume create /swap
sudo chmod 700 /swap
sudo btrfs filesystem mkswapfile \
  --size "${hibernate_swap_gib}G" \
  /swap/hibernate.swap
sudo chmod 600 /swap/hibernate.swap
sudo swapon /swap/hibernate.swap
```

Add this line to `/etc/fstab` exactly once:

```fstab
/swap/hibernate.swap none swap defaults,pri=0 0 0
```

The low priority keeps Fedora's zram swap preferred during normal use.

### 3. Configure resume and rebuild the initramfs

```bash
hibernate_resume_device=$(findmnt -no SOURCE /)
hibernate_resume_device=${hibernate_resume_device%%[*}
hibernate_resume_uuid=$(sudo blkid -s UUID -o value "$hibernate_resume_device")
hibernate_resume_offset=$(sudo btrfs inspect-internal map-swapfile -r /swap/hibernate.swap)

sudo install -d -m 755 /etc/dracut.conf.d
printf '%s\n' 'add_dracutmodules+=" resume "' | \
  sudo tee /etc/dracut.conf.d/60-hibernate-resume.conf >/dev/null

sudo grubby --update-kernel=ALL --remove-args='resume resume_offset'
sudo grubby --update-kernel=ALL \
  --args="resume=UUID=$hibernate_resume_uuid resume_offset=$hibernate_resume_offset"
sudo dracut --regenerate-all --force
```

Use `btrfs inspect-internal map-swapfile`; the offset reported by `filefrag` is
not the correct Btrfs resume offset. See the
[Btrfs hibernation documentation](https://btrfs.readthedocs.io/en/latest/ch-swapfile.html).

### 4. Configure lid handling and the 12-hour fallback

Create `/etc/systemd/logind.conf.d/60-lid-suspend-then-hibernate.conf`:

```ini
[Login]
HandleLidSwitch=suspend-then-hibernate
HandleLidSwitchDocked=ignore
```

Create `/etc/systemd/sleep.conf.d/60-suspend-then-hibernate.conf`:

```ini
[Sleep]
HibernateDelaySec=12h
HibernateOnACPower=no
```

The fixed timer is used because ACPI battery alarms are firmware-dependent and
did not wake the Dell XPS 15 9520 reliably.

### 5. Reboot, verify, and test

Reboot before relying on hibernation. Then verify:

```bash
cat /proc/swaps
systemd-analyze cat-config systemd/logind.conf
systemd-analyze cat-config systemd/sleep.conf
sudo grubby --info=ALL
sudo lsinitrd -m "/boot/initramfs-$(uname -r).img" | grep resume
```

Save open work before the first test, disconnect docks and AC power, then run:

```bash
systemctl hibernate
```

Power the laptop back on and confirm that the previous session resumes. Only
after direct hibernation succeeds should `suspend-then-hibernate` be trusted.

### Rollback

Remove the two systemd drop-ins, remove the resume arguments with `grubby`, and
rebuild the initramfs. Then run `swapoff /swap/hibernate.swap`, remove its
`/etc/fstab` entry, and delete the swap file. Reboot to restore Fedora's default
lid behavior.
