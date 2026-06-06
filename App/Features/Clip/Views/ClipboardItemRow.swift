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
