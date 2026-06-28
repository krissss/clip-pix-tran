import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ClipPixTran

struct VisionQRCodeProviderTests {
    @Test func recognizesQRCodePayloadFromPNGData() async throws {
        let payload = "https://example.com/clip-pix-tran"
        let provider = VisionQRCodeProvider()
        let pngData = try makeQRCodePNGData(payload: payload)

        let result = try await provider.recognize(in: pngData)

        #expect(result.primaryValue == payload)
    }

    private func makeQRCodePNGData(payload: String) throws -> Data {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw TestImageError.filterCreationFailed
        }

        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else {
            throw TestImageError.outputImageMissing
        }

        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            throw TestImageError.cgImageCreationFailed
        }

        return try pngData(from: cgImage)
    }

    private func pngData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw TestImageError.destinationCreationFailed
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestImageError.destinationFinalizeFailed
        }

        return data as Data
    }
}

private enum TestImageError: Error {
    case filterCreationFailed
    case outputImageMissing
    case cgImageCreationFailed
    case destinationCreationFailed
    case destinationFinalizeFailed
}
