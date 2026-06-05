import UIKit

/// Computes the shared visible area between two aligned images and crops both
/// to that overlap, avoiding any black "uncovered" borders introduced by warping.
struct CropService {

    func cropToSharedOverlap(_ aligned: AlignmentResult) -> (UIImage, UIImage) {
        let canvas = CGRect(x: 0,
                            y: 0,
                            width: aligned.imageA.size.width * aligned.imageA.scale,
                            height: aligned.imageA.size.height * aligned.imageA.scale)

        // Where B's pixels actually exist after applying its transform.
        // Vision's transform is in pixel space with top-left origin; we translate
        // a full-canvas rect by the same translation to find the valid region.
        let tx = aligned.appliedTransform.tx
        let ty = aligned.appliedTransform.ty

        let translatedB = canvas.offsetBy(dx: tx, dy: ty)
        let overlapPixels = canvas.intersection(translatedB).integral

        guard !overlapPixels.isNull, overlapPixels.width > 8, overlapPixels.height > 8 else {
            // Degenerate alignment — return originals.
            return (aligned.imageA, aligned.imageB)
        }

        let croppedA = aligned.imageA.croppingPixels(to: overlapPixels) ?? aligned.imageA
        let croppedB = aligned.imageB.croppingPixels(to: overlapPixels) ?? aligned.imageB
        return (croppedA, croppedB)
    }
}
