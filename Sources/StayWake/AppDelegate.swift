import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var settings = PowerSettings.unknown

    /// How often to re-read the lid-close override. The state can change from
    /// outside the app (the `staywake` shell function, System Settings), so the
    /// icon polls rather than assuming it is the only writer.
    private let refreshInterval: TimeInterval = 5

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        refresh()
        // The timer only needs the icon to be right; the full read happens when
        // the menu opens, so this stays a single cheap subprocess.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.settings.sleepDisabled = PowerManager.readSleepDisabled()
            self.updateStatusItem()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    // MARK: - State

    private func refresh() {
        settings = PowerManager.read()
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        let symbol = settings.sleepDisabled ? "bolt.fill" : "bolt.slash"
        let label = settings.sleepDisabled
            ? "StayWake: lid closed keeps the Mac awake"
            : "StayWake: lid closed lets the Mac sleep"

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        image?.isTemplate = true
        button.image = image
        // Never leave an invisible item in the menu bar if the symbol is missing.
        button.title = image == nil ? (settings.sleepDisabled ? "AWAKE" : "SLEEP") : ""
        button.toolTip = label
    }

    // MARK: - Menu

    // Rebuilt on every open so the values shown are never stale.
    func menuWillOpen(_ menu: NSMenu) {
        refresh()
        menu.removeAllItems()

        let heading = settings.sleepDisabled ? "Staying awake with the lid closed" : "Sleeping when the lid closes"
        menu.addItem(disabledItem(heading))
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: settings.sleepDisabled ? "Let It Sleep" : "Stay Awake",
            action: #selector(toggleStayAwake),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        for line in detailLines() {
            menu.addItem(disabledItem(line))
        }
        menu.addItem(.separator())

        if !PowerManager.canElevateSilently {
            let install = NSMenuItem(
                title: "Install Passwordless Helper…",
                action: #selector(installHelper),
                keyEquivalent: ""
            )
            install.target = self
            menu.addItem(install)
        }

        let launch = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = launchesAtLogin ? .on : .off
        menu.addItem(launch)

        let quit = NSMenuItem(title: "Quit StayWake", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// The same values `wakestatus` prints, formatted for a menu.
    private func detailLines() -> [String] {
        func minutes(_ value: Int?) -> String {
            guard let value else { return "—" }
            return value == 0 ? "never" : "\(value) min"
        }
        return [
            "SleepDisabled: \(settings.sleepDisabled ? "1" : "0")",
            "Sleep: \(minutes(settings.sleep))",
            "Disk sleep: \(minutes(settings.diskSleep))",
            "Display sleep: \(minutes(settings.displaySleep))",
            "Wake on network: \(settings.wakeOnNetwork.map { $0 ? "on" : "off" } ?? "—")",
        ]
    }

    // MARK: - Actions

    @objc private func toggleStayAwake() {
        let target = !settings.sleepDisabled

        guard PowerManager.canElevateSilently else {
            presentHelperMissingAlert()
            return
        }

        if let failure = PowerManager.apply(enabled: target) {
            alert(style: .warning, title: "Could not change the sleep setting", message: failure)
        }
        refresh()
    }

    @objc private func installHelper() {
        guard let script = Bundle.main.path(forResource: "install-helper", ofType: "sh") else {
            alert(style: .warning,
                  title: "Installer missing",
                  message: "install-helper.sh was not found inside the app bundle.")
            return
        }

        let command = "/bin/bash \(shellQuoted(script)) \(shellQuoted(NSUserName()))"
        let source = "do shell script \(appleScriptQuoted(command)) with administrator privileges"

        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)

        if let errorInfo {
            // -128 is the user cancelling the authentication dialog.
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            if code != -128 {
                let detail = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error."
                alert(style: .warning, title: "Helper installation failed", message: detail)
            }
            return
        }

        alert(style: .informational,
              title: "Passwordless helper installed",
              message: "Toggling no longer asks for your password.\n\n"
                     + "Remove it any time with:\nsudo rm /etc/sudoers.d/staywake")
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchesAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert(style: .warning,
                  title: "Could not change the login item",
                  message: error.localizedDescription
                         + "\n\nThis usually means the app is not in /Applications.")
        }
    }

    private var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Alerts

    private func presentHelperMissingAlert() {
        let response = alert(
            style: .informational,
            title: "Passwordless helper not installed",
            message: "StayWake needs a one-time sudoers rule to run pmset without a password prompt.",
            buttons: ["Install…", "Cancel"]
        )
        if response == .alertFirstButtonReturn { installHelper() }
    }

    @discardableResult
    private func alert(style: NSAlert.Style,
                       title: String,
                       message: String,
                       buttons: [String] = ["OK"]) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        for button in buttons { alert.addButton(withTitle: button) }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    // MARK: - Quoting

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
