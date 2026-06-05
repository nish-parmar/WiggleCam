import UIKit

/// A raw, pre-processing pair of frames captured from the device.
struct CapturedPair: Hashable, Identifiable {
    let id = UUID()
    let imageA: UIImage
    let imageB: UIImage
    let mode: CaptureMode
    let captureDate: Date

    /// Horizontal field of view (degrees) for each lens at the moment of capture.
    /// Only meaningful for `.dualCamera`; nil for sequential (single-lens) captures.
    let fovA: Float?
    let fovB: Float?

    static func == (lhs: CapturedPair, rhs: CapturedPair) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
