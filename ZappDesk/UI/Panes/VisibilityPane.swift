/*
 * VisibilityPane.swift — ZappDesk
 *
 * Settings Pane: Dock icon & Menu Bar icon visibility configuration.
 * Supports running as a menu bar app, dock app, or completely hidden daemon.
 */

import AppKit

final class VisibilityPaneController: NSViewController {

    private var menuBarToggle: NSSwitch!
    private var dockToggle:    NSSwitch!
    private var hotkeyLabel: NSTextField!
    private var hiddenLabel: NSTextField!
    private var hiddenNoticeBox: NSBox!

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "Visibility")
        header.font = .systemFont(ofSize: 22, weight: .bold)
        header.translatesAutoresizingMaskIntoConstraints = false

        let state = AppState.shared

        // 1. Menu bar icon toggle
        menuBarToggle = NSSwitch()
        menuBarToggle.state = state.showMenuBarIcon ? .on : .off
        menuBarToggle.target = self
        menuBarToggle.action = #selector(menuBarToggleChanged)

        let menuSub = NSTextField(wrappingLabelWithString: "Displays ZappDesk quick toggle and statistics in the macOS menu bar")
        menuSub.font = .systemFont(ofSize: 11)
        menuSub.textColor = .secondaryLabelColor

        let menuRow = settingsRow(
            label: "Show in Menu Bar",
            control: menuBarToggle,
            subtitle: menuSub
        )

        // 2. Dock icon toggle
        dockToggle = NSSwitch()
        dockToggle.state = state.showDockIcon ? .on : .off
        dockToggle.target = self
        dockToggle.action = #selector(dockToggleChanged)

        let dockSub = NSTextField(wrappingLabelWithString: "Displays ZappDesk in the macOS Dock and application switcher (Cmd+Tab)")
        dockSub.font = .systemFont(ofSize: 11)
        dockSub.textColor = .secondaryLabelColor

        let dockRow = settingsRow(
            label: "Show in Dock",
            control: dockToggle,
            subtitle: dockSub
        )

        let visibilityGroup = SettingsGroupBox(views: [
            menuRow,
            rowDivider(),
            dockRow
        ])
        visibilityGroup.translatesAutoresizingMaskIntoConstraints = false

        // 3. Hidden notice box
        hiddenNoticeBox = makeHiddenNoticeBox()

        // 4. Summoning Information box
        let summonBox = makeSummonInfoBox()

        let stack = NSStackView(views: [header, visibilityGroup, hiddenNoticeBox, summonBox])
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

            visibilityGroup.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hiddenNoticeBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            summonBox.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        view = container
        updateHiddenNoticeVisibility()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshControls),
            name: GlobalHotkeyManager.statusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshControls),
            name: AppState.stateDidChangeNotification, object: nil)
        refreshControls()
    }

    @objc private func refreshControls() {
        menuBarToggle.state = AppState.shared.showMenuBarIcon ? .on : .off
        dockToggle.state = AppState.shared.showDockIcon ? .on : .off
        let manager = GlobalHotkeyManager.shared
        hotkeyLabel.stringValue = manager.settingsHint
        hotkeyLabel.textColor = manager.isRegistered ? .secondaryLabelColor : .systemOrange
        hiddenLabel.stringValue = "Both icons are hidden. ZappDesk is running in the background. " + manager.settingsHint
        updateHiddenNoticeVisibility()
    }

    private func makeHiddenNoticeBox() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.cornerRadius = Layout.groupCornerRadius
        box.fillColor = NSColor.systemPurple.withAlphaComponent(0.12)
        box.borderColor = NSColor.systemPurple.withAlphaComponent(0.3)
        box.borderWidth = 1
        box.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "eye.slash.fill", accessibilityDescription: nil)
        icon.contentTintColor = .systemPurple
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: "Both icons are hidden. ZappDesk is running completely invisibly in the background. Press ⌥⌘, (Option + Command + Comma) anytime to open Settings.")
        hiddenLabel = label
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
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

    private func makeSummonInfoBox() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.cornerRadius = Layout.groupCornerRadius
        box.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5)
        box.borderColor = NSColor.separatorColor.withAlphaComponent(0.2)
        box.borderWidth = 1
        box.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "How to open ZappDesk when hidden:")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .labelColor

        let item1 = NSTextField(wrappingLabelWithString: GlobalHotkeyManager.shared.settingsHint)
        hotkeyLabel = item1
        item1.font = .systemFont(ofSize: 11)
        item1.textColor = .secondaryLabelColor

        let item2 = NSTextField(labelWithString: "• Terminal:  open zappdesk://settings")
        item2.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        item2.textColor = .secondaryLabelColor

        let item3 = NSTextField(labelWithString: "• Finder / Spotlight:  Open ZappDesk again to bring up Settings")
        item3.font = .systemFont(ofSize: 11)
        item3.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, item1, item2, item3])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14)
        ])
        return box
    }

    private func updateHiddenNoticeVisibility() {
        let bothHidden = !AppState.shared.showMenuBarIcon && !AppState.shared.showDockIcon
        hiddenNoticeBox.isHidden = !bothHidden
    }

    @objc private func menuBarToggleChanged() {
        AppState.shared.showMenuBarIcon = (menuBarToggle.state == .on)
        updateHiddenNoticeVisibility()
    }

    @objc private func dockToggleChanged() {
        AppState.shared.showDockIcon = (dockToggle.state == .on)
        updateHiddenNoticeVisibility()
    }
}
