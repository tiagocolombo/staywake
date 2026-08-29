import Foundation

/// The pmset values the app reads and writes. Mirrors the `staywake` /
/// `letsleep` shell functions in ~/.zshrc.
struct PowerSettings {
    /// Global (AC *and* battery) override that keeps the machine up with the
    /// lid closed. This is the setting the menu bar icon reflects.
    var sleepDisabled: Bool

    // AC-power values, shown as detail lines in the menu.
    var sleep: Int?
    var diskSleep: Int?
    var displaySleep: Int?
    var wakeOnNetwork: Bool?

    static let unknown = PowerSettings(sleepDisabled: false, sleep: nil,
                                       diskSleep: nil, displaySleep: nil,
                                       wakeOnNetwork: nil)
}

enum PowerManager {
    static let pmset = "/usr/bin/pmset"
    static let sudo = "/usr/bin/sudo"

    // The four argument vectors below are duplicated verbatim in
    // scripts/staywake.sudoers. sudo matches on the exact argument list, so
    // any edit here must be mirrored there or the passwordless path breaks.
    static let enableArgs: [[String]] = [
        ["-a", "disablesleep", "1"],
        ["-c", "sleep", "0", "disksleep", "0", "womp", "1"],
    ]
    static let disableArgs: [[String]] = [
        ["-a", "disablesleep", "0"],
        ["-c", "sleep", "1", "disksleep", "10"],
    ]

    // MARK: - Reading

    /// Reads just the lid-close override — the only value the icon depends on.
    /// One cheap subprocess, so the poll timer can afford to run often.
    static func readSleepDisabled() -> Bool {
        // `pmset -g` prints " SleepDisabled\t\t1" only when the override is on.
        for line in Shell.run(pmset, ["-g"]).stdout.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2, fields[0].caseInsensitiveCompare("SleepDisabled") == .orderedSame
            else { continue }
            return fields[1] == "1"
        }
        return false
    }

    /// Reads every value the menu displays. Needs no privileges.
    static func read() -> PowerSettings {
        var settings = PowerSettings.unknown
        settings.sleepDisabled = readSleepDisabled()

        // `pmset -g custom` lists Battery Power first, then AC Power. We only
        // care about the AC block, matching `awk '/AC Power:/,0'` in the alias.
        let custom = Shell.run(pmset, ["-g", "custom"])
        var inACBlock = false
        for line in custom.stdout.split(separator: "\n") {
            if line.contains("AC Power:") { inACBlock = true; continue }
            guard inACBlock else { continue }

            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2, let value = Int(fields[1]) else { continue }

            switch fields[0] {
            case "sleep": settings.sleep = value
            case "disksleep": settings.diskSleep = value
            case "displaysleep": settings.displaySleep = value
            case "womp": settings.wakeOnNetwork = (value == 1)
            default: break
            }
        }

        return settings
    }

    // MARK: - Writing

    /// True when the sudoers rule is installed, i.e. pmset can be driven
    /// without a password prompt.
    static var canElevateSilently: Bool {
        Shell.run(sudo, ["-n", "-l", pmset] + enableArgs[0]).succeeded
    }

    /// Applies the on/off preset. Returns nil on success, or a message
    /// describing the first command that failed.
    static func apply(enabled: Bool) -> String? {
        for args in (enabled ? enableArgs : disableArgs) {
            let result = Shell.run(sudo, ["-n", pmset] + args)
            guard result.succeeded else {
                let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return "`pmset \(args.joined(separator: " "))` failed"
                    + (detail.isEmpty ? "." : ":\n\(detail)")
            }
        }
        return nil
    }
}
