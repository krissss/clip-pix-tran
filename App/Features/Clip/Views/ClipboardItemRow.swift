import SwiftUI

struct ClipboardItemRow: View {
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
                return L10n.clipTextSummary(characterCount: item.text.count)
            }

            return L10n.clipRichTextSummary(characterCount: item.text.count, formatCount: item.payloads.count)
        case .image:
            if item.filePaths.isEmpty {
                return L10n.clipPreviewableImage
            }

            return pathSummary(prefix: L10n.kindImage, paths: item.filePaths)
        case .file:
            return pathSummary(prefix: L10n.kindFile, paths: item.filePaths)
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

        return L10n.clipPathSummary(prefix: prefix, name: name, count: paths.count)
    }

    @ViewBuilder
    private var itemPreview: some View {
        if item.kind == .image, item.imageDataSource.isAvailable {
            ImageThumbnailView(
                source: item.imageDataSource,
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
