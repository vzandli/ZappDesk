/*
 * EventTap.swift — ZappDesk
 *
 * Feature 1: Instant space switch via CGEvent tap.
 * Intercepts keyboard shortcuts (Move left/right space, direct Switch to Desktop N),
 * swallows the key down, and triggers synthetic high-velocity gestures.
 */

import ApplicationServices
import CoreGraphics
import Foundation

private let kRelevantModifiers: CGEventFlags = [
    .maskControl, .maskCommand, .maskAlternate, .maskShift
]

private var gTap: CFMachPort?
private var gTapSource: CFRunLoopSource?
var gLastSpaceSwitchTime = Date.distantPast

func isKeyboardTapInstalled() -> Bool {
    guard let tap = gTap else { return false }
    return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap)
}

func installKeyboardEventTap() -> Bool {
    if isKeyboardTapInstalled() { return true }
    removeKeyboardEventTap()
    guard AXIsProcessTrusted() else { return false }
    let keyDownMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: keyDownMask,
        callback: keyboardEventTapCallback,
        userInfo: nil
    ), let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
        return false
    }

    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    gTap = tap
    gTapSource = source
    return true
}

func removeKeyboardEventTap() {
    if let tap = gTap { CFMachPortInvalidate(tap) }
    if let source = gTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    gTap = nil
    gTapSource = nil
}

func reviveKeyboardTapIfNeeded() {
    guard AXIsProcessTrusted() else { removeKeyboardEventTap(); return }
    if let tap = gTap, CFMachPortIsValid(tap) {
        if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
    } else {
        _ = installKeyboardEventTap()
    }
}

private func keyboardEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let passthrough = Unmanaged.passUnretained(event)

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = gTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return passthrough
    }

    guard type == .keyDown else { return passthrough }

    let state = AppState.shared
    guard state.masterEnabled, state.instantSpaceSwitchEnabled else {
        return passthrough
    }

    // Preserve native handling if user is dragging a window by mouse
    if CGEventSource.buttonState(.combinedSessionState, button: .left) {
        return passthrough
    }

    let flags   = event.flags
    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
    let eventMods = flags.intersection(kRelevantModifiers)

    // 1. Direct "Switch to Desktop N" (1..16)
    for (idx, binding) in gSpaceKeys.enumerated() {
        guard let binding,
              keycode == binding.keycode,
              eventMods == binding.mods else { continue }

        let desktops = getUserDesktops()
        guard idx < desktops.count else { return passthrough }

        switch switchToSpace(desktops[idx]) {
        case .requested, .busy, .alreadyThere:
            return nil
        case .declined:
            return passthrough
        }
    }

    // 2. Relative "Move left / right a space"
    let direction: Int
    if let b = gBindingLeft, keycode == b.keycode, eventMods == b.mods {
        direction = -1
    } else if let b = gBindingRight, keycode == b.keycode, eventMods == b.mods {
        direction = 1
    } else {
        return passthrough
    }

    let (spaceIDs, currentIdx) = getSpaceList()
    guard currentIdx >= 0 else { return passthrough }

    let targetIdx = currentIdx + direction
    guard targetIdx >= 0, targetIdx < spaceIDs.count else {
        // At the edge: swallow to prevent native bounce animation
        return nil
    }

    return switchToSpace(spaceIDs[targetIdx]) == .declined ? passthrough : nil
}
