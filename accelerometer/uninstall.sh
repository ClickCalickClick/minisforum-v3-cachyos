#!/usr/bin/env bash
# Run with: sudo bash accelerometer/uninstall.sh   (then reboot)
# Do this BEFORE a BIOS update; rebuild with install.sh afterwards. The hwdb
# mount matrix stays: it's harmless and also needed once the kernel knows
# SMOCF05 natively.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
rm -f /etc/initcpio/acpi_override/*.aml
# The acpi_override hook fails the initramfs build when it has no tables.
sed -i -E '/^HOOKS=/s/ acpi_override//' /etc/mkinitcpio.conf
grep '^HOOKS=' /etc/mkinitcpio.conf
limine-mkinitcpio
echo "Override removed. Reboot."
