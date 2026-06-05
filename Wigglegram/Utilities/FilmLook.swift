import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// A subtle, optional grading pass — slight desaturation, mild grain, light vignette.
/// Purely cosmetic; does NOT alter image content (no AI, no faces touched).
enum FilmLook {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func apply(to image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let ci = CIImage(cgImage: cg)

        // Slight desaturation + warm/cool tweak.
        let color = CIFilter.colorControls()
        color.inputImage = ci
        color.saturation = 0.55
        color.contrast   = 1.08
        color.brightness = -0.02
        let graded = color.outputImage ?? ci

        // Soft vignette.
        let vignette = CIFilter.vignette()
        vignette.inputImage = graded
        vignette.intensity  = 0.6
        vignette.radius     = 1.5
        let vignetted = vignette.outputImage ?? graded

        // Mild grain.
        let noise = CIFilter.randomGenerator().outputImage?
            .cropped(to: ci.extent)
        let grainBlend = CIFilter.sourceOverCompositing()
        if let noise {
            let dim = CIFilter.colorMatrix()
            dim.inputImage = noise
            // ~6% alpha grain — perceptible but never distracting.
            dim.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.06)
            grainBlend.inputImage = dim.outputImage
            grainBlend.backgroundImage = vignetted
        } else {
            grainBlend.inputImage = vignetted
        }
        let final = grainBlend.outputImage ?? vignetted

        guard let out = context.createCGImage(final, from: ci.extent) else { return nil }
        return UIImage(cgImage: out, scale: image.scale, orientation: .up)
    }
}
