#!/bin/bash
# Run with: sudo bash hibernate/uninstall.sh
set -euo pipefail
[ "$EUID" = 0 ] || { echo "run with sudo"; exit 1; }
rm -f /etc/systemd/sleep.conf.d/v3-hibernate.conf /usr/lib/systemd/system-sleep/v3-hibernate-gpu-apps \
      /usr/lib/systemd/system-sleep/v3-hibernate-cover
swapoff /swap/swapfile 2>/dev/null || true
sed -i '\|^/swap/swapfile |d; \|[[:space:]]/swap[[:space:]]|d' /etc/fstab
systemctl daemon-reload
rm -f /swap/swapfile
umount /swap 2>/dev/null || true
UUID=$(findmnt -no UUID /); TOP=$(mktemp -d)
mount -o subvolid=5 "UUID=$UUID" "$TOP"
[ -d "$TOP/@swap" ] && btrfs subvolume delete "$TOP/@swap"
umount "$TOP"; rmdir "$TOP" /swap 2>/dev/null || true
echo "Removed."
