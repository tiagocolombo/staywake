# StayWake

A macOS menu bar app that shows — and switches — whether the Mac stays awake
with the lid closed. It replaces the `staywake` / `letsleep` / `wakestatus`
shell functions in `~/.zshrc`.

There is no Dock icon and no window; just a bolt in the menu bar:

| Icon | Meaning |
|---|---|
| filled bolt | closing the lid keeps the Mac awake |
| crossed bolt | closing the lid lets the Mac sleep |

Clicking it opens a menu with **Stay Awake** / **Let It Sleep**, the current
power behaviour in plain English, and a login-item toggle.

## Install

Download or build `StayWake-<version>.dmg`, open it, and drag StayWake onto
Applications.

The app is **ad-hoc signed, not notarized** — there is no paid Apple Developer
certificate behind it. macOS will therefore refuse the first launch. Right-click
StayWake in Applications and choose **Open**, then **Open** again in the dialog;
or approve it under System Settings → Privacy & Security. Once only.

If macOS claims the app is damaged, clear the download flag:

```sh
xattr -dr com.apple.quarantine /Applications/StayWake.app
```

## Build

Needs the Swift toolchain from the Command Line Tools. No Xcode, no Apple
Developer account, no certificate.

```sh
./build.sh      # dist/StayWake.app  (universal: arm64 + x86_64)
./package.sh    # dist/StayWake-1.0.0.dmg
```

`build.sh` compiles one slice per triple and joins them with `lipo`, because
SwiftPM's own `--arch a --arch b` mode needs XCBuild, which ships only with
Xcode.

## What it changes

Exactly what the shell functions did — the same four `pmset` invocations:

| | Stay Awake | Let It Sleep |
|---|---|---|
| global override | `pmset -a disablesleep 1` | `pmset -a disablesleep 0` |
| on AC power | `pmset -c sleep 0 disksleep 0 womp 1` | `pmset -c sleep 1 disksleep 10` |

> [!WARNING]
> `disablesleep` is **global**, not AC-only: it suppresses sleep on battery
> too. Switch back to *Let It Sleep* before travelling, or the Mac will run
> with the lid shut in your bag.

## One-click switching

`pmset -a disablesleep` requires root, and a GUI app cannot `sudo` silently, so
by default macOS asks for your password on every switch.

**Set Up One-Click Switching** in the menu removes that. Despite the wording of
an earlier version, it installs **no background program** — it writes a single
permission file:

```
/etc/sudoers.d/staywake
```

listing the four argument lists in the table above, and nothing else. `sudo`
matches a command's full argument list literally, so the rule cannot be used to
run other `pmset` commands, let alone other binaries. The installer validates
the file with `visudo -c` before installing it, so a malformed rule can never
lock you out of `sudo`.

Do it by hand instead, if you prefer:

```sh
sudo ./scripts/install-sudoers-rule.sh
sudo ./scripts/remove-sudoers-rule.sh
```

Without the rule the app still reads and displays state — only switching is
blocked, and the menu says so.

## From the terminal

The same binary replaces `wakestatus`:

```sh
$ /Applications/StayWake.app/Contents/MacOS/StayWake --status
Staying awake with the lid closed
  Never sleeps when idle
  Screen turns off after 10 min
  Hard disks keep spinning
  Wakes for network access
```

## Uninstall

```sh
rm -rf /Applications/StayWake.app
sudo rm -f /etc/sudoers.d/staywake
```

## Notes

- The icon polls every 5 seconds and re-reads everything when the menu opens,
  so changes made from the terminal or System Settings show up.
- **Open at Login** uses `SMAppService`, which wants the app in `/Applications`.
  Running it from `dist/` may make registration fail.
