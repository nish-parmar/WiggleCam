import UIKit

enum WigglegramStage: String, CaseIterable, Identifiable {
    case normalizing   = "Matching Lenses"
    case aligning      = "Aligning Images"
    case cropping      = "Cropping"
    case building      = "Building Wigglegram"
    case done          = "Done"

    var id: String { rawValue }

    var progressFraction: Double {
        switch self {
        case .normalizing: return 0.20
        case .aligning:    return 0.50
        case .cropping:    return 0.75
        case .building:    return 0.95
        case .done:        return 1.0
        }
    }
}

protocol WigglegramBuilding {
    func build(from pair: CapturedPair,
               progress: @MainActor @escaping (WigglegramStage) -> Void) async throws -> Wigglegram
}

final class WigglegramBuilder: WigglegramBuilding {
    let normalizer: FOVNormalizer
    let aligner: ImageAligning
    let cropper: CropService

    init(normalizer: FOVNormalizer = FOVNormalizer(),
         aligner: ImageAligning = ImageAlignmentService(),
         cropper: CropService = CropService()) {
        self.normalizer = normalizer
        self.aligner = aligner
        self.cropper = cropper
    }

    func build(from pair: CapturedPair,
               progress: @MainActor @escaping (WigglegramStage) -> Void) async throws -> Wigglegram {
        // 1. Center-crop the wider-FOV image to match the narrower one so the
        //    two frames represent the same angular region of the scene.
        //    Without this, dual-cam wigglegrams look like a zoom, not parallax.
        await MainActor.run { progress(.normalizing) }
        let normalized = normalizer.normalize(pair)

        // 2. Align B to A using homographic registration (with translation fallback).
        await MainActor.run { progress(.aligning) }
        let aligned = try await aligner.align(imageA: normalized.imageA,
                                              imageB: normalized.imageB)

        // 3. Crop both to the shared valid region.
        await MainActor.run { progress(.cropping) }
        let (a, b) = cropper.cropToSharedOverlap(aligned)

        // 4. Final pass: ensure both frames are exactly the same pixel size.
        await MainActor.run { progress(.building) }
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
