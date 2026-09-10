/*
 * AutoFollow.swift — ZappDesk
 *
 * Feature 2: Auto-follow on app activation (Cmd+Tab, Dock click).
 * Detects when an app becomes active on another space and jumps there instantly.
 */

import AppKit
import CoreGraphics
import Foundation

private let kAutoFollowSuppressionWindow: TimeInterval = 0.3
private let kAutoFollowEchoWindow:        TimeInterval = 0.3
private let kAutoFollowClickWindow:       TimeInterval = 0.5

private var gLastFollowedPid:  pid_t = -1
private var gLastFollowedTime: Date  = .distantPast

final class AutoFollowObserver: NSObject {
    static let shared = AutoFollowObserver()

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appActivated(_ note: Notification) {
        let state = AppState.shared
        guard state.masterEnabled, state.instantAppSwitchEnabled, !spaceSwitchSequence.isRunning else { return }

        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        let pid = app.processIdentifier

        // 1. Echo guard: ignore repeated activation of the same PID
        if pid == gLastFollowedPid {
            if Date().timeIntervalSince(gLastFollowedTime) <= kAutoFollowEchoWindow { return }
        } else {
            gLastFollowedPid = -1
        }

        // 2. User navigation guard: ignore if user just switched spaces manually
        guard Date().timeIntervalSince(gLastSpaceSwitchTime) > kAutoFollowSuppressionWindow else {
            return
        }

        // 3. Clicked-window detection: if user just clicked inside an onscreen window, do not navigate away
        let sinceLeftClick = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
        let sinceRightClick = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .rightMouseDown)
        let sinceClick = min(sinceLeftClick, sinceRightClick)

        if sinceClick < kAutoFollowClickWindow && isPointerInsideOnscreenWindow(of: pid) {
            return
        }

        // 4. Determine destination space for the app
        let targetSpace = findSpaceForPid(pid)
        guard targetSpace != 0 else { return }

        if switchToSpace(targetSpace) == .requested {
            gLastFollowedPid  = pid
            gLastFollowedTime = Date()
        }
    }

    private func isPointerInsideOnscreenWindow(of pid: pid_t) -> Bool {
        guard let location = CGEvent(source: nil)?.location,
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else { return false }

        for window in windows {
            guard let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == pid else { continue }

            let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            if alpha <= 0 { continue }

            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let x = (boundsDict["X"] as? NSNumber)?.doubleValue,
                  let y = (boundsDict["Y"] as? NSNumber)?.doubleValue,
                  let w = (boundsDict["Width"] as? NSNumber)?.doubleValue,
                  let h = (boundsDict["Height"] as? NSNumber)?.doubleValue
            else { continue }

            if CGRect(x: x, y: y, width: w, height: h).contains(location) {
                return true
            }
        }
        return false
    }
}
