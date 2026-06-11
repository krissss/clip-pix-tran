import AppKit
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

            VStack(alignment: .leading, spacing: 0) {
                previewSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                metadataSection
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                    .layoutPriority(1)
            }
            .padding(ControlPanelDesign.Layout.detailContentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .controlPanelContentSurface()
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button(action: copyAction) {
                Label(L10n.commonCopy, systemImage: "doc.on.doc")
            }
            .buttonStyle(ControlPanelButtonStyle(tint: ControlPanelDesign.tint(for: .clip), prominence: .primary))
            .help(L10n.clipCopyBack)

            if canCopyPlainText {
                Button(action: copyPlainTextAction) {
                    Image(systemName: "text.alignleft")
                }
                .buttonStyle(ControlPanelIconButtonStyle())
                .help(L10n.commonCopyPlainText)
            }

            Button(action: togglePinnedAction) {
                Image(systemName: item.isPinned ? "pin.slash" : "pin")
            }
            .buttonStyle(ControlPanelIconButtonStyle(role: item.isPinned ? .selected : .normal, tint: ControlPanelDesign.tint(for: .clip)))
            .help(item.isPinned ? L10n.commonUnfavorite : L10n.commonFavorite)

            if item.isText {
                Button(action: translateAction) {
                    Image(systemName: "text.bubble")
                }
                .buttonStyle(ControlPanelIconButtonStyle())
                .help(L10n.clipSendToTran)
            }

            if canPreview {
                Button(action: systemPreviewAction) {
                    Image(systemName: "eye")
                }
                .buttonStyle(ControlPanelIconButtonStyle())
                .help(L10n.pixOpenInPreview)
            }

            if canRevealInFinder {
                Button(action: revealInFinderAction) {
                    Image(systemName: "folder")
                }
                .buttonStyle(ControlPanelIconButtonStyle())
                .help(L10n.commonRevealInFinder)
            }

            Spacer()

            Button(role: .destructive, action: deleteAction) {
                Image(systemName: "trash")
            }
            .buttonStyle(ControlPanelIconButtonStyle(role: .destructive))
            .help(L10n.commonDeleteRecord)
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
            ControlPanelSectionLabel(title: L10n.pixDetails, systemImage: "info.circle")

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                ClipboardMetadataRow(title: L10n.pixType, value: item.kind.displayName)
                ClipboardMetadataRow(title: L10n.pixCreatedAt, value: item.createdAt.absoluteDisplayString)
                ClipboardMetadataRow(title: L10n.clipLastCopied, value: item.lastCopiedAt.absoluteDisplayString)

                if item.isText {
                    ClipboardMetadataRow(title: L10n.clipCharacterCount, value: "\(item.text.count)")
                    ClipboardMetadataRow(title: L10n.clipFormatCount, value: "\(item.payloads.count)")
                }

                if item.kind != .text {
                    ClipboardMetadataRow(title: L10n.clipItemCount, value: "\(max(item.filePaths.count, item.imageData == nil ? 0 : 1))")
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
                    title: item.payloads.isEmpty ? L10n.clipTextPreview : L10n.clipRichText,
                    systemImage: "text.alignleft"
                )

                Spacer()

                if !item.payloads.isEmpty {
                    Label(L10n.clipKeepsFormatting, systemImage: "checkmark.seal")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            RichTextPreviewView(
                text: item.text,
                richTextData: item.richTextPreviewData
            )
            .frame(minHeight: 240, maxHeight: .infinity)
            .controlPanelTextSurface()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .controlPanelDetailSection()
    }
}

private struct ClipboardImagePreview: View {
    let item: ClipboardItem
    let previewAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ControlPanelSectionLabel(title: L10n.pixImagePreview, systemImage: "photo")

            if let imageData = item.imageData {
                Button(action: previewAction) {
                    ClipboardFittedPreviewImage(data: imageData)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.pixOpenInPreview)
                .padding(ControlPanelDesign.Layout.detailContentPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .controlPanelTextSurface()
            } else {
                ContentUnavailableView(L10n.commonCannotPreviewImage, systemImage: "photo")
                    .frame(minHeight: 220)
            }

            if !item.filePaths.isEmpty {
                ClipboardPathList(paths: item.filePaths)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .controlPanelDetailSection()
    }
}

private struct ClipboardFittedPreviewImage: View {
    let data: Data

    @State private var thumbnailData: Data?
    @State private var didLoadThumbnail = false

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
                height: max(1, proxy.size.height)
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
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private struct ClipboardFilePreview: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ControlPanelSectionLabel(title: L10n.kindFile, systemImage: "doc")

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
                    .help(L10n.commonRevealInFinder)
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
