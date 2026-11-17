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

/// A detached copy of the pixels the editor loaded.
///
/// The AI features bake a new base bitmap (a cut-out, a replaced background
/// or a retouched source) and then hand it back to the editor. Keeping the
/// buffer in a small value type lets that pass run off the main actor without
/// exposing the mutable storage of `Editor`.
public struct EditorSourceSnapshot: Equatable, Sendable {
    public var width: UInt32
    public var height: UInt32
    /// Straight (non-premultiplied) sRGB RGBA, row-major, top row first.
    public var rgba: [UInt8]

    public init(width: UInt32, height: UInt32, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
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

    /// Keep the geometry usable without losing a turn.
    ///
    /// The rotation wraps like the web's `((startRot + dDeg + 540) % 360) -
    /// 180` instead of clamping: a handle drag that crosses the ±180° branch
    /// cut would otherwise stop at the limit and jump, while the wrapped
    /// value keeps turning in the same direction.
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
        if copy.rotation > 180 || copy.rotation < -180 {
            var wrapped = copy.rotation.truncatingRemainder(dividingBy: 360)
            if wrapped > 180 { wrapped -= 360 }
            if wrapped < -180 { wrapped += 360 }
            copy.rotation = wrapped
        }
        copy.opacity = min(max(copy.opacity, 0), 1)
        return copy
    }
}

/// The sliders of the editor. Ranges follow the web `ADJUST_RANGES`: mostly
/// ±100, with 0…100 for the amount-only sliders.
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
    /// Halo-limited local contrast, −100…100.
    public var clarity: Float
    /// Small-radius output sharpening, 0…100.
    public var sharpen: Float
    /// Edge-aware luminance denoise, 0…100.
    public var denoise: Float
    /// Portrait skin smoothing, 0…100. Edge-aware and mask-guided.
    public var smoothSkin: Float
    /// Blemish/spot removal strength, 0…100.
    public var blemish: Float
    /// Skin texture preservation, 0…100. Higher keeps more pore/detail.
    public var skinTexture: Float
    /// Skin hue/tone correction, −100 = cooler, +100 = warmer.
    public var skinTone: Float
    /// Portrait reshape, the six keys of the web editor's `adjust` object.
    public var faceSlim: Float
    public var jawline: Float
    public var chin: Float
    public var eyeSize: Float
    public var noseSize: Float
    public var mouthSize: Float

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
        gamma: Float = 0,
        clarity: Float = 0,
        sharpen: Float = 0,
        denoise: Float = 0,
        smoothSkin: Float = 0,
        blemish: Float = 0,
        skinTexture: Float = 0,
        skinTone: Float = 0,
        faceSlim: Float = 0,
        jawline: Float = 0,
        chin: Float = 0,
        eyeSize: Float = 0,
        noseSize: Float = 0,
        mouthSize: Float = 0
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
        self.clarity = clarity
        self.sharpen = sharpen
        self.denoise = denoise
        self.smoothSkin = smoothSkin
        self.blemish = blemish
        self.skinTexture = skinTexture
        self.skinTone = skinTone
        self.faceSlim = faceSlim
        self.jawline = jawline
        self.chin = chin
        self.eyeSize = eyeSize
        self.noseSize = noseSize
        self.mouthSize = mouthSize
    }

    public static let zero = EditorAdjustments()

    public var isIdentity: Bool {
        self == EditorAdjustments.zero
    }

    /// True when the colour pass can be skipped. The reshape, detail and beauty
    /// sliders do not touch colour, so they must not force a per-pixel colour
    /// round-trip. Their passes need the source UV and run separately before
    /// this colour stack.
    var isColorIdentity: Bool {
        brightness == 0 && contrast == 0 && saturation == 0 && exposure == 0
            && warmth == 0 && tint == 0 && highlights == 0 && shadows == 0
            && vignette == 0 && whites == 0 && blacks == 0 && vibrance == 0
            && gamma == 0
    }

    /// True when the portrait pass can be skipped. Matches the shader's early
    /// out: `skinTexture` only modulates a smoothing that is already active.
    var isBeautyIdentity: Bool {
        let total = abs(smoothSkin) + abs(blemish) + abs(skinTone)
        return !total.isFinite || total < 0.1
    }

    /// True when the three detail passes can be skipped.
    var isDetailIdentity: Bool {
        let total = abs(clarity) + sharpen + denoise
        return !total.isFinite || total < 0.1
    }

    /// The three detail sliders in the normalised form `DetailKernel` consumes.
    var detail: DetailParameters {
        DetailParameters(
            clarity: clarity / 100,
            sharpen: sharpen / 100,
            denoise: denoise / 100
        )
    }

    /// The four portrait sliders in the normalised form `BeautyKernel`
    /// consumes. The web shader receives the same values divided by 100.
    var beauty: BeautyParameters {
        BeautyParameters(
            smoothSkin: smoothSkin / 100,
            blemish: blemish / 100,
            skinTexture: skinTexture / 100,
            skinTone: skinTone / 100
        )
    }

    /// The six reshape sliders in the form `FaceWarp` consumes.
    public var faceWarp: FaceWarpParameters {
        FaceWarpParameters(
            faceSlim: faceSlim,
            jawline: jawline,
            chin: chin,
            eyeSize: eyeSize,
            noseSize: noseSize,
            mouthSize: mouthSize
        )
    }

    private enum CodingKeys: String, CodingKey {
        case brightness, contrast, saturation, exposure, warmth
        case tint, highlights, shadows, vignette
        case whites, blacks, vibrance, gamma
        case clarity, sharpen, denoise
        case smoothSkin, blemish, skinTexture, skinTone
        case faceSlim, jawline, chin, eyeSize, noseSize, mouthSize
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
        clarity = try container.decodeIfPresent(Float.self, forKey: .clarity) ?? 0
        sharpen = try container.decodeIfPresent(Float.self, forKey: .sharpen) ?? 0
        denoise = try container.decodeIfPresent(Float.self, forKey: .denoise) ?? 0
        smoothSkin = try container.decodeIfPresent(Float.self, forKey: .smoothSkin) ?? 0
        blemish = try container.decodeIfPresent(Float.self, forKey: .blemish) ?? 0
        skinTexture = try container.decodeIfPresent(Float.self, forKey: .skinTexture) ?? 0
        skinTone = try container.decodeIfPresent(Float.self, forKey: .skinTone) ?? 0
        faceSlim = try container.decodeIfPresent(Float.self, forKey: .faceSlim) ?? 0
        jawline = try container.decodeIfPresent(Float.self, forKey: .jawline) ?? 0
        chin = try container.decodeIfPresent(Float.self, forKey: .chin) ?? 0
        eyeSize = try container.decodeIfPresent(Float.self, forKey: .eyeSize) ?? 0
        noseSize = try container.decodeIfPresent(Float.self, forKey: .noseSize) ?? 0
        mouthSize = try container.decodeIfPresent(Float.self, forKey: .mouthSize) ?? 0
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
        try container.encode(clarity, forKey: .clarity)
        try container.encode(sharpen, forKey: .sharpen)
        try container.encode(denoise, forKey: .denoise)
        try container.encode(smoothSkin, forKey: .smoothSkin)
        try container.encode(blemish, forKey: .blemish)
        try container.encode(skinTexture, forKey: .skinTexture)
        try container.encode(skinTone, forKey: .skinTone)
        try container.encode(faceSlim, forKey: .faceSlim)
        try container.encode(jawline, forKey: .jawline)
        try container.encode(chin, forKey: .chin)
        try container.encode(eyeSize, forKey: .eyeSize)
        try container.encode(noseSize, forKey: .noseSize)
        try container.encode(mouthSize, forKey: .mouthSize)
    }

    /// Non-finite values become zero and every value is clamped to the range of
    /// the web editor's `ADJUST_RANGES`: ±100 for the colour and clarity
    /// sliders, 0…100 for the amount-only sliders and −100…100 for the tone.
    public func clamped() -> EditorAdjustments {
        var copy = self
        let fields: [WritableKeyPath<EditorAdjustments, Float>] = [
            \.brightness, \.contrast, \.saturation, \.exposure, \.warmth,
            \.tint, \.highlights, \.shadows, \.vignette,
            \.whites, \.blacks, \.vibrance, \.gamma,
            \.clarity, \.sharpen, \.denoise,
            \.smoothSkin, \.blemish, \.skinTexture, \.skinTone,
            \.faceSlim, \.jawline, \.chin, \.eyeSize, \.noseSize, \.mouthSize,
        ]
        for field in fields {
            var value = copy[keyPath: field]
            if !value.isFinite {
                value = 0
            }
            copy[keyPath: field] = min(max(value, -100), 100)
        }
        copy.sharpen = min(max(copy.sharpen, 0), 100)
        copy.denoise = min(max(copy.denoise, 0), 100)
        copy.smoothSkin = min(max(copy.smoothSkin, 0), 100)
        copy.blemish = min(max(copy.blemish, 0), 100)
        copy.skinTexture = min(max(copy.skinTexture, 0), 100)
        copy.skinTone = min(max(copy.skinTone, -100), 100)
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
public enum EditorFilterCategory: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
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
    /// Vision face anchors in oriented source space. They are derived from the
    /// photo, not edited, so they are not part of the history.
    private var faceAnchors: [EditorFaceAnchor] = []
    /// Optional R/G/B skin mask built from the source and the face boxes.
    /// When absent the kernel falls back to the procedural `skinWeight`.
    private var beautyMask: EditorBeautyMask?
    /// Free-liquify dabs in stored source UV, newest last. The field below is
    /// a cache: rebuilding it is cheap, but not cheap enough for every pixel.
    private var liquifyDabs: [EditorLiquifyDab] = []
    private var liquifyField: EditorLiquifyField?
    /// Region-effect stamps in stored source UV. Size and strength are live
    /// globals, not per-dab values, exactly like the web effect brush.
    private var effectDabs: [EditorEffectDab] = []
    private var effectSize: Float = EditorEffectLimits.defaultSize
    private var effectStrength: Float = EditorEffectLimits.defaultStrength
    /// The shared R/G mask, rasterised once per dab and reused by every frame.
    private var effectMask: EditorEffectMask?
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
    public var currentFaceAnchors: [EditorFaceAnchor] { faceAnchors }
    public var currentBeautyMask: EditorBeautyMask? { beautyMask }
    public var currentLiquifyDabs: [EditorLiquifyDab] { liquifyDabs }
    public var hasLiquify: Bool { !liquifyDabs.isEmpty }
    public var currentEffectDabs: [EditorEffectDab] { effectDabs }
    public var hasEffects: Bool { !effectDabs.isEmpty }
    /// Brush radius as a fraction of the source width.
    public var currentEffectSize: Float { effectSize }
    /// Region-effect blend strength, 0…100.
    public var currentEffectStrength: Float { effectStrength }

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

    /// Attach the Vision face anchors used by the six reshape sliders.
    ///
    /// The boxes are normalised to the oriented source photo, the same space
    /// as the web editor's `u_faces`/`u_anchors` textures. The list is sorted,
    /// clamped and capped at four, so passing raw detector output is safe.
    public mutating func setFaceAnchors(_ anchors: [EditorFaceAnchor]) {
        faceAnchors = FaceWarp.normalize(anchors)
    }

    /// Attach an R/G/B skin mask built by `EditorBeautyMaskBuilder`.
    ///
    /// The mask is optional: without one the kernel uses the procedural
    /// `skinWeight` fallback of the web shader. Passing `nil` restores it.
    /// Building a mask is a source-sized pass, so callers build it once after
    /// face detection (or after replacing the source) instead of per frame.
    public mutating func setBeautyMask(_ mask: EditorBeautyMask?) {
        beautyMask = mask
    }

    /// Build the mask the portrait sliders expect from the current source and
    /// face anchors. Returns `nil` only when the source bitmap is invalid.
    ///
    /// This is deliberately opt-in: `setFaceAnchors` runs on the main thread
    /// after Vision, and a 640 px mask pass belongs on a background queue.
    @discardableResult
    public mutating func buildBeautyMask(
        maxSize: Int = 640,
        feather: Int = 2
    ) -> EditorBeautyMask? {
        let mask = EditorBeautyMaskBuilder.build(
            sourceWidth: Int(width),
            sourceHeight: Int(height),
            rgba: source,
            faces: faceAnchors.map(\.box),
            maxSize: maxSize,
            feather: feather
        )
        beautyMask = mask
        return mask
    }

    /// Replace the free-liquify history.
    ///
    /// Every dab is clamped to the web state limits, malformed entries are
    /// dropped, and only the newest `EditorLiquifyLimits.maxDabs` survive. The
    /// RG field is rebuilt here, not per rendered frame.
    public mutating func setLiquifyDabs(_ dabs: [EditorLiquifyDab]) {
        let normalized = dabs.compactMap { $0.normalized }
        liquifyDabs = Array(
            normalized.suffix(EditorLiquifyLimits.maxDabs)
        )
        rebuildLiquifyField()
    }

    /// Append one dab, the `addLiquifyDab` of the web editor.
    public mutating func addLiquifyDab(_ dab: EditorLiquifyDab) {
        guard let normalized = dab.normalized else { return }
        liquifyDabs.append(normalized)
        if liquifyDabs.count > EditorLiquifyLimits.maxDabs {
            liquifyDabs.removeFirst(
                liquifyDabs.count - EditorLiquifyLimits.maxDabs
            )
        }
        rebuildLiquifyField()
    }

    /// Remove every dab. Face reshape sliders and beauty are untouched.
    public mutating func clearLiquify() {
        guard !liquifyDabs.isEmpty else { return }
        liquifyDabs = []
        liquifyField = nil
    }

    private mutating func rebuildLiquifyField() {
        liquifyField = EditorLiquifyFieldBuilder.build(
            dabs: liquifyDabs,
            sourceWidth: Int(width),
            sourceHeight: Int(height)
        )
    }

    /// Replace the region-effect history.
    ///
    /// Every dab is clamped to the web state limits, malformed entries are
    /// dropped and only the newest `EditorEffectLimits.maxDabs` survive. The
    /// mask is rebuilt here, not per rendered frame.
    public mutating func setEffectDabs(_ dabs: [EditorEffectDab]) {
        let normalized = dabs.compactMap(\.normalized)
        effectDabs = Array(
            normalized.suffix(EditorEffectLimits.maxDabs)
        )
        rebuildEffectMask()
    }

    /// Append one stamp, the `addEffectDab` of the web editor.
    ///
    /// The mask is stamped incrementally so a live stroke does not rasterise
    /// the whole history for every finger move. Only the rare cap trim falls
    /// back to a full rebuild.
    public mutating func addEffectDab(_ dab: EditorEffectDab) {
        guard let normalized = dab.normalized else { return }
        effectDabs.append(normalized)
        let overflow = effectDabs.count - EditorEffectLimits.maxDabs
        if overflow > 0 {
            effectDabs.removeFirst(overflow)
            rebuildEffectMask()
            return
        }
        stampEffectDab(normalized)
    }

    /// Remove every stamp. The brush size and strength are untouched.
    public mutating func clearEffects() {
        guard !effectDabs.isEmpty || effectMask != nil else { return }
        effectDabs = []
        effectMask = nil
    }

    /// Set the brush radius as a fraction of the source width, 0.01…0.2.
    public mutating func setEffectSize(_ size: Float) {
        guard size.isFinite else { return }
        effectSize = min(
            max(size, EditorEffectLimits.minSize),
            EditorEffectLimits.maxSize
        )
    }

    /// Set the blend strength, 0…100.
    public mutating func setEffectStrength(_ strength: Float) {
        guard strength.isFinite else { return }
        effectStrength = min(max(strength, 0), 100)
    }

    /// Set both live globals at once, the shape of a saved web state.
    public mutating func setEffectState(_ state: EditorEffectState) {
        let normalized = state.normalized
        effectSize = normalized.size
        effectStrength = normalized.strength
    }

    private mutating func rebuildEffectMask() {
        effectMask = EditorEffectMaskBuilder.build(
            dabs: effectDabs,
            sourceWidth: Int(width),
            sourceHeight: Int(height)
        )
    }

    private mutating func stampEffectDab(_ dab: EditorEffectDab) {
        if var mask = effectMask {
            if EditorEffectMaskBuilder.stamp(dab, into: &mask) {
                effectMask = mask
            }
            return
        }
        guard var mask = EditorEffectMaskBuilder.makeMask(
            sourceWidth: Int(width),
            sourceHeight: Int(height)
        ) else {
            return
        }
        if EditorEffectMaskBuilder.stamp(dab, into: &mask) {
            effectMask = mask
        }
    }

    public mutating func setAdjustments(_ adjustments: EditorAdjustments) {
        self.adjustments = adjustments.clamped()
    }

    public mutating func setFilter(_ filter: EditorFilter) {
        self.filter = filter
    }

    /// A copy of the pixels currently loaded, for an AI pass.
    public func sourceSnapshot() -> EditorSourceSnapshot {
        EditorSourceSnapshot(
            width: width,
            height: height,
            rgba: source
        )
    }

    /// The source pixels as a `CGImage`, for Vision face detection.
    public func sourceCGImage() -> CGImage? {
        EditorBitmap.cgImage(
            width: Int(width),
            height: Int(height),
            rgba: source
        )
    }

    /// Swap the base bitmap while keeping every edit on top of it.
    ///
    /// The AI actions work in source space at the original resolution, so the
    /// crop, the geometry, the colour stack and the text layers remain valid.
    /// The returned editor starts with a fresh preview cache, exactly like the
    /// web editor's `load()` followed by `setState({...keep})`.
    public func replacingSource(
        _ snapshot: EditorSourceSnapshot
    ) throws -> Editor {
        var copy = try Editor(
            width: snapshot.width,
            height: snapshot.height,
            rgba: snapshot.rgba
        )
        copy.setGeometry(rotate: rotate, flipH: flipH, flipV: flipV)
        copy.setFineRotation(fineRotation)
        copy.setPerspective(x: perspectiveX, y: perspectiveY)
        copy.setCrop(crop)
        copy.setAdjustments(adjustments)
        copy.setFilter(filter)
        copy.setTextLayers(texts)
        copy.setFaceAnchors(faceAnchors)
        copy.setBeautyMask(beautyMask)
        copy.setLiquifyDabs(liquifyDabs)
        copy.setEffectSize(effectSize)
        copy.setEffectStrength(effectStrength)
        copy.setEffectDabs(effectDabs)
        return copy
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

    /// Map a normalized point on the rendered output (0…1 across the current
    /// crop) to stored-source UV.
    ///
    /// This is the web's `sourcePointAt`: it undoes the display geometry
    /// (quarter turn, flip, crop, fine rotation, perspective) only. The face
    /// warp and the liquify field are deliberately not undone, because a new
    /// dab is anchored at the source point the person touched; feeding the
    /// current displacement back would make a stroke chase itself.
    public func sourceUV(forOutputPoint point: SIMD2<Float>) -> SIMD2<Float> {
        let crop = cropPixels()
        let u = min(max(point.x, 0), 1)
        let v = min(max(point.y, 0), 1)
        let displayX = Float(crop.x) + u * Float(crop.width)
        let displayY = Float(crop.y) + v * Float(crop.height)
        let base = displayToSource(
            displayX,
            displayY,
            geometry: sampleGeometry()
        )
        return SIMD2<Float>(
            min(max(base.0 / Float(max(1, width)), 0), 1),
            min(max(base.1 / Float(max(1, height)), 0), 1)
        )
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
        let pixelWidth = Int(outWidth)
        let pixelHeight = Int(outHeight)
        var out = [UInt8](
            repeating: 0,
            count: pixelWidth * pixelHeight * 4
        )
        guard pixelWidth > 0, pixelHeight > 0 else { return out }
        let geometry = sampleGeometry()
        let effective = effectiveAdjustments()
        let colorIdentity = effective.identity && !effective.grayscale
        // The portrait warp is an inverse UV map applied before sampling. Its
        // sampler freezes the six sliders and the resolved anchors once, so
        // the pixel loop below only does arithmetic.
        let warp = FaceWarp(
            parameters: adjustments.clamped().faceWarp,
            anchors: faceAnchors
        ).makeSampler()
        // The beauty pass needs the source UV of each pixel, so it runs after
        // the warp and before the colour stack. Its tap offsets are UV
        // distances, which keeps preview and export visually identical.
        let beauty = BeautyKernel(
            parameters: adjustments.clamped().beauty,
            mask: beautyMask,
            anchors: faceAnchors
        )
        // Denoise, clarity and sharpening come before the portrait pass, as in
        // sections 1–3 of `main.glsl`; all three need source-UV taps.
        let detail = DetailKernel(parameters: adjustments.clamped().detail)
        let detailActive = !detail.isIdentity
        let beautyActive = !beauty.isIdentity
        // Region effects are the first thing after the source sample, before
        // detail and colour, exactly like section 0 of the shader.
        let effect = EditorEffectKernel(
            mask: effectMask,
            size: effectSize,
            strength: effectStrength,
            sourceWidth: Int(width),
            sourceHeight: Int(height)
        )
        let effectActive = effect != nil

        let xScale = Float(crop.width) / Float(outWidth)
        let yScale = Float(crop.height) / Float(outHeight)
        let centerX = Float(outWidth) * 0.5
        let centerY = Float(outHeight) * 0.5
        let maxRadius = max(
            sqrt(centerX * centerX + centerY * centerY),
            1
        )
        let exactCopy = colorIdentity && xScale == 1 && yScale == 1
            && !geometry.hasFine && !geometry.hasPerspective
            && warp.isIdentity && liquifyField == nil && !effectActive
        let bytesPerRow = pixelWidth * 4

        // A live rotate or perspective drag renders hundreds of thousands of
        // pixels. The old loop built four or five short arrays for every one
        // of them (`pixel` and `sampleBilinear`), which turned a gesture into
        // millions of allocations. The buffers stay borrowed for the whole
        // pass and every sample is a SIMD value on the stack.
        let sourcePixels = source
        out.withUnsafeMutableBufferPointer { destination in
            sourcePixels.withUnsafeBufferPointer { pixels in
                let sourcePass: BeautySampleSource? = (detailActive || beautyActive || effectActive)
                    ? BeautySampleSource(
                        width: Int(width),
                        height: Int(height),
                        pixels: pixels
                    )
                    : nil
                for row in 0..<pixelHeight {
                    let displayY = Float(crop.y)
                        + (Float(row) + 0.5) * yScale
                    let rowOffset = row * bytesPerRow
                    for column in 0..<pixelWidth {
                        let displayX = Float(crop.x)
                            + (Float(column) + 0.5) * xScale
                        let sampled = exactCopy
                            ? sourcePixel(
                                displayX,
                                displayY,
                                geometry: geometry,
                                warp: warp,
                                source: pixels
                            )
                            : sampleBilinear(
                                displayX,
                                displayY,
                                geometry: geometry,
                                warp: warp,
                                source: pixels
                            )
                        let offset = rowOffset + column * 4
                        let normalizedX = (Float(column) + 0.5 - centerX)
                            / maxRadius
                        let normalizedY = (Float(row) + 0.5 - centerY)
                            / maxRadius
                        if let sourcePass {
                            let uv = mappedSourceUV(
                                displayX,
                                displayY,
                                geometry: geometry,
                                warp: warp
                            )
                            let base = SIMD3<Float>(
                                Float(sampled.x) / 255,
                                Float(sampled.y) / 255,
                                Float(sampled.z) / 255
                            )
                            var shown = base
                            if let effect {
                                shown = effect.apply(
                                    shown,
                                    uv: uv,
                                    source: sourcePass
                                )
                            }
                            if detailActive {
                                shown = detail.apply(
                                    shown,
                                    uv: uv,
                                    source: sourcePass
                                )
                            }
                            if beautyActive {
                                shown = beauty.apply(
                                    shown,
                                    uv: uv,
                                    source: sourcePass
                                )
                            }
                            if colorIdentity {
                                destination[offset] = Editor.byte(shown.x)
                                destination[offset + 1] = Editor.byte(shown.y)
                                destination[offset + 2] = Editor.byte(shown.z)
                                destination[offset + 3] = sampled.w
                            } else {
                                let adjusted = Editor.applyPixel(
                                    shown.x,
                                    shown.y,
                                    shown.z,
                                    effective,
                                    normalizedX: normalizedX,
                                    normalizedY: normalizedY
                                )
                                destination[offset] = adjusted.0
                                destination[offset + 1] = adjusted.1
                                destination[offset + 2] = adjusted.2
                                destination[offset + 3] = sampled.w
                            }
                        } else if colorIdentity {
                            // The colour pass is the identity here, so the
                            // original channels pass through untouched.
                            destination[offset] = sampled.x
                            destination[offset + 1] = sampled.y
                            destination[offset + 2] = sampled.z
                            destination[offset + 3] = sampled.w
                        } else {
                            let adjusted = Editor.applyPixel(
                                sampled.x,
                                sampled.y,
                                sampled.z,
                                effective,
                                normalizedX: normalizedX,
                                normalizedY: normalizedY
                            )
                            destination[offset] = adjusted.0
                            destination[offset + 1] = adjusted.1
                            destination[offset + 2] = adjusted.2
                            destination[offset + 3] = sampled.w
                        }
                    }
                }
            }
        }
        return out
    }

    /// Display-space pixel to stored-source pixels, through free liquify and
    /// the face warp.
    ///
    /// The web shader's `warpFace()` pushes `uv` through the liquify field and
    /// then through the face reshape; both are source-UV inverse maps, so the
    /// same order is used here. The pushed UV is clamped to the photo, exactly
    /// like the shader's `clamp(uv + pushed, 0.0, 1.0)`.
    @inline(__always)
    private func sourcePoint(
        _ displayX: Float,
        _ displayY: Float,
        geometry: SampleGeometry,
        warp: FaceWarpSampler
    ) -> (Float, Float) {
        let base = displayToSource(
            displayX,
            displayY,
            geometry: geometry
        )
        guard let field = liquifyField else {
            return warpSource(base, warp: warp)
        }
        let uv = SIMD2<Float>(
            base.0 / Float(width),
            base.1 / Float(height)
        )
        let pushed = uv + field.displacement(at: uv)
        let point = (
            min(max(pushed.x, 0), 1) * Float(width),
            min(max(pushed.y, 0), 1) * Float(height)
        )
        return warpSource(point, warp: warp)
    }

    /// Stored-source UV of one output pixel after liquify and the face warp.
    @inline(__always)
    private func mappedSourceUV(
        _ displayX: Float,
        _ displayY: Float,
        geometry: SampleGeometry,
        warp: FaceWarpSampler
    ) -> SIMD2<Float> {
        let point = sourcePoint(
            displayX,
            displayY,
            geometry: geometry,
            warp: warp
        )
        return SIMD2<Float>(
            point.0 / Float(width),
            point.1 / Float(height)
        )
    }

    @inline(__always)
    private static func byte(_ value: Float) -> UInt8 {
        UInt8(min(max((value * 255).rounded(), 0), 255))
    }

    @inline(__always)
    private func sourcePixel(
        _ displayX: Float,
        _ displayY: Float,
        geometry: SampleGeometry,
        warp: FaceWarpSampler,
        source pixels: UnsafeBufferPointer<UInt8>
    ) -> SIMD4<UInt8> {
        let point = sourcePoint(
            displayX,
            displayY,
            geometry: geometry,
            warp: warp
        )
        let x = Int(min(max(floor(point.0), 0), Float(width) - 1))
        let y = Int(min(max(floor(point.1), 0), Float(height) - 1))
        let offset = (y * Int(width) + x) * 4
        return SIMD4<UInt8>(
            pixels[offset],
            pixels[offset + 1],
            pixels[offset + 2],
            pixels[offset + 3]
        )
    }

    /// Apply the inverse face warp in oriented source UV space.
    ///
    /// Vision boxes and the web shader's `u_faces` are both normalised to the
    /// oriented photo, so the warp belongs after the geometry mapper has
    /// returned a source pixel and before that pixel is sampled.
    @inline(__always)
    private func warpSource(
        _ point: (Float, Float),
        warp: FaceWarpSampler
    ) -> (Float, Float) {
        guard !warp.isIdentity else { return point }
        let imageWidth = Float(width)
        let imageHeight = Float(height)
        let warped = warp.warp(
            SIMD2<Float>(point.0 / imageWidth, point.1 / imageHeight)
        )
        return (warped.x * imageWidth, warped.y * imageHeight)
    }

    @inline(__always)
    private func sampleBilinear(
        _ displayX: Float,
        _ displayY: Float,
        geometry: SampleGeometry,
        warp: FaceWarpSampler,
        source pixels: UnsafeBufferPointer<UInt8>
    ) -> SIMD4<UInt8> {
        let point = sourcePoint(
            displayX,
            displayY,
            geometry: geometry,
            warp: warp
        )
        let fx = point.0 - 0.5
        let fy = point.1 - 0.5
        let x0 = floor(fx)
        let y0 = floor(fy)
        // A UV round-trip through the warp leaves a sub-1e-4 fraction on a
        // pixel centre. Snapping it keeps an unwarped pixel bit-identical to
        // the nearest sample instead of nudging it by a rounding error.
        var tx = fx - x0
        var ty = fy - y0
        if tx < 0.0001 { tx = 0 } else if tx > 0.9999 { tx = 1 }
        if ty < 0.0001 { ty = 0 } else if ty > 0.9999 { ty = 1 }

        let maxX = Int(width) - 1
        let maxY = Int(height) - 1
        let x0i = Int(min(max(x0, 0), Float(maxX)))
        let y0i = Int(min(max(y0, 0), Float(maxY)))
        let x1i = Int(min(max(x0 + 1, 0), Float(maxX)))
        let y1i = Int(min(max(y0 + 1, 0), Float(maxY)))

        let rowStride = Int(width) * 4
        let offset00 = y0i * rowStride + x0i * 4
        let offset10 = y0i * rowStride + x1i * 4
        let offset01 = y1i * rowStride + x0i * 4
        let offset11 = y1i * rowStride + x1i * 4

        return SIMD4<UInt8>(
            blend(
                pixels[offset00],
                pixels[offset10],
                pixels[offset01],
                pixels[offset11],
                tx,
                ty
            ),
            blend(
                pixels[offset00 + 1],
                pixels[offset10 + 1],
                pixels[offset01 + 1],
                pixels[offset11 + 1],
                tx,
                ty
            ),
            blend(
                pixels[offset00 + 2],
                pixels[offset10 + 2],
                pixels[offset01 + 2],
                pixels[offset11 + 2],
                tx,
                ty
            ),
            blend(
                pixels[offset00 + 3],
                pixels[offset10 + 3],
                pixels[offset01 + 3],
                pixels[offset11 + 3],
                tx,
                ty
            )
        )
    }

    @inline(__always)
    private func blend(
        _ topLeft: UInt8,
        _ topRight: UInt8,
        _ bottomLeft: UInt8,
        _ bottomRight: UInt8,
        _ tx: Float,
        _ ty: Float
    ) -> UInt8 {
        let top = Float(topLeft)
            + (Float(topRight) - Float(topLeft)) * tx
        let bottom = Float(bottomLeft)
            + (Float(bottomRight) - Float(bottomLeft)) * tx
        let value = top + (bottom - top) * ty
        return UInt8(min(max(value.rounded(), 0), 255))
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
            identity: values.isColorIdentity && transform == nil,
            matrix: transform?.matrix,
            offset: transform?.offset
        )
    }

    /// A 3×3 colour matrix with a per-channel offset, row major.
    struct PresetTransform {
        var matrix: [Float]
        var offset: [Float]
    }

    /// The colour transform of one preset, decoded from the shared
    /// `filters.json` spec. The web and the app read the same final matrix, so
    /// a tone cannot drift between the two clients.
    static func presetTransform(_ filter: EditorFilter) -> PresetTransform? {
        guard let spec = EditorFilterSpec.filter(id: filter.rawValue) else {
            assertionFailure("missing filter spec for \(filter.rawValue)")
            return nil
        }
        guard !spec.isIdentity else { return nil }
        return PresetTransform(matrix: spec.matrix, offset: spec.offset)
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
        applyPixel(
            Float(r) / 255,
            Float(g) / 255,
            Float(b) / 255,
            effective,
            normalizedX: normalizedX,
            normalizedY: normalizedY
        )
    }

    /// Float entry point for the portrait pass, which produces values before
    /// the colour stack and keeps its sub-8-bit precision until the end.
    static func applyPixel(
        _ r: Float,
        _ g: Float,
        _ b: Float,
        _ effective: Effective,
        normalizedX: Float,
        normalizedY: Float
    ) -> (UInt8, UInt8, UInt8) {
        let a = effective.adjustments
        var red = r
        var green = g
        var blue = b

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
