import CoreGraphics
import Foundation
import ImageIO

/// Decodes an image into straight (non-premultiplied) RGBA bytes.
///
/// The EXIF orientation is applied, so the editor works on the pixels the user
/// sees. The row order is top-down, matching the Rust editor.
public enum EditorImageDecoder {
    public static func decode(
        _ data: Data
    ) -> (width: UInt32, height: UInt32, rgba: [UInt8])? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        guard let image = orientedImage(source: source, index: 0)
                ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        guard let converted = EditorBitmap.topDownRGBA(from: image) else {
            return nil
        }
        return (
            UInt32(converted.width),
            UInt32(converted.height),
            converted.rgba
        )
    }

    /// Copy with the EXIF orientation applied and no downscaling.
    private static func orientedImage(source: CGImageSource, index: Int) -> CGImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
            as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let maxSide = max(width, height)
        guard maxSide > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }
}
