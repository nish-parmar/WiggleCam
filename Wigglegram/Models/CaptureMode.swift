import Foundation

/// Describes how the app is capturing the two source frames.
enum CaptureMode: Equatable {
    /// Two rear cameras firing simultaneously via AVCaptureMultiCamSession.
    case dualCamera(primary: LensType, secondary: LensType)
    /// Two rapid sequential shots from a single rear camera.
    case sequential(lens: LensType)

    var displayName: String {
        switch self {
        case .dualCamera:  return "Dual Camera Supported"
        case .sequential:  return "Sequential Capture Mode"
        }
    }

    var detailDescription: String {
        switch self {
        case .dualCamera(let a, let b):
            return "\(a.shortName) + \(b.shortName)"
        case .sequential(let lens):
            return "\(lens.shortName) — two rapid shots"
        }
    }
}

enum LensType: String, Equatable {
    case ultraWide
    case wide
    case telephoto

    var shortName: String {
        switch self {
        case .ultraWide:  return "Ultra Wide"
        case .wide:       return "Wide"
        case .telephoto:  return "Telephoto"
        }
    }
}
