import CoreGraphics
import Foundation

/// Conversions between Core Graphics bitmaps and the top-down straight RGBA
/// buffers of the editor.
public enum EditorBitmap {
    /// Draw a `CGImage` into a top-down straight-alpha RGBA buffer.
    ///
    /// A bitmap context keeps its rows in the order of the image, so no
    /// vertical flip is needed here. The decoder, the AI snapshot path and the
    /// tests all share this one conversion.
    public static func topDownRGBA(
        from image: CGImage
    ) -> (width: Int, height: Int, rgba: [UInt8])? {
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
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )
        guard let raw = context.data else { return nil }
        let buffer = Data(bytes: raw, count: bytesPerRow * height)
        return (
            width,
            height,
            unpremultiply(buffer, width: width, height: height)
        )
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
                bytes[index] = UInt8(
                    min(255, Int(bytes[index]) * 255 / Int(alpha))
                )
                bytes[index + 1] = UInt8(
                    min(255, Int(bytes[index + 1]) * 255 / Int(alpha))
                )
                bytes[index + 2] = UInt8(
                    min(255, Int(bytes[index + 2]) * 255 / Int(alpha))
                )
            }
            index += 4
        }
        return bytes
    }
}
