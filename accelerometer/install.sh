#!/usr/bin/env bash
# Run with: sudo bash accelerometer/install.sh   (then reboot)
#
# Builds the accelerometer DSDT override from THIS machine's firmware table
# (see build-dsdt.sh), takes a snapper snapshot, installs the override, the
# acpi_override initramfs hook and the mount-matrix hwdb, and rebuilds the
# initramfs. Remove the override before any BIOS update (uninstall.sh).
set -euo pipefail
cd "$(dirname "$0")"
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

pacman -S --needed --noconfirm acpica iio-sensor-proxy >/dev/null
install -Dm644 61-sensor-minisforum-v3.hwdb /etc/udev/hwdb.d/61-sensor-minisforum-v3.hwdb
systemd-hwdb update

if grep -qsi accel /sys/bus/iio/devices/*/name; then
  echo "accelerometer already present - no DSDT override needed (hwdb installed)"; exit 0
fi
grep -q '\[none\]' /sys/kernel/security/lockdown \
  || { echo "kernel lockdown is on: turn Secure Boot off in the BIOS first"; exit 1; }

w=$(mktemp -d)
cat /sys/firmware/acpi/tables/DSDT > "$w/firmware-dsdt.dat"
bash ./build-dsdt.sh "$w/firmware-dsdt.dat" "$w/build"

if command -v snapper >/dev/null; then
  snapper -c root create -d "before accelerometer DSDT override"
  command -v limine-snapper-sync >/dev/null && limine-snapper-sync >/dev/null 2>&1 || :
  echo "snapshot taken - bootable from Limine -> Snapshots if the override misbehaves"
fi

install -Dm644 "$w/build/dsdt.aml"       /etc/initcpio/acpi_override/minisforum_v3_dsdt.aml
install -Dm644 "$w/build/dsdt.dat"       /etc/initcpio/acpi_override/src/dsdt.dat.orig
install -Dm644 "$w/build/dsdt.dsl.orig"  /etc/initcpio/acpi_override/src/dsdt.dsl.orig
install -Dm644 "$w/build/dsdt.dsl"       /etc/initcpio/acpi_override/src/dsdt.dsl
if ! grep -qE '^HOOKS=.*acpi_override' /etc/mkinitcpio.conf; then
  cp -n /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak-dsdt
  sed -i -E 's/^HOOKS=\((base systemd)/HOOKS=(\1 acpi_override/' /etc/mkinitcpio.conf
fi
grep -E '^HOOKS=.*acpi_override' /etc/mkinitcpio.conf \
  || { echo "could not add acpi_override after 'base systemd' in HOOKS - add it by hand"; exit 1; }
limine-mkinitcpio
echo "Installed for BIOS $(cat /sys/class/dmi/id/bios_version). Reboot."
