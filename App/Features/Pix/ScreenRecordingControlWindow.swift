import AppKit
import SwiftUI

@MainActor
final class ScreenRecordingControlWindow {
    private var window: ScreenRecordingPanel?
    private let stopAction: () -> Void
    private let cancelAction: () -> Void
    private var startedAt: Date
    private var elapsed: TimeInterval = 0
    private var timer: Timer?

    init(
        startedAt: Date,
        stopAction: @escaping () -> Void,
        cancelAction: @escaping () -> Void
    ) {
        self.startedAt = startedAt
        self.stopAction = stopAction
        self.cancelAction = cancelAction
    }

    var excludedWindowIDs: Set<CGWindowID> {
        guard let window else {
            return []
        }

        return [CGWindowID(window.windowNumber)]
    }

    func show() {
        close()

        elapsed = Date().timeIntervalSince(startedAt)
        let hostingView = NSHostingView(rootView: controlView)
        hostingView.frame = CGRect(x: 0, y: 0, width: 180, height: 42)
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        hostingView.frame = CGRect(
            x: 0,
            y: 0,
            width: max(fittingSize.width, 1),
            height: max(fittingSize.height, 1)
        )

        let panel = ScreenRecordingPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.cancelHandler = { [weak self] in
            self?.cancelAction()
        }
        position(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        self.window = panel

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
    }

    func updateStartedAt(_ startedAt: Date) {
        self.startedAt = startedAt
        tick()
    }

    private var controlView: ScreenRecordingControlView {
        ScreenRecordingControlView(
            elapsed: elapsed,
            stopAction: stopAction,
            cancelAction: cancelAction
        )
    }

    private func tick() {
        elapsed = Date().timeIntervalSince(startedAt)
        guard let hostingView = window?.contentView as? NSHostingView<ScreenRecordingControlView> else {
            return
        }

        hostingView.rootView = controlView
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else {
            return
        }

        let padding: CGFloat = 16
        let frame = panel.frame
        let visibleFrame = screen.visibleFrame
        let origin = CGPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.maxY - frame.height - padding
        )
        panel.setFrameOrigin(origin)
    }
}

private final class ScreenRecordingPanel: NSPanel {
    var cancelHandler: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown where event.keyCode == 53:
            cancelHandler?()
        case .rightMouseDown:
            cancelHandler?()
        default:
            super.sendEvent(event)
        }
    }
}

private struct ScreenRecordingControlView: View {
    let elapsed: TimeInterval
    let stopAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)

            Text(Self.elapsedText(elapsed))
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .frame(minWidth: 48, alignment: .leading)

            Button(action: stopAction) {
                Image(systemName: "stop.fill")
                    .frame(width: 22, height: 22)
            }
            .help("停止并保存录屏")

            Button(action: cancelAction) {
                Image(systemName: "xmark")
                    .frame(width: 22, height: 22)
            }
            .help("取消录屏")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18))
        }
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        .fixedSize()
    }

    private static func elapsedText(_ elapsed: TimeInterval) -> String {
        let elapsed = max(Int(elapsed.rounded(.down)), 0)
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
