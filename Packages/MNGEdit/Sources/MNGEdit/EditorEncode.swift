import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension Editor {
    /// Encode an RGBA buffer into the requested container.
    static func encode(
        format: EditorExportFormat,
        quality: UInt8,
        rgba: [UInt8],
        width: UInt32,
        height: UInt32
    ) throws -> Data {
        let image = try makeImage(rgba: rgba, width: width, height: height)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            format.identifier as CFString,
            1,
            nil
        ) else {
            throw MNGEditError.encode(format.rawValue)
        }
        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] =
                Double(min(max(quality, 1), 100)) / 100
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw MNGEditError.encode(format.rawValue)
        }
        return data as Data
    }

    /// Build a CGImage from straight (non-premultiplied) RGBA bytes.
    static func makeImage(
        rgba: [UInt8],
        width: UInt32,
        height: UInt32
    ) throws -> CGImage {
        guard width > 0, height > 0 else {
            throw MNGEditError.invalidDimensions
        }
        let expected = Int(UInt64(width) * UInt64(height) * 4)
        guard rgba.count == expected else {
            throw MNGEditError.invalidBuffer
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(
                width: Int(width),
                height: Int(height),
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: Int(width) * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw MNGEditError.encode("image")
        }
        return image
    }
}

extension EditorExportFormat {
    /// Uniform type identifier used by ImageIO.
    var identifier: String {
        switch self {
        case .jpeg: return UTType.jpeg.identifier
        case .png: return UTType.png.identifier
        case .webp: return UTType.webP.identifier
        }
    }
}
