import AppKit
import QuartzCore
import SwiftUI

struct PixView: View {
    @Bindable var controller: ScreenshotController

    @State private var selectedItemID: ScreenshotItem.ID?
    @State private var searchText = ""
    @State private var showsClearHistoryConfirmation = false
    @State private var gifExportItem: ScreenshotItem?
    @State private var gifExportOptions = ScreenRecordingGIFExportOptions()

    private var visibleItems: [ScreenshotItem] {
        controller.history.items.filtered(matching: searchText)
    }

    private var selectedItem: ScreenshotItem? {
        guard let selectedItemID,
              let selectedItem = visibleItems.first(where: { $0.id == selectedItemID }) else {
            return visibleItems.first
        }

        return selectedItem
    }

    var body: some View {
        GeometryReader { proxy in
            let sidebarWidth = ControlPanelDesign.Layout.historySidebarWidth(for: proxy.size.width)

            HStack(spacing: ControlPanelDesign.Layout.splitSpacing) {
                sidebar
                    .frame(width: sidebarWidth)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Pix")
        .background(ControlPanelBackground())
        .onAppear(perform: selectFirstVisibleItemIfNeeded)
        .onChange(of: visibleItems.map(\.id)) { _, _ in
            selectFirstVisibleItemIfNeeded()
        }
        .confirmationDialog(
            "清空 Pix 历史？",
            isPresented: $showsClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空历史", role: .destructive) {
                clearHistory()
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除全部截图和录屏历史记录，无法撤销。")
        }
        .sheet(item: $gifExportItem) { item in
            ScreenRecordingGIFExportSheet(
                item: item,
                options: $gifExportOptions,
                exportAction: { options in
                    controller.exportGIF(item, options: options)
                    gifExportItem = nil
                },
                cancelAction: {
                    gifExportItem = nil
                }
            )
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader

            ControlPanelSearchField(text: $searchText, prompt: "搜索 Pix 历史")
                .padding(.horizontal, ControlPanelDesign.Layout.searchHorizontalPadding)
                .padding(.bottom, 10)

            sidebarContent
        }
        .controlPanelSidebarSurface()
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            ControlPanelSidebarHeader(
                title: "Pix 历史",
                systemImage: "camera.viewfinder",
                tint: ControlPanelDesign.tint(for: .pix)
            ) {
                Text("\(controller.history.items.count)/\(controller.history.limit)")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            PixCaptureControls(
                mode: $controller.captureMode,
                isCapturing: controller.isCapturing,
                isRecording: controller.isRecording,
                isStoppingRecording: controller.isStoppingRecording,
                captureSelectedRegionAction: captureSelectedRegion,
                captureMainDisplayAction: captureMainDisplay,
                startRecordingAction: startRecording,
                stopCaptureAction: controller.stopCapture
            )
        }
        .padding(.horizontal, ControlPanelDesign.Layout.headerHorizontalPadding)
        .padding(.vertical, 10)
        .frame(minHeight: 96)
    }

    @ViewBuilder
    private var sidebarContent: some View {
        if controller.history.items.isEmpty {
            ControlPanelEmptyState(
                title: "暂无截图",
                systemImage: "camera.viewfinder",
                tint: ControlPanelDesign.tint(for: .pix)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleItems.isEmpty {
            ControlPanelNoResultsState(
                title: "没有匹配 Pix 记录",
                systemImage: "photo.badge.magnifyingglass"
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selectedItemID) {
                Section {
                    historyActions
                }

                ForEach(visibleItems) { item in
                    ScreenshotItemRow(item: item)
                        .tag(item.id)
                        .controlPanelListRow(
                            isSelected: item.id == selectedItemID,
                            tint: ControlPanelDesign.tint(for: .pix)
                        )
                        .contextMenu {
                            contextMenu(for: item)
                        }
                        .onTapGesture {
                            selectedItemID = item.id
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var historyActions: some View {
        HStack {
            Label("\(visibleItems.count) 项记录", systemImage: "clock")
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive) {
                showsClearHistoryConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(ControlPanelIconButtonStyle(role: .destructive))
            .disabled(controller.history.items.isEmpty)
            .help("清空截图历史")
        }
        .font(.callout)
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var detail: some View {
        Group {
            if let selectedItem {
                ScreenshotItemDetailPane(
                    item: selectedItem,
                    copyAction: {
                        controller.copyToPasteboard(selectedItem)
                    },
                    saveAction: {
                        controller.save(selectedItem)
                    },
                    pinAction: {
                        controller.pinToScreen(selectedItem)
                    },
                    previewAction: {
                        SystemImagePreviewService.openInPreviewApp(item: selectedItem)
                    },
                    exportMP4Action: {
                        controller.exportMP4(selectedItem)
                    },
                    exportGIFAction: {
                        configureGIFExport(for: selectedItem)
                    },
                    deleteAction: {
                        delete(selectedItem)
                    }
                )
            } else {
                ScreenshotEmptyDetailPane(
                    needsScreenRecordingPermission: controller.needsScreenRecordingPermission
                )
            }
        }
        .controlPanelContentSurface()
        .overlay(alignment: .top) {
            statusMessages
        }
    }

    @ViewBuilder
    private var statusMessages: some View {
        VStack(spacing: 8) {
            if let errorMessage = controller.history.persistenceErrorMessage {
                ScreenshotStatusBanner(message: errorMessage)
            }

            if let errorMessage = controller.lastErrorMessage {
                ScreenshotStatusBanner(
                    message: errorMessage,
                    showsSettingsButton: controller.needsScreenRecordingPermission
                )
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private func contextMenu(for item: ScreenshotItem) -> some View {
        if item.isImage {
            Button {
                controller.copyToPasteboard(item)
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }

            Button {
                controller.save(item)
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
            }

            Button {
                controller.pinToScreen(item)
            } label: {
                Label("固定到屏幕", systemImage: "pin")
            }
        } else {
            Button {
                controller.exportMP4(item)
            } label: {
                Label("导出 MP4", systemImage: "film")
            }

            Button {
                configureGIFExport(for: item)
            } label: {
                Label("导出 GIF", systemImage: "square.and.arrow.down")
            }
        }

        Button {
            SystemImagePreviewService.openInPreviewApp(item: item)
        } label: {
            Label("预览", systemImage: "eye")
        }

        Button(role: .destructive) {
            delete(item)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    private func selectFirstVisibleItemIfNeeded() {
        guard !visibleItems.isEmpty else {
            selectedItemID = nil
            return
        }

        if let selectedItemID,
           visibleItems.contains(where: { $0.id == selectedItemID }) {
            return
        }

        selectedItemID = visibleItems.first?.id
    }

    private func delete(_ item: ScreenshotItem) {
        controller.delete(item)
        selectFirstVisibleItemIfNeeded()
    }

    private func clearHistory() {
        controller.clearHistory()
        selectFirstVisibleItemIfNeeded()
    }

    private func captureSelectedRegion() {
        Task {
            await controller.performPrimaryCapture()
        }
    }

    private func captureMainDisplay() {
        Task {
            await controller.captureMainDisplay()
        }
    }

    private func startRecording() {
        Task {
            await controller.startSelectedRegionRecording()
        }
    }

    private func configureGIFExport(for item: ScreenshotItem) {
        gifExportOptions = ScreenRecordingGIFExportOptions()
        gifExportItem = item
    }
}

private struct ScreenshotStatusBanner: View {
    let message: String
    var showsSettingsButton = false

    var body: some View {
        HStack(spacing: 10) {
            ControlPanelStatusBanner(message: message) {
                if showsSettingsButton {
                    Button {
                        openScreenRecordingSettings()
                    } label: {
                        Label("打开系统设置", systemImage: "gearshape")
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

private struct ScreenshotItemRow: View {
    let item: ScreenshotItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            historyThumbnail

            VStack(alignment: .leading, spacing: 5) {
                Text(item.createdAt.absoluteDisplayString)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(item.fileSizeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                RelativeTimeText(date: item.createdAt)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var historyThumbnail: some View {
        if item.isImage {
            ImageThumbnailView(
                data: item.data,
                size: CGSize(width: 48, height: ControlPanelDesign.Layout.historyRowThumbnailSize)
            )
        } else {
            ScreenRecordingThumbnailView(
                item: item,
                size: CGSize(width: 48, height: ControlPanelDesign.Layout.historyRowThumbnailSize),
                maxPixelSize: 240
            )
        }
    }
}

private struct ScreenshotItemDetailPane: View {
    let item: ScreenshotItem
    let copyAction: () -> Void
    let saveAction: () -> Void
    let pinAction: () -> Void
    let previewAction: () -> Void
    let exportMP4Action: () -> Void
    let exportGIFAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            actionBar

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    previewSection
                    metadataSection
                }
                .padding(ControlPanelDesign.Layout.detailContentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .controlPanelContentSurface()
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if item.isImage {
                Button(action: copyAction) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(ControlPanelButtonStyle(tint: ControlPanelDesign.tint(for: .pix), prominence: .primary))
                .help("复制截图")

                Button(action: saveAction) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(ControlPanelIconButtonStyle())
                .help("保存截图")

                Button(action: pinAction) {
                    Image(systemName: "pin")
                }
                .buttonStyle(ControlPanelIconButtonStyle())
                .help("固定到屏幕")
            } else {
                Button(action: exportMP4Action) {
                    Label("MP4", systemImage: "film")
                }
                .buttonStyle(ControlPanelButtonStyle(tint: ControlPanelDesign.tint(for: .pix), prominence: .primary))
                .help("导出 MP4")

                Button(action: exportGIFAction) {
                    Label("GIF", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(ControlPanelButtonStyle())
                .help("导出 GIF")
            }

            Button(action: previewAction) {
                Image(systemName: "eye")
            }
            .buttonStyle(ControlPanelIconButtonStyle())
            .help(item.isImage ? "用系统预览.app打开截图" : "打开录屏")

            Spacer()

            Button(role: .destructive, action: deleteAction) {
                Image(systemName: "trash")
            }
            .buttonStyle(ControlPanelIconButtonStyle(role: .destructive))
            .help("删除截图")
        }
        .controlPanelActionBar()
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ControlPanelSectionLabel(
                    title: item.isImage ? "图片预览" : "录屏预览",
                    systemImage: item.isImage ? "photo" : "video"
                )
            }

            if item.isImage {
                ScreenshotFittedPreviewImage(data: item.data)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(ControlPanelDesign.Layout.detailContentPadding)
                    .controlPanelTextSurface()
            } else {
                ScreenRecordingPreviewCard(item: item, previewAction: previewAction)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(ControlPanelDesign.Layout.detailContentPadding)
                    .controlPanelTextSurface()
            }
        }
        .controlPanelDetailSection()
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ControlPanelSectionLabel(title: "详情", systemImage: "info.circle")

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                ScreenshotMetadataRow(title: "类型", value: item.isImage ? "PNG 图片" : "MP4 录屏")
                ScreenshotMetadataRow(title: "创建时间", value: item.createdAt.absoluteDisplayString)
                ScreenshotMetadataRow(title: "大小", value: item.fileSizeText)
                if item.isImage {
                    ScreenshotMetadataRow(title: "数据", value: "\(item.data.count) bytes")
                } else {
                    ScreenshotMetadataRow(title: "时长", value: item.durationText)
                    if let pixelSize = item.pixelSize {
                        ScreenshotMetadataRow(
                            title: "尺寸",
                            value: "\(Int(pixelSize.width)) x \(Int(pixelSize.height))"
                        )
                    }
                }
            }
        }
        .controlPanelDetailSection()
    }
}

private struct ScreenRecordingPreviewCard: View {
    let item: ScreenshotItem
    let previewAction: () -> Void

    var body: some View {
        Button(action: previewAction) {
            ScreenRecordingThumbnailView(
                item: item,
                size: CGSize(width: 520, height: 292),
                cornerRadius: ControlPanelDesign.compactRadius,
                maxPixelSize: 1100
            ) {
                ZStack {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.58)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 54, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)

                    VStack {
                        Spacer()

                        HStack(alignment: .bottom) {
                            Text(item.durationText)
                                .font(.title3.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.white)

                            Spacer()

                            Text(item.fileSizeText)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        .padding(14)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("打开录屏")
    }
}

private struct ScreenRecordingThumbnailView<Overlay: View>: View {
    let item: ScreenshotItem
    let size: CGSize
    var cornerRadius: CGFloat = ControlPanelDesign.compactRadius
    var maxPixelSize: CGFloat = 480
    @ViewBuilder var overlay: () -> Overlay

    @State private var thumbnailData: Data?
    @State private var didLoadThumbnail = false

    init(
        item: ScreenshotItem,
        size: CGSize,
        cornerRadius: CGFloat = ControlPanelDesign.compactRadius,
        maxPixelSize: CGFloat = 480,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self.item = item
        self.size = size
        self.cornerRadius = cornerRadius
        self.maxPixelSize = maxPixelSize
        self.overlay = overlay
    }

    private var image: Image? {
        guard let thumbnailData,
              let nsImage = NSImage(data: thumbnailData) else {
            return nil
        }

        return Image(nsImage: nsImage)
    }

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                placeholder
            }

            overlay()
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.quaternary)
        }
        .task(id: item.recordingFileName) {
            thumbnailData = nil
            didLoadThumbnail = false
            guard let url = item.recordingURL else {
                didLoadThumbnail = true
                return
            }

            thumbnailData = await ScreenRecordingThumbnailRenderer.pngData(
                from: url,
                maxPixelSize: maxPixelSize
            )
            didLoadThumbnail = true
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.quaternary)
            .overlay {
                if didLoadThumbnail {
                    Image(systemName: "video")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
    }
}

private extension ScreenRecordingThumbnailView where Overlay == EmptyView {
    init(
        item: ScreenshotItem,
        size: CGSize,
        cornerRadius: CGFloat = ControlPanelDesign.compactRadius,
        maxPixelSize: CGFloat = 480
    ) {
        self.init(
            item: item,
            size: size,
            cornerRadius: cornerRadius,
            maxPixelSize: maxPixelSize
        ) {
            EmptyView()
        }
    }
}

private struct ScreenshotFittedPreviewImage: View {
    let data: Data

    @State private var thumbnailData: Data?
    @State private var didLoadThumbnail = false

    private let previewHeight: CGFloat = 320
    private let cornerRadius: CGFloat = ControlPanelDesign.compactRadius

    private var nsImage: NSImage? {
        guard let thumbnailData else {
            return nil
        }

        return NSImage(data: thumbnailData)
    }

    var body: some View {
        GeometryReader { proxy in
            let availableSize = CGSize(
                width: max(1, proxy.size.width),
                height: previewHeight
            )

            ZStack {
                if let nsImage {
                    let displaySize = fittedImageSize(
                        imageSize: nsImage.size,
                        availableSize: availableSize
                    )

                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: displaySize.width, height: displaySize.height)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                } else {
                    placeholder
                }
            }
            .frame(width: proxy.size.width, height: previewHeight)
        }
        .frame(height: previewHeight)
        .frame(maxWidth: .infinity)
        .task(id: data) {
            thumbnailData = nil
            didLoadThumbnail = false
            let sourceData = data
            thumbnailData = await Task.detached(priority: .utility) {
                ImageThumbnailRenderer.pngData(
                    from: sourceData,
                    maxPixelSize: 1400
                )
            }.value
            didLoadThumbnail = true
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if didLoadThumbnail {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
    }

    private func fittedImageSize(
        imageSize: CGSize,
        availableSize: CGSize
    ) -> CGSize {
        guard imageSize.width > 0,
              imageSize.height > 0,
              availableSize.width > 0,
              availableSize.height > 0 else {
            return .zero
        }

        let ratio = min(
            availableSize.width / imageSize.width,
            availableSize.height / imageSize.height
        )

        return CGSize(
            width: imageSize.width * ratio,
            height: imageSize.height * ratio
        )
    }
}

private struct ScreenRecordingGIFExportSheet: View {
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

                Button("取消", action: cancelAction)
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

private struct PixCaptureControls: View {
    @Binding var mode: PixCaptureMode
    let isCapturing: Bool
    let isRecording: Bool
    let isStoppingRecording: Bool
    let captureSelectedRegionAction: () -> Void
    let captureMainDisplayAction: () -> Void
    let startRecordingAction: () -> Void
    let stopCaptureAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("捕获模式", selection: $mode) {
                ForEach(PixCaptureMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(isCapturing || isRecording)

            if isCapturing {
                Button(action: stopCaptureAction) {
                    Label("取消框选", systemImage: "xmark.circle")
                }
                .buttonStyle(ControlPanelButtonStyle(prominence: .destructive))
                .help("结束当前框选")
            } else if isRecording {
                Button(action: stopCaptureAction) {
                    Label(
                        isStoppingRecording ? "正在保存" : "停止录屏",
                        systemImage: isStoppingRecording ? "hourglass" : "stop.circle"
                    )
                }
                .buttonStyle(ControlPanelButtonStyle(prominence: .destructive))
                .disabled(isStoppingRecording)
                .help("停止并保存当前录屏")
            } else {
                HStack(spacing: 10) {
                    switch mode {
                    case .screenshot:
                        Button(action: captureSelectedRegionAction) {
                            Label("选区截图", systemImage: "selection.pin.in.out")
                        }
                        .buttonStyle(ControlPanelButtonStyle(tint: ControlPanelDesign.tint(for: .pix), prominence: .primary))
                        .help("拖拽选择屏幕区域")

                        Button(action: captureMainDisplayAction) {
                            Image(systemName: "display")
                        }
                        .buttonStyle(ControlPanelIconButtonStyle())
                        .help("捕获主屏幕画面")
                    case .recording:
                        Button(action: startRecordingAction) {
                            Label("选区录屏", systemImage: "record.circle")
                        }
                        .buttonStyle(ControlPanelButtonStyle(tint: ControlPanelDesign.tint(for: .pix), prominence: .primary))
                        .help("拖拽选择屏幕区域并开始录屏")
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .controlPanelRoundedSurface(background: ControlPanelDesign.embeddedPanelBackground)
    }
}

private struct ScreenshotEmptyDetailPane: View {
    let needsScreenRecordingPermission: Bool

    var body: some View {
        VStack(spacing: 18) {
            ControlPanelIconTile(
                systemImage: "camera.viewfinder",
                tint: ControlPanelDesign.tint(for: .pix),
                size: 52
            )

            VStack(spacing: 6) {
                Text("还没有截图")
                    .font(.title3.weight(.semibold))
            }

            if needsScreenRecordingPermission {
                Button {
                    openScreenRecordingSettings()
                } label: {
                    Label("打开系统设置", systemImage: "gearshape")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .controlPanelContentSurface()
    }
}

private struct ScreenshotMetadataRow: View {
    let title: String
    let value: String

    var body: some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)

            Text(value)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

private func openScreenRecordingSettings() {
    guard let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    ) else {
        return
    }

    NSWorkspace.shared.open(url)
}

private extension ScreenshotItem {
    var fileSizeText: String {
        ByteCountFormatter.string(
            fromByteCount: byteCount,
            countStyle: .file
        )
    }

    var durationText: String {
        let totalSeconds = max(Int((duration ?? 0).rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private extension [ScreenshotItem] {
    func filtered(matching searchText: String) -> [ScreenshotItem] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchText.isEmpty else {
            return self
        }

        return filter { item in
            item.createdAt.absoluteDisplayString.localizedCaseInsensitiveContains(trimmedSearchText)
                || item.fileSizeText.localizedCaseInsensitiveContains(trimmedSearchText)
                || item.durationText.localizedCaseInsensitiveContains(trimmedSearchText)
        }
    }
}

#Preview {
    PixView(
        controller: ScreenshotController(
            history: .preview,
            screenshotService: PreviewScreenshotService(),
            pasteboard: PreviewScreenshotPasteboardService(),
            fileSaver: PreviewScreenshotFileSaver()
        )
    )
}
