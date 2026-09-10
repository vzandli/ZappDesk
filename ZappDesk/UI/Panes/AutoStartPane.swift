/*
 * AutoStartPane.swift — ZappDesk
 *
 * Settings Pane: Launch at Login configuration and app termination.
 */

import AppKit
import ServiceManagement

protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

final class AutoStartPaneController: NSViewController {
    private let service: LoginItemService

    init(service: LoginItemService = SMAppService.mainApp) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }


    private var launchSwitch: NSSwitch!
    private var statusLabel: NSTextField!
    private var warningBox: NSBox!

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "Auto-Start")
        header.font = .systemFont(ofSize: 22, weight: .bold)
        header.translatesAutoresizingMaskIntoConstraints = false

        // Launch switch
        launchSwitch = NSSwitch()
        launchSwitch.target = self
        launchSwitch.action = #selector(launchSwitchToggled)

        statusLabel = NSTextField(wrappingLabelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isHidden = true

        let launchRow = settingsRow(
            label: "Launch ZappDesk at login",
            control: launchSwitch,
            subtitle: statusLabel
        )
        let launchGroup = SettingsGroupBox(views: [launchRow])
        launchGroup.translatesAutoresizingMaskIntoConstraints = false

        // Warning banner
        warningBox = makeWarningBanner()

        // Quit ZappDesk button
        let quitButton = NSButton(title: "Quit ZappDesk", target: self, action: #selector(quitApp))
        quitButton.bezelStyle = .rounded
        quitButton.contentTintColor = .systemRed

        let quitRow = settingsRow(
            label: "Quit application",
            control: quitButton
        )
        let quitGroup = SettingsGroupBox(views: [quitRow])
        quitGroup.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [header, warningBox, launchGroup, quitGroup])
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

            launchGroup.widthAnchor.constraint(equalTo: stack.widthAnchor),
            warningBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            quitGroup.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        view = container
        updateStatus()
        NotificationCenter.default.addObserver(self, selector: #selector(updateStatus),
            name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateStatus()
    }

    private func makeWarningBanner() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.cornerRadius = Layout.groupCornerRadius
        box.fillColor = NSColor.systemOrange.withAlphaComponent(0.12)
        box.borderColor = NSColor.systemOrange.withAlphaComponent(0.3)
        box.borderWidth = 1
        box.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        icon.contentTintColor = .systemOrange
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: "ZappDesk works best in the background. Enable launch at login so instant space transitions are always active.")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .systemOrange
        label.translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView(views: [icon, label])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false

        box.addSubview(content)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14)
        ])
        return box
    }

    @objc private func updateStatus() {
        let status = service.status
        launchSwitch.state = (status == .enabled) ? .on : .off
        warningBox.isHidden = (status == .enabled)

        if status == .requiresApproval {
            statusLabel.stringValue = "Approval needed in System Settings > Login Items"
            statusLabel.isHidden = false
        } else {
            statusLabel.isHidden = true
        }
    }

    @objc private func launchSwitchToggled() {
        do {
            if launchSwitch.state == .on {
                try service.register()
            } else {
                try service.unregister()
            }
            updateStatus()
        } catch {
            updateStatus()
            statusLabel.stringValue = "Error: \(error.localizedDescription)"
            statusLabel.isHidden = false
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
