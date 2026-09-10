/*
 * FeaturesPane.swift — ZappDesk
 *
 * Settings Pane: Instant Space Switch, Instant App Switch, Instant Trackpad Swipe,
 * and Transition Speed slider.
 */

import AppKit

final class FeaturesPaneController: NSViewController {
    private let state: AppState

    init(state: AppState = .shared) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }


    private var spaceSwitchToggle:    NSSwitch!
    private var appSwitchToggle:      NSSwitch!
    private var trackpadSwipeToggle:  NSSwitch!
    private var speedSlider:          NSSlider!
    private var speedLabel:           NSTextField!

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "Features")
        header.font = .systemFont(ofSize: 22, weight: .bold)
        header.translatesAutoresizingMaskIntoConstraints = false

        let state = self.state

        // 1. Instant Space switch
        spaceSwitchToggle = NSSwitch()
        spaceSwitchToggle.state = state.instantSpaceSwitchEnabled ? .on : .off
        spaceSwitchToggle.target = self
        spaceSwitchToggle.action = #selector(spaceSwitchChanged)

        let spaceSub = NSTextField(wrappingLabelWithString: "Bypasses animation for Control + Arrow and direct desktop shortcuts")
        spaceSub.font = .systemFont(ofSize: 11)
        spaceSub.textColor = .secondaryLabelColor

        let spaceRow = settingsRow(
            label: "Instant Space switch",
            control: spaceSwitchToggle,
            subtitle: spaceSub
        )

        // 2. Instant App switch
        appSwitchToggle = NSSwitch()
        appSwitchToggle.state = state.instantAppSwitchEnabled ? .on : .off
        appSwitchToggle.target = self
        appSwitchToggle.action = #selector(appSwitchChanged)

        let appSub = NSTextField(wrappingLabelWithString: "Instantly jumps to the space where the focused app lives on Cmd+Tab")
        appSub.font = .systemFont(ofSize: 11)
        appSub.textColor = .secondaryLabelColor

        let appRow = settingsRow(
            label: "Instant App switch",
            control: appSwitchToggle,
            subtitle: appSub
        )

        // 3. Instant Trackpad swipe
        trackpadSwipeToggle = NSSwitch()
        trackpadSwipeToggle.state = state.instantTrackpadSwipeEnabled ? .on : .off
        trackpadSwipeToggle.target = self
        trackpadSwipeToggle.action = #selector(trackpadSwipeChanged)

        let trackSub = NSTextField(wrappingLabelWithString: "Eliminates delay and snapping delay during multi-finger horizontal swipes")
        trackSub.font = .systemFont(ofSize: 11)
        trackSub.textColor = .secondaryLabelColor

        let trackpadRow = settingsRow(
            label: "Instant Trackpad swipe",
            control: trackpadSwipeToggle,
            subtitle: trackSub
        )

        let featuresGroup = SettingsGroupBox(views: [
            spaceRow,
            rowDivider(),
            appRow,
            rowDivider(),
            trackpadRow
        ])
        featuresGroup.translatesAutoresizingMaskIntoConstraints = false

        // 4. Transition speed slider
        speedSlider = NSSlider(value: state.transitionSpeed, minValue: 0.1, maxValue: 1.0, target: self, action: #selector(speedSliderChanged))
        speedSlider.numberOfTickMarks = 5
        speedSlider.allowsTickMarkValuesOnly = false
        speedSlider.translatesAutoresizingMaskIntoConstraints = false
        speedSlider.widthAnchor.constraint(equalToConstant: 140).isActive = true

        speedLabel = NSTextField(labelWithString: state.isInstantSpeed ? "⚡ Instant" : "Fast")
        speedLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        speedLabel.textColor = .labelColor
        speedLabel.translatesAutoresizingMaskIntoConstraints = false
        speedLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 68).isActive = true

        let sliderStack = NSStackView(views: [speedSlider, speedLabel])
        sliderStack.orientation = .horizontal
        sliderStack.spacing = 8
        sliderStack.alignment = .centerY
        sliderStack.translatesAutoresizingMaskIntoConstraints = false
        sliderStack.setContentHuggingPriority(.required, for: .horizontal)
        sliderStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        let speedRow = settingsRow(
            label: "Transition speed",
            control: sliderStack
        )
        let speedGroup = SettingsGroupBox(views: [speedRow])
        speedGroup.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [header, featuresGroup, speedGroup])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Layout.spacingBetweenGroups
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -24),

            featuresGroup.widthAnchor.constraint(equalTo: stack.widthAnchor),
            speedGroup.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        view = container
        NotificationCenter.default.addObserver(self, selector: #selector(refreshControls),
            name: AppState.stateDidChangeNotification, object: nil)
        refreshControls()
    }

    @objc private func refreshControls() {
        let state = self.state
        spaceSwitchToggle.state = state.instantSpaceSwitchEnabled ? .on : .off
        appSwitchToggle.state = state.instantAppSwitchEnabled ? .on : .off
        trackpadSwipeToggle.state = state.instantTrackpadSwipeEnabled ? .on : .off
        speedSlider.doubleValue = state.transitionSpeed
        speedLabel.stringValue = state.masterEnabled ? (state.isInstantSpeed ? "⚡ Instant" : "Fast") : "Paused"
    }

    @objc private func spaceSwitchChanged() {
        state.instantSpaceSwitchEnabled = (spaceSwitchToggle.state == .on)
    }

    @objc private func appSwitchChanged() {
        state.instantAppSwitchEnabled = (appSwitchToggle.state == .on)
    }

    @objc private func trackpadSwipeChanged() {
        state.instantTrackpadSwipeEnabled = (trackpadSwipeToggle.state == .on)
    }

    @objc private func speedSliderChanged() {
        state.transitionSpeed = speedSlider.doubleValue
    }
}
