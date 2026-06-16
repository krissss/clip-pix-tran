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
        .onChange(of: visibleItems.map(\.id)) { oldIDs, newIDs in
            if oldIDs.first != newIDs.first {
                selectedItemID = newIDs.first
            } else {
                selectFirstVisibleItemIfNeeded()
            }
        }
        .confirmationDialog(
            L10n.pixClearTitle,
            isPresented: $showsClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.commonClearHistory, role: .destructive) {
                clearHistory()
            }

            Button(L10n.commonCancel, role: .cancel) {}
        } message: {
            Text(L10n.pixClearMessage)
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

            ControlPanelSearchField(text: $searchText, prompt: L10n.pixSearch)
                .padding(.horizontal, ControlPanelDesign.Layout.searchHorizontalPadding)
                .padding(.bottom, 10)

            sidebarContent
        }
        .controlPanelSidebarSurface()
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            ControlPanelSidebarHeader(
                title: L10n.pixHistory,
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
                title: L10n.pixEmpty,
                systemImage: "camera.viewfinder",
                tint: ControlPanelDesign.tint(for: .pix)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleItems.isEmpty {
            ControlPanelNoResultsState(
                title: L10n.pixNoResults,
                systemImage: "photo.badge.magnifyingglass"
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    historyActions
                }

                ForEach(visibleItems) { item in
                    Button {
                        selectedItemID = item.id
                    } label: {
                        ScreenshotItemRow(item: item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .controlPanelHistoryRow(
                                isSelected: item.id == selectedItemID,
                                tint: ControlPanelDesign.tint(for: .pix)
                            )
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous)
                            .fill(Color.clear)
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
            Label(L10n.commonItemsCount(visibleItems.count), systemImage: "clock")
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive) {
                showsClearHistoryConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(ControlPanelIconButtonStyle(role: .destructive))
            .disabled(controller.history.items.isEmpty)
            .help(L10n.pixClearHelp)
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
                    ocrStatus: controller.ocr?.status(for: selectedItem.id) ?? .idle,
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
                    },
                    extractTextAction: {
                        Task {
                            await controller.recognizeText(selectedItem)
                        }
                    },
                    copyTextAction: {
                        controller.copyRecognizedText(selectedItem)
                    },
                    translateTextAction: {
                        controller.translateRecognizedText(selectedItem)
                    },
                    updateTextAction: { text in
                        controller.updateRecognizedText(selectedItem, text: text)
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
                Label(L10n.commonCopy, systemImage: "doc.on.doc")
            }

            Button {
                controller.save(item)
            } label: {
                Label(L10n.commonSave, systemImage: "square.and.arrow.down")
            }

            Button {
                controller.pinToScreen(item)
            } label: {
                Label(L10n.commonPinToScreen, systemImage: "pin")
            }

            Button {
                Task { await controller.recognizeText(item) }
            } label: {
                Label(L10n.pixOCRExtract, systemImage: "doc.text.viewfinder")
            }
        } else {
            Button {
                controller.exportMP4(item)
            } label: {
                Label(L10n.commonExportMP4, systemImage: "film")
            }

            Button {
                configureGIFExport(for: item)
            } label: {
                Label(L10n.commonExportGIF, systemImage: "square.and.arrow.down")
            }
        }

        Button {
            SystemImagePreviewService.openInPreviewApp(item: item)
        } label: {
            Label(L10n.commonPreview, systemImage: "eye")
        }

        Button(role: .destructive) {
            delete(item)
        } label: {
            Label(L10n.commonDelete, systemImage: "trash")
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
