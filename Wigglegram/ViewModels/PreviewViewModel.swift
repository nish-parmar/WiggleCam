import SwiftUI

@MainActor
final class PreviewViewModel: ObservableObject {
    @Published var currentFrameIndex: Int = 0
    @Published var isExporting: Bool = false
    @Published var exportMessage: String?
    @Published var errorMessage: String?

    let wigglegram: Wigglegram
    private let exporter: ExportService
    private var timer: Timer?

    init(wigglegram: Wigglegram, exporter: ExportService = ExportService()) {
        self.wigglegram = wigglegram
        self.exporter = exporter
    }

    var displayFrames: [UIImage] { wigglegram.pingPongFrames }
    var displayFramesWithFilmLook: [UIImage] {
        wigglegram.pingPongFrames.compactMap { FilmLook.apply(to: $0) }
    }

    func startPlayback(fps: Int) {
        stopPlayback()
        let interval = 1.0 / Double(max(1, fps))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.currentFrameIndex = (self.currentFrameIndex + 1) % self.displayFrames.count
            }
        }
    }

    func stopPlayback() {
        timer?.invalidate()
        timer = nil
    }

    func export(_ format: ExportFormat, fps: Int, filmLook: Bool) async {
        isExporting = true
        exportMessage = nil
        defer { isExporting = false }
        do {
            let result = try await exporter.export(wigglegram,
                                                    format: format,
                                                    fps: fps,
                                                    applyFilmLook: filmLook)
            HapticManager.notify(.success)
            switch result.format {
            case .gif:    exportMessage = "Saved GIF to Photos"
            case .mp4:    exportMessage = "Saved MP4 to Photos"
            case .frames: exportMessage = "Saved \(result.frameCount) frames to Photos"
            }
        } catch {
            HapticManager.notify(.error)
            errorMessage = error.localizedDescription
        }
    }
}
