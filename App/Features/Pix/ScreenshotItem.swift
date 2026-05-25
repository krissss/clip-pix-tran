import Foundation

struct ScreenshotItem: Codable, Identifiable, Equatable {
    let id: UUID
    let data: Data
    let createdAt: Date

    init(
        id: UUID = UUID(),
        data: Data,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.data = data
        self.createdAt = createdAt
    }
}
