/*
 * AppDelegate.swift — ZappDesk
 *
 * Application lifecycle, system notifications (wake/unlock),
 * activation policy, URL scheme handling, and accessibility onboarding.
 */

import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var axPollTimer: Timer?
    private var lastKnownAXTrusted: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        SwipeDiagnostics.log("launch path=\(Bundle.main.bundlePath) trusted=\(AXIsProcessTrusted()) swipeEnabled=\(AppState.shared.instantTrackpadSwipeEnabled)")
        checkAccessibilityPermissions()
        reloadSystemShortcuts()

        // 1. Feature 1: Instant Space switch event tap
        _ = installKeyboardEventTap()

        // 2. Feature 2: Instant App switch observer
        AutoFollowObserver.shared.start()

        // 3. Feature 3: Instant Trackpad swipe tap
        updateSwipeTap()

        // 4. Global Hotkey (⌥⌘,) to summon settings even when completely hidden
        GlobalHotkeyManager.shared.register()

        // 5. Menu Bar Item
        MenuBarManager.shared.setup()

        // 6. Apply initial Dock & Menu bar visibility
        applyVisibilitySettings()

        // 7. System wake & unlock observers to heal event taps
        registerWakeAndUnlockObservers()

        // 8. Start polling for accessibility permission grant
        startAccessibilityPolling()

        // 9. Sparkle background update checks
        UpdateManager.shared.start()
        NotificationCenter.default.addObserver(self, selector: #selector(configurationChanged),
            name: AppState.stateDidChangeNotification, object: nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "zappdesk" {
            SettingsWindowController.shared.show()
            break
        }
    }

    func applyVisibilitySettings() {
        let state = AppState.shared

        // Dock icon activation policy
        let targetPolicy: NSApplication.ActivationPolicy = state.showDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != targetPolicy {
            NSApp.setActivationPolicy(targetPolicy)
        }

        // Menu bar item visibility
        MenuBarManager.shared.applyVisibility()
        UpdateManager.shared.hasMenuBarPresence = state.showMenuBarIcon
    }

    private func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        lastKnownAXTrusted = isTrusted
        if !isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "ZappDesk needs Accessibility permissions to intercept space switching shortcuts and trackpad swipes for instant transitions.\n\nPlease grant permission in System Settings > Privacy & Security > Accessibility."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Later")

                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private func startAccessibilityPolling() {
        axPollTimer?.invalidate()
        axPollTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollAccessibilityStatus()
        }
        if let timer = axPollTimer { RunLoop.main.add(timer, forMode: .common) }
    }

    @objc private func pollAccessibilityStatus() {
        // There is no public notification for changes to symbolic hotkeys.
        // Refresh off the input callback, including while System Settings is open.
        reloadSystemShortcuts()
        let isTrusted = AXIsProcessTrusted()
        if isTrusted != lastKnownAXTrusted {
            lastKnownAXTrusted = isTrusted
            MenuBarManager.shared.refreshMenu()
        }
        if isTrusted {
            reviveKeyboardTapIfNeeded()
        } else {
            spaceSwitchSequence.cancel()
            removeKeyboardEventTap()
        }
        updateSwipeTap()
    }

    @objc private func configurationChanged() {
        // Stop any remaining steps when a feature is disabled or configuration changes.
        spaceSwitchSequence.cancel()
        updateSwipeTap()
        applyVisibilitySettings()
    }

    func applicationWillTerminate(_ notification: Notification) {
        axPollTimer?.invalidate()
        spaceSwitchSequence.cancel()
        removeKeyboardEventTap()
        removeSwipeTap()
        AutoFollowObserver.shared.stop()
        GlobalHotkeyManager.shared.unregister()
    }

    private func registerWakeAndUnlockObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    @objc private func systemDidWake() {
        spaceSwitchSequence.cancel()
        resetSwipeTracking()
        pollAccessibilityStatus()
    }
}
