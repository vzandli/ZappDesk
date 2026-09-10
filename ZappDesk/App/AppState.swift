/*
 * AppState.swift — ZappDesk
 *
 * Central configuration, preferences persistence, switch statistics,
 * and state notifications.
 */

import Foundation
import AppKit

final class AppState {
    static let shared = AppState()

    static let stateDidChangeNotification = Notification.Name("ZappDeskStateDidChange")
    static let switchDidOccurNotification = Notification.Name("ZappDeskSwitchDidOccur")

    private enum Keys {
        static let instantSpaceSwitch     = "instantSpaceSwitch"
        static let instantAppSwitch       = "instantAppSwitch"
        static let instantTrackpadSwipe   = "instantTrackpadSwipe"
        static let transitionSpeed        = "transitionSpeed"
        static let showMenuBarIcon        = "showMenuBarIcon"
        static let showDockIcon           = "showDockIcon"
        static let masterEnabled          = "masterEnabled"
        static let switchesCount          = "confirmedSwitchesCount"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.instantSpaceSwitch:   true,
            Keys.instantAppSwitch:     true,
            Keys.instantTrackpadSwipe: true,
            Keys.transitionSpeed:      1.0,
            Keys.showMenuBarIcon:      true,
            Keys.showDockIcon:         false,
            Keys.masterEnabled:        true,
            Keys.switchesCount:        0,
        ])
    }

    // MARK: - Properties

    var masterEnabled: Bool {
        get { defaults.bool(forKey: Keys.masterEnabled) }
        set {
            defaults.set(newValue, forKey: Keys.masterEnabled)
            notifyChange()
        }
    }

    var instantSpaceSwitchEnabled: Bool {
        get { defaults.bool(forKey: Keys.instantSpaceSwitch) }
        set {
            defaults.set(newValue, forKey: Keys.instantSpaceSwitch)
            notifyChange()
        }
    }

    var instantAppSwitchEnabled: Bool {
        get { defaults.bool(forKey: Keys.instantAppSwitch) }
        set {
            defaults.set(newValue, forKey: Keys.instantAppSwitch)
            notifyChange()
        }
    }

    var instantTrackpadSwipeEnabled: Bool {
        get { defaults.bool(forKey: Keys.instantTrackpadSwipe) }
        set {
            defaults.set(newValue, forKey: Keys.instantTrackpadSwipe)
            notifyChange()
        }
    }

    /// Transition speed: 1.0 = Instant (no animation), lower values interpolate velocity
    var transitionSpeed: Double {
        get { Self.validatedSpeed(defaults.double(forKey: Keys.transitionSpeed)) }
        set {
            defaults.set(Self.validatedSpeed(newValue), forKey: Keys.transitionSpeed)
            notifyChange()
        }
    }

    static func validatedSpeed(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0.1, value)) : 1
    }

    var isInstantSpeed: Bool {
        return transitionSpeed >= 0.95
    }

    var showMenuBarIcon: Bool {
        get { defaults.bool(forKey: Keys.showMenuBarIcon) }
        set {
            defaults.set(newValue, forKey: Keys.showMenuBarIcon)
            notifyChange()
        }
    }

    var showDockIcon: Bool {
        get { defaults.bool(forKey: Keys.showDockIcon) }
        set {
            defaults.set(newValue, forKey: Keys.showDockIcon)
            notifyChange()
        }
    }

    private(set) var switchesCount: Int {
        get { defaults.integer(forKey: Keys.switchesCount) }
        set {
            defaults.set(newValue, forKey: Keys.switchesCount)
        }
    }

    /// Upper-bound estimate; actual savings depend on animation duration and selected speed.
    /// The confirmed counter uses a new key so historical requests are not presented as confirmed.
    var timeSavedSeconds: Double {
        return Double(switchesCount) * 0.75
    }

    var formattedTimeSaved: String {
        let total = Int(timeSavedSeconds)
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 {
            return "\(minutes) min, \(seconds) sec"
        } else {
            return "\(seconds) sec"
        }
    }

    func recordSwitch() {
        DispatchQueue.main.async {
            self.switchesCount += 1
            NotificationCenter.default.post(name: Self.switchDidOccurNotification, object: nil)
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.stateDidChangeNotification, object: nil)
    }
}
