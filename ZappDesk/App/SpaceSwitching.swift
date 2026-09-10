/*
 * SpaceSwitching.swift — ZappDesk
 *
 * Space queries, synthetic DockSwipe gesture generation, macOS 27 IOHID payload
 * augmentation, cross-display switching, and app window space resolution.
 */

import ApplicationServices
import AppKit
import CoreFoundation
import CoreGraphics
import Foundation

// MARK: - Constants

let kInstantSwitchVelocity: Double    = 9999.0
let kAugmentedInstantVelocity: Double = 9999.0
let kInstantSwitchProgress: Double    = 1.0

private let kIOHIDFluidTouchGestureDataSize: UInt32 = 40
private let kIOHIDVelocityEventDataSize:     UInt32 = 28

enum SwitchResult {
    case requested
    case busy
    case alreadyThere
    case declined
}

// MARK: - OS Version & Direction Convention

private let gAugmentationRequired: Bool =
    ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27

func requiresEventAugmentation() -> Bool {
    return gAugmentationRequired
}

func naturalScrollingEnabled() -> Bool {
    CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                             kCFPreferencesCurrentUser,
                             kCFPreferencesCurrentHost)
    return CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString,
                                     kCFPreferencesAnyApplication) as? Bool ?? true
}

private let kFirstPreferenceDependentSignOSBuild = 5416

// Early Developer beta seeds (26A5288, 26A5388) had a leading '5' (5000+) and were unconditionally
// inverted. Final release builds (e.g. 26A428) dropped the '5' and are later than the beta seeds,
// so they correctly follow naturalScrollingEnabled().
private let gAlwaysInvertedAugmentedSigns: Bool = {
    guard gAugmentationRequired,
          let build = parseOSBuild(osBuildString()),
          build.train == 26, build.letter == "A"
    else { return false }
    return build.number >= 5000 && build.number < kFirstPreferenceDependentSignOSBuild
}()

private func osBuildString() -> String {
    var size = 0
    guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0
    else { return "" }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0
    else { return "" }
    return String(cString: buffer)
}

private func parseOSBuild(_ build: String) -> (train: Int, letter: String, number: Int)? {
    var rest = Substring(build)
    let trainDigits  = rest.prefix(while: { $0.isNumber })
    rest = rest.dropFirst(trainDigits.count)
    let letters      = rest.prefix(while: { $0.isUppercase })
    rest = rest.dropFirst(letters.count)
    let numberDigits = rest.prefix(while: { $0.isNumber })

    guard let train = Int(trainDigits), !letters.isEmpty,
          let number = Int(numberDigits) else { return nil }
    return (train, String(letters), number)
}

func requiresInvertedAugmentedSigns() -> Bool {
    guard gAugmentationRequired else { return false }
    if gAlwaysInvertedAugmentedSigns { return true }
    return naturalScrollingEnabled()
}

private func augmentedHorizontalSign(isRight: Bool) -> Double {
    requiresInvertedAugmentedSigns() ? (isRight ? -1.0 : 1.0)
                                     : (isRight ? 1.0 : -1.0)
}

func currentSwitchVelocity() -> Double {
    let speed = AppState.shared.transitionSpeed
    if speed >= 0.95 {
        return kInstantSwitchVelocity
    }
    return 2500.0 + (speed * 6500.0)
}

// MARK: - Byte Serialization Helpers

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

private func doubleToFixed1616(_ value: Double) -> Int32 {
    guard value.isFinite else { return 0 }
    let scaled  = (value * 65536.0).rounded(.towardZero)
    let clamped = min(max(scaled, Double(Int32.min)), Double(Int32.max))
    let fixed   = Int32(clamped)
    if fixed == 0 && value != 0.0 { return value > 0.0 ? 1 : -1 }
    return fixed
}

// MARK: - macOS 27 IOHID Payload Augmentation

func generateIOHIDPayload(from event: CGEvent) -> Data {
    let phase     = event.getIntegerValueField(kCGEventGesturePhase)
    let motion    = event.getIntegerValueField(kCGEventGestureSwipeMotion)
    let progress  = event.getDoubleValueField(kCGEventGestureSwipeProgress)
    let posX      = event.getDoubleValueField(kCGEventGesturePositionX)
    let posY      = event.getDoubleValueField(kCGEventGesturePositionY)
    let velX      = event.getDoubleValueField(kCGEventGestureSwipeVelocityX)
    let velY      = event.getDoubleValueField(kCGEventGestureSwipeVelocityY)
    let swipeMask = event.getIntegerValueField(kCGEventGestureSwipeMask)

    let includeVelocity = velX != 0.0 || velY != 0.0 || phase == kCGSGesturePhaseEnded

    var payload = Data()

    let timestamp = event.timestamp != 0 ? UInt64(event.timestamp) : mach_absolute_time()
    payload.appendLE(timestamp)
    payload.appendLE(UInt64(0))
    payload.appendLE(UInt32(0))
    payload.appendLE(UInt32(0))
    payload.appendLE(UInt32(includeVelocity ? 2 : 1))

    // IOHIDFluidTouchGestureData
    payload.appendLE(kIOHIDFluidTouchGestureDataSize)
    payload.appendLE(kIOHIDEventTypeFluidTouchGesture)
    payload.appendLE(UInt32((phase & 0xFF) << 24))
    payload.appendLE(UInt8(0))
    payload.append(contentsOf: [0, 0, 0])
    payload.appendLE(doubleToFixed1616(posX))
    payload.appendLE(doubleToFixed1616(posY))
    payload.appendLE(Int32(0))
    payload.appendLE(UInt32(truncatingIfNeeded: swipeMask))
    payload.appendLE(UInt16(truncatingIfNeeded: motion))
    payload.appendLE(kIOHIDGestureFlavorDockPrimary)
    payload.appendLE(doubleToFixed1616(progress))

    // IOHIDVelocityEventData
    if includeVelocity {
        payload.appendLE(kIOHIDVelocityEventDataSize)
        payload.appendLE(kIOHIDEventTypeVelocity)
        payload.appendLE(UInt32(0))
        payload.appendLE(UInt8(1))
        payload.append(contentsOf: [0, 0, 0])
        payload.appendLE(doubleToFixed1616(velX))
        payload.appendLE(doubleToFixed1616(velY))
        payload.appendLE(Int32(0))
    }

    return payload
}

private func appendingBinaryField(_ fieldID: UInt16, to bytes: Data, with payload: Data) -> Data? {
    guard payload.count <= Int(UInt16.max) else { return nil }
    var result = bytes
    result.append(UInt8(payload.count >> 8))
    result.append(UInt8(payload.count & 0xFF))
    result.append(UInt8(fieldID >> 8))
    result.append(UInt8(fieldID & 0xFF))
    result.append(payload)
    return result
}

func replacingBinaryField(_ fieldID: UInt16, in bytes: Data, with payload: Data) -> Data? {
    let base = bytes.startIndex
    let end  = bytes.endIndex
    guard bytes.count >= 4 else { return nil }

    var result = Data(bytes.prefix(4))
    var offset = base + 4

    while offset < end {
        guard offset + 4 <= end else { return nil }
        let elementSize = (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
        let tagAndField = (UInt16(bytes[offset + 2]) << 8) | UInt16(bytes[offset + 3])
        let tag = tagAndField >> 14
        let currentFieldID = tagAndField & 0x3FFF

        let valueSize: Int
        switch tag {
        case 0 where elementSize == 1: valueSize = 8
        case 0 where elementSize > 1: valueSize = Int(elementSize)
        case 1 where elementSize == 1: valueSize = 4
        case 3 where elementSize == 1: valueSize = 4
        case 3 where elementSize == 2: valueSize = 8
        default: return nil
        }

        let recordEnd = offset + 4 + valueSize
        guard recordEnd <= end else { return nil }
        if currentFieldID != fieldID {
            result.append(bytes.subdata(in: offset..<recordEnd))
        }
        offset = recordEnd
    }

    return appendingBinaryField(fieldID, to: result, with: payload)
}

func augmentDockSwipeEvent(_ event: CGEvent, mayCarryExistingPayload: Bool = false) -> CGEvent? {
    guard let cfData = event.data else { return nil }
    let bytes = cfData as Data

    guard bytes.count >= 4,
          bytes[0] == 0, bytes[1] == 0, bytes[2] == 0, bytes[3] == 2
    else { return nil }

    let payload = generateIOHIDPayload(from: event)
    let augmented: Data

    if let replaced = replacingBinaryField(kCGEventIOHIDPayloadField, in: bytes, with: payload) {
        augmented = replaced
    } else if mayCarryExistingPayload {
        return nil
    } else {
        guard let appended = appendingBinaryField(kCGEventIOHIDPayloadField, to: bytes, with: payload)
        else { return nil }
        augmented = appended
    }

    return CGEvent(withDataAllocator: kCFAllocatorDefault, data: augmented as CFData)
}

// MARK: - Synthetic Gesture Construction

private func makeAugmentedDockEvent(phase: Int64, isRight: Bool, velocity: Double) -> CGEvent? {
    guard let ev = CGEvent(source: nil) else { return nil }

    let sign = augmentedHorizontalSign(isRight: isRight)

    ev.setIntegerValueField(kCGSEventTypeField,          value: kCGSEventDockControl)
    ev.setIntegerValueField(kCGEventGestureHIDType,      value: kIOHIDEventTypeDockSwipe)
    ev.setIntegerValueField(kCGEventGesturePhase,        value: phase)
    ev.setDoubleValueField(kCGEventGestureSwipeProgress, value: sign)
    ev.setIntegerValueField(kCGEventGestureSwipeMotion,  value: kGestureMotionHorizontal)
    ev.setIntegerValueField(kCGEventGesturePhase2,       value: phase)
    ev.setDoubleValueField(kCGEventGestureFlavor,        value: Double(kIOHIDGestureFlavorDockPrimary))
    ev.setDoubleValueField(kCGEventGestureTimestamp,     value: Double(mach_absolute_time()))
    ev.setDoubleValueField(kCGEventGesturePositionX,     value: 0.1)

    if phase == kCGSGesturePhaseEnded {
        ev.setDoubleValueField(kCGEventGestureSwipeVelocityX, value: sign * velocity)
    }

    return ev
}

private func postAugmentedSwitchGesture(isRight: Bool, velocity: Double) -> Bool {
    let magnitude = velocity >= kInstantSwitchVelocity ? kAugmentedInstantVelocity : velocity
    let phases = [kCGSGesturePhaseBegan, kCGSGesturePhaseChanged, kCGSGesturePhaseEnded]
    var events = [(dock: CGEvent, gesture: CGEvent)]()

    for phase in phases {
        guard let dockEvent = makeAugmentedDockEvent(phase: phase, isRight: isRight, velocity: magnitude),
              let augmented = augmentDockSwipeEvent(dockEvent),
              let gestureEvent = CGEvent(source: nil)
        else { return false }

        markSyntheticGesture(augmented)
        gestureEvent.setIntegerValueField(kCGSEventTypeField, value: kCGSEventGesture)
        markSyntheticGesture(gestureEvent)
        events.append((augmented, gestureEvent))
    }

    for (dock, gesture) in events {
        dock.post(tap: .cgSessionEventTap)
        gesture.post(tap: .cgSessionEventTap)
    }
    return true
}

private func makeGesturePair(flagDirection: Int64, phase: Int64,
                             progress: Double, velocity: Double) -> (CGEvent, CGEvent)? {
    guard let gestureEvent = CGEvent(source: nil),
          let dockEvent    = CGEvent(source: nil) else { return nil }

    gestureEvent.setIntegerValueField(kCGSEventTypeField, value: kCGSEventGesture)

    dockEvent.setIntegerValueField(kCGSEventTypeField,            value: kCGSEventDockControl)
    dockEvent.setIntegerValueField(kCGEventGestureHIDType,        value: kIOHIDEventTypeDockSwipe)
    dockEvent.setIntegerValueField(kCGEventGesturePhase,          value: phase)
    dockEvent.setIntegerValueField(kCGEventScrollGestureFlagBits, value: flagDirection)
    dockEvent.setIntegerValueField(kCGEventGestureSwipeMotion,    value: kGestureMotionHorizontal)
    dockEvent.setDoubleValueField(kCGEventGestureScrollY,          value: 0)
    dockEvent.setDoubleValueField(kCGEventGestureZoomDeltaX,       value: Double(Float.leastNonzeroMagnitude))

    if phase == kCGSGesturePhaseEnded {
        dockEvent.setDoubleValueField(kCGEventGestureSwipeProgress,  value: progress)
        dockEvent.setDoubleValueField(kCGEventGestureSwipeVelocityX, value: velocity)
        dockEvent.setDoubleValueField(kCGEventGestureSwipeVelocityY, value: 0)
    }

    markSyntheticGesture(dockEvent)
    markSyntheticGesture(gestureEvent)
    return (dockEvent, gestureEvent)
}

@discardableResult
func postSwitchGesture(direction: Int, velocity: Double = currentSwitchVelocity()) -> Bool {
    guard (direction == -1 || direction == 1), velocity > 0 else { return false }
    let isRight = direction > 0

    if requiresEventAugmentation() {
        return postAugmentedSwitchGesture(isRight: isRight, velocity: velocity)
    }

    let flagDirection: Int64 = isRight ? 1 : 0
    let progress             = isRight ? kInstantSwitchProgress : -kInstantSwitchProgress
    let signedVelocity       = isRight ? velocity : -velocity

    guard let began = makeGesturePair(
        flagDirection: flagDirection,
        phase: kCGSGesturePhaseBegan,
        progress: 0,
        velocity: 0
    ), let ended = makeGesturePair(
        flagDirection: flagDirection,
        phase: kCGSGesturePhaseEnded,
        progress: progress,
        velocity: signedVelocity
    ) else { return false }

    // Construct the entire gesture before posting anything, so failure is safe to pass through.
    for (dock, gesture) in [began, ended] {
        dock.post(tap: .cgSessionEventTap)
        gesture.post(tap: .cgSessionEventTap)
    }
    return true
}

let spaceSwitchSequence = SpaceSwitchSequence()

// MARK: - Display & Spaces Queries

private func getDisplaySpaces() -> [[String: Any]]? {
    guard let getConn = cgsMainConnection,
          let copySpaces = cgsCopyDisplaySpaces else { return nil }
    let cid = getConn()
    guard let unmanaged = copySpaces(cid, nil) else { return nil }
    return unmanaged.takeRetainedValue() as? [[String: Any]]
}

func getAllCurrentSpaces() -> Set<CGSSpaceID> {
    guard let displays = getDisplaySpaces() else { return [] }
    var currentSpaces = Set<CGSSpaceID>()
    for display in displays {
        if let current = display["Current Space"] as? [String: Any],
           let sid = (current["id64"] as? NSNumber)?.uint64Value {
            currentSpaces.insert(sid)
        }
    }
    return currentSpaces
}

func getSpaceList() -> (spaceIDs: [CGSSpaceID], currentIndex: Int) {
    guard let mainConn    = cgsMainConnection,
          let getDisplays = cgsCopyDisplaySpaces else { return ([], -1) }

    let cid = mainConn()
    guard cid != 0 else { return ([], -1) }

    guard let displays = getDisplays(cid, nil)?.takeRetainedValue() as? [[String: Any]]
    else { return ([], -1) }

    func spaceList(of display: [String: Any]) -> (spaceIDs: [CGSSpaceID], currentIndex: Int)? {
        guard let currentSpaceDict = display["Current Space"] as? [String: Any],
              let currentSpaceID   = (currentSpaceDict["id64"] as? NSNumber)?.uint64Value,
              let spaces           = display["Spaces"] as? [[String: Any]]
        else { return nil }

        var ids        = [CGSSpaceID]()
        var currentIdx = -1

        for space in spaces {
            guard let sid = (space["id64"] as? NSNumber)?.uint64Value else { continue }
            if sid == currentSpaceID { currentIdx = ids.count }
            ids.append(sid)
        }

        return (ids, currentIdx)
    }

    let cursorUUID = displayUUIDUnderCursor()
    let active     = cgsGetActiveSpace?(cid) ?? 0

    // Pass 1: Display under cursor
    if let cursorUUID {
        for display in displays {
            guard let du = display["Display Identifier"] as? String,
                  displayIdentifierMatches(du, uuid: cursorUUID) else { continue }
            if let result = spaceList(of: display) { return result }
        }
    }

    // Pass 2: Display hosting globally active space
    if active != 0 {
        for display in displays {
            guard let currentSpaceDict = display["Current Space"] as? [String: Any],
                  let currentSpaceID   = (currentSpaceDict["id64"] as? NSNumber)?.uint64Value,
                  currentSpaceID == active else { continue }
            if let result = spaceList(of: display) { return result }
        }
    }

    if let first = displays.first, let result = spaceList(of: first) {
        return result
    }

    return ([], -1)
}

func getUserDesktops() -> [CGSSpaceID] {
    guard let displays = getDisplaySpaces() else { return [] }
    var desktops = [CGSSpaceID]()
    for display in displays {
        guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
        for sp in spaces {
            let type = (sp["type"] as? NSNumber)?.intValue ?? 0
            if type == 0, let sid = (sp["id64"] as? NSNumber)?.uint64Value {
                desktops.append(sid)
            }
        }
    }
    return desktops
}

func switchToSpace(_ targetSpaceID: CGSSpaceID) -> SwitchResult {
    guard !spaceSwitchSequence.isRunning else { return .busy }
    guard let displays = getDisplaySpaces() else { return .declined }
    for display in displays {
        guard let spaces = display["Spaces"] as? [[String: Any]],
              spaces.contains(where: { ($0["id64"] as? NSNumber)?.uint64Value == targetSpaceID }),
              let identifier = display["Display Identifier"] as? String,
              let targetDisplay = displayID(forIdentifier: identifier) else { continue }
        let snapshot: () -> SpaceSwitchSequence.Snapshot? = {
            guard let currentDisplay = getDisplaySpaces()?.first(where: {
                ($0["Display Identifier"] as? String) == identifier
            }), let current = currentDisplay["Current Space"] as? [String: Any],
                let sid = (current["id64"] as? NSNumber)?.uint64Value,
                let spaces = currentDisplay["Spaces"] as? [[String: Any]] else { return nil }
            return .init(spaces: spaces.compactMap { ($0["id64"] as? NSNumber)?.uint64Value }, current: sid)
        }
        guard let initial = snapshot() else { return .declined }
        if initial.current == targetSpaceID { return .alreadyThere }
        guard let originalPos = CGEvent(source: nil)?.location else { return .declined }
        let onCursorDisplay = displayUUIDUnderCursor().map { displayIdentifierMatches(identifier, uuid: $0) } ?? false
        let bounds = CGDisplayBounds(targetDisplay)
        let warpPoint = CGPoint(x: bounds.midX, y: bounds.midY)
        if !onCursorDisplay {
            guard CGWarpMouseCursorPosition(warpPoint) == .success else { return .declined }
        }
        let restoreCursor = {
            guard !onCursorDisplay, let point = CGEvent(source: nil)?.location,
                  abs(point.x - warpPoint.x) <= 2, abs(point.y - warpPoint.y) <= 2 else { return }
            CGWarpMouseCursorPosition(originalPos)
        }
        let started = spaceSwitchSequence.start(target: targetSpaceID, snapshot: snapshot, post: { direction in
            guard AppState.shared.masterEnabled, AXIsProcessTrusted(),
                  !CGEventSource.buttonState(.combinedSessionState, button: .left),
                  let uuid = displayUUIDUnderCursor(), displayIdentifierMatches(identifier, uuid: uuid)
            else { return false }
            let posted = postSwitchGesture(direction: direction)
            SwipeDiagnostics.log("post direction=\(direction) posted=\(posted) target=\(targetSpaceID)")
            if posted { gLastSpaceSwitchTime = Date() }
            return posted
        }, confirmed: {
            gLastSpaceSwitchTime = Date()
            AppState.shared.recordSwitch()
            SwipeDiagnostics.log("confirmed desktop transition")
        }, finished: restoreCursor)
        if !started { restoreCursor() }
        return started ? .requested : .declined
    }
    return .declined
}

/// Auxiliary panels must not prevent following a normal window on another Space.
func isNormalVisibleWindow(_ window: [String: Any], of pid: pid_t) -> Bool {
    (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid &&
    (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 &&
    ((window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0
}

private func displayID(forIdentifier identifier: String) -> CGDirectDisplayID? {
    if identifier == "Main" { return CGMainDisplayID() }
    guard let cfUUID = CFUUIDCreateFromString(nil, identifier as CFString) else { return nil }
    let id = CGDisplayGetDisplayIDFromUUID(cfUUID)
    return id == 0 ? nil : id
}

private func displayUUIDUnderCursor() -> String? {
    let point = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
          let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
          let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
    else { return nil }
    return CFUUIDCreateString(nil, cfUUID) as String?
}

private func mainDisplayUUID() -> String? {
    guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())?.takeRetainedValue()
    else { return nil }
    return CFUUIDCreateString(nil, cfUUID) as String?
}

private func displayIdentifierMatches(_ identifier: String, uuid: String) -> Bool {
    if identifier == "Main" {
        return mainDisplayUUID() == uuid
    }
    return identifier.caseInsensitiveCompare(uuid) == .orderedSame
}

// MARK: - App Space Resolution (Auto-Follow Helper)

func findSpaceForPid(_ pid: pid_t) -> CGSSpaceID {
    let currentSpaces = getAllCurrentSpaces()
    guard let getConn = cgsMainConnection,
          let spacesForWins = slsCopySpacesForWindows else { return 0 }
    let cid = getConn()

    guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return 0
    }

    if windowInfo.contains(where: { isNormalVisibleWindow($0, of: pid) }) { return 0 }

    guard let allWindows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return 0
    }

    var winIDs = [UInt32]()
    for win in allWindows {
        if let ownerPID = (win[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
           ownerPID == pid {
            let layer = (win[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            if layer == 0, let wid = (win[kCGWindowNumber as String] as? NSNumber)?.uint32Value {
                winIDs.append(wid)
            }
        }
    }

    guard !winIDs.isEmpty else { return 0 }

    let winCFArray = winIDs as CFArray
    guard let spacesUnmanaged = spacesForWins(cid, 7, winCFArray) else { return 0 }
    guard let spacesArray = spacesUnmanaged.takeRetainedValue() as? [NSNumber] else { return 0 }

    for sNum in spacesArray {
        let sid = sNum.uint64Value
        if !currentSpaces.contains(sid) && sid != 0 {
            return sid
        }
    }

    return 0
}
