import Foundation
import ImageIO

extension ScreenshotItem {
    var fileSizeText: String {
        ByteCountFormatter.string(
            fromByteCount: byteCount,
            countStyle: .file
        )
    }

    var dimensionsText: String {
        if let pixelSize {
            return pixelSize.pixDimensionText
        }

        guard let imagePixelSize else {
            return isImage ? L10n.pixPNGImage : L10n.pixMP4Recording
        }

        return imagePixelSize.pixDimensionText
    }

    var displayTitle: String {
        if let dimensionText = optionalDimensionsText {
            return "\(captureTypeText) \(dimensionText)"
        }

        return captureTypeText
    }

    private var captureTypeText: String {
        if isRecording {
            return L10n.pixRecording
        }

        switch captureSource {
        case .fullScreen:
            return L10n.pixFullScreen
        case .selectedRegion, .none:
            return L10n.pixScreenshot
        }
    }

    private var optionalDimensionsText: String? {
        if let pixelSize {
            return pixelSize.pixDimensionText
        }

        return imagePixelSize?.pixDimensionText
    }

    var durationText: String {
        let totalSeconds = max(Int((duration ?? 0).rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var imagePixelSize: CGSize? {
        guard isImage,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }

        return CGSize(width: width, height: height)
    }
}

private extension CGSize {
    var pixDimensionText: String {
        "\(Int(width.rounded())) x \(Int(height.rounded()))"
    }
}

extension [ScreenshotItem] {
    func filtered(matching searchText: String) -> [ScreenshotItem] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchText.isEmpty else {
            return self
        }

        return filter { item in
            item.createdAt.absoluteDisplayString.localizedCaseInsensitiveContains(trimmedSearchText)
                || item.displayTitle.localizedCaseInsensitiveContains(trimmedSearchText)
                || item.dimensionsText.localizedCaseInsensitiveContains(trimmedSearchText)
                || item.fileSizeText.localizedCaseInsensitiveContains(trimmedSearchText)
                || item.durationText.localizedCaseInsensitiveContains(trimmedSearchText)
        }
    }
}
