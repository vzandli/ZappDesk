/*
 * UIComponents.swift — ZappDesk
 *
 * Reusable AppKit UI layout components matching modern macOS system settings.
 */

import AppKit

enum Layout {
    static let sidebarWidth: CGFloat       = 200
    static let contentWidth: CGFloat       = 480
    static let windowHeight: CGFloat       = 480
    static let rowHorizontalPad: CGFloat   = 16
    static let rowVerticalPad: CGFloat     = 10
    static let groupCornerRadius: CGFloat  = 10
    static let spacingBetweenGroups: CGFloat = 14
}

final class SettingsGroupBox: NSBox {
    init(views: [NSView]) {
        super.init(frame: .zero)
        boxType = .custom
        titlePosition = .noTitle
        cornerRadius = Layout.groupCornerRadius
        borderWidth = 1
        borderColor = NSColor.separatorColor.withAlphaComponent(0.2)
        fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false

        for v in views {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        contentView = stack
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

func settingsRow(
    label: String,
    control: NSView,
    subtitle: NSView? = nil
) -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let titleLabel = NSTextField(labelWithString: label)
    titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
    titleLabel.textColor = .labelColor
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    control.setAccessibilityLabel(label)
    control.translatesAutoresizingMaskIntoConstraints = false
    control.setContentHuggingPriority(.required, for: .horizontal)
    control.setContentCompressionResistancePriority(.required, for: .horizontal)

    container.addSubview(titleLabel)
    container.addSubview(control)

    var constraints = [
        titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.rowHorizontalPad),
        titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -12),
        control.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.rowHorizontalPad),
        control.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor)
    ]

    if let sub = subtitle {
        container.addSubview(sub)
        sub.translatesAutoresizingMaskIntoConstraints = false
        sub.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sub.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        constraints.append(contentsOf: [
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: Layout.rowVerticalPad),
            sub.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            sub.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            sub.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -12),
            sub.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Layout.rowVerticalPad)
        ])
    } else {
        constraints.append(contentsOf: [
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: Layout.rowVerticalPad + 2),
            titleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Layout.rowVerticalPad - 2)
        ])
    }

    NSLayoutConstraint.activate(constraints)
    return container
}

func rowDivider() -> NSView {
    let div = NSBox()
    div.boxType = .separator
    div.translatesAutoresizingMaskIntoConstraints = false
    div.heightAnchor.constraint(equalToConstant: 1).isActive = true
    return div
}
