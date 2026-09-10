/*
 * SwipeIntercept.swift — ZappDesk
 *
 * Feature 3: Instant trackpad gesture interception.
 * Intercepts horizontal multi-finger trackpad swipes and executes
 * an instant switch instead of the native slow slide animation.
 */

import ApplicationServices
import CoreGraphics
import Foundation

private let kGestureDirectionThreshold: Double = 0.05
private let kGestureReversalThreshold:  Double = 0.2

/// Opaque tokens so the shared callback can tell which tap was disabled.
private let kDockTapInfo = UnsafeMutableRawPointer(bitPattern: 0x444F434B)!
private let kGestureTapInfo = UnsafeMutableRawPointer(bitPattern: 0x47535452)!

private var gDockControlTap:       CFMachPort?
private var gDockControlTapSource: CFRunLoopSource?
private var gGestureTap:           CFMachPort?
private var gGestureTapSource:     CFRunLoopSource?

private var gTracedChangedEvent = false
private var gLastSwipeEventTime = Date.distantPast
private var gPendingSwipeGeneration = 0
private var gLastDisableLogTime = Date.distantPast
private var gSuppressedDisableLogs = 0

private var gSwipeTracking:        Bool = false
private var gSwipeIntentDirection: Int = 0
private var gSwipeIntentProgress:  Double = 0.0
/// Set false if the system rejects defaultTap on companion gesture envelopes.
private var gCompanionGestureTapUsable = true

func isSwipeTapInstalled() -> Bool {
    guard let dock = gDockControlTap, let gesture = gGestureTap else { return false }
    return CFMachPortIsValid(dock) && CFMachPortIsValid(gesture)
}

func updateSwipeTap() {
    let state = AppState.shared
    let shouldEnable = state.masterEnabled && state.instantTrackpadSwipeEnabled && AXIsProcessTrusted()
    if shouldEnable {
        reviveSwipeTapIfNeeded()
    } else if isSwipeTapInstalled() {
        removeSwipeTap()
    }
}

private func installSwipeTap() {
    let maskDockControl = CGEventMask(1 << kCGSEventDockControl)
    let maskGesture     = CGEventMask(1 << kCGSEventGesture)

    guard let dcTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: maskDockControl,
        callback: swipeTapCallback,
        userInfo: kDockTapInfo
    ), let dcSource = CFMachPortCreateRunLoopSource(nil, dcTap, 0) else {
        return
    }

    guard let gTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: maskGesture,
        callback: swipeTapCallback,
        userInfo: kGestureTapInfo
    ), let gSource = CFMachPortCreateRunLoopSource(nil, gTap, 0) else {
        CFMachPortInvalidate(dcTap)
        return
    }

    gDockControlTap       = dcTap
    gDockControlTapSource = dcSource
    gGestureTap           = gTap
    gGestureTapSource     = gSource
    gCompanionGestureTapUsable = true

    CFRunLoopAddSource(CFRunLoopGetMain(), dcSource, .commonModes)
    CFRunLoopAddSource(CFRunLoopGetMain(), gSource, .commonModes)

    CGEvent.tapEnable(tap: dcTap, enable: true)
    CGEvent.tapEnable(tap: gTap, enable: false) // Enabled dynamically on Began
    SwipeDiagnostics.log("swipe taps installed")
}

func removeSwipeTap() {
    resetSwipeTracking()
    if let t = gDockControlTap { CFMachPortInvalidate(t) }
    if let t = gGestureTap     { CFMachPortInvalidate(t) }
    if let s = gDockControlTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
    if let s = gGestureTapSource     { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
    gDockControlTap       = nil
    gDockControlTapSource = nil
    gGestureTap           = nil
    gGestureTapSource     = nil
}

func reviveSwipeTapIfNeeded() {
    guard isSwipeTapInstalled() else {
        removeSwipeTap()
        installSwipeTap()
        return
    }
    if gSwipeTracking && Date().timeIntervalSince(gLastSwipeEventTime) > 2 {
        resetSwipeTracking()
    }
    if let dock = gDockControlTap, !CGEvent.tapIsEnabled(tap: dock) {
        CGEvent.tapEnable(tap: dock, enable: true)
    }
    if gCompanionGestureTapUsable, let gesture = gGestureTap,
       CGEvent.tapIsEnabled(tap: gesture) != gSwipeTracking {
        CGEvent.tapEnable(tap: gesture, enable: gSwipeTracking)
    }
}

func resetSwipeTracking() {
    SwipeDiagnostics.log("reset tracking=\(gSwipeTracking)")
    gPendingSwipeGeneration += 1
    endHorizontalSwipeTracking()
}

private func endHorizontalSwipeTracking() {
    gSwipeTracking        = false
    gSwipeIntentDirection = 0
    gSwipeIntentProgress  = 0.0
    if gCompanionGestureTapUsable, let tap = gGestureTap, CGEvent.tapIsEnabled(tap: tap) {
        CGEvent.tapEnable(tap: tap, enable: false)
    }
}

struct SwipeTapRecovery: Equatable {
    var enableDock: Bool
    var enableGesture: Bool
    var markCompanionUnusable: Bool
}

/// Recovery after a CGEvent tap disable. Must never call tapEnable(false) or
/// clear in-flight swipe state: those re-enter this callback and drop the gesture.
func swipeTapRecoveryAfterDisable(
    isGestureTap: Bool,
    tracking: Bool
) -> SwipeTapRecovery {
    if isGestureTap {
        return SwipeTapRecovery(
            enableDock: false,
            enableGesture: false,
            markCompanionUnusable: tracking
        )
    }
    return SwipeTapRecovery(
        enableDock: true,
        enableGesture: false,
        markCompanionUnusable: false
    )
}

private func logTapDisabled(type: CGEventType, isGestureTap: Bool) {
    let now = Date()
    if now.timeIntervalSince(gLastDisableLogTime) < 1 {
        gSuppressedDisableLogs += 1
        return
    }
    let suppressed = gSuppressedDisableLogs
    gSuppressedDisableLogs = 0
    gLastDisableLogTime = now
    let extra = suppressed > 0 ? " suppressed=\(suppressed)" : ""
    SwipeDiagnostics.log(
        "tap disabled type=\(type.rawValue) tracking=\(gSwipeTracking) gestureTap=\(isGestureTap)\(extra)"
    )
}

func neutralizedSwipeEnd(_ event: CGEvent) -> CGEvent? {
    // Hardware events contain additional private records that our serializer
    // does not understand. Never require parsing those records to intercept a
    // swipe. Build a fresh closing event with only the fields Dock needs.
    guard let closing = CGEvent(source: nil) else { return nil }
    closing.location = event.location
    closing.flags = event.flags
    closing.timestamp = event.timestamp
    closing.setIntegerValueField(kCGSEventTypeField, value: kCGSEventDockControl)
    closing.setIntegerValueField(kCGEventGestureHIDType, value: kIOHIDEventTypeDockSwipe)
    closing.setIntegerValueField(kCGEventGestureSwipeMotion, value: kGestureMotionHorizontal)
    closing.setIntegerValueField(kCGEventGesturePhase, value: kCGSGesturePhaseEnded)
    closing.setIntegerValueField(kCGEventGesturePhase2, value: kCGSGesturePhaseEnded)
    closing.setDoubleValueField(kCGEventGestureFlavor, value: Double(kIOHIDGestureFlavorDockPrimary))
    closing.setDoubleValueField(kCGEventGesturePositionX, value: event.getDoubleValueField(kCGEventGesturePositionX))
    closing.setDoubleValueField(kCGEventGesturePositionY, value: event.getDoubleValueField(kCGEventGesturePositionY))
    closing.setDoubleValueField(kCGEventGestureSwipeVelocityX, value: 0)
    closing.setDoubleValueField(kCGEventGestureSwipeVelocityY, value: 0)
    closing.setDoubleValueField(kCGEventGestureSwipeProgress, value: 0)
    guard let augmented = augmentDockSwipeEvent(closing) else { return nil }
    // Serialization does not preserve source user data; stamp after rebuilding.
    markSyntheticGesture(augmented)
    return augmented
}

private func isRightSwipe(_ sign: Double) -> Bool {
    return sign > 0
}

func requestedTravelSign(
    progress: Double,
    lastSign: Int,
    extreme: Double
) -> Int? {
    guard lastSign != 0 else {
        guard abs(progress) >= kGestureDirectionThreshold else { return nil }
        return progress > 0 ? 1 : -1
    }

    let travelBack = (extreme - progress) * Double(lastSign)
    guard travelBack >= kGestureReversalThreshold else { return nil }
    return -lastSign
}

func extendGestureExtreme(
    _ extreme: inout Double,
    towards progress: Double,
    sign: Int
) {
    guard sign != 0, (progress - extreme) * Double(sign) > 0 else { return }
    extreme = progress
}

private func performSwipeSwitch(isRight: Bool) {
    // Preserve a reversal that arrives before the preceding switch is confirmed.
    gPendingSwipeGeneration += 1
    let token = gPendingSwipeGeneration
    let deadline = Date().addingTimeInterval(1.5)
    func attempt() {
        guard token == gPendingSwipeGeneration,
              AppState.shared.masterEnabled, AppState.shared.instantTrackpadSwipeEnabled else { return }
        if spaceSwitchSequence.isRunning {
            if Date() < deadline { DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: attempt) }
            return
        }
        let (spaces, currentIdx) = getSpaceList()
        let targetIdx = currentIdx + (isRight ? 1 : -1)
        guard currentIdx >= 0, spaces.indices.contains(targetIdx) else {
            SwipeDiagnostics.log("swipe boundary/query failure right=\(isRight) index=\(currentIdx) count=\(spaces.count)")
            return
        }
        let result = switchToSpace(spaces[targetIdx])
        SwipeDiagnostics.log("swipe request right=\(isRight) index=\(currentIdx) target=\(targetIdx) result=\(result)")
    }
    attempt()
}

private func swipeTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let passthrough = Unmanaged.passUnretained(event)

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        let isGestureTap = userInfo == kGestureTapInfo
        logTapDisabled(type: type, isGestureTap: isGestureTap)
        let recovery = swipeTapRecoveryAfterDisable(
            isGestureTap: isGestureTap,
            tracking: gSwipeTracking
        )
        if recovery.markCompanionUnusable {
            gCompanionGestureTapUsable = false
        }
        if recovery.enableDock, let dock = gDockControlTap {
            CGEvent.tapEnable(tap: dock, enable: true)
        }
        if recovery.enableGesture, let gesture = gGestureTap {
            CGEvent.tapEnable(tap: gesture, enable: true)
        }
        return passthrough
    }

    // Ignore synthetic events generated by ZappDesk
    if isSyntheticGesture(event) {
        return passthrough
    }

    let state = AppState.shared
    guard state.masterEnabled, state.instantTrackpadSwipeEnabled else {
        return passthrough
    }

    let eventType = event.getIntegerValueField(kCGSEventTypeField)
    guard eventType == kCGSEventDockControl || eventType == kCGSEventGesture else {
        return passthrough
    }

    // Swallowing companion gesture envelopes during active tracking so Dock doesn't see half a gesture
    if eventType == kCGSEventGesture {
        return gSwipeTracking ? nil : passthrough
    }

    if SwipeDiagnostics.enabled {
        let phase = event.getIntegerValueField(kCGEventGesturePhase)
        if phase == kCGSGesturePhaseBegan { gTracedChangedEvent = false }
        if phase != kCGSGesturePhaseChanged || !gTracedChangedEvent {
            SwipeDiagnostics.log("native tracking=\(gSwipeTracking) type=\(eventType) phase=\(phase) motion=\(event.getIntegerValueField(kCGEventGestureSwipeMotion)) progress=\(event.getDoubleValueField(kCGEventGestureSwipeProgress)) velocity=\(event.getDoubleValueField(kCGEventGestureSwipeVelocityX))")
            if let bytes = event.data {
                SwipeDiagnostics.log("native bytes=\((bytes as Data).base64EncodedString())")
            }
            if phase == kCGSGesturePhaseChanged { gTracedChangedEvent = true }
        }
    }
    let motion = event.getIntegerValueField(kCGEventGestureSwipeMotion)
    guard motion == kGestureMotionHorizontal else {
        return passthrough
    }

    let phase = event.getIntegerValueField(kCGEventGesturePhase)
    gLastSwipeEventTime = Date()

    switch phase {
    case kCGSGesturePhaseBegan:
        // Only the Space query gates interception. Native event serialization
        // includes undocumented records and is not a capability check.
        let (spaces, current) = getSpaceList()
        SwipeDiagnostics.log("begin spaces=\(spaces) current=\(current) connection=\(cgsMainConnection?() ?? -1)")
        guard current >= 0, !spaces.isEmpty else { return passthrough }
        gSwipeTracking        = true
        gSwipeIntentDirection = 0
        gSwipeIntentProgress  = 0.0
        if gCompanionGestureTapUsable, let gTap = gGestureTap {
            CGEvent.tapEnable(tap: gTap, enable: true)
        }
        return nil // Swallow Began so OS animation does not kick off

    case kCGSGesturePhaseChanged:
        guard gSwipeTracking else { return passthrough }
        let progress = event.getDoubleValueField(kCGEventGestureSwipeProgress)
        extendGestureExtreme(&gSwipeIntentProgress, towards: progress, sign: gSwipeIntentDirection)

        if let travelSign = requestedTravelSign(
            progress: progress,
            lastSign: gSwipeIntentDirection,
            extreme: gSwipeIntentProgress
        ) {
            gSwipeIntentDirection = travelSign
            gSwipeIntentProgress  = progress
            performSwipeSwitch(isRight: isRightSwipe(Double(travelSign)))
        }
        return nil

    case kCGSGesturePhaseEnded:
        guard gSwipeTracking else { return passthrough }

        // Fallback for very fast flick gestures where Changed wasn't delivered with sufficient travel
        if gSwipeIntentDirection == 0 {
            let velX = event.getDoubleValueField(kCGEventGestureSwipeVelocityX)
            if velX != 0 {
                performSwipeSwitch(isRight: isRightSwipe(velX))
            }
        }
        endHorizontalSwipeTracking()

        // macOS 27's Dock needs to see the gesture close to keep its
        // internal state consistent — pass the Ended event through
        // with its motion zeroed out so it cannot trigger a switch.
        if requiresEventAugmentation() {
            guard let neutral = neutralizedSwipeEnd(event) else { return nil }
            return Unmanaged.passRetained(neutral)
        }
        return nil

    case kCGSGesturePhaseCancelled:
        endHorizontalSwipeTracking()
        return nil

    default:
        return gSwipeTracking ? nil : passthrough
    }
}
