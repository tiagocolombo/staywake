# StayWake

A macOS menu bar app that shows — and toggles — whether the Mac stays awake
with the lid closed. It is a GUI replacement for the `staywake` / `letsleep` /
`wakestatus` shell functions in `~/.zshrc`.

```
⚡  lid closed keeps the Mac awake
⚡̸  lid closed lets the Mac sleep
```

## What it changes

Exactly what the shell functions did — the same four `pmset` invocations:

| | Stay Awake | Let It Sleep |
|---|---|---|
| global override | `pmset -a disablesleep 1` | `pmset -a disablesleep 0` |
| on AC power | `pmset -c sleep 0 disksleep 0 womp 1` | `pmset -c sleep 1 disksleep 10` |

`disablesleep` is **global**, not AC-only: it suppresses sleep on battery too.
Switch back to *Let It Sleep* before travelling, or the Mac will cook in a bag.

## Build

Needs the Swift toolchain from the Command Line Tools. No Xcode, no Apple
Developer account, no signing certificate.

```sh
./build.sh
cp -R dist/StayWake.app /Applications/
open /Applications/StayWake.app
```

## The passwordless helper

`pmset -a disablesleep` requires root, and a GUI app cannot `sudo` silently.
On first toggle the app offers to install a sudoers rule:

```
/etc/sudoers.d/staywake
```

It grants your user the four argument lists in the table above and nothing
else. `sudo` matches a command's full argument list literally, so the rule
cannot be used to run other `pmset` commands, let alone other binaries. The
installer validates the file with `visudo -c` before installing it, so a
malformed rule can never lock you out of `sudo`.

Install or remove it by hand instead, if you prefer:

```sh
sudo ./scripts/install-helper.sh
sudo ./scripts/uninstall-helper.sh
```

Without the rule the app still reads and displays state — only toggling is
blocked.

## Checking state from the terminal

The same binary doubles as a `wakestatus` replacement:

```sh
$ /Applications/StayWake.app/Contents/MacOS/StayWake --status
SleepDisabled:   1 (stays awake with the lid closed)
Sleep:           never
Disk sleep:      never
Display sleep:   10 min
Wake on network: on
Passwordless:    yes
```

## Notes

- The icon polls `pmset` every 5 seconds and refreshes whenever the menu
  opens, so changes made from the terminal or System Settings show up.
- **Launch at Login** uses `SMAppService`, which wants the app to live in
  `/Applications`. Running it from `dist/` may make registration fail.
- The app has no Dock icon (`LSUIElement`); quit it from its own menu.
