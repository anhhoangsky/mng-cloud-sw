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

/// The horizontal alignment of a text layer.
public enum EditorTextAlign: String, Codable, Equatable, CaseIterable, Sendable {
    case left
    case center
    case right
}

/// The fonts offered by the text pane, the first five of the web catalog.
public enum EditorTextFont: String, Codable, Equatable, CaseIterable, Sendable {
    case sys
    case serif
    case mono
    case round
    case heavy

    public var title: String {
        switch self {
        case .sys: return "San"
        case .serif: return "Serif"
        case .mono: return "Mono"
        case .round: return "Rounded"
        case .heavy: return "Heavy"
        }
    }

    /// The PostScript name of the face used by the exporter. The system font
    /// is resolved with `CTFontCreateUIFontForLanguage`.
    var postScriptName: String? {
        switch self {
        case .sys: return nil
        case .serif: return "Georgia"
        case .mono: return "Menlo"
        case .round: return "ArialRoundedMTBold"
        case .heavy: return "Arial-Black"
        }
    }
}

/// One text layer over the photo, normalized to the exported image.
///
/// `x`/`y` are the centre of the layer, `size` is a fraction of the export
/// height, exactly like the `AurumTextLayer` of the web editor, so the preview
/// and the full-resolution export line up.
public struct EditorTextLayer: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var x: Float
    public var y: Float
    public var size: Float
    public var color: String
    public var bold: Bool
    public var italic: Bool
    public var outline: Bool
    public var shadow: Bool
    public var align: EditorTextAlign
    public var rotation: Float
    public var opacity: Float
    public var font: EditorTextFont

    public init(
        id: String,
        text: String = "",
        x: Float = 0.5,
        y: Float = 0.5,
        size: Float = 0.07,
        color: String = "#ffffff",
        bold: Bool = false,
        italic: Bool = false,
        outline: Bool = false,
        shadow: Bool = true,
        align: EditorTextAlign = .center,
        rotation: Float = 0,
        opacity: Float = 1,
        font: EditorTextFont = .sys
    ) {
        self.id = id
        self.text = text
        self.x = x
        self.y = y
        self.size = size
        self.color = color
        self.bold = bold
        self.italic = italic
        self.outline = outline
        self.shadow = shadow
        self.align = align
        self.rotation = rotation
        self.opacity = opacity
        self.font = font
    }

    /// Clamp the geometry so the exporter can trust the layer.
    public func normalized() -> EditorTextLayer {
        var copy = self
        if !copy.x.isFinite { copy.x = 0.5 }
        if !copy.y.isFinite { copy.y = 0.5 }
        if !copy.size.isFinite { copy.size = 0.07 }
        if !copy.rotation.isFinite { copy.rotation = 0 }
        if !copy.opacity.isFinite { copy.opacity = 1 }
        copy.x = min(max(copy.x, 0), 1)
        copy.y = min(max(copy.y, 0), 1)
        copy.size = min(max(copy.size, 0.015), 0.30)
        copy.rotation = min(max(copy.rotation, -180), 180)
        copy.opacity = min(max(copy.opacity, 0), 1)
        return copy
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
/// The names, the order, the categories and the recipes are the ones of the
/// Aurum release (`src/core/color.ts`), so the photo looks the same in the app
/// and in the browser. The legacy keys of the first native release
/// (`natural`, `korea`, `japan`, `skin`, `fade`) stay decodable.
public enum EditorFilter: String, Equatable, CaseIterable, Sendable {
    case original
    case vivid
    case dramatic
    case mono
    case vintage
    case warm
    case cool
    case meituNatural = "meitu-natural"
    case meituKorea = "meitu-korea"
    case meituJapan = "meitu-japan"
    case meituSkin = "meitu-skin"
    case meituPink = "meitu-pink"
    case meituWhite = "meitu-white"
    case xingtuFilm = "xingtu-film"
    case xingtuHK = "xingtu-hk"
    case xingtuShowa = "xingtu-showa"
    case xingtuKama = "xingtu-kama"
    case xingtuNight = "xingtu-night"
    case xingtuMorning = "xingtu-morning"
    case lrCinema = "lr-cinema"
    case lrMoody = "lr-moody"
    case lrVibrant = "lr-vibrant"
    case lrPastel = "lr-pastel"
    case lrDesert = "lr-desert"
    case lrStreet = "lr-street"
    case lrFaded = "lr-faded"
    case lrTeal = "lr-teal"
    case monoWarm = "mono-warm"
    case monoCool = "mono-cool"

    public init(key: String) throws {
        switch key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "original": self = .original
        case "vivid": self = .vivid
        case "dramatic": self = .dramatic
        case "warm": self = .warm
        case "cool": self = .cool
        case "mono": self = .mono
        case "vintage": self = .vintage
        case "fade", "lr-faded": self = .lrFaded
        case "natural", "meitu-natural": self = .meituNatural
        case "korea", "meitu-korea": self = .meituKorea
        case "japan", "meitu-japan": self = .meituJapan
        case "skin", "meitu-skin": self = .meituSkin
        case "meitu-pink": self = .meituPink
        case "meitu-white": self = .meituWhite
        case "xingtu-film": self = .xingtuFilm
        case "xingtu-hk": self = .xingtuHK
        case "xingtu-showa": self = .xingtuShowa
        case "xingtu-kama": self = .xingtuKama
        case "xingtu-night": self = .xingtuNight
        case "xingtu-morning": self = .xingtuMorning
        case "lr-cinema": self = .lrCinema
        case "lr-moody": self = .lrMoody
        case "lr-vibrant": self = .lrVibrant
        case "lr-pastel": self = .lrPastel
        case "lr-desert": self = .lrDesert
        case "lr-street": self = .lrStreet
        case "lr-teal": self = .lrTeal
        case "mono-warm": self = .monoWarm
        case "mono-cool": self = .monoCool
        default: throw MNGEditError.unknownFilter(key)
        }
    }

    /// The family of the filter, used by the category rail of the pane.
    public var category: EditorFilterCategory {
        switch self {
        case .original, .vivid, .dramatic, .vintage, .warm, .cool:
            return .root
        case .meituNatural, .meituKorea, .meituJapan, .meituSkin,
             .meituPink, .meituWhite:
            return .meitu
        case .xingtuFilm, .xingtuHK, .xingtuShowa, .xingtuKama,
             .xingtuNight, .xingtuMorning:
            return .xingtu
        case .lrCinema, .lrMoody, .lrVibrant, .lrPastel, .lrDesert,
             .lrStreet, .lrFaded, .lrTeal:
            return .lr
        case .mono, .monoWarm, .monoCool:
            return .mono
        }
    }
}

/// The tone families of the filter rail.
public enum EditorFilterCategory: String, Equatable, CaseIterable, Sendable {
    case root
    case meitu
    case xingtu
    case lr
    case mono

    public var title: String {
        switch self {
        case .root: return "Chuẩn"
        case .meitu: return "Meitu"
        case .xingtu: return "XingTu"
        case .lr: return "Lightroom"
        case .mono: return "Mono"
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
    /// The continuous angle of the photo, in degrees, −180…180, applied on
    /// top of the quarter turns around the centre of the oriented image.
    private var fineRotation: Float = 0
    /// Z-axis perspective correction, -100…100. Positive `perspectiveY`
    /// grows the top edge, positive `perspectiveX` grows the left edge, the
    /// same convention as the web editor's `perspectiveY`/`perspectiveX`.
    private var perspectiveX: Float = 0
    private var perspectiveY: Float = 0
    private var flipH = false
    private var flipV = false
    private var crop: EditorCrop = .full
    private var adjustments: EditorAdjustments = .zero
    private var filter: EditorFilter = .original
    private var texts: [EditorTextLayer] = []
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
    public var fineRotationDegrees: Float { fineRotation }
    public var perspectiveXDegrees: Float { perspectiveX }
    public var perspectiveYDegrees: Float { perspectiveY }
    public var isFlippedHorizontally: Bool { flipH }
    public var isFlippedVertically: Bool { flipV }
    public var currentCrop: EditorCrop { crop }
    public var currentAdjustments: EditorAdjustments { adjustments }
    public var currentFilter: EditorFilter { filter }
    public var textLayers: [EditorTextLayer] { texts }

    public mutating func setGeometry(rotate: UInt8, flipH: Bool, flipV: Bool) {
        self.rotate = rotate % 4
        self.flipH = flipH
        self.flipV = flipV
    }

    /// Set the fine angle, wrapping it into the −180…180 range the web
    /// rotation ruler uses.
    public mutating func setFineRotation(_ degrees: Float) {
        guard degrees.isFinite else {
            fineRotation = 0
            return
        }
        var next = degrees.truncatingRemainder(dividingBy: 360)
        if next > 180 { next -= 360 }
        if next < -180 { next += 360 }
        fineRotation = next
    }

    /// Set the Z-axis perspective correction. The values are the web editor's
    /// -100…100 sliders; `PERSPECTIVE_MAX` caps the actual projective term.
    public mutating func setPerspective(x: Float, y: Float) {
        perspectiveX = x.isFinite ? min(max(x, -100), 100) : 0
        perspectiveY = y.isFinite ? min(max(y, -100), 100) : 0
    }

    public mutating func setCrop(_ crop: EditorCrop) {
        self.crop = crop
    }

    public mutating func setTextLayers(_ layers: [EditorTextLayer]) {
        texts = layers.map { $0.normalized() }
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
        let composited = compositeTextLayers(
            rgba,
            width: crop.width,
            height: crop.height
        )
        return try Editor.encode(format: format, quality: quality, rgba: composited,
                                width: crop.width, height: crop.height)
    }

    private func renderRGBA(
        _ crop: EditorCropPixels,
        outWidth: UInt32,
        outHeight: UInt32
    ) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: Int(outWidth) * Int(outHeight) * 4)
        let geometry = sampleGeometry()
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
                if identity && xScale == 1 && yScale == 1
                    && !geometry.hasFine && !geometry.hasPerspective {
                    // Exact copy keeps the common no-op preview byte-for-byte.
                    sampled = sourcePixel(displayX, displayY, geometry: geometry)
                } else {
                    sampled = sampleBilinear(
                        displayX,
                        displayY,
                        geometry: geometry
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

    private func sourcePixel(
        _ displayX: Float,
        _ displayY: Float,
        geometry: SampleGeometry
    ) -> [UInt8] {
        let source = displayToSource(displayX, displayY, geometry: geometry)
        let x = Int(min(max(floor(source.0), 0), Float(width) - 1))
        let y = Int(min(max(floor(source.1), 0), Float(height) - 1))
        return pixel(x, y)
    }

    private func sampleBilinear(
        _ displayX: Float,
        _ displayY: Float,
        geometry: SampleGeometry
    ) -> [UInt8] {
        let source = displayToSource(displayX, displayY, geometry: geometry)
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

    /// The projective cap of the web editor's `PERSPECTIVE_MAX`.
    private static let perspectiveMax: Float = 0.32

    /// The constants of one sampling pass.
    ///
    /// Trigonometry and the perspective cover zoom are computed once per
    /// render; the per-pixel mapper only uses multiply/divide, which keeps a
    /// live slider drag usable even on a phone.
    private struct SampleGeometry {
        let orientedWidth: Float
        let orientedHeight: Float
        let halfWidth: Float
        let halfHeight: Float
        let rotate: UInt8
        let flipH: Bool
        let flipV: Bool
        let hasFine: Bool
        let cos: Float
        let sin: Float
        let fineZoom: Float
        let hasPerspective: Bool
        let warpX: Float
        let warpY: Float
        let perspectiveZoom: Float
    }

    private func sampleGeometry() -> SampleGeometry {
        let oriented = orientedSize()
        let halfWidth = Float(oriented.width) * 0.5
        let halfHeight = Float(oriented.height) * 0.5
        let hasFine = abs(fineRotation) > 0.0001
        let radians = fineRotation * .pi / 180
        let cosine = hasFine ? cos(radians) : 1
        let sine = hasFine ? sin(radians) : 0
        // Zoom just enough that the rotated rectangle still covers the whole
        // frame: the same cover rule as the web transform.
        let fineZoom = hasFine
            ? max(
                abs(cosine) + (halfHeight / halfWidth) * abs(sine),
                abs(cosine) + (halfWidth / halfHeight) * abs(sine)
            )
            : 1
        let warpX = perspectiveX / 100 * Editor.perspectiveMax
        let warpY = perspectiveY / 100 * Editor.perspectiveMax
        let hasPerspective = abs(warpX) > 0.00001 || abs(warpY) > 0.00001
        let perspectiveZoom = hasPerspective
            ? Editor.perspectiveCover(
                warpX: warpX,
                warpY: warpY,
                halfWidth: halfWidth,
                halfHeight: halfHeight,
                cosine: cosine,
                sine: sine,
                fineZoom: fineZoom,
                hasFine: hasFine
            )
            : 1
        return SampleGeometry(
            orientedWidth: Float(oriented.width),
            orientedHeight: Float(oriented.height),
            halfWidth: halfWidth,
            halfHeight: halfHeight,
            rotate: rotate,
            flipH: flipH,
            flipV: flipV,
            hasFine: hasFine,
            cos: cosine,
            sin: sine,
            fineZoom: fineZoom,
            hasPerspective: hasPerspective,
            warpX: warpX,
            warpY: warpY,
            perspectiveZoom: perspectiveZoom
        )
    }

    /// Smallest extra zoom that keeps every corner of the display frame
    /// inside the image after the fine rotation and the projective warp.
    private static func perspectiveCover(
        warpX: Float,
        warpY: Float,
        halfWidth: Float,
        halfHeight: Float,
        cosine: Float,
        sine: Float,
        fineZoom: Float,
        hasFine: Bool
    ) -> Float {
        if perspectiveCovers(
            zoom: 1,
            warpX: warpX,
            warpY: warpY,
            halfWidth: halfWidth,
            halfHeight: halfHeight,
            cosine: cosine,
            sine: sine,
            fineZoom: fineZoom,
            hasFine: hasFine
        ) {
            return 1
        }
        var low: Float = 1
        var high: Float = 8
        if !perspectiveCovers(
            zoom: high,
            warpX: warpX,
            warpY: warpY,
            halfWidth: halfWidth,
            halfHeight: halfHeight,
            cosine: cosine,
            sine: sine,
            fineZoom: fineZoom,
            hasFine: hasFine
        ) {
            return high
        }
        for _ in 0..<28 {
            let middle = (low + high) * 0.5
            if perspectiveCovers(
                zoom: middle,
                warpX: warpX,
                warpY: warpY,
                halfWidth: halfWidth,
                halfHeight: halfHeight,
                cosine: cosine,
                sine: sine,
                fineZoom: fineZoom,
                hasFine: hasFine
            ) {
                high = middle
            } else {
                low = middle
            }
        }
        return high
    }

    private static func perspectiveCovers(
        zoom: Float,
        warpX: Float,
        warpY: Float,
        halfWidth: Float,
        halfHeight: Float,
        cosine: Float,
        sine: Float,
        fineZoom: Float,
        hasFine: Bool
    ) -> Bool {
        let xs: [Float] = [-halfWidth, halfWidth]
        let ys: [Float] = [-halfHeight, halfHeight]
        for dx in xs {
            for dy in ys {
                var x = dx
                var y = dy
                if hasFine {
                    let rx = (cosine * dx + sine * dy) / fineZoom
                    let ry = (-sine * dx + cosine * dy) / fineZoom
                    x = rx
                    y = ry
                }
                let nx = x / (halfWidth * zoom)
                let ny = y / (halfHeight * zoom)
                let w = 1 - warpY * ny - warpX * nx
                if abs(w) < 0.0001 {
                    return false
                }
                if abs(nx / w) > 1.0005 || abs(ny / w) > 1.0005 {
                    return false
                }
            }
        }
        return true
    }

    /// Map a display-space continuous coordinate (pixel centers) back to the
    /// stored source.
    ///
    /// The fine angle is undone around the centre of the oriented image
    /// first, with the cover scale that keeps the turned photo filling the
    /// frame. The projective warp is undone next, then flip (it is a
    /// display-space transform) and the inverse quarter turn.
    private func displayToSource(
        _ displayX: Float,
        _ displayY: Float,
        geometry: SampleGeometry
    ) -> (Float, Float) {
        var x = displayX - geometry.halfWidth
        var y = displayY - geometry.halfHeight

        if geometry.hasFine {
            let rx = (geometry.cos * x + geometry.sin * y) / geometry.fineZoom
            let ry = (-geometry.sin * x + geometry.cos * y) / geometry.fineZoom
            x = rx
            y = ry
        }

        if geometry.hasPerspective {
            let nx = x / (geometry.halfWidth * geometry.perspectiveZoom)
            let ny = y / (geometry.halfHeight * geometry.perspectiveZoom)
            let w = 1 - geometry.warpY * ny - geometry.warpX * nx
            let inverse = abs(w) < 0.0001 ? 0 : 1 / w
            x = nx * inverse * geometry.halfWidth
            y = ny * inverse * geometry.halfHeight
        }

        x += geometry.halfWidth
        y += geometry.halfHeight

        let dx = geometry.flipH ? geometry.orientedWidth - x : x
        let dy = geometry.flipV ? geometry.orientedHeight - y : y
        let imageWidth = Float(width)
        let imageHeight = Float(height)
        switch geometry.rotate {
        case 1: return (dy, imageHeight - dx)
        case 2: return (imageWidth - dx, imageHeight - dy)
        case 3: return (imageWidth - dy, dx)
        default: return (dx, dy)
        }
    }

    private func effectiveAdjustments() -> Effective {
        let values = adjustments.clamped()
        let transform = Editor.presetTransform(filter)
        return Effective(
            adjustments: values,
            grayscale: false,
            identity: values.isIdentity && transform == nil,
            matrix: transform?.matrix,
            offset: transform?.offset
        )
    }

    /// A 3×3 colour matrix with a per-channel offset, row major.
    struct PresetTransform {
        var matrix: [Float]
        var offset: [Float]
    }

    static func identityTransform() -> PresetTransform {
        PresetTransform(
            matrix: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            offset: [0, 0, 0]
        )
    }

    /// The diagonal gains of the web `gains()` helper.
    static func gains(_ r: Float, _ g: Float, _ b: Float) -> PresetTransform {
        PresetTransform(
            matrix: [r, 0, 0, 0, g, 0, 0, 0, b],
            offset: [0, 0, 0]
        )
    }

    static func saturationTransform(_ value: Float) -> PresetTransform {
        let s = max(0, 1 + value)
        let lr: Float = 0.2126
        let lg: Float = 0.7152
        let lb: Float = 0.0722
        let inv = 1 - s
        return PresetTransform(
            matrix: [
                lr * inv + s, lg * inv, lb * inv,
                lr * inv, lg * inv + s, lb * inv,
                lr * inv, lg * inv, lb * inv + s,
            ],
            offset: [0, 0, 0]
        )
    }

    static func contrastTransform(_ value: Float) -> PresetTransform {
        let c = max(0.05, 1 + value)
        let shift = 0.5 * (1 - c)
        return PresetTransform(
            matrix: [c, 0, 0, 0, c, 0, 0, 0, c],
            offset: [shift, shift, shift]
        )
    }

    static func brightnessTransform(_ value: Float) -> PresetTransform {
        let add = value * 0.22
        return PresetTransform(
            matrix: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            offset: [add, add, add]
        )
    }

    /// Apply `before` first, then `after`, like the web `compose()`.
    static func compose(
        _ after: PresetTransform,
        _ before: PresetTransform
    ) -> PresetTransform {
        var matrix = [Float](repeating: 0, count: 9)
        for row in 0..<3 {
            let r = row * 3
            for column in 0..<3 {
                matrix[r + column] =
                    after.matrix[r] * before.matrix[column]
                    + after.matrix[r + 1] * before.matrix[3 + column]
                    + after.matrix[r + 2] * before.matrix[6 + column]
            }
        }
        var offset = [Float](repeating: 0, count: 3)
        for row in 0..<3 {
            offset[row] =
                after.matrix[row * 3] * before.offset[0]
                + after.matrix[row * 3 + 1] * before.offset[1]
                + after.matrix[row * 3 + 2] * before.offset[2]
                + after.offset[row]
        }
        return PresetTransform(matrix: matrix, offset: offset)
    }

    /// The colour transform of one preset, the same recipe as
    /// `PRESETS` in the Aurum release's `src/core/color.ts`.
    static func presetTransform(_ filter: EditorFilter) -> PresetTransform? {
        switch filter {
        case .original:
            return nil
        case .vivid:
            return compose(contrastTransform(0.08), saturationTransform(0.38))
        case .dramatic:
            let grade = compose(
                contrastTransform(0.27),
                saturationTransform(-0.18)
            )
            let split = PresetTransform(
                matrix: [1.05, 0, 0, 0, 1.02, 0, 0, 0, 1.08],
                offset: [-0.012, -0.008, 0.012]
            )
            return compose(split, grade)
        case .mono:
            return compose(contrastTransform(0.1), saturationTransform(-1))
        case .vintage:
            return PresetTransform(
                matrix: [
                    0.92, 0.32, 0.08,
                    0.14, 0.86, 0.11,
                    0.06, 0.19, 0.72,
                ],
                offset: [0.035, 0.02, 0]
            )
        case .warm:
            return gains(1.12, 1.02, 0.88)
        case .cool:
            return gains(0.9, 1, 1.16)
        case .meituNatural:
            return compose(gains(1.04, 1.02, 0.98), saturationTransform(0.12))
        case .meituKorea:
            return compose(gains(1.06, 1.0, 0.98), saturationTransform(0.15))
        case .meituJapan:
            return compose(gains(1.03, 1.01, 1.02), contrastTransform(-0.08))
        case .meituSkin:
            return compose(gains(1.05, 1.03, 0.99), brightnessTransform(0.14))
        case .meituPink:
            return compose(gains(1.07, 0.99, 0.97), saturationTransform(0.2))
        case .meituWhite:
            return compose(gains(1.08, 1.08, 1.08), saturationTransform(-0.05))
        case .xingtuFilm:
            return compose(
                gains(0.97, 1.02, 1.07),
                compose(contrastTransform(0.12), saturationTransform(0.05))
            )
        case .xingtuHK:
            return compose(
                gains(1.02, 1.0, 1.04),
                compose(contrastTransform(0.1), saturationTransform(-0.08))
            )
        case .xingtuShowa:
            return compose(
                gains(1.04, 1.0, 0.93),
                compose(contrastTransform(-0.05), saturationTransform(-0.15))
            )
        case .xingtuKama:
            return compose(gains(1.06, 1.02, 0.9), saturationTransform(0.1))
        case .xingtuNight:
            return compose(
                gains(0.94, 0.98, 1.08),
                compose(contrastTransform(0.08), saturationTransform(-0.05))
            )
        case .xingtuMorning:
            return compose(gains(1.07, 1.04, 0.93), saturationTransform(0.08))
        case .lrCinema:
            return compose(
                gains(0.98, 1.02, 1.06),
                compose(contrastTransform(0.15), saturationTransform(0.05))
            )
        case .lrMoody:
            return compose(
                gains(0.97, 0.98, 1.02),
                compose(contrastTransform(0.18), saturationTransform(-0.15))
            )
        case .lrVibrant:
            return compose(contrastTransform(0.05), saturationTransform(0.35))
        case .lrPastel:
            return compose(
                gains(1.03, 1.03, 1.03),
                compose(contrastTransform(-0.1), saturationTransform(0.1))
            )
        case .lrDesert:
            return compose(gains(1.08, 1.0, 0.88), saturationTransform(0.15))
        case .lrStreet:
            return compose(contrastTransform(0.2), saturationTransform(-0.1))
        case .lrFaded:
            return compose(
                gains(1.02, 1.02, 1.02),
                compose(contrastTransform(-0.12), saturationTransform(-0.15))
            )
        case .lrTeal:
            return compose(gains(0.93, 1.04, 1.07), saturationTransform(0.1))
        case .monoWarm:
            return compose(gains(1.06, 1.02, 0.94), saturationTransform(-1))
        case .monoCool:
            return compose(gains(0.94, 0.98, 1.06), saturationTransform(-1))
        }
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
