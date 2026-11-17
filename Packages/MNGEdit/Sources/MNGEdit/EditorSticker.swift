import Foundation

/// One emoji sticker over the photo, normalized to the exported image.
///
/// A sticker is glyph-first: the same one-glyph model as the web editor, so a
/// state written by either client opens in the other. `size` is a fraction of
/// the export height, like `EditorTextLayer`, and may cover the whole frame
/// (0.02…1) because stickers are not bounded by a text line.
public struct EditorStickerLayer: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// One emoji family. ZWJ sequences, skin tones and variation selectors
    /// are preserved by `EditorStickerSanitizer`.
    public var glyph: String
    public var x: Float
    public var y: Float
    public var size: Float
    public var rotation: Float
    public var opacity: Float

    public init(
        id: String,
        glyph: String,
        x: Float = 0.5,
        y: Float = 0.5,
        size: Float = 0.24,
        rotation: Float = 0,
        opacity: Float = 1
    ) {
        self.id = id
        self.glyph = glyph
        self.x = x
        self.y = y
        self.size = size
        self.rotation = rotation
        self.opacity = opacity
    }

    /// Clamp the geometry to the export frame and drop an empty glyph.
    ///
    /// An empty glyph would be an invisible node that still eats gestures, so
    /// it is rejected instead of replaced with a placeholder. The rotation
    /// wraps like the text layer, so a handle drag keeps turning in the same
    /// direction across the ±180° branch cut.
    public func normalized() -> EditorStickerLayer? {
        let clean = EditorStickerSanitizer.sanitize(glyph)
        guard !clean.isEmpty else { return nil }
        var copy = self
        copy.glyph = clean
        if !copy.x.isFinite { copy.x = 0.5 }
        if !copy.y.isFinite { copy.y = 0.5 }
        if !copy.size.isFinite { copy.size = 0.24 }
        if !copy.rotation.isFinite { copy.rotation = 0 }
        if !copy.opacity.isFinite { copy.opacity = 1 }
        copy.x = min(max(copy.x, 0), 1)
        copy.y = min(max(copy.y, 0), 1)
        copy.size = min(max(copy.size, 0.02), 1)
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

/// The shared emoji rail: the same 28 glyphs as the web text pane.
public enum EditorStickerCatalog {
    public static let glyphs: [String] = [
        "😀", "😂", "🥰", "😎", "🤩", "😭", "😡", "🥳",
        "👍", "👏", "🙏", "💪", "❤️", "🔥", "✨", "⭐",
        "🌸", "🌈", "🎉", "💯", "🍀", "🐱", "🐶", "🎀",
        "👑", "💋", "🍕", "☕️",
    ]
}

/// Reduce an untrusted string to something an emoji font can draw.
///
/// The web counterpart (`sanitizeStickerGlyph`) strips control characters and
/// lone surrogates, keeps at most 16 code points, then trims. Swift strings
/// cannot carry an unpaired surrogate, so the scalar pass covers the rest.
public enum EditorStickerSanitizer {
    public static let maxCodePoints = 16

    public static func sanitize(_ input: String) -> String {
        var out = ""
        var count = 0
        for scalar in input.unicodeScalars {
            let value = scalar.value
            if value <= 0x1f || (0x7f...0x9f).contains(value) {
                continue
            }
            out.unicodeScalars.append(scalar)
            count += 1
            if count == maxCodePoints { break }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A layer over the photo, in draw order.
///
/// The web state v2 carries text and stickers in one array so the z-order is
/// preserved across kinds. This union mirrors that array and encodes flat
/// objects with a `kind` field, which is the shape the web importer reads.
/// A missing `kind` is a text layer, matching the v2.0 states.
public enum EditorLayer: Codable, Equatable, Sendable, Identifiable {
    case text(EditorTextLayer)
    case sticker(EditorStickerLayer)

    public static let maxLayers = 64

    public var id: String {
        switch self {
        case .text(let layer): return layer.id
        case .sticker(let layer): return layer.id
        }
    }

    public var textLayer: EditorTextLayer? {
        if case .text(let layer) = self { return layer }
        return nil
    }

    public var stickerLayer: EditorStickerLayer? {
        if case .sticker(let layer) = self { return layer }
        return nil
    }

    public var x: Float {
        get {
            switch self {
            case .text(let layer): return layer.x
            case .sticker(let layer): return layer.x
            }
        }
        set {
            switch self {
            case .text(var layer):
                layer.x = newValue
                self = .text(layer)
            case .sticker(var layer):
                layer.x = newValue
                self = .sticker(layer)
            }
        }
    }

    public var y: Float {
        get {
            switch self {
            case .text(let layer): return layer.y
            case .sticker(let layer): return layer.y
            }
        }
        set {
            switch self {
            case .text(var layer):
                layer.y = newValue
                self = .text(layer)
            case .sticker(var layer):
                layer.y = newValue
                self = .sticker(layer)
            }
        }
    }

    public var size: Float {
        get {
            switch self {
            case .text(let layer): return layer.size
            case .sticker(let layer): return layer.size
            }
        }
        set {
            switch self {
            case .text(var layer):
                layer.size = newValue
                self = .text(layer)
            case .sticker(var layer):
                layer.size = newValue
                self = .sticker(layer)
            }
        }
    }

    public var rotation: Float {
        get {
            switch self {
            case .text(let layer): return layer.rotation
            case .sticker(let layer): return layer.rotation
            }
        }
        set {
            switch self {
            case .text(var layer):
                layer.rotation = newValue
                self = .text(layer)
            case .sticker(var layer):
                layer.rotation = newValue
                self = .sticker(layer)
            }
        }
    }

    public var opacity: Float {
        get {
            switch self {
            case .text(let layer): return layer.opacity
            case .sticker(let layer): return layer.opacity
            }
        }
        set {
            switch self {
            case .text(var layer):
                layer.opacity = newValue
                self = .text(layer)
            case .sticker(var layer):
                layer.opacity = newValue
                self = .sticker(layer)
            }
        }
    }

    /// Normalize and drop a sticker whose glyph is empty.
    public func normalized() -> EditorLayer? {
        switch self {
        case .text(let layer):
            return .text(layer.normalized())
        case .sticker(let layer):
            return layer.normalized().map(EditorLayer.sticker)
        }
    }

    public func withID(_ id: String) -> EditorLayer {
        switch self {
        case .text(var layer):
            layer.id = id
            return .text(layer)
        case .sticker(var layer):
            layer.id = id
            return .sticker(layer)
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case kind
        case id
        case text
        case glyph
        case x
        case y
        case size
        case color
        case bold
        case italic
        case outline
        case shadow
        case align
        case rotation
        case opacity
        case font
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(String.self, forKey: .kind)
            ?? "text"
        let id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? UUID().uuidString
        let x = try container.decodeIfPresent(Float.self, forKey: .x)
        let y = try container.decodeIfPresent(Float.self, forKey: .y)
        let size = try container.decodeIfPresent(Float.self, forKey: .size)
        let rotation = try container.decodeIfPresent(Float.self, forKey: .rotation)
        let opacity = try container.decodeIfPresent(Float.self, forKey: .opacity)

        switch kind {
        case "text":
            let align = try container
                .decodeIfPresent(String.self, forKey: .align)
                .flatMap(EditorTextAlign.init(rawValue:)) ?? .center
            let font = try container
                .decodeIfPresent(String.self, forKey: .font)
                .flatMap(EditorTextFont.init(rawValue:)) ?? .sys
            self = .text(
                EditorTextLayer(
                    id: id,
                    text: try container.decodeIfPresent(String.self, forKey: .text) ?? "",
                    x: x ?? 0.5,
                    y: y ?? 0.5,
                    size: size ?? 0.07,
                    color: try container.decodeIfPresent(String.self, forKey: .color) ?? "#ffffff",
                    bold: try container.decodeIfPresent(Bool.self, forKey: .bold) ?? false,
                    italic: try container.decodeIfPresent(Bool.self, forKey: .italic) ?? false,
                    outline: try container.decodeIfPresent(Bool.self, forKey: .outline) ?? false,
                    shadow: try container.decodeIfPresent(Bool.self, forKey: .shadow) ?? true,
                    align: align,
                    rotation: rotation ?? 0,
                    opacity: opacity ?? 1,
                    font: font
                )
            )
        case "sticker":
            let glyph = EditorStickerSanitizer.sanitize(
                try container.decodeIfPresent(String.self, forKey: .glyph) ?? ""
            )
            guard !glyph.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .glyph,
                    in: container,
                    debugDescription: "a sticker needs a glyph"
                )
            }
            self = .sticker(
                EditorStickerLayer(
                    id: id,
                    glyph: glyph,
                    x: x ?? 0.5,
                    y: y ?? 0.5,
                    size: size ?? 0.24,
                    rotation: rotation ?? 0,
                    opacity: opacity ?? 1
                )
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "unknown layer kind \(kind)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let layer):
            try container.encode("text", forKey: .kind)
            try container.encode(layer.id, forKey: .id)
            try container.encode(layer.text, forKey: .text)
            try container.encode(layer.x, forKey: .x)
            try container.encode(layer.y, forKey: .y)
            try container.encode(layer.size, forKey: .size)
            try container.encode(layer.color, forKey: .color)
            try container.encode(layer.bold, forKey: .bold)
            try container.encode(layer.italic, forKey: .italic)
            try container.encode(layer.outline, forKey: .outline)
            try container.encode(layer.shadow, forKey: .shadow)
            try container.encode(layer.align.rawValue, forKey: .align)
            try container.encode(layer.rotation, forKey: .rotation)
            try container.encode(layer.opacity, forKey: .opacity)
            try container.encode(layer.font.rawValue, forKey: .font)
        case .sticker(let layer):
            try container.encode("sticker", forKey: .kind)
            try container.encode(layer.id, forKey: .id)
            try container.encode(layer.glyph, forKey: .glyph)
            try container.encode(layer.x, forKey: .x)
            try container.encode(layer.y, forKey: .y)
            try container.encode(layer.size, forKey: .size)
            try container.encode(layer.rotation, forKey: .rotation)
            try container.encode(layer.opacity, forKey: .opacity)
        }
    }
}
