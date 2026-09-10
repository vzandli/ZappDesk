import XCTest
import AppKit
import ServiceManagement
@testable import ZappDesk

final class SettingsRegressionTests: XCTestCase {
    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    private func toggle(_ label: String, in view: NSView) throws -> NSSwitch {
        try XCTUnwrap(descendants(view).compactMap { $0 as? NSSwitch }.first {
            $0.accessibilityLabel() == label
        })
    }

    func testFeatureControlsRefreshWhenPreferencesChangeElsewhere() throws {
        _ = NSApplication.shared
        let suite = "ZappDeskTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        let pane = FeaturesPaneController(state: state)
        let view = pane.view
        let space = try toggle("Instant Space switch", in: view)
        let app = try toggle("Instant App switch", in: view)
        let swipe = try toggle("Instant Trackpad swipe", in: view)
        state.instantSpaceSwitchEnabled = false
        state.instantAppSwitchEnabled = false
        state.instantTrackpadSwipeEnabled = false
        XCTAssertEqual(space.state, .off)
        XCTAssertEqual(app.state, .off)
        XCTAssertEqual(swipe.state, .off)
        state.instantSpaceSwitchEnabled = true
        XCTAssertEqual(space.state, .on)
    }

    private final class FailingLoginService: LoginItemService {
        var status: SMAppService.Status
        init(status: SMAppService.Status) { self.status = status }
        func register() throws { throw NSError(domain: "TestLoginService", code: 1) }
        func unregister() throws { throw NSError(domain: "TestLoginService", code: 2) }
    }

    func testFailedLoginRegistrationRestoresOffState() throws {
        _ = NSApplication.shared
        let pane = AutoStartPaneController(service: FailingLoginService(status: .notRegistered))
        let control = try toggle("Launch ZappDesk at login", in: pane.view)
        control.state = .on
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(control.action), to: control.target, from: control))
        XCTAssertEqual(control.state, .off)
        XCTAssertTrue(descendants(pane.view).compactMap { $0 as? NSTextField }.contains {
            !$0.isHidden && $0.stringValue.hasPrefix("Error:")
        })
    }

    func testFailedLoginRemovalRestoresOnState() throws {
        _ = NSApplication.shared
        let pane = AutoStartPaneController(service: FailingLoginService(status: .enabled))
        let control = try toggle("Launch ZappDesk at login", in: pane.view)
        control.state = .off
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(control.action), to: control.target, from: control))
        XCTAssertEqual(control.state, .on)
    }
}
