import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Downsizes imported card images (Spec §5: images must be shrunk on import,
/// target ≤ a few hundred KB, to respect CloudKit limits and offline storage).
///
/// Uses ImageIO/CoreGraphics — cross-platform (iOS + macOS), no UIKit/AppKit — so
/// it lives in the pure core and is unit-testable. EXIF orientation is baked in.
public enum ImageDownsizer {

    /// Re-encode `data` as a JPEG no larger than `maxPixel` on its long edge.
    /// Returns `nil` if the data isn't a decodable image.
    public static func downsized(_ data: Data,
                                 maxPixel: Int = 1024,
                                 quality: CGFloat = 0.7) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // honor EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbnailOptions as CFDictionary) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let encodeOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
        ]
        CGImageDestinationAddImage(destination, thumbnail, encodeOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
