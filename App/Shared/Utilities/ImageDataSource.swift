import Foundation

struct ImageDataSource: Equatable, Sendable {
    let id: String
    let inlineData: Data?
    let filePath: String?

    static func == (lhs: ImageDataSource, rhs: ImageDataSource) -> Bool {
        lhs.id == rhs.id
            && lhs.filePath == rhs.filePath
            && lhs.inlineData?.count == rhs.inlineData?.count
    }

    init(id: String, inlineData: Data? = nil, filePath: String? = nil) {
        self.id = id
        self.inlineData = inlineData
        self.filePath = filePath
    }

    var isAvailable: Bool {
        inlineData != nil || filePath != nil
    }

    nonisolated func loadData() -> Data? {
        if let inlineData {
            return inlineData
        }

        guard let filePath else {
            return nil
        }

        return try? Data(contentsOf: URL(fileURLWithPath: filePath))
    }
}
