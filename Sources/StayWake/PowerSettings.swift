import Foundation

/// The pmset values the app reads and writes. Mirrors the `staywake` /
/// `letsleep` shell functions in ~/.zshrc.
struct PowerSettings {
    /// Global (AC *and* battery) override that keeps the machine up with the
    /// lid closed. This is the setting the menu bar icon reflects.
    var sleepDisabled: Bool

    // Values for the AC-power profile, described in the menu's submenu.
    var sleep: Int?
    var diskSleep: Int?
    var displaySleep: Int?
    var wakeOnNetwork: Bool?

    static let unknown = PowerSettings(sleepDisabled: false, sleep: nil,
                                       diskSleep: nil, displaySleep: nil,
                                       wakeOnNetwork: nil)
}

// MARK: - Plain-English descriptions
//
// The menu and `--status` share this so the wording can never drift between
// them. Nothing here exposes a pmset key name or a raw 0/1 — those mean
// nothing to someone reading a menu.
extension PowerSettings {
    /// One line describing what closing the lid will do right now.
    var headline: String {
        sleepDisabled ? "Staying awake with the lid closed"
                      : "Sleeps when you close the lid"
    }

    /// Short form for the icon's tooltip.
    var tooltip: String {
        sleepDisabled ? "StayWake — lid closed keeps the Mac awake"
                      : "StayWake — lid closed lets the Mac sleep"
    }

    /// Current power behaviour, one sentence per setting. Values that could
    /// not be read are omitted rather than shown as a placeholder.
    var details: [String] {
        var lines: [String] = []

        if let sleep {
            lines.append(sleep == 0 ? "Never sleeps when idle"
                                    : "Sleeps after \(sleep) min idle")
        }
        if let displaySleep {
            lines.append(displaySleep == 0 ? "Screen stays on"
                                           : "Screen turns off after \(displaySleep) min")
        }
        if let diskSleep {
            lines.append(diskSleep == 0 ? "Hard disks keep spinning"
                                        : "Hard disks spin down after \(diskSleep) min")
        }
        if let wakeOnNetwork {
            lines.append(wakeOnNetwork ? "Wakes for network access"
                                       : "Ignores network access while asleep")
        }

        return lines
    }
}

enum PowerManager {
    static let pmset = "/usr/bin/pmset"
    static let sudo = "/usr/bin/sudo"

    // The four argument vectors below are duplicated verbatim in
    // scripts/install-sudoers-rule.sh. sudo matches on the exact argument
    // list, so any edit here must be mirrored there or switching breaks.
    static let stayAwakeArgs: [[String]] = [
        ["-a", "disablesleep", "1"],
        ["-c", "sleep", "0", "disksleep", "0", "womp", "1"],
    ]
    static let letSleepArgs: [[String]] = [
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

    /// True once /etc/sudoers.d/staywake is in place, i.e. the pmset commands
    /// can run without a password prompt.
    static var isAuthorized: Bool {
        Shell.run(sudo, ["-n", "-l", pmset] + stayAwakeArgs[0]).succeeded
    }

    /// Applies the on/off preset. Returns nil on success, or a message
    /// describing the first command that failed.
    static func apply(stayAwake: Bool) -> String? {
        for args in (stayAwake ? stayAwakeArgs : letSleepArgs) {
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
