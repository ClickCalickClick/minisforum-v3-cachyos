# Only the power button wakes it (original Minisforum V3)

**Symptom:** the V3 goes to sleep in a bag, then wakes up again on its own
and gets warm. No cover opening, no button press.

**Cause:** the V3 only has s2idle ("modern standby"), and several devices are
allowed to end it. Counting `power/wakeup_active_count` on my machine:

| Wake source | Device | Activations | In a bag |
|---|---|---|---|
| Touchscreen (I2C HID) | `i2c-PNP0C50:00` | 143 | Pressure on the glass from the folded cover |
| Cover / lid switch | `PNP0C0D:00` | 7 | The cover shifts a little |
| Charger | `power_supply/ACAD` | 6 | Plug or power-bank blips |
| Keyboard cover (USB `05af:326a`) | `usb 1-2` | 1 | Keys pressed against the screen |
| Power button | `PNP0C0C:00` | 5 | Keep: this is the one wake we want |

Battery-level changes can't wake it (the battery device has no wakeup
source), so `acpi.ec_no_wakeup=1` isn't needed.

**Fix:** a `systemd-sleep` hook switches off wake for the touchscreen, the lid
switch, the charger and the keyboard cover right **before every sleep**. Doing
it at sleep time rather than in a udev rule matters: the touchscreen's
`power/wakeup` file only appears once its module (`i2c_hid_acpi`) has
probed, and `usbhid` turns wake back on for boot keyboards by itself.

Trade-off: opening the cover no longer wakes it. Open the cover, then press
the power button.

It also turns on `pm_debug_messages`, so if anything else still wakes it, the
kernel log names the IRQ or GPE:

```bash
journalctl -k -b | grep -iE 'wakeup|GPE'
```

## Install / remove

```bash
sudo sh sleep-wake/install.sh      # takes effect on the next sleep
sudo sh sleep-wake/uninstall.sh    # then reboot
```

`install.sh` copies `v3-wake-sources` to `/usr/lib/systemd/system-sleep/` and
writes `/etc/tmpfiles.d/v3-pm-debug.conf`.

## Test it at your desk first

1. Undock (no external monitor or USB receivers), then close the cover. It
   sleeps.
2. Press keys on the folded cover, press on the screen, open the cover. It
   should stay asleep.
3. Press the power button. It wakes.

**If it's still awake in a bag:** check that nothing is holding the lid
switch with `systemd-inhibit --list`. Caffeine's "stay awake when the lid is
closed" option, or an attached external monitor, keeps the machine awake
on purpose.
