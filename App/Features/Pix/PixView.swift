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
            controller.captureMode = .screenshot
            await controller.captureSelectedRegion()
        }
    }

    private func captureMainDisplay() {
        Task {
            controller.captureMode = .screenshot
            await controller.captureMainDisplay()
        }
    }

    private func startRecording() {
        Task {
            controller.captureMode = .recording
            await controller.startSelectedRegionRecording()
        }
    }

    private func configureGIFExport(for item: ScreenshotItem) {
        gifExportOptions = ScreenRecordingGIFExportOptions()
        gifExportItem = item
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
