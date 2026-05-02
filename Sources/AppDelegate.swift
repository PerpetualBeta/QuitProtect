import AppKit
import ApplicationServices
import SwiftUI
import ServiceManagement

// MARK: - App Delegate

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    let engine = QuitProtectEngine()
    let updateChecker = JorvikUpdateChecker(repoName: "QuitProtect")

    // Settings (stored properties for @Observable, synced to UserDefaults)
    var quitMode: QuitMode = {
        QuitMode(rawValue: UserDefaults.standard.integer(forKey: "quitMode")) ?? .doublePress
    }() {
        didSet {
            UserDefaults.standard.set(quitMode.rawValue, forKey: "quitMode")
            engine.updateMode(quitMode)
        }
    }

    var holdDuration: Double = {
        UserDefaults.standard.object(forKey: "holdDuration") as? Double ?? 1.0
    }() {
        didSet {
            UserDefaults.standard.set(holdDuration, forKey: "holdDuration")
            engine.updateHoldDuration(holdDuration)
        }
    }

    var doublePressInterval: Double = {
        UserDefaults.standard.object(forKey: "doublePressInterval") as? Double ?? 0.4
    }() {
        didSet {
            UserDefaults.standard.set(doublePressInterval, forKey: "doublePressInterval")
            engine.updateDoublePressInterval(doublePressInterval)
        }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["menuBarPillEnabled": true])
        migrateLegacyPillColorKey()

        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        updateChecker.checkOnSchedule()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Start the engine (permission polling will auto-start when granted)
        engine.start(mode: quitMode, holdDuration: holdDuration, doublePressInterval: doublePressInterval)

        // Poll for isActive to update icon once permission is granted and tap is created
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                self.updateIcon()
                if self.engine.isActive { timer.invalidate() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    // One-shot removal of the user-chosen pill colour key from the old design.
    // The new pill uses fixed grey/light colours; the key is dead weight.
    private func migrateLegacyPillColorKey() {
        let migrated = "didMigratePillColorV2"
        if UserDefaults.standard.bool(forKey: migrated) { return }
        UserDefaults.standard.removeObject(forKey: "menuBarPillColor")
        UserDefaults.standard.set(true, forKey: migrated)
    }

    // MARK: - Icon

    func updateIcon() {
        let symbolName = engine.isActive ? "power.circle.fill" : "power.circle"
        statusItem.button?.image = JorvikMenuBarPill.icon(
            symbolName: symbolName,
            accessibilityDescription: "QuitProtect"
        )
    }

    // MARK: - Dynamic menu (NSMenuDelegate)

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateIcon()

        var actions: [JorvikMenuBuilder.ActionItem] = []

        // Toggle protection
        actions.append(JorvikMenuBuilder.ActionItem(
            title: "Protection Active",
            action: #selector(toggleProtection),
            target: self,
            state: engine.isActive ? .on : .off
        ))

        // Current mode display
        let modeStr = "Mode: \(quitMode.displayName)"
        let modeAttr = NSAttributedString(string: modeStr, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        actions.append(JorvikMenuBuilder.ActionItem(
            title: modeStr,
            action: #selector(noop),
            target: self,
            isEnabled: false,
            attributedTitle: modeAttr
        ))

        // Blocked count
        let countStr = "Quits blocked: \(engine.blockedCount)"
        let countAttr = NSAttributedString(string: countStr, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        actions.append(JorvikMenuBuilder.ActionItem(
            title: countStr,
            action: #selector(noop),
            target: self,
            isEnabled: false,
            attributedTitle: countAttr
        ))

        let built = JorvikMenuBuilder.buildMenu(
            appName: "QuitProtect",
            aboutAction: #selector(openAbout),
            settingsAction: #selector(openSettings),
            target: self,
            actions: actions
        )

        menu.removeAllItems()
        for item in built.items {
            built.removeItem(item)
            menu.addItem(item)
        }
    }

    // MARK: - Actions

    @objc private func toggleProtection() {
        if engine.isActive {
            engine.stop()
        } else {
            engine.start(mode: quitMode, holdDuration: holdDuration, doublePressInterval: doublePressInterval)
        }
        updateIcon()
    }

    @objc private func noop() {}

    // MARK: - About & Settings

    @objc private func openAbout() {
        JorvikAboutView.showWindow(
            appName: "QuitProtect",
            repoName: "QuitProtect",
            productPage: "utilities/quitprotect"
        )
    }

    @objc private func openSettings() {
        let delegate = self
        JorvikSettingsView.showWindow(
            appName: "QuitProtect",
            updateChecker: updateChecker
        ) {
            QuitProtectSettingsContent(delegate: delegate)
        }
    }
}
