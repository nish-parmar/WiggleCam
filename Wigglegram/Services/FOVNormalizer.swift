import UIKit
import CoreGraphics

/// Brings two images captured from different lenses onto a common angular
/// field-of-view by center-cropping the wider-FOV image down to match the
/// narrower-FOV image's coverage.
///
/// This is the critical pre-processing step for dual-camera stereoscopic
/// wigglegrams. On most iPhones the dual-cam pair is Wide (~65° HFOV) +
/// Ultra-Wide (~120° HFOV). Without normalization, the two frames have
/// roughly a 2× scale mismatch, which translation-only alignment cannot
/// correct — the ping-pong then reads as a *zoom*, not parallax.
///
/// After normalization, both images cover the same angular extent and
/// differ only by the small physical baseline between the two lenses.
/// That baseline *is* the stereoscopic parallax you want to see.
struct FOVNormalizer {

    struct Output {
        let imageA: UIImage
        let imageB: UIImage
        /// FOV both images now share, in degrees.
        let commonFOV: Float
    }

    /// Crops the wider-FOV image down so both frames cover the same angular
    /// extent. If FOVs are unknown or equal, the pair is returned untouched.
    func normalize(_ pair: CapturedPair) -> Output {
        let imageA = pair.imageA.normalizedOrientation()
        let imageB = pair.imageB.normalizedOrientation()

        guard let fovA = pair.fovA, let fovB = pair.fovB,
              fovA > 0, fovB > 0, abs(fovA - fovB) > 0.5 else {
            return Output(imageA: imageA, imageB: imageB,
                          commonFOV: pair.fovA ?? pair.fovB ?? 0)
        }

        // Target = the *narrower* lens (smaller FOV).
        let targetFOV = min(fovA, fovB)

        let outA = (fovA > targetFOV)
            ? Self.centerCrop(imageA, fromFOV: fovA, toFOV: targetFOV)
            : imageA
        let outB = (fovB > targetFOV)
            ? Self.centerCrop(imageB, fromFOV: fovB, toFOV: targetFOV)
            : imageB

        return Output(imageA: outA, imageB: outB, commonFOV: targetFOV)
    }

    /// Center-crops `image` so that the remaining region subtends `toFOV`
    /// instead of `fromFOV`. Pinhole approximation:
    ///   ratio = tan(toFOV/2) / tan(fromFOV/2)
    /// Both dimensions are scaled by `ratio` and the crop is taken around
    /// the image center.
    private static func centerCrop(_ image: UIImage, fromFOV: Float, toFOV: Float) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let pixelWidth  = CGFloat(cg.width)
        let pixelHeight = CGFloat(cg.height)

        let halfFrom = Double(fromFOV) * .pi / 360.0  // (fromFOV/2) in radians
        let halfTo   = Double(toFOV)   * .pi / 360.0
        let ratio    = CGFloat(tan(halfTo) / tan(halfFrom))

        let newWidth  = max(8, (pixelWidth  * ratio).rounded())
        let newHeight = max(8, (pixelHeight * ratio).rounded())
        let originX   = ((pixelWidth  - newWidth)  / 2).rounded()
        let originY   = ((pixelHeight - newHeight) / 2).rounded()

        let cropRect = CGRect(x: originX, y: originY, width: newWidth, height: newHeight)
        guard let cropped = cg.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }
}
