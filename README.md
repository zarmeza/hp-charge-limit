# hp-charge-limit

Hardware-level 80% charge cap for HP laptops that do not expose one in the
BIOS, using HP's own ACPI charge-mode methods through `acpi_call`.

Tested on: HP Laptop 15-ef2xxx (board `887A`), BIOS F.34, Ubuntu 26.04,
kernel 7.0.

## Why

Consumer HP laptops have no `charge_control_end_threshold` and no BIOS
"Battery Care" option, so TLP and friends do nothing. This board's DSDT,
however, implements HP's WMI charge controls:

| Method | WMI cmd | Purpose |
|---|---|---|
| `GBCC` / `SBCC` | `0x1F` | get/set charge control |
| `GBCO` / `SBCO` | `0x2B` | get/set charge mode |

`SBCO` mode `5` writes EC `BDVO = 0x45` (inhibit), mode `0` writes `0x40`
(auto). `GBCO` reads back `4` for inhibit and `0` for auto. The AC stays
connected: the laptop runs from mains while the battery rests at the cap,
so unlike unplugging at 80% this adds **zero** charge cycles.

## Install

```bash
sudo apt install acpi-call-dkms
sudo ./install.sh
```

## Status

```bash
sudo /usr/local/sbin/hp-charge-limit --status
```

## Desktop indicator (optional)

GNOME 50 has the right icon for this state, but only uses it when UPower
reports `ChargeThresholdEnabled=true`. That flag needs a kernel-level charge
threshold, which this laptop does not expose; the limit lives in the EC via HP
WMI. As a result, GNOME shows a plain battery at 80% even though the charger is
connected and charging is deliberately paused.

The optional extension patches the live GNOME Shell power toggle so that:

- UPower `pending-charge` + AC online shows `battery-level-N-plugged-in-symbolic`
  (green battery with a mains plug) instead of the plain battery icon.
- The quick-settings tile says **"Plugged in · charging paused"**.
- The same indicator is used on the lock screen.

It is cosmetic only: the daemon still owns the 75/80 hysteresis and the ACPI
calls. Install it as your desktop user, without sudo:

```bash
./extension/install.sh
```

If the icon does not change immediately, log out and back in. Remove it with:

```bash
./extension/uninstall.sh
```

## Stop / uninstall

```bash
sudo systemctl stop hp-charge-limit    # restores auto charging
sudo ./uninstall.sh                    # removes everything, restores auto
```

## Behaviour

- AC online, capacity >= 80% -> inhibit charge.
- AC online, capacity <= 75% -> allow charge.
- 76-79% -> keep the current mode (hysteresis, avoids 79<->80 micro-cycles).
- AC offline -> auto.
- The daemon re-reads the mode every 20 s and corrects drift.
- A battery already above 80% is not forced down; it simply stops charging
  where it is. Unplug and use it if you want to bring it to 80%.

## Manual reset

If the service is removed or `acpi_call` fails after a kernel update and the
battery will not charge:

```bash
sudo modprobe acpi_call
echo '\_SB.WMID.SBCC 0 0 0 0' | sudo tee /proc/acpi/call
echo '\_SB.WMID.SBCO 0 0 0 0' | sudo tee /proc/acpi/call
```

A full power-off (hold the button ~10 s) also resets the EC.

## Caveats

- `acpi-call-dkms` must rebuild on kernel updates; if it fails, the service
  cannot start. The EC keeps its last mode until reset (see above).
- The daemon needs root and writes only the two fixed command strings above.
- Should work on other HP boards whose DSDT exposes `GBCO`/`SBCO`, but it is
  only tested on `887A`. Check `sudo grep -a -l GBCO
  /sys/firmware/acpi/tables/DSDT` before assuming.
- If you dual-boot, the EC mode may persist into Windows; HP's own tools or
  the manual reset above will normalise it.
