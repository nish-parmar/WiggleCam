import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Result of aligning one image to another.
struct AlignmentResult {
    /// Image A (reference) — unchanged content.
    let imageA: UIImage
    /// Image B warped into A's coordinate space.
    let imageB: UIImage
    /// The affine transform that was applied to B (for diagnostics / cropping).
    /// Even when a homographic warp was used internally, we report the
    /// dominant translation here so the crop step has something to work with.
    let appliedTransform: CGAffineTransform
}

/// Basic image alignment via Vision's traditional (non-ML) image registration.
///
/// Vision's `VNHomographicImageRegistrationRequest` and
/// `VNTranslationalImageRegistrationRequest` perform classical
/// feature-based registration — no neural networks, no synthetic content.
/// The transform is applied to image B so that it spatially matches image A.
///
/// Internally we try the homographic request first (it can absorb small
/// residual scale / rotation differences that remain after FOV
/// normalization), and fall back to the translation request if homography
/// fails to converge.
///
/// This service is intentionally a thin, replaceable façade. Swap in an
/// OpenCV homography / ECC backend later by conforming to `ImageAligning`.
protocol ImageAligning {
    /// Aligns the two images in `pair.imageA` / `pair.imageB`. The pair's
    /// images are expected to already be FOV-normalized.
    func align(imageA: UIImage, imageB: UIImage) async throws -> AlignmentResult
}

enum AlignmentError: LocalizedError {
    case requestFailed(String)
    case noTransform
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .requestFailed(let m): return "Image alignment failed: \(m)"
        case .noTransform:          return "Could not determine an alignment transform."
        case .invalidImage:         return "Source images were invalid."
        }
    }
}

final class ImageAlignmentService: ImageAligning {

    func align(imageA: UIImage, imageB: UIImage) async throws -> AlignmentResult {
        let normalizedA = imageA.normalizedOrientation()
        let normalizedB = imageB.normalizedOrientation()

        guard let cgA = normalizedA.cgImage, normalizedB.cgImage != nil else {
            throw AlignmentError.invalidImage
        }

        // Vision works in pixel space; ensure both images share the same canvas
        // size by resizing B to A's pixel dimensions BEFORE registration.
        // Proportional resize only — no content alteration.
        let sizeA = CGSize(width: cgA.width, height: cgA.height)
        let resizedB = normalizedB.resized(to: sizeA)
        guard let cgBResized = resizedB.cgImage else { throw AlignmentError.invalidImage }

        // Try homography first (handles small residual scale / rotation that
        // a pure translation cannot). If it fails, fall back to translation.
        if let homography = try? await Self.detectHomography(reference: cgA, moving: cgBResized),
           let warpedB = Self.applyHomography(homography, to: cgBResized) {
            let translation = Self.translationFrom(homography,
                                                    imageWidth: CGFloat(cgA.width),
                                                    imageHeight: CGFloat(cgA.height))
            return AlignmentResult(imageA: UIImage(cgImage: cgA),
                                   imageB: warpedB,
                                   appliedTransform: translation)
        }

        let transform = (try? await Self.detectTranslation(reference: cgA, moving: cgBResized))
            ?? .identity
        let warpedB = Self.applyAffine(transform, to: cgBResized) ?? resizedB
        return AlignmentResult(imageA: UIImage(cgImage: cgA),
                               imageB: warpedB,
                               appliedTransform: transform)
    }

    // MARK: - Vision: homography
    private static func detectHomography(reference: CGImage, moving: CGImage) async throws -> matrix_float3x3 {
        try await withCheckedThrowingContinuation { cont in
            let request = VNHomographicImageRegistrationRequest(targetedCGImage: moving,
                                                                 options: [:]) { req, err in
                if let err {
                    cont.resume(throwing: AlignmentError.requestFailed(err.localizedDescription))
                    return
                }
                guard let observation = req.results?.first as? VNImageHomographicAlignmentObservation else {
                    cont.resume(throwing: AlignmentError.noTransform)
                    return
                }
                cont.resume(returning: observation.warpTransform)
            }
            let handler = VNImageRequestHandler(cgImage: reference, options: [:])
            do { try handler.perform([request]) }
            catch { cont.resume(throwing: AlignmentError.requestFailed(error.localizedDescription)) }
        }
    }

    // MARK: - Vision: translation (fallback)
    private static func detectTranslation(reference: CGImage, moving: CGImage) async throws -> CGAffineTransform {
        try await withCheckedThrowingContinuation { cont in
            let request = VNTranslationalImageRegistrationRequest(targetedCGImage: moving,
                                                                   options: [:]) { req, err in
                if let err {
                    cont.resume(throwing: AlignmentError.requestFailed(err.localizedDescription))
                    return
                }
                guard let observation = req.results?.first as? VNImageTranslationAlignmentObservation else {
                    cont.resume(throwing: AlignmentError.noTransform)
                    return
                }
                cont.resume(returning: observation.alignmentTransform)
            }
            let handler = VNImageRequestHandler(cgImage: reference, options: [:])
            do { try handler.perform([request]) }
            catch { cont.resume(throwing: AlignmentError.requestFailed(error.localizedDescription)) }
        }
    }

    // MARK: - Apply homography
    private static func applyHomography(_ h: matrix_float3x3, to cg: CGImage) -> UIImage? {
        let ci = CIImage(cgImage: cg)
        let w = CGFloat(cg.width), hgt = CGFloat(cg.height)

        // CoreImage's CIPerspectiveTransform takes 4 corner points (output
        // positions for each of the input image's corners) in CoreImage's
        // bottom-left coordinate space. Map the input corners through `h`
        // (which is in pixel space, top-left origin) and flip Y.
        func warp(_ x: CGFloat, _ y: CGFloat) -> CIVector {
            let v = SIMD3<Float>(Float(x), Float(y), 1)
            let r = h * v
            let nx = CGFloat(r.x / r.z)
            let ny = CGFloat(r.y / r.z)
            return CIVector(x: nx, y: hgt - ny)
        }
        let topLeft     = warp(0, 0)
        let topRight    = warp(w, 0)
        let bottomRight = warp(w, hgt)
        let bottomLeft  = warp(0, hgt)

        let filter = CIFilter.perspectiveTransform()
        filter.inputImage = ci
        filter.topLeft     = CGPoint(x: topLeft.x,     y: topLeft.y)
        filter.topRight    = CGPoint(x: topRight.x,    y: topRight.y)
        filter.bottomRight = CGPoint(x: bottomRight.x, y: bottomRight.y)
        filter.bottomLeft  = CGPoint(x: bottomLeft.x,  y: bottomLeft.y)

        guard let out = filter.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let canvas = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        guard let cgOut = context.createCGImage(out, from: canvas) else { return nil }
        return UIImage(cgImage: cgOut)
    }

    // MARK: - Apply translation
    private static func applyAffine(_ transform: CGAffineTransform, to cg: CGImage) -> UIImage? {
        let ci = CIImage(cgImage: cg)
        // Vision's transform is in image (pixel) space with top-left origin.
        // CoreImage uses bottom-left origin, so we flip Y for the translation.
        let flipped = CGAffineTransform(a: transform.a,
                                        b: -transform.b,
                                        c: -transform.c,
                                        d: transform.d,
                                        tx: transform.tx,
                                        ty: -transform.ty)
        let transformed = ci.transformed(by: flipped)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let canvas = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        guard let out = context.createCGImage(transformed, from: canvas) else { return nil }
        return UIImage(cgImage: out)
    }

    /// Extracts the dominant translation component of a 3×3 homography so
    /// `CropService` has a sensible shared-overlap region to work with.
    /// We compute the homography's effect on the image center: that delta
    /// is a good approximation of the bulk shift.
    private static func translationFrom(_ h: matrix_float3x3,
                                        imageWidth w: CGFloat,
                                        imageHeight hgt: CGFloat) -> CGAffineTransform {
        let cx = Float(w * 0.5), cy = Float(hgt * 0.5)
        let v = SIMD3<Float>(cx, cy, 1)
        let r = h * v
        let nx = r.x / r.z, ny = r.y / r.z
        return CGAffineTransform(translationX: CGFloat(nx) - CGFloat(cx),
                                 y: CGFloat(ny) - CGFloat(cy))
    }
}
