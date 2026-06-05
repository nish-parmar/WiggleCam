import Foundation
import SwiftUI

enum CaptureModePreference: String, CaseIterable, Identifiable {
    /// Use dual-cam if available, otherwise fall back to sequential.
    case auto
    /// Force two sequential shots from a single lens (more parallax,
    /// requires the user to move slightly between shots).
    case sequential
    /// Force dual-cam only; capture falls back to sequential if not supported.
    case dualOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:       return "Auto"
        case .sequential: return "Sequential"
        case .dualOnly:   return "Dual Camera"
        }
    }

    var explanation: String {
        switch self {
        case .auto:
            return "Use both rear lenses simultaneously when supported; otherwise fall back to two rapid shots."
        case .sequential:
            return "Take two rapid shots from a single lens. Slightly slide the phone horizontally between shots for stronger parallax."
        case .dualOnly:
            return "Always try to capture from two rear lenses at once for crisp, synchronised frames."
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("wg.fps") var framesPerSecond: Int = 8
    @AppStorage("wg.filmLook") var filmLookEnabled: Bool = false
    @AppStorage("wg.captureMode") private var captureModeRaw: String = CaptureModePreference.auto.rawValue

    var captureModePreference: CaptureModePreference {
        get { CaptureModePreference(rawValue: captureModeRaw) ?? .auto }
        set { captureModeRaw = newValue.rawValue }
    }
}
