import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import MNGEdit

/// Conversions between the editor's top-down snapshots, Core Image and the
/// brush masks. The AI engines and the compositing path share these so a mask
/// cannot be flipped or resampled differently depending on which engine made
/// it.
enum EditorAIImage {
    static func makeContext() -> CIContext {
        CIContext(options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .outputColorSpace: CGColorSpaceCreateDeviceRGB(),
        ])
    }

    /// The source pixels as a Core Image bitmap. The buffer is top-down, and
    /// the resulting `CIImage` keeps the same orientation, so Vision boxes and
    /// Core Image crops stay aligned.
    static func makeImage(
        _ source: EditorSourceSnapshot
    ) throws -> CIImage {
        guard source.width > 0, source.height > 0 else {
            throw EditorAIError.failed
        }
        let expected = Int(source.width) * Int(source.height) * 4
        guard source.rgba.count == expected,
              let provider = CGDataProvider(
                data: Data(source.rgba) as CFData
              ),
              let cgImage = CGImage(
                width: Int(source.width),
                height: Int(source.height),
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: Int(source.width) * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.last.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw EditorAIError.failed
        }
        return CIImage(cgImage: cgImage)
    }

    static func scaledImage(
        _ source: EditorSourceSnapshot,
        maxSide: CGFloat
    ) throws -> CIImage {
        let input = try makeImage(source)
        let extent = input.extent
        let side = max(extent.width, extent.height)
        guard maxSide > 0, side > maxSide else { return input }
        let scale = maxSide / side
        let width = max(1, (extent.width * scale).rounded())
        let height = max(1, (extent.height * scale).rounded())
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        return input
            .transformed(
                by: CGAffineTransform(scaleX: scale, y: scale)
            )
            .cropped(to: target)
    }

    /// The mask as a top-down Core Image bitmap. The brush stores the same
    /// row order, so the painted edge lands on the pixel under the finger.
    static func maskImage(_ mask: EditorAIMask) throws -> CIImage {
        guard mask.width > 0,
              mask.height > 0,
              mask.bytes.count == mask.width * mask.height,
              let provider = CGDataProvider(
                data: Data(mask.bytes) as CFData
              ),
              let image = CGImage(
                width: mask.width,
                height: mask.height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: mask.width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.none.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw EditorAIError.failed
        }
        return CIImage(cgImage: image)
    }

    /// Resample a soft mask into the brush contract: long side at most
    /// `maxSide`, aspect preserved, row 0 at the top.
    static func makeMask(
        from image: CIImage,
        maxSide: Int
    ) throws -> EditorAIMask {
        let extent = image.extent
        guard extent.width >= 1, extent.height >= 1, maxSide > 0 else {
            throw EditorAIError.failed
        }
        let side = max(extent.width, extent.height)
        let scale = side > CGFloat(maxSide) ? CGFloat(maxSide) / side : 1
        let width = max(1, Int((extent.width * scale).rounded()))
        let height = max(1, Int((extent.height * scale).rounded()))
        let target = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(width),
            height: CGFloat(height)
        )
        let scaled = image
            .transformed(
                by: CGAffineTransform(scaleX: scale, y: scale)
            )
            .cropped(to: target)
        let context = makeContext()
        guard let cgImage = context.createCGImage(
            scaled,
            from: target,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        ), let converted = EditorBitmap.topDownRGBA(from: cgImage) else {
            throw EditorAIError.failed
        }
        guard converted.width == width, converted.height == height else {
            throw EditorAIError.failed
        }
        var bytes = [UInt8](repeating: 0, count: width * height)
        let count = min(bytes.count, converted.width * converted.height)
        var index = 0
        while index < count {
            bytes[index] = converted.rgba[index * 4]
            index += 1
        }
        return EditorAIMask(width: width, height: height, bytes: bytes)
    }

    static func snapshot(
        from image: CIImage,
        width: Int,
        height: Int
    ) throws -> EditorSourceSnapshot {
        guard width > 0, height > 0 else { throw EditorAIError.failed }
        let extent = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(width),
            height: CGFloat(height)
        )
        let context = makeContext()
        guard let cgImage = context.createCGImage(
            image.cropped(to: extent),
            from: extent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        ), let converted = EditorBitmap.topDownRGBA(from: cgImage) else {
            throw EditorAIError.failed
        }
        return EditorSourceSnapshot(
            width: UInt32(converted.width),
            height: UInt32(converted.height),
            rgba: converted.rgba
        )
    }

    static func scaleMask(
        _ mask: CIImage,
        to extent: CGRect
    ) -> CIImage {
        let scaleX = extent.width / max(mask.extent.width, 1)
        let scaleY = extent.height / max(mask.extent.height, 1)
        return mask
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: extent)
    }

    /// A grayscale bitmap from a float alpha plane. Row 0 stays at the top;
    /// the Core ML output is already top-down, so no flip is applied.
    static func alphaImage(
        _ values: [Float],
        width: Int,
        height: Int
    ) throws -> CIImage {
        guard width > 0, height > 0,
              values.count == width * height else {
            throw EditorAIError.failed
        }
        var bytes = [UInt8](repeating: 0, count: values.count)
        for index in 0..<values.count {
            let value = min(max(values[index], 0), 1)
            bytes[index] = UInt8((value * 255).rounded())
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.none.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw EditorAIError.failed
        }
        return CIImage(cgImage: image)
    }
}
