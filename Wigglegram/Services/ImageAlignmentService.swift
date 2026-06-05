import UIKit
import Vision
import CoreImage

/// Result of aligning one image to another.
struct AlignmentResult {
    /// Image A (reference) — unchanged content.
    let imageA: UIImage
    /// Image B warped into A's coordinate space.
    let imageB: UIImage
    /// The affine transform that was applied to B (for diagnostics / future use).
    let appliedTransform: CGAffineTransform
}

/// Basic image alignment via Vision's traditional (non-ML) image registration.
///
/// Vision's `VNTranslationalImageRegistrationRequest` performs classical
/// feature-based registration — no neural networks, no synthetic content.
/// The transform is applied to image B so that it spatially matches image A.
///
/// This service is intentionally a thin, replaceable façade. Swap in an OpenCV
/// homography / ECC backend later by conforming to `ImageAligning`.
protocol ImageAligning {
    func align(_ pair: CapturedPair) async throws -> AlignmentResult
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

    func align(_ pair: CapturedPair) async throws -> AlignmentResult {
        let normalizedA = pair.imageA.normalizedOrientation()
        let normalizedB = pair.imageB.normalizedOrientation()

        guard let cgA = normalizedA.cgImage, normalizedB.cgImage != nil else {
            throw AlignmentError.invalidImage
        }

        // Vision works in pixel space; ensure both images share the same canvas size
        // by resizing B to A's pixel dimensions BEFORE registration. We only do a
        // proportional resize — no content alteration.
        let sizeA = CGSize(width: cgA.width, height: cgA.height)
        let resizedB = normalizedB.resized(to: sizeA)
        guard let cgBResized = resizedB.cgImage else { throw AlignmentError.invalidImage }

        let transform: CGAffineTransform
        do {
            transform = try await Self.detectTranslation(reference: cgA, moving: cgBResized)
        } catch {
            // If registration fails outright (e.g. low contrast / no features),
            // we fall back to identity so the rest of the pipeline still produces a frame.
            transform = .identity
        }

        let warpedB = Self.applyTransform(transform, to: cgBResized) ?? resizedB
        let resultA = UIImage(cgImage: cgA)

        return AlignmentResult(imageA: resultA, imageB: warpedB, appliedTransform: transform)
    }

    // MARK: - Vision registration
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
            do {
                try handler.perform([request])
            } catch {
                cont.resume(throwing: AlignmentError.requestFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Apply transform
    private static func applyTransform(_ transform: CGAffineTransform, to cg: CGImage) -> UIImage? {
        let ci = CIImage(cgImage: cg)
        // Vision's transform is in image (pixel) space with the origin at top-left.
        // CoreImage uses bottom-left origin, so we flip Y for translation.
        let flipped = CGAffineTransform(a: transform.a,
                                        b: -transform.b,
                                        c: -transform.c,
                                        d: transform.d,
                                        tx: transform.tx,
                                        ty: -transform.ty)
        let transformed = ci.transformed(by: flipped)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        // Render onto the original canvas extent so the output matches A's size.
        let canvas = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        guard let out = context.createCGImage(transformed, from: canvas) else { return nil }
        return UIImage(cgImage: out)
    }
}
