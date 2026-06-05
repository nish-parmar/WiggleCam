@preconcurrency import AVFoundation
import UIKit
import Combine

/// Detected camera capability for the current device.
enum CameraCapability: Equatable {
    /// AVCaptureMultiCamSession is supported with this lens pair.
    case dual(primary: AVCaptureDevice, secondary: AVCaptureDevice, primaryLens: LensType, secondaryLens: LensType)
    /// Only single-camera capture is available; we'll take two sequential shots from this lens.
    case sequential(device: AVCaptureDevice, lens: LensType)

    var mode: CaptureMode {
        switch self {
        case .dual(_, _, let a, let b): return .dualCamera(primary: a, secondary: b)
        case .sequential(_, let lens):  return .sequential(lens: lens)
        }
    }
}

enum CameraError: LocalizedError {
    case notAuthorized
    case noBackCamera
    case configurationFailed(String)
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:               return "Camera access is required to take wigglegrams."
        case .noBackCamera:                return "No rear camera was found on this device."
        case .configurationFailed(let m):  return "Could not configure the camera: \(m)"
        case .captureFailed(let m):        return "Capture failed: \(m)"
        }
    }
}

@MainActor
final class CameraService: NSObject, ObservableObject {
    // MARK: - Published State
    @Published private(set) var capability: CameraCapability?
    @Published private(set) var isSessionRunning: Bool = false
    @Published private(set) var isCapturing: Bool = false
    @Published var lastError: CameraError?

    // MARK: - Session
    /// Either an AVCaptureMultiCamSession (when dual is supported) or AVCaptureSession.
    private(set) var session: AVCaptureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "app.wigglegram.cameraSession")

    // MARK: - Outputs / Inputs
    private var primaryOutput: AVCapturePhotoOutput?
    private var secondaryOutput: AVCapturePhotoOutput?
    private var primaryInput: AVCaptureDeviceInput?
    private var secondaryInput: AVCaptureDeviceInput?

    // Cached so we can stamp FOV onto each CapturedPair.
    private var primaryDevice: AVCaptureDevice?
    private var secondaryDevice: AVCaptureDevice?

    // MARK: - In-flight capture state
    private var pendingDualResults: [String: UIImage] = [:]
    private var pendingDualContinuation: CheckedContinuation<(UIImage, UIImage), Error>?
    private let pendingPrimaryID = "primary"
    private let pendingSecondaryID = "secondary"

    private var sequentialContinuation: CheckedContinuation<UIImage, Error>?

    deinit {
        // Stop session synchronously off the main actor; safe since we own the queue.
        let s = session
        DispatchQueue.global(qos: .userInitiated).async {
            if s.isRunning { s.stopRunning() }
        }
    }

    // MARK: - Authorization
    func requestAuthorizationIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:    return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default:             return false
        }
    }

    // MARK: - Configure
    func configure(preference: CaptureModePreference = .auto) async {
        guard await requestAuthorizationIfNeeded() else {
            lastError = .notAuthorized
            return
        }

        let detected = detectCapability(preference: preference)
        capability = detected

        switch detected {
        case .dual(let primary, let secondary, let aLens, let bLens):
            primaryDevice = primary
            secondaryDevice = secondary
            await configureDualSession(primary: primary, secondary: secondary,
                                       primaryLens: aLens, secondaryLens: bLens)
        case .sequential(let device, _):
            primaryDevice = device
            secondaryDevice = nil
            await configureSingleSession(device: device)
        case .none:
            lastError = .noBackCamera
        }
    }

    func startSession() {
        let session = self.session
        sessionQueue.async { [weak self] in
            if !session.isRunning {
                session.startRunning()
                let running = session.isRunning
                Task { @MainActor in self?.isSessionRunning = running }
            }
        }
    }

    func stopSession() {
        let session = self.session
        sessionQueue.async { [weak self] in
            if session.isRunning {
                session.stopRunning()
                Task { @MainActor in self?.isSessionRunning = false }
            }
        }
    }

    // MARK: - Capability Detection
    private func detectCapability(preference: CaptureModePreference) -> CameraCapability? {
        let isMultiSupported = AVCaptureMultiCamSession.isMultiCamSupported

        let wide  = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        let ultra = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
        let tele  = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)

        // If the user has explicitly chosen sequential capture, honor it
        // immediately — same lens, two slightly different positions yields
        // the strongest, most uniform parallax.
        if preference == .sequential {
            if let w = wide  { return .sequential(device: w, lens: .wide) }
            if let u = ultra { return .sequential(device: u, lens: .ultraWide) }
            if let t = tele  { return .sequential(device: t, lens: .telephoto) }
            return nil
        }

        // Otherwise prefer dual-cam pairings (auto + dualOnly both want this).
        // Preferred pairings:
        //   1) Wide + Ultra Wide (largest baseline on most iPhones)
        //   2) Wide + Telephoto
        if isMultiSupported, let w = wide, let u = ultra {
            return .dual(primary: w, secondary: u, primaryLens: .wide, secondaryLens: .ultraWide)
        }
        if isMultiSupported, let w = wide, let t = tele {
            return .dual(primary: w, secondary: t, primaryLens: .wide, secondaryLens: .telephoto)
        }

        // Fallback to a single rear camera (prefer wide).
        if let w = wide  { return .sequential(device: w, lens: .wide) }
        if let u = ultra { return .sequential(device: u, lens: .ultraWide) }
        if let t = tele  { return .sequential(device: t, lens: .telephoto) }
        return nil
    }

    // MARK: - Dual Session Configuration
    /// Builds the dual-cam pipeline on the session queue, then returns the configured
    /// components so the caller can assign them on the main actor.
    private struct DualConfig {
        let session: AVCaptureSession
        let primaryInput: AVCaptureDeviceInput
        let secondaryInput: AVCaptureDeviceInput
        let primaryOutput: AVCapturePhotoOutput
        let secondaryOutput: AVCapturePhotoOutput
    }

    private struct SingleConfig {
        let session: AVCaptureSession
        let input: AVCaptureDeviceInput
        let output: AVCapturePhotoOutput
    }

    private func configureDualSession(primary: AVCaptureDevice,
                                      secondary: AVCaptureDevice,
                                      primaryLens: LensType,
                                      secondaryLens: LensType) async {
        let result: Result<DualConfig, CameraError> = await withCheckedContinuation { cont in
            sessionQueue.async {
                cont.resume(returning: Self.buildDualConfig(primary: primary, secondary: secondary))
            }
        }
        switch result {
        case .success(let cfg):
            self.session = cfg.session
            self.primaryInput = cfg.primaryInput
            self.secondaryInput = cfg.secondaryInput
            self.primaryOutput = cfg.primaryOutput
            self.secondaryOutput = cfg.secondaryOutput
        case .failure(let err):
            self.lastError = err
        }
    }

    nonisolated private static func buildDualConfig(primary: AVCaptureDevice,
                                                    secondary: AVCaptureDevice) -> Result<DualConfig, CameraError> {
        let multi = AVCaptureMultiCamSession()
        multi.beginConfiguration()
        defer { multi.commitConfiguration() }
        do {
            let primaryInput = try AVCaptureDeviceInput(device: primary)
            let secondaryInput = try AVCaptureDeviceInput(device: secondary)
            guard multi.canAddInput(primaryInput), multi.canAddInput(secondaryInput) else {
                return .failure(.configurationFailed("Cannot add both inputs"))
            }
            multi.addInputWithNoConnections(primaryInput)
            multi.addInputWithNoConnections(secondaryInput)

            let primaryOutput = AVCapturePhotoOutput()
            let secondaryOutput = AVCapturePhotoOutput()
            guard multi.canAddOutput(primaryOutput), multi.canAddOutput(secondaryOutput) else {
                return .failure(.configurationFailed("Cannot add both outputs"))
            }
            multi.addOutputWithNoConnections(primaryOutput)
            multi.addOutputWithNoConnections(secondaryOutput)

            if let primaryVideo = primaryInput.ports(for: .video,
                                                     sourceDeviceType: primary.deviceType,
                                                     sourceDevicePosition: .back).first {
                let conn = AVCaptureConnection(inputPorts: [primaryVideo], output: primaryOutput)
                if multi.canAddConnection(conn) { multi.addConnection(conn) }
            }
            if let secVideo = secondaryInput.ports(for: .video,
                                                   sourceDeviceType: secondary.deviceType,
                                                   sourceDevicePosition: .back).first {
                let conn = AVCaptureConnection(inputPorts: [secVideo], output: secondaryOutput)
                if multi.canAddConnection(conn) { multi.addConnection(conn) }
            }
            return .success(DualConfig(session: multi,
                                       primaryInput: primaryInput,
                                       secondaryInput: secondaryInput,
                                       primaryOutput: primaryOutput,
                                       secondaryOutput: secondaryOutput))
        } catch {
            return .failure(.configurationFailed(error.localizedDescription))
        }
    }

    // MARK: - Single Session Configuration
    private func configureSingleSession(device: AVCaptureDevice) async {
        let result: Result<SingleConfig, CameraError> = await withCheckedContinuation { cont in
            sessionQueue.async {
                cont.resume(returning: Self.buildSingleConfig(device: device))
            }
        }
        switch result {
        case .success(let cfg):
            self.session = cfg.session
            self.primaryInput = cfg.input
            self.secondaryInput = nil
            self.primaryOutput = cfg.output
            self.secondaryOutput = nil
        case .failure(let err):
            self.lastError = err
        }
    }

    nonisolated private static func buildSingleConfig(device: AVCaptureDevice) -> Result<SingleConfig, CameraError> {
        let single = AVCaptureSession()
        single.sessionPreset = .photo
        single.beginConfiguration()
        defer { single.commitConfiguration() }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard single.canAddInput(input) else {
                return .failure(.configurationFailed("Cannot add input"))
            }
            single.addInput(input)
            let output = AVCapturePhotoOutput()
            guard single.canAddOutput(output) else {
                return .failure(.configurationFailed("Cannot add output"))
            }
            single.addOutput(output)
            return .success(SingleConfig(session: single, input: input, output: output))
        } catch {
            return .failure(.configurationFailed(error.localizedDescription))
        }
    }

    // MARK: - Capture
    func capturePair() async throws -> CapturedPair {
        guard let capability else { throw CameraError.noBackCamera }
        isCapturing = true
        defer { isCapturing = false }

        switch capability {
        case .dual:
            let (imageA, imageB) = try await captureDualImages()
            return CapturedPair(imageA: imageA,
                                imageB: imageB,
                                mode: capability.mode,
                                captureDate: Date(),
                                fovA: primaryDevice?.activeFormat.videoFieldOfView,
                                fovB: secondaryDevice?.activeFormat.videoFieldOfView)
        case .sequential(_, let lens):
            let a = try await captureSingle()
            // Brief delay so the user's slight hand motion gives a small viewpoint shift.
            try? await Task.sleep(nanoseconds: 120_000_000)
            let b = try await captureSingle()
            return CapturedPair(imageA: a,
                                imageB: b,
                                mode: .sequential(lens: lens),
                                captureDate: Date(),
                                fovA: primaryDevice?.activeFormat.videoFieldOfView,
                                fovB: primaryDevice?.activeFormat.videoFieldOfView)
        }
    }

    private func captureDualImages() async throws -> (UIImage, UIImage) {
        guard let primaryOutput, let secondaryOutput else {
            throw CameraError.captureFailed("Outputs not ready")
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(UIImage, UIImage), Error>) in
            pendingDualResults.removeAll()
            pendingDualContinuation = cont

            let settingsPrimary = AVCapturePhotoSettings()
            settingsPrimary.flashMode = .off
            let settingsSecondary = AVCapturePhotoSettings()
            settingsSecondary.flashMode = .off

            // `capturePhoto` is documented to be safe to call from any thread; it
            // internally hops to the photo output's serial queue. Calling it directly
            // avoids capturing non-Sendable AV types in a @Sendable dispatch closure.
            primaryOutput.capturePhoto(with: settingsPrimary,
                                       delegate: DualPhotoDelegate(owner: self, slot: pendingPrimaryID))
            secondaryOutput.capturePhoto(with: settingsSecondary,
                                         delegate: DualPhotoDelegate(owner: self, slot: pendingSecondaryID))
        }
    }

    private func captureSingle() async throws -> UIImage {
        guard let primaryOutput else { throw CameraError.captureFailed("Output not ready") }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UIImage, Error>) in
            sequentialContinuation = cont
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            primaryOutput.capturePhoto(with: settings,
                                       delegate: SinglePhotoDelegate(owner: self))
        }
    }

    // MARK: - Delegate callbacks (called on the photo output's internal queue)
    nonisolated fileprivate func dualDelegateDidProduce(image: UIImage?, error: Error?, slot: String) {
        Task { @MainActor in
            if let error {
                self.pendingDualContinuation?.resume(throwing: error)
                self.pendingDualContinuation = nil
                self.pendingDualResults.removeAll()
                return
            }
            guard let image else { return }
            self.pendingDualResults[slot] = image

            if let a = self.pendingDualResults[self.pendingPrimaryID],
               let b = self.pendingDualResults[self.pendingSecondaryID],
               let cont = self.pendingDualContinuation {
                cont.resume(returning: (a, b))
                self.pendingDualContinuation = nil
                self.pendingDualResults.removeAll()
            }
        }
    }

    nonisolated fileprivate func singleDelegateDidProduce(image: UIImage?, error: Error?) {
        Task { @MainActor in
            if let error {
                self.sequentialContinuation?.resume(throwing: error)
            } else if let image {
                self.sequentialContinuation?.resume(returning: image)
            } else {
                self.sequentialContinuation?.resume(throwing: CameraError.captureFailed("No image data"))
            }
            self.sequentialContinuation = nil
        }
    }
}

// MARK: - Photo Delegates
private final class DualPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    weak var owner: CameraService?
    let slot: String
    /// Self-retain so the delegate stays alive during the async capture round-trip.
    private var retainCycle: DualPhotoDelegate?

    init(owner: CameraService, slot: String) {
        self.owner = owner
        self.slot = slot
        super.init()
        self.retainCycle = self
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        defer { retainCycle = nil }
        let image = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
        owner?.dualDelegateDidProduce(image: image, error: error, slot: slot)
    }
}

private final class SinglePhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    weak var owner: CameraService?
    private var retainCycle: SinglePhotoDelegate?

    init(owner: CameraService) {
        self.owner = owner
        super.init()
        self.retainCycle = self
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        defer { retainCycle = nil }
        let image = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
        owner?.singleDelegateDidProduce(image: image, error: error)
    }
}
