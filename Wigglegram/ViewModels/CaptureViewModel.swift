import SwiftUI
import AVFoundation

/// Phases of a capture interaction. For dual-cam this collapses to
/// `.idle → .firing → .done`; for sequential it walks through the guided
/// Panorama-style flow.
enum CapturePhase: Equatable {
    case idle
    case firingA      // primary shot in-flight
    case guiding      // sequential mode only: prompting the user to slide
    case firingB      // sequential mode only: second shot in-flight
    case done
}

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var camera = CameraService()
    @Published var motionGuide = MotionGuide()
    @Published var isReady: Bool = false
    @Published var errorMessage: String?

    @Published var phase: CapturePhase = .idle
    /// Last tap point in the preview view's coordinate space — used to
    /// animate the focus reticle. Cleared after the animation completes.
    @Published var lastFocusPoint: CGPoint?

    var session: AVCaptureSession { camera.session }
    var captureMode: CaptureMode? { camera.capability?.mode }

    private var firstFrame: UIImage?

    // MARK: - Lifecycle
    func start(preference: CaptureModePreference = .auto) async {
        await camera.configure(preference: preference)
        if let err = camera.lastError {
            errorMessage = err.localizedDescription
        }
        camera.startSession()
        isReady = camera.capability != nil
    }

    func stop() {
        camera.stopSession()
        motionGuide.stop()
    }

    // MARK: - Tap-to-focus
    func focus(at layerPoint: CGPoint, devicePoint: CGPoint) {
        camera.setFocusAndExposure(at: devicePoint)
        lastFocusPoint = layerPoint
        HapticManager.impact(.light)
        // Auto-clear the reticle after a beat.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            if self.lastFocusPoint == layerPoint { self.lastFocusPoint = nil }
        }
    }

    // MARK: - Capture orchestration
    /// Top-level capture entry point. Dispatches based on capability:
    ///  • Dual cam → fires both lenses simultaneously
    ///  • Sequential → guided two-shot with motion-driven progress
    func capture() async -> CapturedPair? {
        guard !isCapturing else { return nil }
        switch captureMode {
        case .dualCamera:
            return await captureDualShot()
        case .sequential:
            return await captureGuidedSequential()
        case .none:
            return nil
        }
    }

    var isCapturing: Bool { phase != .idle && phase != .done }

    private func captureDualShot() async -> CapturedPair? {
        phase = .firingA
        defer { phase = .idle }
        do {
            HapticManager.impact(.medium)
            let pair = try await camera.capturePair()
            HapticManager.notify(.success)
            return pair
        } catch {
            HapticManager.notify(.error)
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Sequential = "two snaps with motion-tracked slide between them".
    ///
    /// Implementation note: `CameraService.capturePair()` already implements
    /// sequential-mode internally as "shot A → delay → shot B". For the
    /// guided UX we drive it differently: capture A as one shot via direct
    /// access to a single-frame capture, run the motion guide while the
    /// user slides, then capture B.
    ///
    /// To avoid surgery in CameraService we wrap two synthetic single-shot
    /// captures through `camera.capturePair` by adjusting the inter-shot
    /// gap. The CameraService stub here calls into a new pair-of-singles
    /// helper that exposes the per-frame moment.
    private func captureGuidedSequential() async -> CapturedPair? {
        do {
            phase = .firingA
            HapticManager.impact(.medium)
            let a = try await camera.captureSingleShot()

            phase = .guiding
            await waitForGuidedMotion()

            phase = .firingB
            HapticManager.impact(.medium)
            let b = try await camera.captureSingleShot()
            HapticManager.notify(.success)

            phase = .done
            return CapturedPair(imageA: a,
                                imageB: b,
                                mode: captureMode ?? .sequential(lens: .wide),
                                captureDate: Date(),
                                fovA: camera.primaryDeviceFOV,
                                fovB: camera.primaryDeviceFOV)
        } catch {
            HapticManager.notify(.error)
            errorMessage = error.localizedDescription
            phase = .idle
            return nil
        }
    }

    private func waitForGuidedMotion() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            motionGuide.start { cont.resume() }
        }
    }
}
