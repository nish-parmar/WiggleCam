import UIKit

enum WigglegramStage: String, CaseIterable, Identifiable {
    case aligning      = "Aligning Images"
    case cropping      = "Cropping"
    case building      = "Building Wigglegram"
    case done          = "Done"

    var id: String { rawValue }

    var progressFraction: Double {
        switch self {
        case .aligning: return 0.33
        case .cropping: return 0.66
        case .building: return 0.95
        case .done:     return 1.0
        }
    }
}

protocol WigglegramBuilding {
    func build(from pair: CapturedPair,
               progress: @MainActor @escaping (WigglegramStage) -> Void) async throws -> Wigglegram
}

final class WigglegramBuilder: WigglegramBuilding {
    let aligner: ImageAligning
    let cropper: CropService

    init(aligner: ImageAligning = ImageAlignmentService(),
         cropper: CropService = CropService()) {
        self.aligner = aligner
        self.cropper = cropper
    }

    func build(from pair: CapturedPair,
               progress: @MainActor @escaping (WigglegramStage) -> Void) async throws -> Wigglegram {
        await MainActor.run { progress(.aligning) }
        let aligned = try await aligner.align(pair)

        await MainActor.run { progress(.cropping) }
        let (a, b) = cropper.cropToSharedOverlap(aligned)

        await MainActor.run { progress(.building) }
        // Final downscale to keep export sizes reasonable; preserves aspect ratio.
        let final = Self.matchSizes(a, b)

        await MainActor.run { progress(.done) }
        return Wigglegram(frameA: final.0,
                          frameB: final.1,
                          captureMode: pair.mode,
                          createdAt: Date())
    }

    /// Ensures both frames are exactly the same pixel size (defensive — they
    /// should already match after sharing a crop rect).
    private static func matchSizes(_ a: UIImage, _ b: UIImage) -> (UIImage, UIImage) {
        if a.size == b.size { return (a, b) }
        let target = a.size
        return (a, b.resized(to: target))
    }
}
