import AppKit
import SwiftUI

struct ScreenRecordingThumbnailView<Overlay: View>: View {
    let item: ScreenshotItem
    let size: CGSize
    var cornerRadius: CGFloat = ControlPanelDesign.compactRadius
    var maxPixelSize: CGFloat = 480
    @ViewBuilder var overlay: () -> Overlay

    @State private var thumbnailData: Data?
    @State private var didLoadThumbnail = false

    init(
        item: ScreenshotItem,
        size: CGSize,
        cornerRadius: CGFloat = ControlPanelDesign.compactRadius,
        maxPixelSize: CGFloat = 480,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self.item = item
        self.size = size
        self.cornerRadius = cornerRadius
        self.maxPixelSize = maxPixelSize
        self.overlay = overlay
    }

    private var image: Image? {
        guard let thumbnailData,
              let nsImage = NSImage(data: thumbnailData) else {
            return nil
        }

        return Image(nsImage: nsImage)
    }

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                placeholder
            }

            overlay()
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.quaternary)
        }
        .task(id: item.recordingFileName) {
            thumbnailData = nil
            didLoadThumbnail = false
            guard let url = item.recordingURL else {
                didLoadThumbnail = true
                return
            }

            thumbnailData = await ScreenRecordingThumbnailRenderer.pngData(
                from: url,
                maxPixelSize: maxPixelSize
            )
            didLoadThumbnail = true
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.quaternary)
            .overlay {
                if didLoadThumbnail {
                    Image(systemName: "video")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
    }
}

extension ScreenRecordingThumbnailView where Overlay == EmptyView {
    init(
        item: ScreenshotItem,
        size: CGSize,
        cornerRadius: CGFloat = ControlPanelDesign.compactRadius,
        maxPixelSize: CGFloat = 480
    ) {
        self.init(
            item: item,
            size: size,
            cornerRadius: cornerRadius,
            maxPixelSize: maxPixelSize
        ) {
            EmptyView()
        }
    }
}
