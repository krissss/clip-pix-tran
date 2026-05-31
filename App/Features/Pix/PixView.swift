import AppKit
import SwiftUI

struct PixView: View {
    @Bindable var controller: ScreenshotController

    @State private var selectedItemID: ScreenshotItem.ID?
    @State private var searchText = ""

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
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader

            ControlPanelSearchField(text: $searchText, prompt: "搜索截图历史")
                .padding(.horizontal, ControlPanelDesign.Layout.searchHorizontalPadding)
                .padding(.bottom, 10)

            sidebarContent
        }
        .controlPanelSidebarSurface()
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            ControlPanelSidebarHeader(
                title: "截图历史",
                systemImage: "camera.viewfinder",
                tint: ControlPanelDesign.tint(for: .pix)
            ) {
                Text("\(controller.history.items.count)/\(controller.history.limit)")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            PixCaptureControls(
                isCapturing: controller.isCapturing,
                captureSelectedRegionAction: captureSelectedRegion,
                captureMainDisplayAction: captureMainDisplay,
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
                title: "没有匹配截图",
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
            Label("\(visibleItems.count) 张截图", systemImage: "clock")
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive, action: clearHistory) {
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
            await controller.captureSelectedRegion()
        }
    }

    private func captureMainDisplay() {
        Task {
            await controller.captureMainDisplay()
        }
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
            ImageThumbnailView(
                data: item.data,
                size: CGSize(width: 48, height: ControlPanelDesign.Layout.historyRowThumbnailSize)
            )

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
}

private struct ScreenshotItemDetailPane: View {
    let item: ScreenshotItem
    let copyAction: () -> Void
    let saveAction: () -> Void
    let pinAction: () -> Void
    let previewAction: () -> Void
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

            Button(action: previewAction) {
                Image(systemName: "eye")
            }
            .buttonStyle(ControlPanelIconButtonStyle())
            .help("用系统预览.app打开截图")

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
                ControlPanelSectionLabel(title: "图片预览", systemImage: "photo")
            }

            ScreenshotFittedPreviewImage(data: item.data)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(ControlPanelDesign.Layout.detailContentPadding)
            .controlPanelTextSurface()
        }
        .controlPanelDetailSection()
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ControlPanelSectionLabel(title: "详情", systemImage: "info.circle")

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                ScreenshotMetadataRow(title: "类型", value: "PNG 图片")
                ScreenshotMetadataRow(title: "创建时间", value: item.createdAt.absoluteDisplayString)
                ScreenshotMetadataRow(title: "大小", value: item.fileSizeText)
                ScreenshotMetadataRow(title: "数据", value: "\(item.data.count) bytes")
            }
        }
        .controlPanelDetailSection()
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

private struct PixCaptureControls: View {
    let isCapturing: Bool
    let captureSelectedRegionAction: () -> Void
    let captureMainDisplayAction: () -> Void
    let stopCaptureAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isCapturing {
                Button(action: stopCaptureAction) {
                    Label("停止截图", systemImage: "xmark.circle")
                }
                .buttonStyle(ControlPanelButtonStyle(prominence: .destructive))
                .help("结束当前框选")
            } else {
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
            fromByteCount: Int64(data.count),
            countStyle: .file
        )
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
