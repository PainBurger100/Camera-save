import UIKit
import ImageIO
import QuickLookThumbnailing

/// Native decoders handle CR2 and other RAW files supported by the installed iOS version.
/// Quick Look is a fallback for provider formats without a directly readable image.
enum PreviewService {
    static func filePreview(_ url: URL, pixels: CGFloat = 1800) async throws -> UIImage {
        if let image = await Task.detached(priority: .userInitiated, operation: { () -> UIImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(pixels),
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cgImage)
        }).value { return image }
        return try await withCheckedThrowingContinuation { continuation in
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: pixels, height: pixels), scale: 1, representationTypes: .thumbnail)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
                if let representation { continuation.resume(returning: representation.uiImage) }
                else { continuation.resume(throwing: error ?? FoliowError.message("No preview is available for this camera or photo format. Your original has not changed.")) }
            }
        }
    }
}
