import Foundation
import CoreMotion

/// Tracks accumulated horizontal-ish device motion to drive the Panorama-style
/// sequential capture guide. Emits a normalized progress value (0...1) and
/// invokes `onComplete` exactly once when enough motion has been observed
/// (or when the safety timeout elapses).
///
/// Implementation is intentionally simple — we integrate the magnitude of
/// `userAcceleration` (gravity-removed) over time and trigger when the
/// integrated value crosses a tuned threshold. The user just has to *move*
/// the phone; direction doesn't strictly matter, but a smooth horizontal
/// slide gives the cleanest parallax baseline.
@MainActor
final class MotionGuide: ObservableObject {
    @Published private(set) var progress: Double = 0   // 0...1
    @Published private(set) var isTracking: Bool = false

    private let manager = CMMotionManager()
    private let updateHz: Double = 60
    private let motionThreshold: Double = 0.55  // tuned for ~3–5 cm slide
    private let safetyTimeout: TimeInterval = 1.6

    private var accumulator: Double = 0
    private var startedAt: Date?
    private var onComplete: (() -> Void)?
    private var timeoutTask: Task<Void, Never>?

    /// Begins tracking. `onComplete` fires when either the motion threshold
    /// is reached or the safety timeout elapses, whichever comes first.
    func start(onComplete: @escaping () -> Void) {
        stop()
        self.onComplete = onComplete
        self.accumulator = 0
        self.progress = 0
        self.startedAt = Date()
        self.isTracking = true

        if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = 1.0 / updateHz
            manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, let motion else { return }
                self.handle(motion: motion)
            }
        }

        // Hard safety timeout — even if the user holds perfectly still we
        // still fire the second capture so the shot is never lost.
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.safetyTimeout ?? 1.6) * 1_000_000_000)
            await MainActor.run { self?.finishIfNeeded() }
        }
    }

    func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
        timeoutTask?.cancel()
        timeoutTask = nil
        isTracking = false
    }

    // MARK: - Private
    private func handle(motion: CMDeviceMotion) {
        let a = motion.userAcceleration
        let mag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
        accumulator += mag * (1.0 / updateHz)
        let p = min(1.0, accumulator / motionThreshold)
        // Also blend in elapsed-time progress so the bar always advances even
        // with sub-threshold motion — feels more responsive.
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        let timeP = min(1.0, elapsed / safetyTimeout)
        progress = max(p, timeP * 0.85)  // motion is preferred, time is the floor

        if accumulator >= motionThreshold {
            finishIfNeeded()
        }
    }

    private func finishIfNeeded() {
        guard isTracking else { return }
        let cb = onComplete
        onComplete = nil
        stop()
        progress = 1.0
        cb?()
    }
}
