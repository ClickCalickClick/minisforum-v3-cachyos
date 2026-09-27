#!/bin/bash
# check-fixes.sh - verify every Minisforum V3 / CachyOS hardware fix is still in place.
# Run after a system update, a snapper rollback, or whenever something feels off:
#     bash check-fixes.sh
# Exit code 0 = all good, 1 = something needs attention. No root needed.
# See README.md for what each item is and how to restore it.

ok=0; bad=0
pass() { printf '  \033[32mOK\033[0m   %s\n' "$1"; ok=$((ok+1)); }
fail() { printf '  \033[31mFAIL\033[0m %s\n       -> %s\n' "$1" "$2"; bad=$((bad+1)); }
warn() { printf '  \033[33mWARN\033[0m %s\n       -> %s\n' "$1" "$2"; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

hdr "0. Machine"
model="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) $(cat /sys/class/dmi/id/product_name 2>/dev/null), BIOS $(cat /sys/class/dmi/id/bios_version 2>/dev/null)"
[ "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" = V3 ] && pass "$model" \
  || warn "$model" "this kit is for the original V3; the V3 SE has its own repo (minisforum-v3se-cachyos)"

hdr "1. Accelerometer / auto-rotate  [README §1]"
accel=$(grep -l lsm6ds3tr-c_accel /sys/bus/iio/devices/iio:device*/name 2>/dev/null | head -1 | xargs -r dirname)
native=$( [ -n "$accel" ] && readlink -f "$accel" | grep -q 'i2c-SMOCF05:' && echo yes )
if [ -n "$native" ]; then
  pass "kernel supports SMOCF05 natively - no DSDT override needed"
  ls /etc/initcpio/acpi_override/*.aml >/dev/null 2>&1 \
    && warn "a DSDT override is still installed" "no longer needed: sudo bash accelerometer/uninstall.sh"
else
  [ -s /etc/initcpio/acpi_override/minisforum_v3_dsdt.aml ] \
    && pass "override table present: /etc/initcpio/acpi_override/minisforum_v3_dsdt.aml" \
    || fail "override table missing" "sudo bash accelerometer/install.sh, then reboot"
  grep -qE '^HOOKS=\(base systemd acpi_override' /etc/mkinitcpio.conf \
    && pass "acpi_override hook in /etc/mkinitcpio.conf (right after 'base systemd')" \
    || fail "acpi_override hook missing from HOOKS in /etc/mkinitcpio.conf" "re-add it after 'base systemd' (check for a .pacnew), then: sudo limine-mkinitcpio"
  journalctl -k -b --no-pager 2>/dev/null | grep -q "ACPI: Table Upgrade: override \[DSDT" \
    && pass "kernel accepted the DSDT override this boot" \
    || fail "kernel did not load the override this boot" "initramfs may be stale: sudo limine-mkinitcpio && reboot (Secure Boot must be off)"
fi
[ -e /etc/mkinitcpio.conf.pacnew ] && warn "/etc/mkinitcpio.conf.pacnew exists" "merge it by hand (keep the acpi_override hook); never just replace the file"
[ -s /etc/udev/hwdb.d/61-sensor-minisforum-v3.hwdb ] \
  && pass "mount-matrix hwdb present" \
  || fail "hwdb file missing: /etc/udev/hwdb.d/61-sensor-minisforum-v3.hwdb" "sudo bash accelerometer/install.sh"
if [ -n "$accel" ]; then
  pass "accelerometer device present (lsm6ds3tr-c_accel)"
  udevadm info -q property "$accel" 2>/dev/null | grep -q '^ACCEL_MOUNT_MATRIX=-1, 0, 0; 0, -1, 0; 0, 0, -1' \
    && pass "mount matrix applied to the sensor" \
    || fail "mount matrix not applied (rotation will be inverted)" "sudo systemd-hwdb update && sudo udevadm trigger"
else
  fail "no accelerometer in /sys/bus/iio/devices" "see the items above"
fi
systemctl is-active -q iio-sensor-proxy && pass "iio-sensor-proxy running" || warn "iio-sensor-proxy not running" "starts on demand; run 'monitor-sensor' to test"

hdr "2. Internal microphone  [README §2]"
[ -s /usr/lib/firmware/hda-minisforum-v3se.fw ] && grep -q '0x19 0x04a19150' /usr/lib/firmware/hda-minisforum-v3se.fw \
  && pass "patch firmware present: /usr/lib/firmware/hda-minisforum-v3se.fw" \
  || fail "patch firmware missing or altered" "sudo bash microphone/install.sh, reboot"
grep -qs 'patch=hda-minisforum-v3se.fw' /etc/modprobe.d/minisforum-audio.conf \
  && pass "modprobe option present: /etc/modprobe.d/minisforum-audio.conf" \
  || fail "modprobe option missing" "sudo bash microphone/install.sh, reboot"
journalctl -k -b --no-pager 2>/dev/null | grep -q "Applying patch firmware 'hda-minisforum-v3se.fw'" \
  && pass "kernel applied the patch this boot" \
  || fail "kernel did not apply the patch this boot" "check the two items above, then reboot"
card=$(grep -l "ALC245" /proc/asound/card*/codec#0 2>/dev/null | head -1 | sed -E 's#/proc/asound/card([0-9]+)/.*#\1#')
if [ -n "$card" ] && amixer -c "$card" cget name='Capture Source' >/dev/null 2>&1; then
  pass "ALC245 exposes 'Capture Source' (auto-mic disabled) on card $card"
  amixer -c "$card" cget name='Capture Source' | grep -q ': values=0' \
    && pass "Capture Source = Internal Mic" \
    || warn "Capture Source is set to the headset jack" "GNOME Settings -> Sound -> Input -> Internal Microphone"
else
  fail "no 'Capture Source' control - the pin patch is not in effect" "see items above"
fi

hdr "3. Tablet mode, auto-rotate, on-screen keyboard  [README §3]"
if [ -n "$accel" ]; then
  udevadm info -q property "$accel" 2>/dev/null | grep -qx 'IIO_SENSOR_PROXY_TYPE=iio-poll-accel' \
    && pass "iio-sensor-proxy polls the accelerometer (no FIFO interrupt)" \
    || fail "accelerometer uses the FIFO interrupt - rotation can freeze after a suspend" "sudo sh tablet-mode/install.sh"
fi
realsw=$(for ev in /sys/class/input/event*; do case "$(readlink -f "$ev")" in */ID9001:*/gpio-keys*) echo "/dev/input/${ev##*/}";; esac; done | head -1)
if [ -z "$realsw" ]; then
  fail "no ID9001 tablet-mode switch found" "unexpected on a V3: journalctl -k -b | grep -i gpio-keys"
else
  systemctl is-active -q v3-tablet-mode.service \
    && pass "v3-tablet-mode.service running" \
    || fail "v3-tablet-mode.service not running - no tablet mode with the cover detached" "sudo sh tablet-mode/install.sh; journalctl -u v3-tablet-mode -b"
  udevadm info -q property "$realsw" 2>/dev/null | grep -qx 'LIBINPUT_IGNORE_DEVICE=1' \
    && pass "real tablet switch hidden from libinput ($realsw)" \
    || fail "real tablet switch still visible to libinput" "sudo sh tablet-mode/install.sh, then log out/in"
  grep -qs '^N: Name="V3 cover tablet-mode switch"' /proc/bus/input/devices \
    && pass "virtual tablet-mode switch present" \
    || fail "virtual tablet-mode switch missing" "journalctl -u v3-tablet-mode -b"
  lsusb 2>/dev/null | grep -q 05af:326a && cover=attached || cover=detached
  managed=$(gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
    --method org.freedesktop.DBus.Properties.Get org.gnome.Mutter.DisplayConfig PanelOrientationManaged 2>/dev/null)
  case "$cover/$managed" in
    detached/*true*)  pass "cover detached and GNOME is in touch mode (auto-rotate + on-screen keyboard)";;
    detached/*false*) fail "cover detached but GNOME is not in touch mode" "journalctl -u v3-tablet-mode -b";;
    attached/*true*)  warn "cover attached but GNOME is in touch mode" "fine if the cover is folded back; if the letter keys are dead, fold it closed and reopen";;
    attached/*false*) pass "cover attached, laptop mode";;
    *) warn "could not read GNOME's touch-mode state" "run from inside the GNOME session";;
  esac
fi

hdr "4. Package sanity"
for p in acpica iio-sensor-proxy; do
  pacman -Q "$p" >/dev/null 2>&1 && pass "package $p installed" || fail "package $p missing" "sudo pacman -S --needed $p"
done
pn=$(find /etc -name '*.pacnew' 2>/dev/null | wc -l)
[ "$pn" -gt 0 ] && warn "$pn .pacnew file(s) under /etc" "review with 'pacdiff'; merge, don't blindly replace (especially /etc/mkinitcpio.conf)"

printf '\n\033[1mSummary:\033[0m %d OK, %d FAIL\n' "$ok" "$bad"
printf 'Shared setup (fingerprint, Vocalinux, TouchyWeather) is checked by the V3 SE repo'"'"'s check-fixes.sh.\n'
[ "$bad" -eq 0 ]
