import AppKit
import SwiftUI

struct ScreenshotItemDetailPane: View {
    let item: ScreenshotItem
    let copyAction: () -> Void
    let saveAction: () -> Void
    let pinAction: () -> Void
    let previewAction: () -> Void
    let exportMP4Action: () -> Void
    let exportGIFAction: () -> Void
    let deleteAction: () -> Void

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
            if item.isImage {
                Button(action: copyAction) {
                    Label(L10n.commonCopy, systemImage: "doc.on.doc")
                }
                .buttonStyle(ControlPanelButtonStyle(tint: ControlPanelDesign.tint(for: .pix), prominence: .primary))
                .help(L10n.pixCopyScreenshot)

                Button(action: saveAction) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(ControlPanelIconButtonStyle())
                .help(L10n.pixSaveScreenshot)

                Button(action: pinAction) {
                    Image(systemName: "pin")
                }
                .buttonStyle(ControlPanelIconButtonStyle())
                .help(L10n.commonPinToScreen)
            } else {
                Button(action: exportMP4Action) {
                    Label("MP4", systemImage: "film")
                }
                .buttonStyle(ControlPanelButtonStyle(tint: ControlPanelDesign.tint(for: .pix), prominence: .primary))
                .help(L10n.commonExportMP4)

                Button(action: exportGIFAction) {
                    Label("GIF", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(ControlPanelButtonStyle())
                .help(L10n.commonExportGIF)
            }

            Button(action: previewAction) {
                Image(systemName: "eye")
            }
            .buttonStyle(ControlPanelIconButtonStyle())
            .help(item.isImage ? L10n.pixOpenInPreview : L10n.pixOpenRecording)

            Spacer()

            Button(role: .destructive, action: deleteAction) {
                Image(systemName: "trash")
            }
            .buttonStyle(ControlPanelIconButtonStyle(role: .destructive))
            .help(L10n.pixDeleteScreenshot)
        }
        .controlPanelActionBar()
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ControlPanelSectionLabel(
                    title: item.isImage ? L10n.pixImagePreview : L10n.pixRecordingPreview,
                    systemImage: item.isImage ? "photo" : "video"
                )
            }

            if item.isImage {
                Button(action: previewAction) {
                    ScreenshotFittedPreviewImage(data: item.data)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.pixOpenInPreview)
                .padding(ControlPanelDesign.Layout.detailContentPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .controlPanelTextSurface()
            } else {
                ScreenRecordingPreviewCard(item: item, previewAction: previewAction)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(ControlPanelDesign.Layout.detailContentPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .controlPanelTextSurface()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .controlPanelDetailSection()
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ControlPanelSectionLabel(title: L10n.pixDetails, systemImage: "info.circle")

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                ScreenshotMetadataRow(title: L10n.pixType, value: item.isImage ? L10n.pixPNGImage : L10n.pixMP4Recording)
                ScreenshotMetadataRow(title: L10n.pixCreatedAt, value: item.createdAt.absoluteDisplayString)
                ScreenshotMetadataRow(title: L10n.pixFileSize, value: item.fileSizeText)
                if item.isRecording {
                    ScreenshotMetadataRow(title: L10n.pixDuration, value: item.durationText)
                    if let pixelSize = item.pixelSize {
                        ScreenshotMetadataRow(
                            title: L10n.pixDimensions,
                            value: "\(Int(pixelSize.width)) x \(Int(pixelSize.height))"
                        )
                    }
                }
            }
        }
        .controlPanelDetailSection()
    }
}

private struct ScreenRecordingPreviewCard: View {
    let item: ScreenshotItem
    let previewAction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let thumbnailSize = fittedThumbnailSize(in: proxy.size)

            Button(action: previewAction) {
                ScreenRecordingThumbnailView(
                    item: item,
                    size: thumbnailSize,
                    cornerRadius: ControlPanelDesign.compactRadius,
                    maxPixelSize: 1100
                ) {
                    ZStack {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.58)],
                            startPoint: .center,
                            endPoint: .bottom
                        )

                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 54, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)

                        VStack {
                            Spacer()

                            HStack(alignment: .bottom) {
                                Text(item.durationText)
                                    .font(.title3.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.white)

                                Spacer()

                                Text(item.fileSizeText)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.82))
                            }
                            .padding(14)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.pixOpenRecording)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fittedThumbnailSize(in availableSize: CGSize) -> CGSize {
        let width = max(1, availableSize.width)
        let height = max(1, availableSize.height)
        let aspectRatio = 16.0 / 9.0

        let heightFromWidth = width / aspectRatio
        if heightFromWidth <= height {
            return CGSize(width: width, height: heightFromWidth)
        }

        return CGSize(width: height * aspectRatio, height: height)
    }
}

private struct ScreenshotFittedPreviewImage: View {
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

private struct ScreenshotMetadataRow: View {
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
