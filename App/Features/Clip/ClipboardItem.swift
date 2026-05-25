import Foundation

struct ClipboardItem: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date
    var lastCopiedAt: Date
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        lastCopiedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.lastCopiedAt = lastCopiedAt
        self.isPinned = isPinned
    }
}
