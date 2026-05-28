import AppKit
import SwiftUI

@MainActor
final class ClipboardQuickPanelPresenter {
    private var panel: KeyboardHandlingPanel?
    private weak var monitor: ClipboardMonitor?
    private weak var previousApplication: NSRunningApplication?
    private var localMouseDownMonitor: Any?
    private var globalMouseDownMonitor: Any?
    private var resignKeyObserver: Any?
    var openFullClipboardAction: (() -> Void)?

    func toggle(monitor: ClipboardMonitor) {
        if let panel, panel.isVisible {
            dismiss()
            return
        }

        show(monitor: monitor)
    }

    func show(monitor: ClipboardMonitor) {
        self.monitor = monitor
        previousApplication = NSWorkspace.shared.frontmostApplication

        if panel == nil {
            panel = makePanel()
        }

        guard let panel else {
            return
        }

        let rootView = ClipboardQuickPanelView(
            monitor: monitor,
            onSelect: { [weak self] item in
                self?.select(item)
            },
            onSelectPlainText: { [weak self] item in
                self?.select(item, asPlainText: true)
            },
            onOpenFullClipboard: { [weak self] in
                self?.openFullClipboard()
            },
            onClose: { [weak self] in
                self?.dismiss()
            }
        )

        panel.contentView = NSHostingView(rootView: rootView)
        panel.setFrameOrigin(panelOrigin(for: panel.frame.size))
        panel.deminiaturize(nil)
        panel.orderFrontRegardless()
        panel.makeKey()
        installAutoDismissObservers(for: panel)
    }

    private func select(_ item: ClipboardItem, asPlainText: Bool = false) {
        guard let monitor else {
            return
        }

        if asPlainText, item.isText {
            monitor.copyPlainTextToPasteboard(item)
        } else {
            monitor.copyToPasteboard(item)
        }
        dismiss()

        previousApplication?.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Self.pasteIntoFocusedField()
        }
    }

    private func openFullClipboard() {
        dismiss()
        openFullClipboardAction?()
    }

    private func makePanel() -> KeyboardHandlingPanel {
        let panel = KeyboardHandlingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 430),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        return panel
    }

    private func dismiss() {
        removeAutoDismissObservers()
        panel?.orderOut(nil)
    }

    private func installAutoDismissObservers(for panel: NSPanel) {
        removeAutoDismissObservers()

        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else {
                return event
            }

            if self.shouldDismissForCurrentMouseLocation() {
                self.dismiss()
            }

            return event
        }

        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.dismiss()
            }
        }

        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.dismiss()
            }
        }
    }

    private func removeAutoDismissObservers() {
        if let localMouseDownMonitor {
            NSEvent.removeMonitor(localMouseDownMonitor)
            self.localMouseDownMonitor = nil
        }

        if let globalMouseDownMonitor {
            NSEvent.removeMonitor(globalMouseDownMonitor)
            self.globalMouseDownMonitor = nil
        }

        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
            self.resignKeyObserver = nil
        }
    }

    private func shouldDismissForCurrentMouseLocation() -> Bool {
        guard let panel, panel.isVisible else {
            return false
        }

        return !panel.frame.contains(NSEvent.mouseLocation)
    }

    private func panelOrigin(for size: CGSize) -> CGPoint {
        let anchor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main else {
            return CGPoint(x: anchor.x, y: anchor.y)
        }

        return ClipboardQuickPanelPositioning.panelOrigin(
            near: anchor,
            panelSize: size,
            visibleFrame: screen.visibleFrame
        )
    }

    private static func pasteIntoFocusedField() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        let keyCodeV: CGKeyCode = 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

enum ClipboardQuickPanelPositioning {
    static func panelOrigin(
        near anchor: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 8,
        margin: CGFloat = 12
    ) -> CGPoint {
        let minX = visibleFrame.minX + margin
        let maxX = max(minX, visibleFrame.maxX - panelSize.width - margin)
        let spaceRight = visibleFrame.maxX - anchor.x
        let spaceLeft = anchor.x - visibleFrame.minX
        let placeRight = spaceRight >= panelSize.width + gap || spaceRight >= spaceLeft
        let unclampedX = placeRight ? anchor.x + gap : anchor.x - panelSize.width - gap
        let x = min(max(unclampedX, minX), maxX)

        let minY = visibleFrame.minY + margin
        let maxY = max(minY, visibleFrame.maxY - panelSize.height - margin)
        let spaceBelow = anchor.y - visibleFrame.minY
        let spaceAbove = visibleFrame.maxY - anchor.y
        let placeBelow = spaceBelow >= panelSize.height + gap || spaceBelow >= spaceAbove
        let unclampedY = placeBelow ? anchor.y - panelSize.height - gap : anchor.y + gap
        let y = min(max(unclampedY, minY), maxY)

        return CGPoint(
            x: x,
            y: y
        )
    }
}

private final class KeyboardHandlingPanel: NSPanel {
    var keyDownHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyDownHandler?(event) == true {
            return
        }

        super.sendEvent(event)
    }
}

private struct ClipboardQuickPanelView: View {
    @Bindable var monitor: ClipboardMonitor
    let onSelect: (ClipboardItem) -> Void
    let onSelectPlainText: (ClipboardItem) -> Void
    let onOpenFullClipboard: () -> Void
    let onClose: () -> Void

    @State private var searchText = ""
    @State private var selectedItemID: ClipboardItem.ID?
    @FocusState private var searchFieldFocused: Bool

    private var visibleItems: [ClipboardItem] {
        monitor.history.filteredItems(matching: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(.secondary)

                TextField("搜索剪贴板历史", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFieldFocused)

                Button(action: onOpenFullClipboard) {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.borderless)
                .help("打开完整剪贴板")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("关闭")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if visibleItems.isEmpty {
                ContentUnavailableView(
                    "没有匹配记录",
                    systemImage: "doc.text.magnifyingglass"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleItems) { item in
                                ClipboardQuickPanelRow(
                                    item: item,
                                    isSelected: item.id == selectedVisibleItemID
                                ) {
                                    onSelect(item)
                                }
                                .id(item.id)

                                if item.id != visibleItems.last?.id {
                                    Divider()
                                        .padding(.leading, 66)
                                }
                            }
                        }
                    }
                    .onChange(of: selectedVisibleItemID) { _, selectedID in
                        if let selectedID {
                            withAnimation(.snappy(duration: 0.12)) {
                                proxy.scrollTo(selectedID, anchor: .center)
                            }
                        }
                    }
                }
            }

            Divider()

            shortcutHints
        }
        .frame(width: 420, height: 430)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary)
        }
        .background(KeyboardEventBridge { event in
            handleKeyDown(event)
        })
        .onAppear {
            selectedItemID = visibleItems.first?.id
            searchFieldFocused = true
        }
        .onChange(of: visibleItems.map(\.id)) { _, ids in
            guard let selectedItemID, ids.contains(selectedItemID) else {
                self.selectedItemID = ids.first
                return
            }
        }
    }

    private var selectedVisibleItemID: ClipboardItem.ID? {
        if let selectedItemID, visibleItems.contains(where: { $0.id == selectedItemID }) {
            return selectedItemID
        }

        return visibleItems.first?.id
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 76:
            guard let item = selectedVisibleItem else {
                return false
            }

            if event.modifierFlags.contains(.command) {
                onSelectPlainText(item)
            } else {
                onSelect(item)
            }
            return true
        case 53:
            onClose()
            return true
        case 125:
            moveSelection(offset: 1)
            return true
        case 126:
            moveSelection(offset: -1)
            return true
        default:
            return false
        }
    }

    private var selectedVisibleItem: ClipboardItem? {
        guard let selectedVisibleItemID else {
            return nil
        }

        return visibleItems.first { $0.id == selectedVisibleItemID }
    }

    private func moveSelection(offset: Int) {
        guard !visibleItems.isEmpty else {
            return
        }

        let currentIndex = selectedVisibleItemID.flatMap { selectedItemID in
            visibleItems.firstIndex { $0.id == selectedItemID }
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), visibleItems.count - 1)
        selectedItemID = visibleItems[nextIndex].id
    }

    private var shortcutHints: some View {
        HStack(spacing: 10) {
            ShortcutHint(keys: "↑↓", title: "选择")
            ShortcutHint(keys: "Enter", title: "粘贴")
            ShortcutHint(keys: "⌘Enter", title: "纯文本")
            ShortcutHint(keys: "Esc", title: "关闭")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShortcutHint: View {
    let keys: String
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quinary)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(title)
        }
    }
}

private struct ClipboardQuickPanelRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                preview

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.displayTitle)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Label(item.kind.displayName, systemImage: item.kind.systemImage)
                            .labelStyle(.titleAndIcon)

                        RelativeTimeText(date: item.lastCopiedAt)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.16))
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var preview: some View {
        if item.kind == .image, let imageData = item.imageData {
            ImageThumbnailView(
                data: imageData,
                size: CGSize(width: 42, height: 42)
            )
        } else {
            Image(systemName: item.kind.systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 42)
                .background(.quinary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct KeyboardEventBridge: NSViewRepresentable {
    let handler: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        KeyboardEventBridgeView(handler: handler)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyboardEventBridgeView)?.handler = handler
    }
}

private final class KeyboardEventBridgeView: NSView {
    var handler: (NSEvent) -> Bool

    init(handler: @escaping (NSEvent) -> Bool) {
        self.handler = handler
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        (window as? KeyboardHandlingPanel)?.keyDownHandler = { [weak self] event in
            self?.handler(event) ?? false
        }
    }

    deinit {
        (window as? KeyboardHandlingPanel)?.keyDownHandler = nil
    }
}
