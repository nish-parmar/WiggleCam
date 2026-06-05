import UIKit

/// A raw, pre-processing pair of frames captured from the device.
struct CapturedPair: Hashable, Identifiable {
    let id = UUID()
    let imageA: UIImage
    let imageB: UIImage
    let mode: CaptureMode
    let captureDate: Date

    static func == (lhs: CapturedPair, rhs: CapturedPair) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
