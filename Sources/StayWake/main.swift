import AppKit

// `StayWake --status` prints the same values the menu shows and exits — a
// drop-in replacement for the `wakestatus` shell function, and the easiest way
// to check the pmset parsing without opening the menu.
if CommandLine.arguments.contains("--status") {
    let settings = PowerManager.read()

    func minutes(_ value: Int?) -> String {
        guard let value else { return "unknown" }
        return value == 0 ? "never" : "\(value) min"
    }

    print("SleepDisabled:   \(settings.sleepDisabled ? "1 (stays awake with the lid closed)" : "0 (sleeps when the lid closes)")")
    print("Sleep:           \(minutes(settings.sleep))")
    print("Disk sleep:      \(minutes(settings.diskSleep))")
    print("Display sleep:   \(minutes(settings.displaySleep))")
    print("Wake on network: \(settings.wakeOnNetwork.map { $0 ? "on" : "off" } ?? "unknown")")
    print("Passwordless:    \(PowerManager.canElevateSilently ? "yes" : "no (helper not installed)")")
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// Menu bar only: no Dock icon, no app switcher entry.
application.setActivationPolicy(.accessory)
application.run()
