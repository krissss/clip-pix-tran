import Foundation

struct UpdateChangelogEntry: Identifiable, Equatable {
    let version: String
    let date: String?
    let body: String

    var id: String { version }

    var displayTitle: String {
        if let date, !date.isEmpty {
            return "\(version) - \(date)"
        }

        return version
    }
}

enum UpdateChangelog {
    static let defaultRemoteURL = URL(
        string: "https://krissss.github.io/clip-pix-tran/CHANGELOG.md"
    )!

    static func entries(
        in markdown: String,
        from currentVersion: String,
        through latestVersion: String
    ) -> [UpdateChangelogEntry] {
        let current = AppVersion(currentVersion)
        let latest = AppVersion(latestVersion)

        return parseEntries(in: markdown).filter { entry in
            let version = AppVersion(entry.version)
            return version > current && version <= latest
        }
    }

    static func parseEntries(in markdown: String) -> [UpdateChangelogEntry] {
        let lines = markdown.components(separatedBy: .newlines)
        var entries: [UpdateChangelogEntry] = []
        var currentHeader: (version: String, date: String?)?
        var currentBody: [String] = []

        func flushCurrentEntry() {
            guard let header = currentHeader else {
                return
            }

            let body = trimmedBody(currentBody)
            guard !body.isEmpty else {
                return
            }

            entries.append(UpdateChangelogEntry(
                version: header.version,
                date: header.date,
                body: body
            ))
        }

        for line in lines {
            if let header = parseVersionHeader(line) {
                flushCurrentEntry()
                currentHeader = header.version.lowercased() == "unreleased" ? nil : header
                currentBody = []
            } else if currentHeader != nil {
                currentBody.append(line)
            }
        }

        flushCurrentEntry()
        return entries
    }

    private static func parseVersionHeader(_ line: String) -> (version: String, date: String?)? {
        guard line.hasPrefix("## ") else {
            return nil
        }

        let trimmed = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("["),
           let closingBracket = trimmed.firstIndex(of: "]")
        {
            let version = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closingBracket])
            let remaining = trimmed[trimmed.index(after: closingBracket)...]
            let date = remaining
                .trimmingCharacters(in: CharacterSet(charactersIn: " -"))
                .nilIfEmpty
            return (version, date)
        }

        let parts = trimmed.split(separator: " - ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else {
            return nil
        }

        return (String(first), parts.dropFirst().first.map(String.init))
    }

    private static func trimmedBody(_ lines: [String]) -> String {
        var body = lines
        while body.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            body.removeFirst()
        }
        while body.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            body.removeLast()
        }

        return body.joined(separator: "\n")
    }
}

private struct AppVersion: Comparable {
    let components: [Int]
    let normalized: String

    init(_ rawValue: String) {
        normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("v")
        components = normalized
            .split(separator: ".")
            .map { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        for index in 0..<maxCount {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }

        return false
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
