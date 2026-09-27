#!/usr/bin/env bash
# Run with: sudo bash microphone/install.sh   (then reboot)
#
# Internal mic fix for the Realtek ALC245 (subsystem 1f4c:e001, shared with the
# V3 SE, hence the file name): the headset-mic jack pin 0x19 always reads
# "plugged", so the kernel locks capture to the empty jack. The patch firmware
# marks the pin as having no presence detect. Only applied if this machine has
# exactly that codec and pin default.
set -euo pipefail
cd "$(dirname "$0")"
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

hit=
for f in /proc/asound/card*/codec#*; do
  grep -q 'Codec: Realtek ALC245' "$f" || continue
  grep -q 'Subsystem Id: 0x1f4ce001' "$f" || continue
  awk '/^Node /{n=$2} /Pin Default/ && n=="0x19"{print $3}' "$f" | grep -qE '^0x04a19(050|150)' && hit=$f
done
[[ -n $hit ]] || { echo "not the ALC245 1f4c:e001 with the broken jack pin - not applied"; exit 1; }

install -Dm644 hda-minisforum-v3se.fw /usr/lib/firmware/hda-minisforum-v3se.fw
install -Dm644 minisforum-audio.conf  /etc/modprobe.d/minisforum-audio.conf
limine-mkinitcpio
echo "Installed. Reboot, then set Settings -> Sound -> Input volume to about 30 %."
