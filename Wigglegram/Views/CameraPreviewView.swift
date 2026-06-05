import SwiftUI
import AVFoundation

/// SwiftUI wrapper around AVCaptureVideoPreviewLayer.
///
/// Reports two coordinate spaces back to its caller on tap:
///  - `layerPoint` (in the preview view's own coordinate space) — useful for
///    positioning a focus reticle in SwiftUI overlay space.
///  - `devicePoint` (AVFoundation normalized 0..1) — pass to
///    `CameraService.setFocusAndExposure(at:)`.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: ((_ layerPoint: CGPoint, _ devicePoint: CGPoint) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        context.coordinator.parent = self
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            // Force-cast is safe because layerClass is overridden above.
            layer as! AVCaptureVideoPreviewLayer
        }
    }

    final class Coordinator: NSObject {
        var parent: CameraPreviewView
        init(_ parent: CameraPreviewView) { self.parent = parent }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? PreviewUIView else { return }
            let layerPoint = recognizer.location(in: view)
            let devicePoint = view.previewLayer
                .captureDevicePointConverted(fromLayerPoint: layerPoint)
            parent.onTap?(layerPoint, devicePoint)
        }
    }
}
