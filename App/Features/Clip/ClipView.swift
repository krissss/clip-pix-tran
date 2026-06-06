import SwiftUI

struct ClipView: View {
    @Bindable var monitor: ClipboardMonitor
    let translateAction: (ClipboardItem) -> Void

    @State private var searchText = ""
    @State private var selectedItemID: ClipboardItem.ID?
    @State private var showsClearHistoryConfirmation = false

    private var visibleItems: [ClipboardItem] {
        monitor.history.filteredItems(matching: searchText)
    }

    private var selectedItem: ClipboardItem? {
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
        .navigationTitle("Clip")
        .background(ControlPanelBackground())
        .onAppear(perform: selectFirstVisibleItemIfNeeded)
        .onChange(of: visibleItems.map(\.id)) { _, _ in
            selectFirstVisibleItemIfNeeded()
        }
        .confirmationDialog(
            "清空剪贴板历史？",
            isPresented: $showsClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空历史", role: .destructive) {
                clearHistory()
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除全部剪贴板历史记录，无法撤销。")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader

            ControlPanelSearchField(text: $searchText, prompt: "搜索剪贴板历史")
                .padding(.horizontal, ControlPanelDesign.Layout.searchHorizontalPadding)
                .padding(.bottom, 10)

            sidebarContent
        }
        .controlPanelSidebarSurface()
    }

    private var sidebarHeader: some View {
        ControlPanelSidebarHeader(
            title: "剪贴板历史",
            systemImage: "doc.on.clipboard",
            tint: ControlPanelDesign.tint(for: .clip)
        ) {
            Text("\(monitor.history.items.count)/\(monitor.history.limit)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, ControlPanelDesign.Layout.headerHorizontalPadding)
        .padding(.vertical, ControlPanelDesign.Layout.headerVerticalPadding)
    }

    @ViewBuilder
    private var sidebarContent: some View {
        if monitor.history.items.isEmpty {
            ControlPanelEmptyState(
                title: "暂无剪贴板记录",
                systemImage: "doc.on.clipboard",
                tint: ControlPanelDesign.tint(for: .clip)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleItems.isEmpty {
            ControlPanelNoResultsState(
                title: "没有匹配记录",
                systemImage: "doc.text.magnifyingglass"
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selectedItemID) {
                Section {
                    historyActions
                }

                ForEach(visibleItems) { item in
                    ClipboardItemRow(item: item)
                        .tag(item.id)
                        .controlPanelListRow(
                            isSelected: item.id == selectedItemID,
                            tint: ControlPanelDesign.tint(for: .clip)
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
            Label("\(visibleItems.count) 条记录", systemImage: "clock")
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive) {
                showsClearHistoryConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(ControlPanelIconButtonStyle(role: .destructive))
            .disabled(monitor.history.items.isEmpty)
            .help("清空剪贴板历史")
        }
        .font(.callout)
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var detail: some View {
        Group {
            if let selectedItem {
                ClipboardItemDetailPane(
                    item: selectedItem,
                    copyAction: {
                        monitor.copyToPasteboard(selectedItem)
                    },
                    copyPlainTextAction: {
                        monitor.copyPlainTextToPasteboard(selectedItem)
                    },
                    togglePinnedAction: {
                        monitor.history.togglePinned(selectedItem)
                    },
                    deleteAction: {
                        delete(selectedItem)
                    },
                    systemPreviewAction: {
                        SystemImagePreviewService.openInPreviewApp(item: selectedItem)
                    },
                    revealInFinderAction: {
                        FinderRevealService.revealFirstPath(in: selectedItem)
                    },
                    translateAction: {
                        translateAction(selectedItem)
                    }
                )
            } else {
                ControlPanelEmptyState(
                    title: "选择一条记录",
                    systemImage: "sidebar.right",
                    tint: ControlPanelDesign.tint(for: .clip)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if let errorMessage = monitor.history.persistenceErrorMessage {
                ClipboardStatusBanner(message: errorMessage)
            }

            if let errorMessage = monitor.lastErrorMessage {
                ClipboardStatusBanner(message: errorMessage)
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private func contextMenu(for item: ClipboardItem) -> some View {
        Button {
            monitor.copyToPasteboard(item)
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }

        Button {
            monitor.history.togglePinned(item)
        } label: {
            Label(
                item.isPinned ? "取消收藏" : "收藏",
                systemImage: item.isPinned ? "pin.slash" : "pin"
            )
        }

        if item.isText {
            if item.richTextPreviewData != nil {
                Button {
                    monitor.copyPlainTextToPasteboard(item)
                } label: {
                    Label("复制纯文本", systemImage: "text.alignleft")
                }
            }

            Button {
                translateAction(item)
            } label: {
                Label("翻译", systemImage: "text.bubble")
            }
        }

        if canPreview(item) {
            Button {
                SystemImagePreviewService.openInPreviewApp(item: item)
            } label: {
                Label("预览", systemImage: "eye")
            }
        }

        if canRevealInFinder(item) {
            Button {
                FinderRevealService.revealFirstPath(in: item)
            } label: {
                Label("在访达中显示", systemImage: "folder")
            }
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

    private func delete(_ item: ClipboardItem) {
        monitor.history.delete(item)
        selectFirstVisibleItemIfNeeded()
    }

    private func clearHistory() {
        monitor.clearHistory()
        selectFirstVisibleItemIfNeeded()
    }

    private func canPreview(_ item: ClipboardItem) -> Bool {
        SystemImagePreviewService.canPreview(item)
    }

    private func canRevealInFinder(_ item: ClipboardItem) -> Bool {
        !item.filePaths.isEmpty
    }
}

private struct ClipboardStatusBanner: View {
    let message: String

    var body: some View {
        ControlPanelStatusBanner(message: message)
    }
}

#Preview {
    ClipView(
        monitor: ClipboardMonitor(
            pasteboard: PreviewClipboardService(),
            history: ClipboardHistoryStore.preview
        ),
        translateAction: { _ in }
    )
}
