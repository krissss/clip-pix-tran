import SwiftUI

struct ClipView: View {
    @Bindable var monitor: ClipboardMonitor
    let translateAction: (ClipboardItem) -> Void

    @State private var searchText = ""
    @State private var selectedItemID: ClipboardItem.ID?

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
            Label("\(visibleItems.count) 条记录", systemImage: "clock")
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive, action: monitor.clearHistory) {
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

private struct ClipboardItemRow: View {
    let item: ClipboardItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            itemPreview

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.displayTitle)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(summaryText)
                    .lineLimit(2)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                RelativeTimeText(date: item.lastCopiedAt)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
    }

    private var summaryText: String {
        switch item.kind {
        case .text:
            if item.payloads.isEmpty {
                return "文本 · \(item.text.count) 个字符"
            }

            return "带格式文本 · \(item.text.count) 个字符 · \(item.payloads.count) 种格式"
        case .image:
            if item.filePaths.isEmpty {
                return "图片 · 可预览"
            }

            return pathSummary(prefix: "图片", paths: item.filePaths)
        case .file:
            return pathSummary(prefix: "文件", paths: item.filePaths)
        }
    }

    private func pathSummary(prefix: String, paths: [String]) -> String {
        guard let firstPath = paths.first else {
            return prefix
        }

        let url = URL(fileURLWithPath: firstPath)
        let name = url.lastPathComponent
        if paths.count == 1 {
            return "\(prefix) · \(name)"
        }

        return "\(prefix) · \(name) 等 \(paths.count) 项"
    }

    @ViewBuilder
    private var itemPreview: some View {
        if item.kind == .image, let imageData = item.imageData {
            ImageThumbnailView(
                data: imageData,
                size: CGSize(
                    width: ControlPanelDesign.Layout.historyRowThumbnailSize,
                    height: ControlPanelDesign.Layout.historyRowThumbnailSize
                )
            )
        } else {
            Image(systemName: item.kind.systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(
                    width: ControlPanelDesign.Layout.historyRowThumbnailSize,
                    height: ControlPanelDesign.Layout.historyRowThumbnailSize
                )
                .controlPanelQuietSurface()
        }
    }
}

private struct ClipboardItemDetailPane: View {
    let item: ClipboardItem
    let copyAction: () -> Void
    let copyPlainTextAction: () -> Void
    let togglePinnedAction: () -> Void
    let deleteAction: () -> Void
    let systemPreviewAction: () -> Void
    let revealInFinderAction: () -> Void
    let translateAction: () -> Void

    private var canPreview: Bool {
        SystemImagePreviewService.canPreview(item)
    }

    private var canRevealInFinder: Bool {
        !item.filePaths.isEmpty
    }

    private var canCopyPlainText: Bool {
        item.isText && item.richTextPreviewData != nil
    }

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
            .buttonStyle(ControlPanelButtonStyle(tint: ControlPanelDesign.tint(for: .clip), prominence: .primary))
            .help("复制回剪贴板")

            if canCopyPlainText {
                Button(action: copyPlainTextAction) {
                    Image(systemName: "text.alignleft")
                }
                .buttonStyle(ControlPanelIconButtonStyle())
                .help("复制为纯文本")
            }

            Button(action: togglePinnedAction) {
                Image(systemName: item.isPinned ? "pin.slash" : "pin")
            }
            .buttonStyle(ControlPanelIconButtonStyle(role: item.isPinned ? .selected : .normal, tint: ControlPanelDesign.tint(for: .clip)))
            .help(item.isPinned ? "取消收藏" : "收藏")

            if item.isText {
                Button(action: translateAction) {
                    Image(systemName: "text.bubble")
                }
                .buttonStyle(ControlPanelIconButtonStyle())
                .help("发送到 Tran")
            }

            if canPreview {
                Button(action: systemPreviewAction) {
                    Image(systemName: "eye")
                }
                .buttonStyle(ControlPanelIconButtonStyle())
                .help("用系统预览.app打开图片")
            }

            if canRevealInFinder {
                Button(action: revealInFinderAction) {
                    Image(systemName: "folder")
                }
                .buttonStyle(ControlPanelIconButtonStyle())
                .help("在访达中显示")
            }

            Spacer()

            Button(role: .destructive, action: deleteAction) {
                Image(systemName: "trash")
            }
            .buttonStyle(ControlPanelIconButtonStyle(role: .destructive))
            .help("删除记录")
        }
        .controlPanelActionBar()
    }

    @ViewBuilder
    private var previewSection: some View {
        switch item.kind {
        case .text:
            ClipboardTextPreview(item: item)
        case .image:
            ClipboardImagePreview(item: item)
        case .file:
            ClipboardFilePreview(item: item)
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ControlPanelSectionLabel(title: "详情", systemImage: "info.circle")

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                ClipboardMetadataRow(title: "类型", value: item.kind.displayName)
                ClipboardMetadataRow(title: "创建时间", value: item.createdAt.absoluteDisplayString)
                ClipboardMetadataRow(title: "最近复制", value: item.lastCopiedAt.absoluteDisplayString)

                if item.isText {
                    ClipboardMetadataRow(title: "字符数", value: "\(item.text.count)")
                    ClipboardMetadataRow(title: "格式数", value: "\(item.payloads.count)")
                }

                if item.kind != .text {
                    ClipboardMetadataRow(title: "项目数", value: "\(max(item.filePaths.count, item.imageData == nil ? 0 : 1))")
                }
            }
        }
        .controlPanelDetailSection()
    }
}

private struct ClipboardTextPreview: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ControlPanelSectionLabel(
                    title: item.payloads.isEmpty ? "文本预览" : "带格式文本",
                    systemImage: "text.alignleft"
                )

                Spacer()

                if !item.payloads.isEmpty {
                    Label("保留格式", systemImage: "checkmark.seal")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            RichTextPreviewView(
                text: item.text,
                richTextData: item.richTextPreviewData
            )
            .frame(minHeight: 240, maxHeight: 420)
            .controlPanelTextSurface()
        }
        .controlPanelDetailSection()
    }
}

private struct ClipboardImagePreview: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ControlPanelSectionLabel(title: "图片预览", systemImage: "photo")

            if let imageData = item.imageData {
                ImageThumbnailView(
                    data: imageData,
                    size: CGSize(width: 320, height: 200),
                    cornerRadius: ControlPanelDesign.cardRadius,
                    maxPixelSize: 720
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(ControlPanelDesign.Layout.detailContentPadding)
                .controlPanelTextSurface()
            } else {
                ContentUnavailableView("无法预览图片", systemImage: "photo")
                    .frame(minHeight: 220)
            }

            if !item.filePaths.isEmpty {
                ClipboardPathList(paths: item.filePaths)
            }
        }
        .controlPanelDetailSection()
    }
}

private struct ClipboardFilePreview: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ControlPanelSectionLabel(title: "文件", systemImage: "doc")

            ClipboardPathList(paths: item.filePaths)
        }
        .controlPanelDetailSection()
    }
}

private struct ClipboardPathList: View {
    let paths: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(paths, id: \.self) { path in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.body)
                            .lineLimit(1)

                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }

                    Spacer()

                    Button {
                        FinderRevealService.reveal(path: path)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(ControlPanelIconButtonStyle())
                    .help("在访达中显示")
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .controlPanelTextSurface()
            }
        }
    }
}


private struct ClipboardMetadataRow: View {
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

#Preview {
    ClipView(
        monitor: ClipboardMonitor(
            pasteboard: PreviewClipboardService(),
            history: ClipboardHistoryStore.preview
        ),
        translateAction: { _ in }
    )
}
