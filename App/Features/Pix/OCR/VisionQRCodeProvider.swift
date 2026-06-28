import Foundation
import ImageIO
import Vision

/// 基于原生 Vision 框架的二维码识别。
nonisolated struct VisionQRCodeProvider: Sendable {
    func recognize(in data: Data) async throws -> QRCodeResult {
        guard !data.isEmpty,
              let cgImage = makeCGImage(from: data) else {
            throw QRCodeError.invalidImage
        }

        return try await Task.detached(priority: .userInitiated) { [cgImage] in
            try await Self.performRecognition(on: cgImage)
        }.value
    }

    private func makeCGImage(from data: Data) -> CGImage? {
        if let provider = CGDataProvider(data: data as CFData) {
            if let image = CGImage(
                pngDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            ) {
                return image
            }

            if let image = CGImage(
                jpegDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            ) {
                return image
            }
        }

        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        return nil
    }

    private static func performRecognition(on cgImage: CGImage) async throws -> QRCodeResult {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        do {
            try VNSequenceRequestHandler().perform([request], on: cgImage)
        } catch {
            throw QRCodeError.underlying(error.localizedDescription)
        }

        let values = (request.results ?? []).compactMap { observation -> String? in
            guard let payload = observation.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !payload.isEmpty else {
                return nil
            }

            return payload
        }

        guard !values.isEmpty else {
            throw QRCodeError.noCodeRecognized
        }

        return QRCodeResult(values: values)
    }
}

struct QRCodeResult: Equatable, Sendable {
    let values: [String]

    var primaryValue: String? {
        values.first
    }
}

enum QRCodeError: LocalizedError, Equatable {
    case invalidImage
    case noCodeRecognized
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            L10n.pixQRCodeInvalidImage
        case .noCodeRecognized:
            L10n.pixQRCodeNoCodeRecognized
        case .underlying(let message):
            message
        }
    }
}
