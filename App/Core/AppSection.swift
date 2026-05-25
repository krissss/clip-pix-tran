import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case clip
    case pix
    case tran

    var id: Self { self }

    var title: String {
        switch self {
        case .clip:
            "Clip"
        case .pix:
            "Pix"
        case .tran:
            "Tran"
        }
    }

    var systemImage: String {
        switch self {
        case .clip:
            "doc.on.clipboard"
        case .pix:
            "camera.viewfinder"
        case .tran:
            "text.bubble"
        }
    }
}
