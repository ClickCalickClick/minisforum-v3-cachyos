#!/bin/sh
# Run with: sudo sh sleep-wake/install.sh
set -e
cd "$(dirname "$0")"
install -m 755 v3-wake-sources /usr/lib/systemd/system-sleep/v3-wake-sources
# Log the waking IRQ / GPE on every resume, so any remaining wake can be named
echo 'w /sys/power/pm_debug_messages - - - - 1' > /etc/tmpfiles.d/v3-pm-debug.conf
echo 1 > /sys/power/pm_debug_messages
echo "Installed; takes effect on the next sleep, no reboot needed."
echo "After an unexpected wake: journalctl -k -b | grep -iE 'wakeup|GPE'"
