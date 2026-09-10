/*
 * SettingsWindow.swift — ZappDesk
 *
 * Preferences window controller with modern macOS sidebar layout.
 */

import AppKit

enum SettingsPane: Int, CaseIterable {
    case autoStart
    case features
    case visibility
    case about

    var title: String {
        switch self {
        case .autoStart:  return "Auto-Start"
        case .features:   return "Features"
        case .visibility: return "Visibility"
        case .about:      return "About"
        }
    }

    var symbol: String {
        switch self {
        case .autoStart:  return "power"
        case .features:   return "bolt.fill"
        case .visibility: return "eye"
        case .about:      return "info.circle"
        }
    }
}

final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var splitViewController: NSSplitViewController?
    private var sidebarController: SettingsSidebarController?
    private let contentHost = ContentHostController()
    private var paneControllers: [SettingsPane: NSViewController] = [:]
    private var currentPane: NSViewController?

    func show(pane: SettingsPane = .features) {
        GlobalHotkeyManager.shared.register()
        if window == nil {
            window = makeWindow()
        }
        guard let win = window else { return }
        let winWidth = Layout.sidebarWidth + Layout.contentWidth
        let winHeight = Layout.windowHeight
        win.setContentSize(NSSize(width: winWidth, height: winHeight))
        selectPane(pane)
        win.center()
        win.makeKeyAndOrderFront(nil)
        win.layoutIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
    }

    func selectPane(_ pane: SettingsPane) {
        sidebarController?.select(pane)
        showPane(pane)
    }

    private func makeWindow() -> NSWindow {
        let winWidth = Layout.sidebarWidth + Layout.contentWidth
        let winHeight = Layout.windowHeight

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winWidth, height: winHeight),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "ZappDesk Settings"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: winWidth, height: winHeight)
        win.setContentSize(NSSize(width: winWidth, height: winHeight))
        win.delegate = self

        let splitVC = NSSplitViewController()
        splitViewController = splitVC
        splitVC.splitView.isVertical = true
        splitVC.splitView.dividerStyle = .thin

        let sidebarVC = SettingsSidebarController { [weak self] selectedPane in
            self?.showPane(selectedPane)
        }
        sidebarController = sidebarVC

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = Layout.sidebarWidth
        sidebarItem.maximumThickness = Layout.sidebarWidth
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.holdingPriority = .defaultHigh
        splitVC.addSplitViewItem(sidebarItem)

        let contentItem = NSSplitViewItem(viewController: contentHost)
        contentItem.minimumThickness = Layout.contentWidth
        contentItem.holdingPriority = .defaultLow
        splitVC.addSplitViewItem(contentItem)

        win.contentViewController = splitVC
        return win
    }

    private func showPane(_ pane: SettingsPane) {
        let controller: NSViewController
        if let existing = paneControllers[pane] {
            controller = existing
        } else {
            switch pane {
            case .autoStart:  controller = AutoStartPaneController()
            case .features:   controller = FeaturesPaneController()
            case .visibility: controller = VisibilityPaneController()
            case .about:      controller = AboutPaneController()
            }
            paneControllers[pane] = controller
            contentHost.addChild(controller)
        }

        guard controller !== currentPane else { return }

        currentPane?.view.removeFromSuperview()
        currentPane = controller

        let container = contentHost.view
        let paneView = controller.view
        paneView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(paneView)

        NSLayoutConstraint.activate([
            paneView.topAnchor.constraint(equalTo: container.topAnchor),
            paneView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            paneView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            paneView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        container.layoutSubtreeIfNeeded()
    }
}

private final class ContentHostController: NSViewController {
    override func loadView() {
        let v = NSView()
        v.wantsLayer = true
        v.translatesAutoresizingMaskIntoConstraints = false
        view = v
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.contentWidth)
        ])
    }
}

// MARK: - Sidebar Controller

private final class SettingsSidebarController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    private let onSelectPane: (SettingsPane) -> Void
    private var tableView: NSTableView!
    private let panes = SettingsPane.allCases
    private var isSelectingProgrammatically = false

    init(onSelect: @escaping (SettingsPane) -> Void) {
        self.onSelectPane = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false

        let table = NSTableView()
        table.style = .sourceList
        table.headerView = nil
        table.rowHeight = 32
        table.backgroundColor = .clear

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("PaneCol"))
        table.addTableColumn(col)
        table.dataSource = self
        table.delegate = self

        scroll.documentView = table
        tableView = table
        view = scroll
    }

    func select(_ pane: SettingsPane) {
        _ = view
        guard let idx = panes.firstIndex(of: pane) else { return }
        if tableView.selectedRow != idx {
            isSelectingProgrammatically = true
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            isSelectingProgrammatically = false
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return panes.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let pane = panes[row]
        let cell = NSTableCellView()

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: nil)
        icon.contentTintColor = .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let text = NSTextField(labelWithString: pane.title)
        text.font = .systemFont(ofSize: 13, weight: .medium)
        text.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [icon, text])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSelectingProgrammatically else { return }
        let selected = tableView.selectedRow
        guard selected >= 0 && selected < panes.count else { return }
        onSelectPane(panes[selected])
    }
}
