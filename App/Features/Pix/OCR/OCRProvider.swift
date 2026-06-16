import Foundation

/// 一次 OCR 识别的结果。
struct OCRResult: Equatable, Sendable {
    /// 已按阅读顺序拼接好的纯文本。
    let text: String
    /// 平均置信度（0~1），仅供展示，可能为 nil。
    let confidence: Float?
}

/// OCR 识别错误。归一化底层差异，供 UI 展示。
enum OCRError: LocalizedError, Equatable {
    /// 图片数据无法解码或不支持。
    case invalidImage
    /// 识别完成但未提取到任何文字。
    case noTextRecognized
    /// 其余底层错误。
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            L10n.pixOCRInvalidImage
        case .noTextRecognized:
            L10n.pixOCRNoTextRecognized
        case .underlying(let message):
            message
        }
    }
}

/// OCR provider 协议。本期仅有原生 Vision 实现，但保留协议以便后续接入云端 OCR。
protocol OCRProvider: Sendable {
    func recognize(textIn data: Data) async throws -> OCRResult
}

/// OCR provider 的描述信息，用于后续设置面板展示与选择。
struct OCRProviderDescriptor: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let systemImage: String
    let isLocal: Bool
}

extension OCRProviderDescriptor {
    /// 原生 Vision 框架。
    static let vision = OCRProviderDescriptor(
        id: "vision",
        name: "Apple Vision",
        systemImage: "eye",
        isLocal: true
    )

    static let builtIn: [OCRProviderDescriptor] = [.vision]

    static func descriptor(for id: String) -> OCRProviderDescriptor {
        builtIn.first { $0.id == id } ?? .vision
    }
}
