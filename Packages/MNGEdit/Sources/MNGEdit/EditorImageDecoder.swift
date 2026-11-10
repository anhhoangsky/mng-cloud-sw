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
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        // The bitmap context is bottom-up; flip it back to the natural order.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let raw = context.data else { return nil }
        let buffer = Data(bytes: raw, count: bytesPerRow * height)
        return (
            UInt32(width),
            UInt32(height),
            unpremultiply(buffer, width: width, height: height)
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

    /// Core Graphics stores premultiplied alpha; the editor expects straight.
    private static func unpremultiply(
        _ buffer: Data,
        width: Int,
        height: Int
    ) -> [UInt8] {
        var bytes = [UInt8](buffer)
        let count = min(bytes.count, width * height * 4)
        var index = 0
        while index + 3 < count {
            let alpha = bytes[index + 3]
            if alpha > 0 && alpha < 255 {
                bytes[index] = UInt8(min(255, Int(bytes[index]) * 255 / Int(alpha)))
                bytes[index + 1] = UInt8(min(255, Int(bytes[index + 1]) * 255 / Int(alpha)))
                bytes[index + 2] = UInt8(min(255, Int(bytes[index + 2]) * 255 / Int(alpha)))
            }
            index += 4
        }
        return bytes
    }
}
