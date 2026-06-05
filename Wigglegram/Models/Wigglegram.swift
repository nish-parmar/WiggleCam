import UIKit

/// The processed pair of aligned, cropped frames ready to animate or export.
struct Wigglegram: Hashable, Identifiable {
    let id = UUID()
    let frameA: UIImage
    let frameB: UIImage
    let captureMode: CaptureMode
    let createdAt: Date

    /// Ping-pong sequence: A, B, A, B (the requested default).
    var pingPongFrames: [UIImage] {
        [frameA, frameB, frameA, frameB]
    }

    static func == (lhs: Wigglegram, rhs: Wigglegram) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
