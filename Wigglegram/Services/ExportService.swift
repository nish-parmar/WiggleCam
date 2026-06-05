import UIKit
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import AVFoundation
import Photos

enum ExportError: LocalizedError {
    case photoPermissionDenied
    case writeFailed(String)
    case noFrames

    var errorDescription: String? {
        switch self {
        case .photoPermissionDenied: return "Photos access was denied — please enable it in Settings."
        case .writeFailed(let m):    return "Export failed: \(m)"
        case .noFrames:              return "No frames to export."
        }
    }
}

struct ExportResult {
    let format: ExportFormat
    let fileURL: URL?
    let frameCount: Int
}

final class ExportService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Public API
    func export(_ wigglegram: Wigglegram,
                format: ExportFormat,
                fps: Int,
                applyFilmLook: Bool) async throws -> ExportResult {
        try await ensurePhotoLibraryAddPermission()
        let frames = renderFrames(wigglegram, applyFilmLook: applyFilmLook)
        guard !frames.isEmpty else { throw ExportError.noFrames }

        switch format {
        case .gif:
            let url = try writeGIF(frames: frames, fps: fps)
            try await saveImageFileToPhotos(url: url)
            return ExportResult(format: .gif, fileURL: url, frameCount: frames.count)

        case .mp4:
            let url = try await writeMP4(frames: frames, fps: fps)
            try await saveVideoToPhotos(url: url)
            return ExportResult(format: .mp4, fileURL: url, frameCount: frames.count)

        case .frames:
            let urls = try writeFrames(frames)
            for u in urls { try await saveImageFileToPhotos(url: u) }
            return ExportResult(format: .frames, fileURL: nil, frameCount: urls.count)
        }
    }

    // MARK: - Permissions
    private func ensurePhotoLibraryAddPermission() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { (cont: CheckedContinuation<PHAuthorizationStatus, Never>) in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { s in cont.resume(returning: s) }
            }
            if granted != .authorized && granted != .limited {
                throw ExportError.photoPermissionDenied
            }
        default:
            throw ExportError.photoPermissionDenied
        }
    }

    // MARK: - Frame rendering
    private func renderFrames(_ wigglegram: Wigglegram, applyFilmLook: Bool) -> [UIImage] {
        let base = wigglegram.pingPongFrames
        guard applyFilmLook else { return base }
        return base.map { FilmLook.apply(to: $0) ?? $0 }
    }

    // MARK: - GIF
    private func writeGIF(frames: [UIImage], fps: Int) throws -> URL {
        let url = makeTempURL(extension: "gif")
        let delay = 1.0 / Double(max(1, fps))

        let fileProps: CFDictionary = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ] as CFDictionary

        let frameProps: CFDictionary = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: delay,
                kCGImagePropertyGIFUnclampedDelayTime as String: delay
            ]
        ] as CFDictionary

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL,
                                                          UTType.gif.identifier as CFString,
                                                          frames.count, nil) else {
            throw ExportError.writeFailed("Could not create GIF destination")
        }
        CGImageDestinationSetProperties(dest, fileProps)

        for image in frames {
            guard let cg = image.cgImage else { continue }
            CGImageDestinationAddImage(dest, cg, frameProps)
        }
        if !CGImageDestinationFinalize(dest) {
            throw ExportError.writeFailed("GIF finalize failed")
        }
        return url
    }

    // MARK: - MP4
    private func writeMP4(frames: [UIImage], fps: Int) async throws -> URL {
        guard let first = frames.first, let firstCG = first.cgImage else {
            throw ExportError.noFrames
        }
        let url = makeTempURL(extension: "mp4")
        try? fileManager.removeItem(at: url)

        let width = firstCG.width - (firstCG.width % 2)
        let height = firstCG.height - (firstCG.height % 2)
        let size = CGSize(width: width, height: height)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                            sourcePixelBufferAttributes: sourcePixelBufferAttributes)

        guard writer.canAdd(input) else { throw ExportError.writeFailed("Cannot add video input") }
        writer.add(input)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: Int32(max(1, fps)))
        // Loop the ping-pong sequence a few times so the MP4 has perceivable length.
        let loopCount = 4
        let allFrames = Array(repeating: frames, count: loopCount).flatMap { $0 }

        let queue = DispatchQueue(label: "app.wigglegram.mp4Writer")

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var index = 0
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if index >= allFrames.count {
                        input.markAsFinished()
                        writer.finishWriting {
                            if writer.status == .completed {
                                cont.resume()
                            } else {
                                cont.resume(throwing: ExportError.writeFailed(writer.error?.localizedDescription ?? "writer failed"))
                            }
                        }
                        return
                    }
                    let image = allFrames[index]
                    let pts = CMTimeMultiply(frameDuration, multiplier: Int32(index))
                    guard let buffer = Self.pixelBuffer(from: image, size: size, pool: adaptor.pixelBufferPool) else {
                        index += 1
                        continue
                    }
                    if !adaptor.append(buffer, withPresentationTime: pts) {
                        input.markAsFinished()
                        writer.cancelWriting()
                        cont.resume(throwing: ExportError.writeFailed("append failed at \(index)"))
                        return
                    }
                    index += 1
                }
            }
        }
        return url
    }

    private static func pixelBuffer(from image: UIImage,
                                    size: CGSize,
                                    pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?

        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        } else {
            let attrs: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            CVPixelBufferCreate(kCFAllocatorDefault,
                                Int(size.width),
                                Int(size.height),
                                kCVPixelFormatType_32BGRA,
                                attrs as CFDictionary,
                                &pixelBuffer)
        }

        guard let buffer = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let ctx = context, let cg = image.cgImage else { return nil }
        ctx.draw(cg, in: CGRect(origin: .zero, size: size))
        return buffer
    }

    // MARK: - JPG Frames
    private func writeFrames(_ frames: [UIImage]) throws -> [URL] {
        // Export the two unique source frames (A & B), not the ping-pong duplicates.
        let unique = Array(frames.prefix(2))
        var urls: [URL] = []
        for (i, frame) in unique.enumerated() {
            let url = makeTempURL(extension: "jpg", suffix: "frame-\(i + 1)")
            guard let data = frame.jpegData(compressionQuality: 0.95) else {
                throw ExportError.writeFailed("JPG encode failed")
            }
            try data.write(to: url)
            urls.append(url)
        }
        return urls
    }

    // MARK: - Photos save
    private func saveImageFileToPhotos(url: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, fileURL: url, options: nil)
            }, completionHandler: { success, error in
                if success { cont.resume() }
                else { cont.resume(throwing: ExportError.writeFailed(error?.localizedDescription ?? "photo save failed")) }
            })
        }
    }

    private func saveVideoToPhotos(url: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .video, fileURL: url, options: nil)
            }, completionHandler: { success, error in
                if success { cont.resume() }
                else { cont.resume(throwing: ExportError.writeFailed(error?.localizedDescription ?? "video save failed")) }
            })
        }
    }

    // MARK: - Helpers
    private func makeTempURL(extension ext: String, suffix: String = UUID().uuidString) -> URL {
        let dir = fileManager.temporaryDirectory
        return dir.appendingPathComponent("wigglegram-\(suffix).\(ext)")
    }
}
