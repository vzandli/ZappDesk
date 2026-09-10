/*
 * PrivateAPI.swift — ZappDesk
 *
 * Encapsulates undocumented CoreGraphics event fields, WindowServer CGS types,
 * and dynamic runtime symbol resolution via dlsym for macOS space switching.
 */

import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Undocumented CGEvent Field IDs

let kCGSEventTypeField            = CGEventField(rawValue: 55)!
let kCGEventGestureHIDType        = CGEventField(rawValue: 110)!
let kCGEventGestureScrollY        = CGEventField(rawValue: 119)!
let kCGEventGestureSwipeMotion    = CGEventField(rawValue: 123)!
let kCGEventGestureSwipeProgress  = CGEventField(rawValue: 124)!
let kCGEventGesturePositionX      = CGEventField(rawValue: 125)!
let kCGEventGesturePositionY      = CGEventField(rawValue: 126)!
let kCGEventGestureSwipeVelocityX = CGEventField(rawValue: 129)!
let kCGEventGestureSwipeVelocityY = CGEventField(rawValue: 130)!
let kCGEventGesturePhase          = CGEventField(rawValue: 132)!
let kCGEventGesturePhase2         = CGEventField(rawValue: 134)!
let kCGEventGestureFlavor         = CGEventField(rawValue: 138)!
let kCGEventGestureZoomDeltaX     = CGEventField(rawValue: 139)!
let kCGEventScrollGestureFlagBits = CGEventField(rawValue: 148)!
let kCGEventGestureTimestamp      = CGEventField(rawValue: 169)!
let kCGEventGestureSwipeMask      = CGEventField(rawValue: 115)!

/// Undocumented binary field for serialized IOHID queue payload (macOS 27+)
let kCGEventIOHIDPayloadField: UInt16 = 4205

// MARK: - Undocumented Event Type Constants

let kIOHIDEventTypeDockSwipe: Int64 = 23
let kCGSEventGesture:         Int64 = 29
let kCGSEventDockControl:     Int64 = 30

let kCGSGesturePhaseBegan:     Int64 = 1
let kCGSGesturePhaseChanged:   Int64 = 2
let kCGSGesturePhaseEnded:     Int64 = 4
let kCGSGesturePhaseCancelled: Int64 = 8

let kIOHIDEventTypeVelocity:          UInt32 = 9
let kIOHIDEventTypeFluidTouchGesture: UInt32 = 23
let kIOHIDGestureFlavorDockPrimary:   UInt16 = 3

let kGestureMotionHorizontal: Int64 = 1

/// Marker stamped into synthetic events' source user data so event taps do not loop
let kSyntheticGestureMarker: Int64 = 0x5A415050 // "ZAPP"

func markSyntheticGesture(_ event: CGEvent) {
    event.setIntegerValueField(.eventSourceUserData, value: kSyntheticGestureMarker)
}

func isSyntheticGesture(_ event: CGEvent) -> Bool {
    return event.getIntegerValueField(.eventSourceUserData) == kSyntheticGestureMarker
}

// MARK: - CGS Type Aliases & Signatures

typealias CGSConnectionID = Int32
typealias CGSSpaceID      = UInt64

typealias FnMainConnection   = @convention(c) () -> CGSConnectionID
typealias FnActiveSpace      = @convention(c) (CGSConnectionID) -> CGSSpaceID
typealias FnDisplaySpaces    = @convention(c) (CGSConnectionID, CFString?) -> Unmanaged<CFArray>?
typealias FnSpacesForWindows = @convention(c) (CGSConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?
typealias FnCopySpaces       = @convention(c) (CGSConnectionID, Int32) -> Unmanaged<CFArray>?
typealias FnSpaceCopyName    = @convention(c) (CGSConnectionID, CGSSpaceID) -> Unmanaged<CFString>?

// MARK: - Runtime Symbol Resolution

private let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2 as Int)

private func loadSymbol<T>(_ name: String) -> T? {
    guard let ptr = dlsym(rtldDefault, name) else { return nil }
    return unsafeBitCast(ptr, to: T.self)
}

let cgsMainConnection:       FnMainConnection?   = loadSymbol("CGSMainConnectionID")
let cgsGetActiveSpace:       FnActiveSpace?      = loadSymbol("CGSGetActiveSpace")
let cgsCopyDisplaySpaces:    FnDisplaySpaces?    = loadSymbol("CGSCopyManagedDisplaySpaces")
let slsCopySpacesForWindows: FnSpacesForWindows? = loadSymbol("SLSCopySpacesForWindows")
let slsCopySpaces:           FnCopySpaces?       = loadSymbol("SLSCopySpaces")
let slsSpaceCopyName:        FnSpaceCopyName?    = loadSymbol("SLSSpaceCopyName")
