# AGENTS.md

Guidance for coding agents working in `hp-charge-limit`.

## What this project is

A hardware-level battery charge cap for HP laptops that do not expose
`charge_control_end_threshold` or a BIOS battery-care setting. It uses HP's
own WMI charge-mode methods through `acpi_call`.

Tested on:

- HP Laptop 15-ef2xxx, board `887A`, BIOS F.34
- Ubuntu 26.04, kernel 7.0
- GNOME Shell 50.1 on Wayland
- UPower 1.91.1
- `acpi-call-dkms` 1.2.2, Secure Boot disabled

The AC adapter stays connected. The embedded controller (EC) blocks charging
at the cap, so the laptop runs from mains while the battery rests at ~80%.
This is intentionally not an 80 <-> 20 charge-cycle regime.

## Safety rules: read before changing anything

These are not style preferences. Mistakes can leave the battery unable to
charge.

1. **Only `SBCO` inputs `0` and `5` are supported.**
   - `SBCO 0 0 0 0` = auto / charging allowed.
   - `SBCO 0 5 0 0` = inhibit / charging blocked.
2. **Never call `SBCO` with input `6` or `7`.** The DSDT sets EC flags
   `SHPM`/`STOE`; these are ship/storage modes and can leave the battery
   disabled until AC reconnect or a full EC reset.
3. **Do not experiment with arbitrary EC registers or other `SBCO` inputs.**
   The daemon writes only the fixed HP WMI commands documented here.
4. **Do not force discharge or deliberately run the battery down** to test the
   cap. If the battery is above 80%, it simply stops charging where it is.
5. **Preserve the 75/80 hysteresis** unless the user explicitly asks for a
   different policy. It avoids constant 79 <-> 80 mode changes.
6. **The daemon is the source of truth.** The GNOME extension is cosmetic and
   must never perform ACPI calls or change charge state.
7. **Do not replace this with TLP, a kernel charge threshold, or raw EC
   access.** This board exposes neither a kernel threshold nor a BIOS setting;
   HP WMI is the working interface.
8. Treat root actions carefully. Daemon installs, status calls, ACPI writes,
   and service restarts require root. The extension installs per-user and
   must not be installed with `sudo`.

## ACPI mode mapping

The input values for `SBCO` and the values read back from `GBCO` use different
numbering. Do not feed a `GBCO` result back into `SBCO`.

| Operation | Value | Meaning |
|---|---|---|
| `SBCO` input | `0` | auto / charging allowed |
| `SBCO` input | `5` | inhibit / charging blocked |
| `GBCO` readback | `0` | auto |
| `GBCO` readback | `4` | inhibit |

`GBCO` returns a package shaped like:

```text
[0x0, 0x4, {0xMODE, 0xff, 0xFLAGS, 0x00}]
```

The daemon parses the first byte of the inner buffer. Any other readback value
is treated as unexpected and left alone. Do not add automatic correction for
unknown modes.

`/proc/acpi/call` output contains null bytes. Always filter them before command
substitution or parsing. The current implementation is:

```bash
out=$(tr -d '\000' < "$CALL" 2>/dev/null) || return 1
```

Do not revert this to `$(<"$CALL")`; Bash logs a warning every poll and the
parsed value can be corrupted.

## Control policy

Defaults:

- Stop charging at `>= 80%` while AC is online.
- Resume charging at `<= 75%` while AC is online.
- Between 76% and 79%, keep the current mode (hysteresis).
- AC offline: restore auto charging.
- Poll every 20 seconds and correct mode drift.

Environment overrides:

- `HPL_STOP` (default `80`)
- `HPL_START` (default `75`)
- `HPL_POLL` (default `20`)
- `HPL_AC`, `HPL_BAT`, `HPL_CALL`, `HPL_RUNDIR` for testing/custom paths

If defaults change, update the daemon header, README, tests, and this file.

## File map

| Path | Purpose |
|---|---|
| `hp-charge-limit` | Bash daemon; ACPI calls, hysteresis, status/restore |
| `hp-charge-limit.service` | Root systemd unit; restores auto on stop |
| `install.sh` | Installs daemon, unit, module config, docs |
| `uninstall.sh` | Removes daemon and restores auto charging |
| `test-logic.sh` | 15 logic tests using fake ACPI output |
| `extension/` | Optional GNOME Shell 50 desktop indicator |
| `README.md` | User-facing behavior, install, caveats |
| `acpi-call.conf` | Loads `acpi_call` at boot |

Installed locations:

- `/usr/local/sbin/hp-charge-limit`
- `/etc/systemd/system/hp-charge-limit.service`
- `/etc/modules-load.d/acpi-call.conf`
- `~/.local/share/gnome-shell/extensions/hp-charge-limit@zarmeza/`

The installed daemon can lag the repository until `sudo ./install.sh` is run.
Check `stat` or `cmp` before assuming a source fix is live.

## Common commands

```bash
# Logic tests
./test-logic.sh

# Install/update the root daemon (must be run by the user with sudo)
sudo ./install.sh

# Live status
sudo /usr/local/sbin/hp-charge-limit --status

# Service logs and state
journalctl -u hp-charge-limit.service -f
systemctl status hp-charge-limit.service --no-pager

# Manual recovery if charging is stuck off
sudo modprobe acpi_call
echo '\_SB.WMID.SBCC 0 0 0 0' | sudo tee /proc/acpi/call
echo '\_SB.WMID.SBCO 0 0 0 0' | sudo tee /proc/acpi/call
```

`ExecStopPost` runs `--restore`, so stopping the service intentionally restores
auto charging. That is expected, not a bug.

## GNOME extension

The extension exists because GNOME 50 only uses its
`battery-level-N-plugged-in-symbolic` icon when UPower reports both:

```text
State === PENDING_CHARGE
ChargeThresholdEnabled === true
```

This laptop has no kernel charge threshold, so UPower reports
`pending-charge` but `ChargeThresholdEnabled=false`. GNOME therefore shows a
plain battery even though AC is connected and charging is deliberately paused.

The extension patches the live `PowerToggle._sync()` so that:

- `pending-charge` + AC online shows `battery-level-N-plugged-in-symbolic`.
- Quick Settings shows the subtitle `Plugged in · charging paused`.
- The accessible name describes the paused state.
- The same indicator is used on the lock screen.

Implementation notes:

- UUID: `hp-charge-limit@zarmeza`
- Session modes: `user`, `unlock-dialog`
- AC is read from UPower line-power devices. Do not use
  `DisplayDevice.Online`; it is false even when plugged in on this machine.
- `PowerToggle` in GNOME 50 does not own the subtitle/accessibility text, so
  the extension must clear/restore its custom values when pausing ends and on
  `disable()`.
- GJS on this system does **not** provide `String.prototype.format`. Use
  `.replace('{placeholder}', value)` or a template literal instead.
- GNOME only scans extension directories at login. `gnome-extensions enable`
  fails until the running shell has discovered the new directory. The install
  script queues the UUID in `org.gnome.shell enabled-extensions` so it loads on
  the next login.
- The generic subtitle is intentional. An exact "limit 80%" label would
  require the daemon to publish its configured cap in a state file.

## Design constraints

- Keep the extension purely cosmetic. If it breaks, the cap must still work.
- Keep the root daemon independent of the desktop session.
- Preserve `set -uo pipefail` in the daemon. Avoid adding `set -e`; a transient
  read or ACPI failure should cause a retry, not terminate the service.
- Keep the service's `ExecStopPost` restore behavior.
- Do not assume the extension API is stable; it depends on private GNOME Shell
  internals. Re-check `ui/status/system.js` and `ui/quickSettings.js` when
  updating GNOME.
- `acpi-call-dkms` must rebuild after kernel updates. If it fails to build, the
  service cannot control charging and the EC keeps its last mode.
- The EC mode can persist into Windows on dual-boot systems.

## Validation

Before finishing a change:

```bash
./test-logic.sh
bash -n hp-charge-limit install.sh uninstall.sh test-logic.sh
bash -n extension/install.sh extension/uninstall.sh
python3 -m json.tool extension/metadata.json >/dev/null

tmp=$(mktemp --suffix=.mjs)
cp extension/extension.js "$tmp"
node --check "$tmp"
rm -f "$tmp"
```

For extension state after login:

```bash
gnome-extensions info hp-charge-limit@zarmeza
gsettings get org.gnome.shell enabled-extensions
journalctl --user -b -o cat /usr/bin/gnome-shell | grep hp-charge-limit
```

Do not probe unknown ACPI modes on real hardware. Use `HPL_LIB_ONLY=1` and a
fake `HPL_CALL` file for parser/logic tests.

<!-- carrot-handoff:begin -->
## Handoff notes

This repository uses zanoria to carry a task between agent tools.
The note is `.carrot.md`, committed to this repository.

Before starting work here, run `zanoria load`. If a note exists it
describes work already in progress: read it, follow its `Next action`, and
do not re-derive what its `Decisions` section already settled.

Before you finish, run `zanoria save "<one-line task>"` and then
fill in `Tried and failed` and `Decisions` by hand. The tool can record the
git state; it cannot know what you tried.

Two things to leave alone. `State` is machine-derived and regenerates on
every save, so edits to it are lost. And do not add a `##` heading of your
own: only the six canonical headings round-trip in place, so dated or
thematic context belongs under a `###` inside an existing section.

Commit the note. An uncommitted note does not survive a context reset.
<!-- carrot-handoff:end -->
