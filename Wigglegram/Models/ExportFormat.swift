import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case gif
    case mp4
    case frames

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gif:    return "Export GIF"
        case .mp4:    return "Export MP4"
        case .frames: return "Export Frames"
        }
    }

    var systemImage: String {
        switch self {
        case .gif:    return "photo.stack"
        case .mp4:    return "film"
        case .frames: return "rectangle.grid.2x2"
        }
    }
}
