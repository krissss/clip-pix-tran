import AppKit
import QuartzCore
import SwiftUI

struct ScreenRecordingGIFExportSheet: View {
    private static let minimumWindowSize = NSSize(width: 920, height: 620)
    private static let idealWindowSize = NSSize(width: 1160, height: 760)

    let item: ScreenshotItem
    @Binding var options: ScreenRecordingGIFExportOptions
    let exportAction: (ScreenRecordingGIFExportOptions) -> Void
    let cancelAction: () -> Void

    @State private var preview: ScreenRecordingGIFPreview?
    @State private var isLoadingPreview = false
    @State private var didLoadPreview = false

    private let maximumPreviewPixelSize: CGFloat = 720

    private var sanitizedOptions: ScreenRecordingGIFExportOptions {
        options.sanitized
    }

    private var sourceDuration: TimeInterval {
        max(item.duration ?? 0, 0)
    }

    private var outputDuration: TimeInterval {
        guard sourceDuration > 0 else {
            return 0
        }

        return sourceDuration / sanitizedOptions.playbackSpeed
    }

    private var estimatedFrameCount: Int {
        guard outputDuration > 0 else {
            return 0
        }

        return min(
            max(Int(ceil(outputDuration * sanitizedOptions.frameRate)), 1),
            sanitizedOptions.maximumFrameCount
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .font(.title3)
                    .foregroundStyle(ControlPanelDesign.tint(for: .pix))

                VStack(alignment: .leading, spacing: 3) {
                    Text("导出 GIF")
                        .font(.headline)

                    Text("\(item.durationText) · \(item.fileSizeText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 18) {
                ScreenRecordingGIFPreviewPlayer(
                    preview: preview,
                    isLoading: isLoadingPreview,
                    didLoad: didLoadPreview
                )
                .layoutPriority(1)

                VStack(alignment: .leading, spacing: 14) {
                    gifOptionsGrid

                    HStack(spacing: 10) {
                        Label("\(estimatedFrameCount) 帧", systemImage: "rectangle.stack")
                        Label(outputDurationText, systemImage: "timer")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                }
                .frame(width: 250, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Spacer()

                Button(action: cancelAction) {
                    Label("取消", systemImage: "xmark")
                }
                .buttonStyle(ControlPanelButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button {
                    exportAction(sanitizedOptions)
                } label: {
                    Label("导出", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(ControlPanelButtonStyle(tint: ControlPanelDesign.tint(for: .pix), prominence: .primary))
            }
        }
        .padding(20)
        .frame(
            minWidth: Self.minimumWindowSize.width,
            idealWidth: Self.idealWindowSize.width,
            maxWidth: 1600,
            minHeight: Self.minimumWindowSize.height,
            idealHeight: Self.idealWindowSize.height,
            maxHeight: 1100,
            alignment: .topLeading
        )
        .presentationSizing(.fitted)
        .background(
            ScreenRecordingGIFExportWindowConfigurator(
                minimumSize: Self.minimumWindowSize,
                idealSize: Self.idealWindowSize
            )
        )
        .task(id: previewTaskID) {
            await reloadPreview()
        }
    }

    private var previewTaskID: String {
        [
            item.recordingFileName ?? item.id.uuidString,
            String(format: "%.2f", sanitizedOptions.frameRate),
            String(format: "%.2f", sanitizedOptions.playbackSpeed),
            String(format: "%.0f", sanitizedOptions.maximumPixelSize),
            "\(sanitizedOptions.maximumFrameCount)"
        ].joined(separator: "-")
    }

    private var gifOptionsGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 12) {
            GridRow {
                Text("帧率")
                    .foregroundStyle(.secondary)

                ScreenRecordingGIFDoubleInput(
                    value: $options.frameRate,
                    lowerBound: 1,
                    step: 1,
                    unit: "fps",
                    maximumFractionDigits: 0,
                    roundsToStep: true
                )
            }

            GridRow {
                Text("速度")
                    .foregroundStyle(.secondary)

                ScreenRecordingGIFDoubleInput(
                    value: $options.playbackSpeed,
                    lowerBound: 0.25,
                    upperBound: 4,
                    step: 0.25,
                    unit: "x",
                    maximumFractionDigits: 2
                )
            }

            GridRow {
                Text("最大边长")
                    .foregroundStyle(.secondary)

                ScreenRecordingGIFDoubleInput(
                    value: maximumPixelSizeInput,
                    lowerBound: 320,
                    upperBound: 1920,
                    step: 10,
                    unit: "px",
                    maximumFractionDigits: 0
                )
            }

            GridRow {
                Text("最大帧数")
                    .foregroundStyle(.secondary)

                ScreenRecordingGIFIntegerInput(
                    value: $options.maximumFrameCount,
                    lowerBound: 1,
                    step: 30,
                    unit: "帧"
                )
            }
        }
        .font(.callout)
    }

    private var maximumPixelSizeInput: Binding<Double> {
        Binding {
            Double(options.maximumPixelSize)
        } set: { value in
            options.maximumPixelSize = CGFloat(value)
        }
    }

    private func reloadPreview() async {
        preview = nil
        isLoadingPreview = true
        didLoadPreview = false

        do {
            try await Task.sleep(nanoseconds: 250_000_000)
        } catch {
            return
        }

        guard let url = item.recordingURL else {
            isLoadingPreview = false
            didLoadPreview = true
            return
        }

        let nextPreview = await ScreenRecordingGIFPreviewRenderer.preview(
            from: url,
            options: sanitizedOptions,
            maximumFrameCount: sanitizedOptions.maximumFrameCount,
            maximumPixelSize: min(sanitizedOptions.maximumPixelSize, maximumPreviewPixelSize)
        )

        if Task.isCancelled {
            return
        }

        preview = nextPreview
        isLoadingPreview = false
        didLoadPreview = true
    }

    private var outputDurationText: String {
        let totalSeconds = max(Int(outputDuration.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct ScreenRecordingGIFPreviewPlayer: View {
    let preview: ScreenRecordingGIFPreview?
    let isLoading: Bool
    let didLoad: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous)
                    .fill(.quaternary)

                if let preview {
                    ScreenRecordingGIFPreviewLayerPlayer(preview: preview)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else if isLoading {
                    ProgressView()
                        .controlSize(.regular)
                } else if didLoad {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "play.rectangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous)
                    .stroke(.quaternary)
            }
            .overlay(alignment: .bottomTrailing) {
                if let preview {
                    Text(previewBadgeText(for: preview))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.58))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .padding(8)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func previewBadgeText(for preview: ScreenRecordingGIFPreview) -> String {
        if preview.isTruncated {
            return "\(preview.frames.count) 帧 · 前 \(preview.previewedDuration.gifPreviewDurationText)"
        }

        return "\(preview.frames.count) 帧预览"
    }
}

private struct ScreenRecordingGIFPreviewLayerPlayer: NSViewRepresentable {
    let preview: ScreenRecordingGIFPreview

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true

        let layer = CALayer()
        layer.contentsGravity = .resizeAspect
        layer.masksToBounds = true
        view.layer = layer

        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let layer = view.layer else {
            return
        }

        context.coordinator.update(preview: preview, layer: layer)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private var previewID: UUID?
        private var frames: [CGImage] = []
        private var frameDelay: TimeInterval = 0.1
        private var frameIndex = 0
        private var timer: Timer?
        private weak var layer: CALayer?

        func update(preview: ScreenRecordingGIFPreview, layer: CALayer) {
            self.layer = layer

            guard previewID != preview.id else {
                return
            }

            previewID = preview.id
            frames = preview.frames
            frameDelay = preview.frameDelay.isFinite && preview.frameDelay > 0
                ? preview.frameDelay
                : 0.1
            frameIndex = 0

            displayCurrentFrame()
            restartTimerIfNeeded()
        }

        func stop() {
            timer?.invalidate()
            timer = nil
            frames = []
            previewID = nil
            layer?.contents = nil
        }

        private func restartTimerIfNeeded() {
            timer?.invalidate()
            timer = nil

            guard frames.count > 1 else {
                return
            }

            let timer = Timer(timeInterval: frameDelay, repeats: true) { [weak self] _ in
                self?.advanceFrame()
            }
            timer.tolerance = min(frameDelay * 0.1, 0.005)
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        private func advanceFrame() {
            guard !frames.isEmpty else {
                stop()
                return
            }

            frameIndex = (frameIndex + 1) % frames.count
            displayCurrentFrame()
        }

        private func displayCurrentFrame() {
            guard !frames.isEmpty,
                  let layer else {
                return
            }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.contents = frames[min(frameIndex, frames.count - 1)]
            CATransaction.commit()
        }
    }
}

private struct ScreenRecordingGIFExportWindowConfigurator: NSViewRepresentable {
    let minimumSize: NSSize
    let idealSize: NSSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            configure(window: view.window, coordinator: context.coordinator)
        }

        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: view.window, coordinator: context.coordinator)
        }
    }

    private func configure(window: NSWindow?, coordinator: Coordinator) {
        guard let window else {
            return
        }

        window.styleMask.insert(.resizable)
        window.contentMinSize = minimumSize

        guard coordinator.sizedWindow !== window else {
            return
        }

        coordinator.sizedWindow = window

        if window.frame.width < idealSize.width || window.frame.height < idealSize.height {
            var frame = window.frame
            frame.size.width = max(frame.width, idealSize.width)
            frame.size.height = max(frame.height, idealSize.height)
            window.setFrame(frame, display: true, animate: false)
            window.center()
        }
    }

    final class Coordinator {
        weak var sizedWindow: NSWindow?
    }
}

private struct ScreenRecordingGIFDoubleInput: View {
    @Binding var value: Double
    let lowerBound: Double
    var upperBound: Double?
    let step: Double
    let unit: String
    let maximumFractionDigits: Int
    var roundsToStep = false

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $text)
                .focused($isFocused)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 76)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commitText)
                .onChange(of: text) { _, newValue in
                    updateValue(from: newValue)
                }
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        text = formatted(value)
                    } else {
                        commitText()
                    }
                }
                .onChange(of: value) { _, newValue in
                    guard !isFocused else {
                        return
                    }

                    text = formatted(clampedValue(newValue))
                }

            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            Stepper("", value: stepperBinding, step: step)
                .labelsHidden()
        }
        .onAppear {
            text = formatted(clampedValue(value))
        }
    }

    private var stepperBinding: Binding<Double> {
        Binding {
            clampedValue(value)
        } set: { newValue in
            let nextValue = clampedValue(newValue)
            value = nextValue
            text = formatted(nextValue)
        }
    }

    private func updateValue(from newText: String) {
        guard let parsed = Double(newText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }

        value = clampedValue(parsed)
    }

    private func commitText() {
        let nextValue = clampedValue(parsedTextValue ?? value)
        value = nextValue
        text = formatted(nextValue)
    }

    private var parsedTextValue: Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(
            .number
                .grouping(.never)
                .precision(.fractionLength(0...maximumFractionDigits))
        )
    }

    private func clampedValue(_ nextValue: Double) -> Double {
        let steppedValue: Double
        if roundsToStep, step > 0 {
            steppedValue = (nextValue / step).rounded() * step
        } else {
            steppedValue = nextValue
        }

        return steppedValue.gifInputBounded(lowerBound: lowerBound, upperBound: upperBound)
    }
}

private struct ScreenRecordingGIFIntegerInput: View {
    @Binding var value: Int
    let lowerBound: Int
    var upperBound: Int?
    let step: Int
    let unit: String

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $text)
                .focused($isFocused)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 76)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commitText)
                .onChange(of: text) { _, newValue in
                    updateValue(from: newValue)
                }
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        text = "\(value)"
                    } else {
                        commitText()
                    }
                }
                .onChange(of: value) { _, newValue in
                    guard !isFocused else {
                        return
                    }

                    text = "\(newValue.gifInputBounded(lowerBound: lowerBound, upperBound: upperBound))"
                }

            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            Stepper("", value: stepperBinding, step: step)
                .labelsHidden()
        }
        .onAppear {
            text = "\(value.gifInputBounded(lowerBound: lowerBound, upperBound: upperBound))"
        }
    }

    private var stepperBinding: Binding<Int> {
        Binding {
            value.gifInputBounded(lowerBound: lowerBound, upperBound: upperBound)
        } set: { newValue in
            let clampedValue = newValue.gifInputBounded(lowerBound: lowerBound, upperBound: upperBound)
            value = clampedValue
            text = "\(clampedValue)"
        }
    }

    private func updateValue(from newText: String) {
        guard let parsed = Int(newText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }

        value = parsed.gifInputBounded(lowerBound: lowerBound, upperBound: upperBound)
    }

    private func commitText() {
        let clampedValue = (parsedTextValue ?? value).gifInputBounded(
            lowerBound: lowerBound,
            upperBound: upperBound
        )
        value = clampedValue
        text = "\(clampedValue)"
    }

    private var parsedTextValue: Int? {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private extension Comparable {
    func gifInputBounded(lowerBound: Self, upperBound: Self?) -> Self {
        let lowerBoundedValue = max(self, lowerBound)
        guard let upperBound else {
            return lowerBoundedValue
        }

        return min(lowerBoundedValue, upperBound)
    }
}

private extension TimeInterval {
    var gifPreviewDurationText: String {
        let totalSeconds = max(Int(rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
