import Foundation

enum TranslationTextFormatting {
    static func compactDisplayText(_ text: String) -> String {
        compactDisplayLines(text).joined(separator: "\n")
    }

    static func compactDisplayLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
