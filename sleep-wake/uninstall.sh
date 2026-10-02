#!/bin/sh
# Run with: sudo sh sleep-wake/uninstall.sh, then reboot to re-enable the wake sources
set -e
rm -f /usr/lib/systemd/system-sleep/v3-wake-sources /etc/tmpfiles.d/v3-pm-debug.conf
echo 0 > /sys/power/pm_debug_messages
echo "Removed. Reboot to restore the default wake sources."
