import CoreGraphics
import CoreImage
import Foundation
import MNGEdit

/// A top-down, straight-alpha RGBA buffer in the same orientation as
/// `EditorSourceSnapshot`.
///
/// Core ML inputs are built from this type, never from a `CIImage` extent
/// directly, so a coordinate flip cannot creep into the model path.
struct EditorAIPixelBuffer: Equatable, Sendable {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    init?(width: Int, height: Int, rgba: [UInt8]) {
        guard width > 0, height > 0,
              rgba.count == width * height * 4 else {
            return nil
        }
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    init(source: EditorSourceSnapshot) throws {
        guard let buffer = EditorAIPixelBuffer(
            width: Int(source.width),
            height: Int(source.height),
            rgba: source.rgba
        ) else {
            throw EditorAIError.failed
        }
        self = buffer
    }

    var sourceSnapshot: EditorSourceSnapshot {
        EditorSourceSnapshot(
            width: UInt32(width),
            height: UInt32(height),
            rgba: rgba
        )
    }

    /// Fit the source inside a `side`-sided square without distorting it.
    /// The padding repeats the edge pixels instead of adding black bars: a
    /// matting model sees a plausible border, and the returned `content`
    /// rectangle is what the alpha is cropped back to.
    static func letterboxed(
        _ source: EditorSourceSnapshot,
        side: Int
    ) throws -> (buffer: EditorAIPixelBuffer, content: CGRect) {
        guard side > 0, source.width > 0, source.height > 0 else {
            throw EditorAIError.failed
        }
        let width = Int(source.width)
        let height = Int(source.height)
        let scale = CGFloat(side) / CGFloat(max(width, height))
        let contentWidth = max(1, Int((CGFloat(width) * scale).rounded()))
        let contentHeight = max(1, Int((CGFloat(height) * scale).rounded()))
        let x = (side - contentWidth) / 2
        let top = (side - contentHeight) / 2

        let image = try EditorAIImage.makeImage(source)
        let scaled = image.transformed(
            by: CGAffineTransform(
                scaleX: CGFloat(contentWidth) / CGFloat(width),
                y: CGFloat(contentHeight) / CGFloat(height)
            )
        )
        // Core Image's origin is bottom-left; `top` is measured from the top.
        let placed = scaled.transformed(
            by: CGAffineTransform(
                translationX: CGFloat(x),
                y: CGFloat(side - contentHeight - top)
            )
        )
        let square = CGRect(x: 0, y: 0, width: side, height: side)
        let padded = placed.clampedToExtent().cropped(to: square)
        let buffer = try render(padded, width: side, height: side)
        return (
            buffer,
            CGRect(
                x: x,
                y: top,
                width: contentWidth,
                height: contentHeight
            )
        )
    }

    /// A top-down crop. Used by the face parser, where a manual row copy is
    /// cheaper and less error-prone than another Core Image round trip.
    func cropped(
        x: Int,
        y: Int,
        width: Int,
        height: Int
    ) throws -> EditorAIPixelBuffer {
        guard x >= 0, y >= 0, width > 0, height > 0,
              x + width <= self.width,
              y + height <= self.height else {
            throw EditorAIError.failed
        }
        if x == 0, y == 0, width == self.width, height == self.height {
            return self
        }
        let rowBytes = width * 4
        var output = [UInt8](repeating: 0, count: rowBytes * height)
        for row in 0..<height {
            let start = ((y + row) * self.width + x) * 4
            output.replaceSubrange(
                (row * rowBytes)..<((row + 1) * rowBytes),
                with: rgba[start..<(start + rowBytes)]
            )
        }
        guard let buffer = EditorAIPixelBuffer(
            width: width,
            height: height,
            rgba: output
        ) else {
            throw EditorAIError.failed
        }
        return buffer
    }

    func resized(width: Int, height: Int) throws -> EditorAIPixelBuffer {
        guard width > 0, height > 0 else { throw EditorAIError.failed }
        if width == self.width, height == self.height { return self }
        let image = try EditorAIImage.makeImage(sourceSnapshot)
        let scaled = image.transformed(
            by: CGAffineTransform(
                scaleX: CGFloat(width) / CGFloat(self.width),
                y: CGFloat(height) / CGFloat(self.height)
            )
        )
        return try Self.render(scaled, width: width, height: height)
    }

    private static func render(
        _ image: CIImage,
        width: Int,
        height: Int
    ) throws -> EditorAIPixelBuffer {
        let extent = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(width),
            height: CGFloat(height)
        )
        let context = EditorAIImage.makeContext()
        guard let cgImage = context.createCGImage(
            image.cropped(to: extent),
            from: extent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        ), let converted = EditorBitmap.topDownRGBA(from: cgImage),
           let buffer = EditorAIPixelBuffer(
            width: width,
            height: height,
            rgba: converted.rgba
           ) else {
            throw EditorAIError.failed
        }
        return buffer
    }
}
