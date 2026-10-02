# Minisforum V3 on CachyOS: hardware fixes

The fixes I needed to get the original **Minisforum V3** tablet fully working
on CachyOS with GNOME: the accelerometer (auto-rotate), the internal
microphone, and tablet mode with the keyboard cover detached (auto-rotate and
the on-screen keyboard). Each one has an install script, an uninstall script,
and an explanation of what was wrong. There is also a fix for the V3 waking up by
itself in a bag (the power button hibernates).

The **V3 SE** is a different machine (different CPU, BIOS, keyboard cover and
no tablet-mode switch) and has its own repo:
[minisforum-v3se-cachyos](https://github.com/ClickCalickClick/minisforum-v3se-cachyos).
Setup that's the same on both (fingerprint login, Vocalinux dictation, the
TouchyWeather and TouchyStats extensions) is documented there.

| | |
|---|---|
| Model | Minisforum **V3** (board HPPAC), BIOS 1.06 (2024-04-16) |
| CPU / GPU | AMD Ryzen 7 8840U / Radeon 780M (Hawk Point) |
| Audio | Realtek ALC245, subsystem **1f4c:e001** (same as the V3 SE) |
| Sensors | ST LSM6DS3TR-C accelerometer/gyro, ACPI ID `SMOCF05` |
| Tablet-mode switch | ACPI `ID9001` (`PNP0C60`), hall sensor on GPIO 5, exposed as `gpio-keys` |
| Keyboard cover | USB `05af:326a` with a real multitouch touchpad |
| Tested with | CachyOS, `linux-cachyos` 7.2.7, GNOME 50.5 (Wayland), libinput 1.32.0, iio-sensor-proxy 3.9, Limine |

## Quick start

Secure Boot must be off (the kernel ignores table overrides otherwise).

```bash
git clone https://github.com/ClickCalickClick/minisforum-v3-cachyos.git
cd minisforum-v3-cachyos
sudo bash accelerometer/install.sh
sudo bash microphone/install.sh
sudo sh tablet-mode/install.sh
sudo bash hibernate/install.sh
```

Reboot, then check everything in one go (also handy after updates):

```bash
bash check-fixes.sh
```

---

## 1. Accelerometer / auto-rotate (`accelerometer/`)

**Symptom:** no `/sys/bus/iio/devices/`, no auto-rotate toggle in GNOME.

**Cause:** the BIOS names the LSM6DS3TR-C `SMOCF05`, an ID the kernel's
`st_lsm6dsx` driver doesn't know (it knows `SMO8B30` for the same chip).

**Fix:** `install.sh` dumps this machine's own DSDT, renames the device to
`SMO8B30`, bumps the table's OEM revision, and loads the result at boot
through the `acpi_override` initramfs hook. It also installs the mount-matrix
hwdb (the sensor is mounted inverted) and takes a snapper snapshot first.

The V3 BIOS has an unrelated device with `_HID "ID9001"`, which the ACPI
compiler rejects (error 6033, IDs must be 7-8 characters). `build-dsdt.sh`
compiles with `iasl -f` to keep it exactly as shipped, accepts that one error
and nothing else, and then checks that the result differs from the stock
table in exactly the three intended lines. On BIOS 1.06 the result is
byte-identical to the override I've been running.

**BIOS updates:** remove the override first (`sudo bash
accelerometer/uninstall.sh`, reboot), update, then run `install.sh` again.
An override built from a different BIOS's table can break boot.

**Upstream:** I've re-sent the kernel patch that adds `SMOCF05` to the
driver. Once it's in your kernel, `check-fixes.sh` will say so and the
override can go; the hwdb file stays.

## 2. Internal microphone (`microphone/`)

**Symptom:** the internal mic records silence.

**Cause:** the headset-mic jack pin (0x19) has no working presence detect and
always reads "plugged", so the kernel locks recording to the empty jack.

**Fix:** a small HDA patch firmware that marks the pin as having no presence
detect, loaded through a modprobe option. After a reboot GNOME shows
"Internal Microphone" as an input; about 30 % input volume works well. The
files are named `v3se` because the V3 SE has the same codec and the same bug.

**Upstream:** sent to the ALSA maintainers:
https://lore.kernel.org/linux-sound/?q=s%3AMinisforum

## 3. Tablet mode, auto-rotate, on-screen keyboard (`tablet-mode/`)

**Symptoms:** with the cover detached there's no auto-rotate and no
on-screen keyboard; after reattaching the cover the letter keys are
sometimes dead; rotation can freeze after a suspend.

**Causes, in short:** the V3's tablet-mode switch only reacts to folding the
cover back, not to detaching it, and GNOME trusts that switch alone; the
switch can stick "on" after a reattach; and the accelerometer's interrupt
can stop firing after a suspend.

**Fix:** a small service that provides a virtual tablet-mode switch, plus two
udev rules. [tablet-mode/README.md](tablet-mode/README.md) has the full
explanation.

## 4. Waking up in a bag: hibernate with the power button (`hibernate/`)

**Symptom:** the V3 sleeps in a bag, then wakes up again on its own and gets
warm.

**Cause:** a cover that shifts a few centimetres reads as "opened", and the
hardware turns opening the cover into a power-button press, so it wakes from
sleep. When the V3 is fully off, the cover can't turn it on.

**Fix:** the power button hibernates (powers off like a shutdown), and the
cover still sleeps as before. It needs two small workarounds: closing
Vocalinux across hibernate (an amdgpu kernel bug), and re-detecting the
keyboard cover after resume. [hibernate/README.md](hibernate/README.md) has
the details, including getting the firmware to boot Limine instead of
Windows.

If you'd rather keep sleep only, [sleep-wake/](sleep-wake/README.md) stops
the touchscreen, charger and keyboard cover waking it, but it can't stop the
cover itself.

## 5. Shared with the V3 SE

Documented in the
[V3 SE repo](https://github.com/ClickCalickClick/minisforum-v3se-cachyos):
fingerprint login (works out of the box, just enroll), Vocalinux dictation,
the TouchyWeather top-bar extension, and the
[TouchyStats](https://github.com/ClickCalickClick/TouchyStats-GNOME) system
monitor. If the desktop ever stutters, `tools/lagprobe.py` (in both repos)
shows what is blocking gnome-shell. The V3 does **not** need the SE's
touchpad disable-while-typing daemon, because the V3 cover has a real
touchpad.
