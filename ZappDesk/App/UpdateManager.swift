/*
 * UpdateManager.swift — ZappDesk
 *
 * Sparkle 2 integration: background update checks, manual "Check for Updates…",
 * and gentle reminders that respect the menu bar app lifestyle.
 */

import AppKit
import Sparkle

final class UpdateManager: NSObject {
    static let shared = UpdateManager()

    /// Posted on the main thread whenever `canCheckForUpdates` or `pendingUpdateVersion` changes.
    static let statusDidChangeNotification = Notification.Name("ZappDeskUpdateStatusDidChange")

    private let updaterController: SPUStandardUpdaterController
    private let reminders = GentleUpdateReminders()
    private var canCheckObservation: NSKeyValueObservation?
    private var started = false

    /// False while an update session is already in progress.
    private(set) var canCheckForUpdates = false {
        didSet { if canCheckForUpdates != oldValue { notify() } }
    }

    /// A scheduled update found while ZappDesk was in the background. It is surfaced in the
    /// menu bar instead of an alert nobody sees; choosing Check for Updates shows it immediately.
    private(set) var pendingUpdateVersion: String? {
        didSet { if pendingUpdateVersion != oldValue { notify() } }
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set {
            updaterController.updater.automaticallyChecksForUpdates = newValue
            notify()
        }
    }

    /// Without a menu bar item there is nowhere quiet to announce an update, so Sparkle's own
    /// alert is allowed through instead.
    var hasMenuBarPresence: Bool {
        get { reminders.hasMenuBarPresence }
        set { reminders.hasMenuBarPresence = newValue }
    }

    private override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: reminders
        )
        super.init()
        reminders.onPendingUpdateChange = { [weak self] version in
            self?.pendingUpdateVersion = version
        }
        canCheckObservation = updaterController.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
            [weak self] updater, _ in
            DispatchQueue.main.async {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    /// Starts the updater. Safe to call more than once; only the first call has an effect.
    func start() {
        guard !started else { return }
        started = true
        updaterController.startUpdater()
    }

    var currentVersion: String {
        let marketingVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(marketingVersion) (\(build))"
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.statusDidChangeNotification, object: nil)
    }
}

/// Sparkle's gentle-reminder hooks for a menu bar app: a scheduled update is only shown as an
/// alert when ZappDesk already has focus. Otherwise it is recorded so the menu can point at it.
/// Sparkle calls these on the main thread.
private final class GentleUpdateReminders: NSObject, SPUStandardUserDriverDelegate {
    var onPendingUpdateChange: ((String?) -> Void)?
    var hasMenuBarPresence = true

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus || !hasMenuBarPresence
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        onPendingUpdateChange?(update.displayVersionString)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        onPendingUpdateChange?(nil)
    }

    func standardUserDriverWillFinishUpdateSession() {
        onPendingUpdateChange?(nil)
    }
}
