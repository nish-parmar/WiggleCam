import UIKit

extension UIImage {

    /// Re-renders the image so its `imageOrientation` is `.up` and pixel data
    /// matches the visible orientation. Required before pixel-space math.
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Resizes to the given size in points (preserving scale).
    func resized(to newSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Crops by a rect in pixel space (matches `cgImage.width/height`).
    func croppingPixels(to pixelRect: CGRect) -> UIImage? {
        guard let cg = cgImage else { return nil }
        guard let cropped = cg.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }
}
