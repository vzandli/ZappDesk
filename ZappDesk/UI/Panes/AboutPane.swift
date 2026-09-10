/*
 * AboutPane.swift — ZappDesk
 *
 * Settings Pane: About information, version, software updates, and live productivity statistics.
 */

import AppKit

final class AboutPaneController: NSViewController {

    private var statsLabel: NSTextField!
    private var savingsLabel: NSTextField!
    private var checkUpdatesButton: NSButton!
    private var autoUpdateToggle: NSSwitch!

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "About")
        header.font = .systemFont(ofSize: 22, weight: .bold)
        header.translatesAutoresizingMaskIntoConstraints = false

        // App identity
        let appIcon = NSImageView()
        if let icon = NSApp.applicationIconImage {
            appIcon.image = icon
        } else {
            appIcon.image = NSImage(systemSymbolName: "bolt.horizontal.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 42, weight: .bold))
            appIcon.contentTintColor = .systemBlue
        }
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        appIcon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        appIcon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let appTitle = NSTextField(labelWithString: "ZappDesk")
        appTitle.font = .systemFont(ofSize: 18, weight: .bold)

        let appVersion = NSTextField(labelWithString: UpdateManager.shared.currentVersion)
        appVersion.font = .systemFont(ofSize: 12)
        appVersion.textColor = .secondaryLabelColor

        let identityStack = NSStackView(views: [appTitle, appVersion])
        identityStack.orientation = .vertical
        identityStack.alignment = .leading
        identityStack.spacing = 2

        let appHeaderStack = NSStackView(views: [appIcon, identityStack])
        appHeaderStack.orientation = .horizontal
        appHeaderStack.alignment = .centerY
        appHeaderStack.spacing = 14

        // Statistics Group
        statsLabel = NSTextField(labelWithString: "")
        statsLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        statsLabel.textColor = .labelColor

        let statsSub = NSTextField(wrappingLabelWithString: "Only observed desktop transitions are counted. Savings are an upper-bound estimate of 750ms per transition; actual savings depend on transition speed.")
        savingsLabel = statsSub
        statsSub.font = .systemFont(ofSize: 11)
        statsSub.textColor = .secondaryLabelColor

        let statsRow = settingsRow(
            label: "Productivity",
            control: statsLabel,
            subtitle: statsSub
        )

        let statsGroup = SettingsGroupBox(views: [statsRow])
        statsGroup.translatesAutoresizingMaskIntoConstraints = false

        // Updates Group
        checkUpdatesButton = NSButton(title: "Check for Updates…", target: self, action: #selector(checkForUpdates))
        checkUpdatesButton.bezelStyle = .rounded

        let checkSub = NSTextField(wrappingLabelWithString: "Updates are downloaded from GitHub Releases and verified with an EdDSA signature before installation.")
        checkSub.font = .systemFont(ofSize: 11)
        checkSub.textColor = .secondaryLabelColor

        let checkRow = settingsRow(
            label: "Software Update",
            control: checkUpdatesButton,
            subtitle: checkSub
        )

        autoUpdateToggle = NSSwitch()
        autoUpdateToggle.target = self
        autoUpdateToggle.action = #selector(autoUpdateChanged)

        let autoSub = NSTextField(wrappingLabelWithString: "Checks for new versions in the background about once a day")
        autoSub.font = .systemFont(ofSize: 11)
        autoSub.textColor = .secondaryLabelColor

        let autoRow = settingsRow(
            label: "Check for updates automatically",
            control: autoUpdateToggle,
            subtitle: autoSub
        )

        let updatesGroup = SettingsGroupBox(views: [checkRow, rowDivider(), autoRow])
        updatesGroup.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [header, appHeaderStack, updatesGroup, statsGroup])
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

            updatesGroup.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statsGroup.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        view = container
        updateStats()
        refreshUpdateControls()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStats),
            name: AppState.switchDidOccurNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshUpdateControls),
            name: UpdateManager.statusDidChangeNotification,
            object: nil
        )
    }

    @objc private func refreshUpdateControls() {
        let updates = UpdateManager.shared
        checkUpdatesButton.isEnabled = updates.canCheckForUpdates
        checkUpdatesButton.title = updates.pendingUpdateVersion.map { "Update to \($0)…" } ?? "Check for Updates…"
        autoUpdateToggle.state = updates.automaticallyChecksForUpdates ? .on : .off
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc private func autoUpdateChanged() {
        UpdateManager.shared.automaticallyChecksForUpdates = (autoUpdateToggle.state == .on)
    }

    @objc private func updateStats() {
        let state = AppState.shared
        statsLabel.stringValue = "\(state.switchesCount) confirmed switches"
        savingsLabel.stringValue = "Up to \(state.formattedTimeSaved) saved (estimate). Based on observed transitions; actual savings depend on transition speed and macOS animations."
    }
}
