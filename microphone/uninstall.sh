#!/usr/bin/env bash
# Run with: sudo bash microphone/uninstall.sh   (then reboot)
# Once the upstream fix is in your kernel, this local workaround can go.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
rm -f /etc/modprobe.d/minisforum-audio.conf /usr/lib/firmware/hda-minisforum-v3se.fw
limine-mkinitcpio
echo "Removed. Reboot."
