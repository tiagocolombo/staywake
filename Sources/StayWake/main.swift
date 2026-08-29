import AppKit

// `StayWake --status` prints what the menu shows and exits — a replacement for
// the `wakestatus` shell function, and the easiest way to check state over SSH.
if CommandLine.arguments.contains("--status") {
    let settings = PowerManager.read()

    print(settings.headline)
    for line in settings.details { print("  \(line)") }
    if !PowerManager.isAuthorized {
        print("  Switching needs your password (one-click setup not run)")
    }
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// Menu bar only: no Dock icon, no app switcher entry.
application.setActivationPolicy(.accessory)
application.run()
