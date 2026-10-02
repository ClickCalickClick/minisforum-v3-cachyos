#!/bin/bash
# Set up hibernation on a btrfs root (the power button then hibernates; the
# cover still sleeps). Run with: sudo bash hibernate/install.sh   (or --dry-run)
# Override the swapfile size with SWAP_SIZE=40g.
set -euo pipefail
DRY=0; [ "${1:-}" = --dry-run ] && DRY=1
run() { echo "+ $*"; [ "$DRY" = 1 ] || "$@"; }
[ "$DRY" = 1 ] || [ "$EUID" = 0 ] || { echo "run with sudo (or use --dry-run)"; exit 1; }
cd "$(dirname "$0")"

[ "$(findmnt -no FSTYPE /)" = btrfs ] || { echo "root is not btrfs; this script only handles btrfs"; exit 1; }
UUID=$(findmnt -no UUID /)
RAM_G=$(awk '/MemTotal/ {print int($2 / 1048576) + 1}' /proc/meminfo)
SIZE=${SWAP_SIZE:-$(( (RAM_G + 7) / 8 * 8 ))g}   # RAM rounded up to 8 GiB
echo "root UUID $UUID, RAM ${RAM_G}G, swapfile $SIZE"

# 1. Top-level @swap subvolume (kept out of snapper snapshots of @)
if [ "$DRY" = 1 ]; then
    echo "+ btrfs subvolume create <top level>/@swap   (if missing)"
else
    TOP=$(mktemp -d)
    mount -o subvolid=5 "UUID=$UUID" "$TOP"
    if [ -d "$TOP/@swap" ]; then echo "@swap subvolume exists"; else run btrfs subvolume create "$TOP/@swap"; fi
    umount "$TOP"; rmdir "$TOP"
fi

run mkdir -p /swap
grep -q '[[:space:]]/swap[[:space:]]' /etc/fstab ||
    run sh -c "echo 'UUID=$UUID /swap btrfs subvol=/@swap,defaults,noatime 0 0' >> /etc/fstab"
run systemctl daemon-reload   # pick up the /etc/fstab changes
mountpoint -q /swap || run mount /swap

# 2. Swapfile (NOCOW, made by btrfs itself); its default priority (-1) is below zram's
[ -f /swap/swapfile ] || run btrfs filesystem mkswapfile --size "$SIZE" --uuid clear /swap/swapfile
grep -q '^/swap/swapfile' /etc/fstab ||
    run sh -c "echo '/swap/swapfile none swap defaults 0 0' >> /etc/fstab"
swapon --show=NAME --noheadings | grep -qx /swap/swapfile || run swapon /swap/swapfile

# 3. Power fully off when hibernating (like a shutdown), so the cover's
#    power-button pulse can't turn it back on
run install -Dm644 v3-hibernate-sleep.conf /etc/systemd/sleep.conf.d/v3-hibernate.conf

# 4. Close Vocalinux (a GPU/Vulkan app) across hibernate: amdgpu oopses otherwise
run install -Dm755 v3-hibernate-gpu-apps /usr/lib/systemd/system-sleep/v3-hibernate-gpu-apps

# 5. Re-detect the keyboard cover after resume (its touchpad sometimes stays dead)
run install -Dm755 v3-hibernate-cover /usr/lib/systemd/system-sleep/v3-hibernate-cover

# Resume needs no kernel parameters: systemd stores the swapfile location in
# the HibernateLocation EFI variable and the initramfs 'systemd' hook reads it.
echo
[ "$DRY" = 1 ] && { echo "Dry run: nothing changed."; exit 0; }
busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate
echo "Expect: s \"yes\". Test with: systemctl hibernate"
