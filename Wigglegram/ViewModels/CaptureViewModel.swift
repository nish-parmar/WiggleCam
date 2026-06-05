import SwiftUI
import AVFoundation

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var camera = CameraService()
    @Published var isReady: Bool = false
    @Published var errorMessage: String?

    var session: AVCaptureSession { camera.session }
    var captureMode: CaptureMode? { camera.capability?.mode }

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
    }

    func capture() async -> CapturedPair? {
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
}
