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

        settings = PowerManager.read()
        updateStatusItem()

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

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        let symbol = settings.sleepDisabled ? "bolt.fill" : "bolt.slash"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: settings.tooltip)
        image?.isTemplate = true
        button.image = image
        // Never leave an invisible item in the menu bar if the symbol is missing.
        button.title = image == nil ? (settings.sleepDisabled ? "AWAKE" : "SLEEP") : ""
        button.toolTip = settings.tooltip
    }

    // MARK: - Menu

    // Rebuilt on every open so nothing shown is ever stale.
    func menuWillOpen(_ menu: NSMenu) {
        settings = PowerManager.read()
        updateStatusItem()

        let authorized = PowerManager.isAuthorized
        menu.removeAllItems()

        menu.addItem(headingItem(settings.headline))
        menu.addItem(.separator())

        // A pair of checked options reads more clearly than one item whose
        // title flips between two meanings.
        menu.addItem(choiceItem("Stay Awake", selected: settings.sleepDisabled,
                                action: #selector(chooseStayAwake)))
        menu.addItem(choiceItem("Let It Sleep", selected: !settings.sleepDisabled,
                                action: #selector(chooseLetSleep)))

        if !settings.details.isEmpty {
            menu.addItem(.separator())
            let submenu = NSMenu()
            for line in settings.details { submenu.addItem(captionItem(line)) }
            let details = NSMenuItem(title: "On Power Adapter", action: nil, keyEquivalent: "")
            details.submenu = submenu
            menu.addItem(details)
        }

        menu.addItem(.separator())

        if !authorized {
            let setUp = NSMenuItem(title: "Set Up One-Click Switching…",
                                   action: #selector(installSudoersRule),
                                   keyEquivalent: "")
            setUp.target = self
            menu.addItem(setUp)
            menu.addItem(captionItem("Switching asks for your password until then"))
        }

        let launch = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = opensAtLogin ? .on : .off
        menu.addItem(launch)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit StayWake", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// Bold, non-clickable line describing the current state.
    private func headingItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.systemFontSize).bold
        ])
        return item
    }

    /// Small grey explanatory line.
    private func captionItem(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        return item
    }

    private func choiceItem(_ title: String, selected: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = selected ? .on : .off
        return item
    }

    // MARK: - Actions

    @objc private func chooseStayAwake() { setStayAwake(true) }
    @objc private func chooseLetSleep() { setStayAwake(false) }

    private func setStayAwake(_ stayAwake: Bool) {
        guard stayAwake != settings.sleepDisabled else { return }

        guard PowerManager.isAuthorized else {
            offerSudoersRule()
            return
        }

        if let failure = PowerManager.apply(stayAwake: stayAwake) {
            alert(style: .warning, title: "Could not change the sleep setting", message: failure)
        }
        settings = PowerManager.read()
        updateStatusItem()
    }

    @objc private func installSudoersRule() {
        guard let script = Bundle.main.path(forResource: "install-sudoers-rule", ofType: "sh") else {
            alert(style: .warning,
                  title: "Setup script missing",
                  message: "install-sudoers-rule.sh was not found inside the app bundle.")
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
                alert(style: .warning, title: "Setup failed", message: detail)
            }
            return
        }

        alert(style: .informational,
              title: "One-click switching is on",
              message: "Switching no longer asks for your password.\n\n"
                     + "To undo this at any time, run:\nsudo rm /etc/sudoers.d/staywake")
    }

    @objc private func toggleOpenAtLogin() {
        do {
            if opensAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert(style: .warning,
                  title: "Could not change the login item",
                  message: error.localizedDescription
                         + "\n\nThis usually means StayWake is not in your Applications folder.")
        }
    }

    private var opensAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Alerts

    /// Explains, in full, what the one-time setup actually installs. This is
    /// the only privileged thing the app ever does, so it says so plainly
    /// rather than asking for trust.
    private func offerSudoersRule() {
        let response = alert(
            style: .informational,
            title: "One-time setup needed",
            message: """
            Changing this setting requires administrator rights, so macOS would \
            ask for your password every single time you switch.

            To avoid that, StayWake can install a small permission file at \
            /etc/sudoers.d/staywake. It lets your account run exactly four \
            power-management commands — the ones behind Stay Awake and Let It \
            Sleep — and nothing else. No background program is installed.

            You will be asked for your password once, now.

            To undo it later, run:
            sudo rm /etc/sudoers.d/staywake
            """,
            buttons: ["Set Up…", "Not Now"]
        )
        if response == .alertFirstButtonReturn { installSudoersRule() }
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

private extension NSFont {
    var bold: NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask)
    }
}
