# Power button hibernates (original Minisforum V3)

**Symptom:** the V3 goes to sleep in a bag, then wakes up again on its own
and gets warm.

**Cause:** the keyboard cover's magnet only has to move a few centimetres for
the hall sensor to read "opened", and on the V3 opening the cover makes the
hardware pulse the power-button line (AMD GPIO 0) to wake the machine. The
kernel log shows `GPIO 0 is active`, and the power button's (`PNP0C0C`) wake
count goes up, not the lid's. So a slightly shifted cover wakes it from sleep
(s2idle) exactly like pressing the power button, and Linux can't block one
without the other ([sleep-wake/](../sleep-wake/README.md) has the details).

When the V3 is fully **off**, opening and closing the cover does **not** turn
it on. So: press the power button before it goes in the bag, and it
hibernates (powers off like a shutdown) instead of sleeping.

| | Result |
|---|---|
| Close the cover | Sleep (instant wake, as before) |
| Press the power button | **Hibernate**: fully off, the cover can't wake it, apps come back in about 15–20 s |
| Hibernate Power Menu extension | Adds **Hibernate** to the power menu |

## What `install.sh` does

- creates a top-level btrfs subvolume `@swap` (so snapper snapshots of `@`
  don't include it), mounted at `/swap`, with a swapfile the size of RAM
  rounded up to 8 GiB (`btrfs filesystem mkswapfile`, NOCOW). zram stays the
  everyday swap.
- `/etc/systemd/sleep.conf.d/v3-hibernate.conf`: `HibernateMode=shutdown`, so
  it powers off like a shutdown instead of the firmware's S4, which may keep
  wake sources armed.
- two `systemd-sleep` hooks (`/usr/lib/systemd/system-sleep/`) and a smaller
  hibernation image target (`/etc/tmpfiles.d/v3-hibernate-image-size.conf`),
  described below.

Resuming needs no kernel parameters: systemd stores the swapfile's location
in the `HibernateLocation` EFI variable, and the initramfs `systemd` hook
reads it.

The GNOME side is per user:

```bash
gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'hibernate'
```

and, for a menu item, the
[Hibernate Power Menu](https://extensions.gnome.org/extension/10398/hibernate-power-menu/)
extension (GNOME 48–50; I hide its "Hybrid Sleep" item, since hybrid sleep is
a sleep the cover can still wake).

## Three problems found on the way, and the fixes for them

**1. GPU apps crash the kernel after resume (`v3-hibernate-gpu-apps`).**
With [Vocalinux](https://github.com/VocaHQ/vocalinux) running (whisper.cpp
on Vulkan), the kernel oopsed 3 seconds after every resume (2 out of 2), in
the amdgpu/TTM buffer code (`ttm_resource_add_bulk_move` /
`ttm_lru_bulk_move_tail` from `amdgpu_gem_fault` / `amdgpu_cs_ioctl`), and the
machine froze. That's a kernel bug (the same family as
[drm/amd #5907](https://gitlab.freedesktop.org/drm/amd/-/work_items/5907)),
not a Vocalinux one. The hook closes Vocalinux right before hibernating and
starts it again after resuming. Suspend isn't affected, so it only acts on
hibernate.

Something to know if you write a hook like this: `systemd-sleep` **freezes
`user.slice`** before the hooks run and only thaws it after the post hooks
return. So a frozen app only reacts to `SIGKILL`, and the post hook must not
talk to the user session (`runuser`, `systemd-run --user`): it waits for an
answer that can't come, and the desktop stays frozen until the hook times
out. The hook hands the relaunch to a transient system service instead,
which waits for the thaw.

**2. The cover's touchpad sometimes stays dead after resume
(`v3-hibernate-cover`).** The firmware powers the USB cover off, and the
kernel's in-place reset (`usb 1-2: WARN: invalid context state for evaluate
context command`) doesn't always bring the touchpad back. The hook toggles the
cover's USB `authorized` flag after resume, which re-detects it from scratch,
just like reseating it.

**3. Hibernation sometimes fails and the desktop comes straight back
(`v3-hibernate-image-size.conf`).** 6 of 13 attempts ended with `PM:
hibernation: Error -12 creating image` (systemd: "Cannot allocate memory").
The kernel first frees memory down to `/sys/power/image_size` (default 2/5 of
RAM, ~10 GiB here), because the snapshot needs a free page for every page it
saves. That part always worked. But while the devices suspend, after that
point, something allocates another 1–3.5 GiB (most likely amdgpu backing up
the 6 GiB VRAM carve-out of this APU), and nothing can be freed any more. The
journal shows it: "Normal pages needed" is 1–3.5 GiB above "Allocated … pages
for snapshot", and needed + available is the same in every run, so the
attempts that grew the most failed. A 6 GiB target leaves room for that
growth. The cost is more swapping before the snapshot, and a smaller image to
write and read.

## Dual boot: the firmware boots Windows first

After hibernating, the firmware has to boot again, and on my V3 it went
straight to Windows. AMI's "FixedBoot" firmware rewrites `BootOrder` at every
power-on, so `efibootmgr -o` doesn't stick. What worked:

1. `sudo limine-scan`, then pick **Windows Boot Manager**, so Windows is in
   Limine's menu.
2. In the BIOS, Boot page, at the bottom: the per-drive priorities submenu
   ("UEFI NVME Drive BBS Priorities" or similar). Set Boot Option #1 to
   Limine.

## Install / remove

```bash
sudo bash hibernate/install.sh --dry-run   # shows every step, changes nothing
sudo bash hibernate/install.sh
sudo bash hibernate/uninstall.sh
```

## Test

1. With Vocalinux running, press the power button. It powers off.
2. Press it again: Limine, then CachyOS, then your session, with your apps
   still open. The desktop should respond straight away, the touchpad should
   work, and Vocalinux should be back after about 5–10 s.
3. `journalctl -b -o short-precise | grep -E 'froze|thawed|returned from sleep'`:
   `thawed` should come within a second or two of `returned`.
