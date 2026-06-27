import SwiftUI

struct ScreenshotItemRow: View {
    let item: ScreenshotItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            historyThumbnail

            VStack(alignment: .leading, spacing: 5) {
                Text(item.displayTitle)
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
                source: item.imageDataSource,
                size: CGSize(width: 48, height: ControlPanelDesign.Layout.historyRowThumbnailSize)
            )
        } else {
            ScreenRecordingThumbnailView(
                item: item,
                size: CGSize(width: 48, height: ControlPanelDesign.Layout.historyRowThumbnailSize),
                maxPixelSize: 240
            ) {
                ScreenshotHistoryRecordingThumbnailOverlay(durationText: item.durationText)
            }
        }
    }
}

private struct ScreenshotHistoryRecordingThumbnailOverlay: View {
    let durationText: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.02), .black.opacity(0.50)],
                startPoint: .top,
                endPoint: .bottom
            )

            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.black.opacity(0.44), in: Circle())

            VStack {
                Spacer()

                HStack {
                    Spacer()

                    Text(durationText)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .padding(4)
            }
        }
    }
}
