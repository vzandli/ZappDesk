import XCTest
import CoreGraphics
@testable import ZappDesk

final class InputRegressionTests: XCTestCase {
    func testDisabledAndCustomSystemShortcuts() {
        applySystemShortcuts([
            "79": ["enabled": false],
            "81": ["enabled": true, "value": ["parameters": [0, 45, 0x120000]]],
            "118": ["enabled": true, "value": ["parameters": [0, 18, 0x040000]]]
        ])
        XCTAssertNil(gBindingLeft)
        XCTAssertEqual(gBindingRight?.keycode, 45)
        XCTAssertEqual(gBindingRight?.mods, [.maskCommand, .maskShift])
        XCTAssertEqual(gSpaceKeys[0]?.keycode, 18)
    }

    func testMissingPreferencesClearPreviouslyLoadedDirectShortcuts() {
        applySystemShortcuts(["118": ["value": ["parameters": [0, 18, 0x040000]]]])
        XCTAssertNotNil(gSpaceKeys[0])
        applySystemShortcuts([:])
        XCTAssertEqual(gBindingLeft?.keycode, 123)
        XCTAssertEqual(gBindingRight?.keycode, 124)
        XCTAssertEqual(gSpaceKeys.count, 16)
        XCTAssertTrue(gSpaceKeys.allSatisfy { $0 == nil })
    }

    func testUnboundSentinelAndMalformedPreferences() {
        applySystemShortcuts([
            "79": ["value": ["parameters": [0, 65535, 0]]],
            "81": ["value": ["parameters": [0]]]
        ])
        XCTAssertNil(gBindingLeft)
        XCTAssertEqual(gBindingRight?.keycode, 124)
    }

    func testGestureThresholdAndReversal() {
        XCTAssertNil(requestedTravelSign(progress: 0.04, lastSign: 0, extreme: 0))
        XCTAssertEqual(requestedTravelSign(progress: 0.06, lastSign: 0, extreme: 0), 1)
        XCTAssertNil(requestedTravelSign(progress: 0.45, lastSign: 1, extreme: 0.6))
        XCTAssertEqual(requestedTravelSign(progress: 0.3, lastSign: 1, extreme: 0.6), -1)
        XCTAssertEqual(requestedTravelSign(progress: -0.3, lastSign: -1, extreme: -0.6), 1)
        var extreme = 0.5
        extendGestureExtreme(&extreme, towards: 0.7, sign: 1)
        extendGestureExtreme(&extreme, towards: 0.4, sign: 1)
        XCTAssertEqual(extreme, 0.7)
    }

    func testAuxiliaryWindowsDoNotBlockAutoFollow() {
        let normal: [String: Any] = [kCGWindowOwnerPID as String: 42,
                                    kCGWindowLayer as String: 0, kCGWindowAlpha as String: 1]
        XCTAssertTrue(isNormalVisibleWindow(normal, of: 42))
        XCTAssertFalse(isNormalVisibleWindow(normal, of: 43))
        var panel = normal
        panel[kCGWindowLayer as String] = 3
        XCTAssertFalse(isNormalVisibleWindow(panel, of: 42))
        panel[kCGWindowLayer as String] = 0
        panel[kCGWindowAlpha as String] = 0
        XCTAssertFalse(isNormalVisibleWindow(panel, of: 42))
    }

    func testSpeedIsFiniteAndWithinSliderRange() {
        XCTAssertEqual(AppState.validatedSpeed(.nan), 1)
        XCTAssertEqual(AppState.validatedSpeed(.infinity), 1)
        XCTAssertEqual(AppState.validatedSpeed(-1), 0.1)
        XCTAssertEqual(AppState.validatedSpeed(9), 1)
        XCTAssertEqual(AppState.validatedSpeed(0.5), 0.5)
    }

    func testBinaryPayloadReplacementRemovesOldValue() throws {
        let original = Data([0, 0, 0, 2, 0, 3, 0x10, 0x6d, 9, 8, 7])
        let updated = try XCTUnwrap(replacingBinaryField(4205, in: original, with: Data([1, 2])))
        XCTAssertEqual(updated, Data([0, 0, 0, 2, 0, 2, 0x10, 0x6d, 1, 2]))
        XCTAssertNil(replacingBinaryField(4205, in: Data([0, 0, 0, 2, 0, 9, 0]), with: Data([1, 2])))
    }

    func testEndingGestureRebuildsZeroMotionPayload() throws {
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.setIntegerValueField(kCGSEventTypeField, value: kCGSEventDockControl)
        event.setIntegerValueField(kCGEventGesturePhase, value: kCGSGesturePhaseEnded)
        event.setDoubleValueField(kCGEventGestureSwipeProgress, value: 0.8)
        event.setDoubleValueField(kCGEventGestureSwipeVelocityX, value: 8000)
        let augmented = try XCTUnwrap(augmentDockSwipeEvent(event))
        let neutral = try XCTUnwrap(neutralizedSwipeEnd(augmented))
        XCTAssertEqual(neutral.getDoubleValueField(kCGEventGestureSwipeProgress), 0)
        XCTAssertEqual(neutral.getDoubleValueField(kCGEventGestureSwipeVelocityX), 0)
        let payload = generateIOHIDPayload(from: neutral)
        XCTAssertEqual(payload.count, 96)
        XCTAssertEqual(Array(payload[64..<68]), [0, 0, 0, 0]) // progress
        XCTAssertEqual(Array(payload[84..<96]), Array(repeating: 0, count: 12)) // velocity xyz
        let serialized = try XCTUnwrap(neutral.data) as Data
        let header = try XCTUnwrap(serialized.range(of: Data([0, 96, 0x10, 0x6d])))
        let embedded = serialized.subdata(in: header.upperBound..<(header.upperBound + 96))
        // CGEvent round-trips quantize timestamps; the embedded motion must match exactly.
        XCTAssertEqual(embedded.dropFirst(8), payload.dropFirst(8))
        XCTAssertEqual(event.getDoubleValueField(kCGEventGestureSwipeProgress), 0.8, accuracy: 0.000001) // original untouched
    }

    func testClosingGestureDoesNotCopyUnrelatedNativeFields() throws {
        let native = try XCTUnwrap(CGEvent(source: nil))
        native.setIntegerValueField(.mouseEventClickState, value: 9)
        native.setIntegerValueField(kCGEventGestureSwipeMask, value: 15)
        native.setDoubleValueField(kCGEventGestureSwipeVelocityY, value: 500)
        native.location = CGPoint(x: 200, y: 300)
        let closing = try XCTUnwrap(neutralizedSwipeEnd(native))
        XCTAssertEqual(closing.getIntegerValueField(.mouseEventClickState), 0)
        XCTAssertEqual(closing.getIntegerValueField(kCGEventGestureSwipeMask), 0)
        XCTAssertEqual(closing.getDoubleValueField(kCGEventGestureSwipeVelocityY), 0)
        XCTAssertEqual(closing.getIntegerValueField(kCGEventGesturePhase), kCGSGesturePhaseEnded)
        XCTAssertEqual(closing.getIntegerValueField(kCGEventGesturePhase2), kCGSGesturePhaseEnded)
        XCTAssertEqual(closing.getIntegerValueField(kCGEventGestureHIDType), kIOHIDEventTypeDockSwipe)
        XCTAssertEqual(closing.location, native.location)
        XCTAssertTrue(isSyntheticGesture(closing))
    }

    func testIdleGestureTapDisableDoesNotReenterEnable() {
        let recovery = swipeTapRecoveryAfterDisable(isGestureTap: true, tracking: false)
        XCTAssertEqual(recovery, SwipeTapRecovery(
            enableDock: false, enableGesture: false, markCompanionUnusable: false
        ))
    }

    func testGestureTapDisableDuringSwipeKeepsDockControlPath() {
        let recovery = swipeTapRecoveryAfterDisable(isGestureTap: true, tracking: true)
        XCTAssertEqual(recovery, SwipeTapRecovery(
            enableDock: false, enableGesture: false, markCompanionUnusable: true
        ))
    }

    func testDockTapDisableReenablesDockWithoutClearingSwipe() {
        let recovery = swipeTapRecoveryAfterDisable(isGestureTap: false, tracking: true)
        XCTAssertEqual(recovery, SwipeTapRecovery(
            enableDock: true, enableGesture: false, markCompanionUnusable: false
        ))
    }
}
