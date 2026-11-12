import Foundation
#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

/// Limits mirrored from the server's `save_edit` route.
public enum EditorLimits {
    public static let maxImageSide: UInt32 = 20_000
    public static let maxImagePixels: UInt64 = 120_000_000
    public static let defaultPreviewSide: UInt32 = 1600
    public static let maxPreviewSide: UInt32 = 4096
}

/// Errors of the editor pipeline, mirroring `mng-edit`'s `Error` enum.
public enum MNGEditError: Error, Equatable {
    case invalidDimensions
    case invalidBuffer
    case unknownFormat(String)
    case unknownFilter(String)
    case adjustments(String)
    case encode(String)
}

/// Normalized crop rectangle (0…1 of the oriented display).
public struct EditorCrop: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float

    public static let full = EditorCrop(x: 0, y: 0, width: 1, height: 1)

    /// Clamp a normalized selection so every value stays finite and the
    /// rectangle stays inside the image.
    public init(x: Float, y: Float, width: Float, height: Float) {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite else {
            self = EditorCrop.full
            return
        }
        let clampedX = min(max(x, 0), 1)
        let clampedY = min(max(y, 0), 1)
        let clampedWidth = min(max(width, 0), 1 - clampedX)
        let clampedHeight = min(max(height, 0), 1 - clampedY)
        if clampedWidth <= Float.ulpOfOne || clampedHeight <= Float.ulpOfOne {
            self = EditorCrop.full
            return
        }
        self.x = clampedX
        self.y = clampedY
        self.width = clampedWidth
        self.height = clampedHeight
    }
}

/// Pixel rectangle selected by the normalized crop.
public struct EditorCropPixels: Equatable, Sendable {
    public var x: UInt32
    public var y: UInt32
    public var width: UInt32
    public var height: UInt32

    public init(x: UInt32, y: UInt32, width: UInt32, height: UInt32) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// The nine sliders of the editor. Every value is clamped to ±100.
public struct EditorAdjustments: Codable, Equatable, Sendable {
    public var brightness: Float
    public var contrast: Float
    public var saturation: Float
    public var exposure: Float
    public var warmth: Float
    public var tint: Float
    public var highlights: Float
    public var shadows: Float
    public var vignette: Float
    /// The top end of the tone scale, like the whites of a raw file.
    public var whites: Float
    /// The bottom end of the tone scale.
    public var blacks: Float
    /// The saturation of the colours that are not saturated yet.
    public var vibrance: Float
    /// The midtones of the tone curve.
    public var gamma: Float

    public init(
        brightness: Float = 0,
        contrast: Float = 0,
        saturation: Float = 0,
        exposure: Float = 0,
        warmth: Float = 0,
        tint: Float = 0,
        highlights: Float = 0,
        shadows: Float = 0,
        vignette: Float = 0,
        whites: Float = 0,
        blacks: Float = 0,
        vibrance: Float = 0,
        gamma: Float = 0
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.exposure = exposure
        self.warmth = warmth
        self.tint = tint
        self.highlights = highlights
        self.shadows = shadows
        self.vignette = vignette
        self.whites = whites
        self.blacks = blacks
        self.vibrance = vibrance
        self.gamma = gamma
    }

    public static let zero = EditorAdjustments()

    public var isIdentity: Bool {
        self == EditorAdjustments.zero
    }

    private enum CodingKeys: String, CodingKey {
        case brightness, contrast, saturation, exposure, warmth
        case tint, highlights, shadows, vignette
        case whites, blacks, vibrance, gamma
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        brightness = try container.decodeIfPresent(Float.self, forKey: .brightness) ?? 0
        contrast = try container.decodeIfPresent(Float.self, forKey: .contrast) ?? 0
        saturation = try container.decodeIfPresent(Float.self, forKey: .saturation) ?? 0
        exposure = try container.decodeIfPresent(Float.self, forKey: .exposure) ?? 0
        warmth = try container.decodeIfPresent(Float.self, forKey: .warmth) ?? 0
        tint = try container.decodeIfPresent(Float.self, forKey: .tint) ?? 0
        highlights = try container.decodeIfPresent(Float.self, forKey: .highlights) ?? 0
        shadows = try container.decodeIfPresent(Float.self, forKey: .shadows) ?? 0
        vignette = try container.decodeIfPresent(Float.self, forKey: .vignette) ?? 0
        whites = try container.decodeIfPresent(Float.self, forKey: .whites) ?? 0
        blacks = try container.decodeIfPresent(Float.self, forKey: .blacks) ?? 0
        vibrance = try container.decodeIfPresent(Float.self, forKey: .vibrance) ?? 0
        gamma = try container.decodeIfPresent(Float.self, forKey: .gamma) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(brightness, forKey: .brightness)
        try container.encode(contrast, forKey: .contrast)
        try container.encode(saturation, forKey: .saturation)
        try container.encode(exposure, forKey: .exposure)
        try container.encode(warmth, forKey: .warmth)
        try container.encode(tint, forKey: .tint)
        try container.encode(highlights, forKey: .highlights)
        try container.encode(shadows, forKey: .shadows)
        try container.encode(vignette, forKey: .vignette)
        try container.encode(whites, forKey: .whites)
        try container.encode(blacks, forKey: .blacks)
        try container.encode(vibrance, forKey: .vibrance)
        try container.encode(gamma, forKey: .gamma)
    }

    /// Non-finite values become zero and every value is clamped to ±100.
    public func clamped() -> EditorAdjustments {
        var copy = self
        let fields: [WritableKeyPath<EditorAdjustments, Float>] = [
            \.brightness, \.contrast, \.saturation, \.exposure, \.warmth,
            \.tint, \.highlights, \.shadows, \.vignette,
            \.whites, \.blacks, \.vibrance, \.gamma,
        ]
        for field in fields {
            var value = copy[keyPath: field]
            if !value.isFinite {
                value = 0
            }
            copy[keyPath: field] = min(max(value, -100), 100)
        }
        return copy
    }

    /// Parse the JSON body the web editor sends. Missing fields default to zero.
    public static func parse(json: String) throws -> EditorAdjustments {
        guard let data = json.data(using: .utf8) else {
            throw MNGEditError.adjustments("invalid json")
        }
        do {
            let parsed = try JSONDecoder().decode(EditorAdjustments.self, from: data)
            return parsed.clamped()
        } catch {
            throw MNGEditError.adjustments("invalid json")
        }
    }
}

/// The one-tap presets of the editor.
///
/// The names and the recipes are the ones of the Aurum release, so the
/// photo looks the same in the app and in the browser.
public enum EditorFilter: String, Equatable, CaseIterable, Sendable {
    case original
    case vivid
    case dramatic
    case mono
    case vintage
    case warm
    case cool
    case fade
    case natural
    case korea
    case japan
    case skin

    public init(key: String) throws {
        switch key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "original": self = .original
        case "vivid": self = .vivid
        case "dramatic": self = .dramatic
        case "warm": self = .warm
        case "cool": self = .cool
        case "mono": self = .mono
        case "vintage": self = .vintage
        case "fade": self = .fade
        case "natural", "meitu-natural": self = .natural
        case "korea", "meitu-korea": self = .korea
        case "japan", "meitu-japan": self = .japan
        case "skin", "meitu-skin": self = .skin
        default: throw MNGEditError.unknownFilter(key)
        }
    }
}

/// The export containers.
public enum EditorExportFormat: String, Equatable, CaseIterable, Sendable {
    case jpeg
    case png
    case webp

    public init(key: String) throws {
        switch key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "jpeg", "jpg": self = .jpeg
        case "png": self = .png
        case "webp": self = .webp
        default: throw MNGEditError.unknownFormat(key)
        }
    }

    public var mime: String {
        switch self {
        case .jpeg: return "image/jpeg"
        case .png: return "image/png"
        case .webp: return "image/webp"
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .webp: return "webp"
        }
    }

    /// True when the platform can write this container.
    ///
    /// ImageIO only gained a WebP encoder on some systems, so the app falls
    /// back to JPEG when it is missing.
    public var isEncodable: Bool {
        #if canImport(CoreGraphics) && canImport(ImageIO)
        let types = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return types.contains(identifier)
        #else
        return true
        #endif
    }
}

/// One decoded image plus the editor state.
///
/// Geometry is applied in this order: rotate, flip, crop. The crop rectangle is
/// normalized to the oriented display, which keeps a selection stable between
/// the preview and the full-resolution export.
public struct Editor: Sendable {
    public private(set) var width: UInt32
    public private(set) var height: UInt32
    private var source: [UInt8]
    private var rotate: UInt8 = 0
    private var flipH = false
    private var flipV = false
    private var crop: EditorCrop = .full
    private var adjustments: EditorAdjustments = .zero
    private var filter: EditorFilter = .original
    private var rendered: (width: UInt32, height: UInt32)

    public init(width: UInt32, height: UInt32, rgba: [UInt8]) throws {
        guard width > 0,
              height > 0,
              width <= EditorLimits.maxImageSide,
              height <= EditorLimits.maxImageSide,
              UInt64(width) * UInt64(height) <= EditorLimits.maxImagePixels else {
            throw MNGEditError.invalidDimensions
        }
        let expected = Int(UInt64(width) * UInt64(height) * 4)
        guard rgba.count == expected else {
            throw MNGEditError.invalidBuffer
        }
        self.width = width
        self.height = height
        self.source = rgba
        self.rendered = (width, height)
    }

    // MARK: - State

    public var rotation: UInt8 { rotate }
    public var isFlippedHorizontally: Bool { flipH }
    public var isFlippedVertically: Bool { flipV }
    public var currentCrop: EditorCrop { crop }
    public var currentAdjustments: EditorAdjustments { adjustments }
    public var currentFilter: EditorFilter { filter }

    public mutating func setGeometry(rotate: UInt8, flipH: Bool, flipV: Bool) {
        self.rotate = rotate % 4
        self.flipH = flipH
        self.flipV = flipV
    }

    public mutating func setCrop(_ crop: EditorCrop) {
        self.crop = crop
    }

    public mutating func setAdjustments(_ adjustments: EditorAdjustments) {
        self.adjustments = adjustments.clamped()
    }

    public mutating func setFilter(_ filter: EditorFilter) {
        self.filter = filter
    }

    /// Size of the rotated and flipped image before cropping.
    public func orientedSize() -> (width: UInt32, height: UInt32) {
        rotate % 2 == 0 ? (width, height) : (height, width)
    }

    /// Pixel rectangle selected by the normalized crop.
    public func cropPixels() -> EditorCropPixels {
        let oriented = orientedSize()
        let x0 = UInt32(floor(crop.x * Float(oriented.width)))
        let y0 = UInt32(floor(crop.y * Float(oriented.height)))
        let x1 = UInt32(ceil((crop.x + crop.width) * Float(oriented.width)))
        let y1 = UInt32(ceil((crop.y + crop.height) * Float(oriented.height)))
        let clampedX0 = min(x0, oriented.width - 1)
        let clampedY0 = min(y0, oriented.height - 1)
        let clampedX1 = min(max(x1, clampedX0 + 1), oriented.width)
        let clampedY1 = min(max(y1, clampedY0 + 1), oriented.height)
        return EditorCropPixels(
            x: clampedX0,
            y: clampedY0,
            width: clampedX1 - clampedX0,
            height: clampedY1 - clampedY0
        )
    }

    /// Full-resolution output dimensions.
    public func outputSize() -> (width: UInt32, height: UInt32) {
        let crop = cropPixels()
        return (crop.width, crop.height)
    }

    public var lastRenderSize: (width: UInt32, height: UInt32) {
        rendered
    }

    // MARK: - Rendering

    /// Render an RGBA preview whose longest side is at most `maxSide`.
    public mutating func renderPreview(maxSide: UInt32 = 0) -> [UInt8] {
        let side: UInt32
        if maxSide == 0 {
            side = EditorLimits.defaultPreviewSide
        } else {
            side = min(max(maxSide, 64), EditorLimits.maxPreviewSide)
        }
        let crop = cropPixels()
        let fitted = Editor.fitWithin(crop.width, crop.height, side)
        let rgba = renderRGBA(crop, outWidth: fitted.width, outHeight: fitted.height)
        rendered = (fitted.width, fitted.height)
        return rgba
    }

    /// Render and encode the full crop.
    public mutating func renderExport(
        format: EditorExportFormat,
        quality: UInt8
    ) throws -> Data {
        let crop = cropPixels()
        let rgba = renderRGBA(crop, outWidth: crop.width, outHeight: crop.height)
        rendered = (crop.width, crop.height)
        return try Editor.encode(format: format, quality: quality, rgba: rgba,
                                width: crop.width, height: crop.height)
    }

    private func renderRGBA(
        _ crop: EditorCropPixels,
        outWidth: UInt32,
        outHeight: UInt32
    ) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: Int(outWidth) * Int(outHeight) * 4)
        let oriented = orientedSize()
        let effective = effectiveAdjustments()
        let identity = effective.identity && !effective.grayscale

        let xScale = Float(crop.width) / Float(outWidth)
        let yScale = Float(crop.height) / Float(outHeight)
        let centerX = Float(outWidth) * 0.5
        let centerY = Float(outHeight) * 0.5
        let maxRadius = max(
            sqrt(centerX * centerX + centerY * centerY),
            1
        )

        let bytesPerRow = Int(outWidth) * 4
        for row in 0..<Int(outHeight) {
            let displayY = Float(crop.y) + (Float(row) + 0.5) * yScale
            for column in 0..<Int(outWidth) {
                let displayX = Float(crop.x) + (Float(column) + 0.5) * xScale
                let sampled: [UInt8]
                if identity && xScale == 1 && yScale == 1 {
                    // Exact copy keeps the common no-op preview byte-for-byte.
                    sampled = sourcePixel(displayX, displayY)
                } else {
                    sampled = sampleBilinear(
                        displayX,
                        displayY,
                        orientedWidth: oriented.width,
                        orientedHeight: oriented.height
                    )
                }
                let adjusted = Editor.applyPixel(
                    sampled[0],
                    sampled[1],
                    sampled[2],
                    effective,
                    normalizedX: (Float(column) + 0.5 - centerX) / maxRadius,
                    normalizedY: (Float(row) + 0.5 - centerY) / maxRadius
                )
                let offset = row * bytesPerRow + column * 4
                out[offset] = adjusted.0
                out[offset + 1] = adjusted.1
                out[offset + 2] = adjusted.2
                out[offset + 3] = sampled[3]
            }
        }
        return out
    }

    private func sourcePixel(_ displayX: Float, _ displayY: Float) -> [UInt8] {
        let source = displayToSource(displayX, displayY)
        let x = Int(min(max(floor(source.0), 0), Float(width) - 1))
        let y = Int(min(max(floor(source.1), 0), Float(height) - 1))
        return pixel(x, y)
    }

    private func sampleBilinear(
        _ displayX: Float,
        _ displayY: Float,
        orientedWidth: UInt32,
        orientedHeight: UInt32
    ) -> [UInt8] {
        let source = displayToSource(displayX, displayY)
        let fx = source.0 - 0.5
        let fy = source.1 - 0.5
        let x0 = floor(fx)
        let y0 = floor(fy)
        let tx = fx - x0
        let ty = fy - y0

        let maxX = Int(width) - 1
        let maxY = Int(height) - 1
        let x0i = Int(min(max(x0, 0), Float(maxX)))
        let y0i = Int(min(max(y0, 0), Float(maxY)))
        let x1i = Int(min(max(x0 + 1, 0), Float(maxX)))
        let y1i = Int(min(max(y0 + 1, 0), Float(maxY)))

        let p00 = pixel(x0i, y0i)
        let p10 = pixel(x1i, y0i)
        let p01 = pixel(x0i, y1i)
        let p11 = pixel(x1i, y1i)

        var out = [UInt8](repeating: 0, count: 4)
        for channel in 0..<4 {
            let top = Float(p00[channel]) + (Float(p10[channel]) - Float(p00[channel])) * tx
            let bottom = Float(p01[channel]) + (Float(p11[channel]) - Float(p01[channel])) * tx
            let value = top + (bottom - top) * ty
            out[channel] = UInt8(min(max(value.rounded(), 0), 255))
        }
        return out
    }

    private func pixel(_ x: Int, _ y: Int) -> [UInt8] {
        let offset = (y * Int(width) + x) * 4
        return [
            source[offset],
            source[offset + 1],
            source[offset + 2],
            source[offset + 3],
        ]
    }

    /// Map a display-space continuous coordinate (pixel centers) back to the
    /// stored source. Flip is applied first, then the inverse rotation.
    private func displayToSource(_ displayX: Float, _ displayY: Float) -> (Float, Float) {
        let oriented = orientedSize()
        let dx = flipH ? Float(oriented.width) - displayX : displayX
        let dy = flipV ? Float(oriented.height) - displayY : displayY
        let imageWidth = Float(width)
        let imageHeight = Float(height)
        switch rotate {
        case 1: return (dy, imageHeight - dx)
        case 2: return (imageWidth - dx, imageHeight - dy)
        case 3: return (imageWidth - dy, dx)
        default: return (dx, dy)
        }
    }

    private func effectiveAdjustments() -> Effective {
        var values = adjustments
        var grayscale = false
        var matrix: [Float]?
        var offset: [Float]?
        switch filter {
        case .original:
            break
        case .vivid:
            values.saturation += 25
            values.contrast += 8
        case .dramatic:
            values.contrast += 27
            values.saturation -= 18
            matrix = [
                1.05, 0, 0,
                0, 1.02, 0,
                0, 0, 1.08,
            ]
            offset = [-0.012, -0.008, 0.012]
        case .warm:
            values.warmth += 35
            values.saturation += 8
        case .cool:
            values.warmth -= 35
        case .mono:
            grayscale = true
            values.contrast += 10
        case .vintage:
            matrix = [
                0.92, 0.32, 0.08,
                0.14, 0.86, 0.11,
                0.06, 0.19, 0.72,
            ]
            offset = [0.035, 0.02, 0]
            values.contrast -= 5
        case .fade:
            values.contrast -= 18
            values.brightness += 4
            values.saturation -= 18
            values.shadows += 12
        case .natural:
            values.brightness += 4
            values.saturation += 12
        case .korea:
            values.brightness += 6
            values.saturation += 15
            values.contrast -= 3
        case .japan:
            values.brightness += 3
            values.saturation += 6
            values.contrast -= 8
        case .skin:
            values.brightness += 14
            values.saturation += 5
        }
        let clamped = values.clamped()
        return Effective(
            adjustments: clamped,
            grayscale: grayscale,
            identity: clamped.isIdentity && matrix == nil,
            matrix: matrix,
            offset: offset
        )
    }

    struct Effective {
        var adjustments: EditorAdjustments
        var grayscale: Bool
        var identity: Bool
        /// The colour matrix of the preset, row major.
        var matrix: [Float]?
        /// The offset of the preset, one value per channel.
        var offset: [Float]?
    }

    // MARK: - Math

    static func fitWithin(_ width: UInt32, _ height: UInt32, _ maxSide: UInt32) -> (
        width: UInt32, height: UInt32
    ) {
        let longest = max(width, height)
        if longest <= maxSide {
            return (width, height)
        }
        let scale = Double(maxSide) / Double(longest)
        return (
            UInt32(max((Double(width) * scale).rounded(), 1)),
            UInt32(max((Double(height) * scale).rounded(), 1))
        )
    }

    static func applyPixel(
        _ r: UInt8,
        _ g: UInt8,
        _ b: UInt8,
        _ effective: Effective,
        normalizedX: Float,
        normalizedY: Float
    ) -> (UInt8, UInt8, UInt8) {
        let a = effective.adjustments
        var red = Float(r) / 255
        var green = Float(g) / 255
        var blue = Float(b) / 255

        // The colour matrix of the preset comes first, the adjustments of
        // the person are applied on top of it.
        if let matrix = effective.matrix {
            let sourceRed = red
            let sourceGreen = green
            let sourceBlue = blue
            red = matrix[0] * sourceRed + matrix[1] * sourceGreen + matrix[2] * sourceBlue
            green = matrix[3] * sourceRed + matrix[4] * sourceGreen + matrix[5] * sourceBlue
            blue = matrix[6] * sourceRed + matrix[7] * sourceGreen + matrix[8] * sourceBlue
            if let offset = effective.offset {
                red += offset[0]
                green += offset[1]
                blue += offset[2]
            }
        }

        if a.exposure != 0 {
            let factor = pow(Float(2), a.exposure / 50)
            red *= factor
            green *= factor
            blue *= factor
        }
        if a.brightness != 0 {
            let offset = a.brightness / 100 * 0.5
            red += offset
            green += offset
            blue += offset
        }
        if a.contrast != 0 {
            let factor = 1 + a.contrast / 100
            red = (red - 0.5) * factor + 0.5
            green = (green - 0.5) * factor + 0.5
            blue = (blue - 0.5) * factor + 0.5
        }
        if a.highlights != 0 || a.shadows != 0 {
            let luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            let clampedLuma = min(max(luma, 0), 1)
            let highlightMask = clampedLuma * clampedLuma
            let clampedShadow = min(max(1 - luma, 0), 1)
            let shadowMask = clampedShadow * clampedShadow
            let lift = min(
                max(a.highlights / 100 * 0.22 * highlightMask
                    + a.shadows / 100 * 0.25 * shadowMask, -0.3),
                0.3
            )
            red += lift
            green += lift
            blue += lift
        }
        if a.warmth != 0 {
            let shift = a.warmth / 100 * 0.12
            red += shift
            blue -= shift
        }
        if a.tint != 0 {
            let shift = a.tint / 100 * 0.10
            green += shift
            red -= shift * 0.5
            blue -= shift * 0.5
        }
        if a.saturation != 0 {
            let luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            let factor = 1 + a.saturation / 100
            red = luma + (red - luma) * factor
            green = luma + (green - luma) * factor
            blue = luma + (blue - luma) * factor
        }
        if a.vibrance != 0 {
            // The colours that are not saturated yet get more of the
            // saturation than the ones that already have it.
            let luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            let current = min(max(abs(red - luma) + abs(green - luma) + abs(blue - luma), 0), 1)
            let factor = 1 + a.vibrance / 100 * 0.6 * (1 - current)
            red = luma + (red - luma) * factor
            green = luma + (green - luma) * factor
            blue = luma + (blue - luma) * factor
        }
        if a.gamma != 0 {
            let exponent = 1 / (1 + a.gamma / 100)
            red = pow(max(red, 0), exponent)
            green = pow(max(green, 0), exponent)
            blue = pow(max(blue, 0), exponent)
        }
        if a.whites != 0 || a.blacks != 0 {
            let luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            let clampedLuma = min(max(luma, 0), 1)
            // The whites move the top of the tone scale, the blacks the
            // bottom of it.
            let whiteLift = a.whites / 100 * 0.20 * pow(clampedLuma, 3)
            let blackLift = a.blacks / 100 * 0.20 * pow(1 - clampedLuma, 3)
            let lift = min(max(whiteLift + blackLift, -0.3), 0.3)
            red += lift
            green += lift
            blue += lift
        }
        if effective.grayscale {
            let luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            red = luma
            green = luma
            blue = luma
        }
        if a.vignette > 0 {
            let distance = sqrt(normalizedX * normalizedX + normalizedY * normalizedY)
            let mask = smoothstep(0.25, 1, distance)
            let factor = 1 - (a.vignette / 100) * 0.65 * mask
            red *= factor
            green *= factor
            blue *= factor
        }

        return (
            UInt8(min(max((red.clamped01 * 255).rounded(), 0), 255)),
            UInt8(min(max((green.clamped01 * 255).rounded(), 0), 255)),
            UInt8(min(max((blue.clamped01 * 255).rounded(), 0), 255))
        )
    }

    static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        if edge1 <= edge0 {
            return 0
        }
        let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

private extension Float {
    var clamped01: Float {
        min(max(self, 0), 1)
    }
}
