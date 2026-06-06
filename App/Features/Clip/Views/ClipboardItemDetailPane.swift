import SwiftUI

struct ClipboardItemDetailPane: View {
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
            ClipboardImagePreview(item: item, previewAction: systemPreviewAction)
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
    let previewAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ControlPanelSectionLabel(title: "图片预览", systemImage: "photo")

            if let imageData = item.imageData {
                Button(action: previewAction) {
                    ImageThumbnailView(
                        data: imageData,
                        size: CGSize(width: 320, height: 200),
                        cornerRadius: ControlPanelDesign.cardRadius,
                        maxPixelSize: 720
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(ControlPanelDesign.Layout.detailContentPadding)
                    .controlPanelTextSurface()
                    .contentShape(RoundedRectangle(cornerRadius: ControlPanelDesign.cardRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("用系统预览.app打开图片")
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
