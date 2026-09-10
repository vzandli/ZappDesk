/*
 * MenuBarManager.swift — ZappDesk
 *
 * Menu bar status item, dropdown menu matching Space Rabbit layout,
 * live statistics updates, and quick feature toggles.
 */

import AppKit

final class MenuBarManager: NSObject, NSMenuDelegate {
    static let shared = MenuBarManager()

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    // Dynamic menu items
    private var permissionWarningItem:      NSMenuItem!
    private var permissionWarningSeparator: NSMenuItem!
    private var masterToggleItem:           NSMenuItem!
    private var spaceSwitchItem:            NSMenuItem!
    private var appSwitchItem:              NSMenuItem!
    private var swipeItem:                  NSMenuItem!
    private var hotkeyWarningItem: NSMenuItem!
    private var statsItem:                  NSMenuItem!
    private var updateItem:                 NSMenuItem!

    func setup() {
        buildMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshMenu),
            name: GlobalHotkeyManager.statusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshMenu),
            name: UpdateManager.statusDidChangeNotification, object: nil)
        applyVisibility()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshMenu),
            name: AppState.stateDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshMenu),
            name: AppState.switchDidOccurNotification,
            object: nil
        )
    }

    func applyVisibility() {
        let shouldShow = AppState.shared.showMenuBarIcon
        if shouldShow && statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                let img = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "ZappDesk")?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
                img?.isTemplate = true
                button.image = img
            }
            item.menu = menu
            statusItem = item
        } else if !shouldShow && statusItem != nil {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
            }
            statusItem = nil
        }
    }

    private func buildMenu() {
        menu.removeAllItems()
        menu.delegate = self

        // 0. Permission Warning (hidden if already granted)
        permissionWarningItem = NSMenuItem(
            title: "⚠️ Accessibility Permission Needed",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        permissionWarningItem.target = self
        menu.addItem(permissionWarningItem)

        permissionWarningSeparator = NSMenuItem.separator()
        menu.addItem(permissionWarningSeparator)

        hotkeyWarningItem = NSMenuItem(title: "Settings hotkey unavailable — Preferences…",
                                      action: #selector(openPreferences), keyEquivalent: "")
        hotkeyWarningItem.target = self
        menu.addItem(hotkeyWarningItem)

        // 1. Header: ZappDesk Title & Master Toggle
        masterToggleItem = NSMenuItem(title: "ZappDesk: Active", action: #selector(toggleMaster), keyEquivalent: "")
        masterToggleItem.target = self
        menu.addItem(masterToggleItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Configure section
        let configHeader = NSMenuItem(title: "Configure:", action: nil, keyEquivalent: "")
        configHeader.isEnabled = false
        menu.addItem(configHeader)

        spaceSwitchItem = NSMenuItem(title: "Instant Space Switch  ^↔", action: #selector(toggleSpaceSwitch), keyEquivalent: "s")
        spaceSwitchItem.target = self
        menu.addItem(spaceSwitchItem)

        appSwitchItem = NSMenuItem(title: "Instant App Switch  ⌘→|", action: #selector(toggleAppSwitch), keyEquivalent: "f")
        appSwitchItem.target = self
        menu.addItem(appSwitchItem)

        swipeItem = NSMenuItem(title: "Instant Trackpad Swipe", action: #selector(toggleSwipe), keyEquivalent: "t")
        swipeItem.target = self
        menu.addItem(swipeItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Statistics
        let statsHeader = NSMenuItem(title: "Statistics:", action: nil, keyEquivalent: "")
        statsHeader.isEnabled = false
        menu.addItem(statsHeader)

        statsItem = NSMenuItem(title: "0 switches • 0 sec saved", action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        menu.addItem(statsItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Version & Preferences
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let versionItem = NSMenuItem(title: "Version \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Quit
        let quitItem = NSMenuItem(title: "Quit ZappDesk", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        refreshMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenu()
    }

    @objc func refreshMenu() {
        hotkeyWarningItem.isHidden = GlobalHotkeyManager.shared.isRegistered
        let isTrusted = AXIsProcessTrusted()
        permissionWarningItem.isHidden = isTrusted
        permissionWarningSeparator.isHidden = isTrusted

        let state = AppState.shared
        masterToggleItem.title = state.masterEnabled ? "ZappDesk: Active" : "ZappDesk: Paused"
        masterToggleItem.state = state.masterEnabled ? .on : .off

        spaceSwitchItem.state = (state.masterEnabled && state.instantSpaceSwitchEnabled) ? .on : .off
        appSwitchItem.state   = (state.masterEnabled && state.instantAppSwitchEnabled) ? .on : .off
        swipeItem.state       = (state.masterEnabled && state.instantTrackpadSwipeEnabled) ? .on : .off

        statsItem.title = "\(state.switchesCount) confirmed switches • up to \(state.formattedTimeSaved) saved (est.)"

        let updates = UpdateManager.shared
        updateItem.title = updates.pendingUpdateVersion.map { "Update to \($0) Available…" } ?? "Check for Updates…"
        updateItem.isEnabled = updates.canCheckForUpdates
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleMaster() {
        AppState.shared.masterEnabled.toggle()
        refreshMenu()
    }

    @objc private func toggleSpaceSwitch() {
        AppState.shared.instantSpaceSwitchEnabled.toggle()
        refreshMenu()
    }

    @objc private func toggleAppSwitch() {
        AppState.shared.instantAppSwitchEnabled.toggle()
        refreshMenu()
    }

    @objc private func toggleSwipe() {
        AppState.shared.instantTrackpadSwipeEnabled.toggle()
        refreshMenu()
    }

    @objc private func openPreferences() {
        SettingsWindowController.shared.show()
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
