import Foundation

enum TranslationTextFormatting {
    static func compactDisplayText(_ text: String) -> String {
        compactDisplayLines(text).joined(separator: "\n")
    }

    static func compactDisplayLines(_ text: String) -> [String] {
        normalizedNewlines(text)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func paragraphDisplayText(_ text: String) -> String {
        let normalizedText = normalizedNewlines(text)
        guard !normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        return normalizedText.trimmingCharacters(in: .newlines)
    }

    static func paragraphDisplayText(_ text: String, matching referenceText: String?) -> String {
        let displayText = paragraphDisplayText(text)
        guard let referenceText,
              let referencePattern = nonEmptyLinePattern(referenceText),
              let displayLines = nonEmptyDisplayLines(displayText),
              displayLines.count == referencePattern.lineCount
        else {
            return displayText
        }

        var alignedText = displayLines.first ?? ""
        for (index, separator) in referencePattern.separators.enumerated() {
            alignedText += separator + displayLines[index + 1]
        }
        return alignedText
    }

    private static func normalizedNewlines(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func nonEmptyDisplayLines(_ text: String) -> [String]? {
        let lines = normalizedNewlines(text)
            .trimmingCharacters(in: .newlines)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return lines.isEmpty ? nil : lines
    }

    private static func nonEmptyLinePattern(_ text: String) -> (lineCount: Int, separators: [String])? {
        let lines = normalizedNewlines(text)
            .trimmingCharacters(in: .newlines)
            .components(separatedBy: "\n")
        var nonEmptyIndexes: [Int] = []

        for (index, line) in lines.enumerated()
            where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            nonEmptyIndexes.append(index)
        }

        guard !nonEmptyIndexes.isEmpty else {
            return nil
        }

        let separators = zip(nonEmptyIndexes, nonEmptyIndexes.dropFirst()).map { pair in
            pair.1 - pair.0 > 1 ? "\n\n" : "\n"
        }
        return (nonEmptyIndexes.count, separators)
    }
}
