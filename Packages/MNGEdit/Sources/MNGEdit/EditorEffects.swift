import Foundation

/// A region-effect stamp in stored-source UV space.
///
/// `radius` is measured on the source width, exactly like the web editor's
/// `EffectDab`, so a dab covers the same physical area in the preview and in a
/// full-resolution export. The pixel is the source texel the mask is sampled
/// at, which keeps preview and export on the same pixels after a warp.
public struct EditorEffectDab: Codable, Equatable, Sendable {
    public var kind: EditorEffectKind
    public var x: Float
    public var y: Float
    /// Brush radius in width-normalised UV units.
    public var radius: Float

    public init(
        kind: EditorEffectKind,
        x: Float,
        y: Float,
        radius: Float
    ) {
        self.kind = kind
        self.x = x
        self.y = y
        self.radius = radius
    }

    /// The web state limits: coordinates and radius are clamped, malformed
    /// dabs are dropped, so a saved JSON can never paint outside the photo.
    var normalized: EditorEffectDab? {
        guard x.isFinite, y.isFinite, radius.isFinite else { return nil }
        return EditorEffectDab(
            kind: kind,
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1),
            radius: min(
                max(radius, EditorEffectLimits.minRadius),
                EditorEffectLimits.maxRadius
            )
        )
    }
}

/// The two styles of the effect brush.
public enum EditorEffectKind: String, Codable, CaseIterable, Sendable {
    case mosaic
    case blur

    public var title: String {
        switch self {
        case .mosaic: return "Mosaic"
        case .blur: return "Làm mờ"
        }
    }
}

public enum EditorEffectLimits {
    /// The history keeps the newest stamps, like `MAX_EFFECT_DABS`.
    public static let maxDabs = 1600
    /// Longest side of the painted mask, in pixels.
    public static let maskMax = 1024
    /// Brush radius in width-normalised UV, the web's 0.002…0.2 range.
    public static let minRadius: Float = 0.002
    public static let maxRadius: Float = 0.2
    public static let minSize: Float = 0.01
    public static let maxSize: Float = 0.2
    public static let defaultSize: Float = 0.08
    public static let defaultStrength: Float = 60
}

/// The state of the effect brush, in the shape of the web's
/// `retouch.effects` block.
public struct EditorEffectState: Codable, Equatable, Sendable {
    public var dabs: [EditorEffectDab]
    /// Brush radius as a fraction of the source width, 0.01…0.2.
    public var size: Float
    /// Blend strength, 0…100.
    public var strength: Float

    public init(
        dabs: [EditorEffectDab] = [],
        size: Float = EditorEffectLimits.defaultSize,
        strength: Float = EditorEffectLimits.defaultStrength
    ) {
        self.dabs = dabs
        self.size = size
        self.strength = strength
    }

    /// Normalise an untrusted state: clamp the globals and keep the newest
    /// valid dabs.
    public var normalized: EditorEffectState {
        var result = EditorEffectState()
        let valid = dabs.compactMap(\.normalized)
        result.dabs = Array(valid.suffix(EditorEffectLimits.maxDabs))
        result.size = min(
            max(size.isFinite ? size : EditorEffectLimits.defaultSize,
                EditorEffectLimits.minSize),
            EditorEffectLimits.maxSize
        )
        result.strength = min(
            max(strength.isFinite ? strength : EditorEffectLimits.defaultStrength,
                0),
            100
        )
        return result
    }
}

/// Uniforms derived from the live brush settings.
///
/// The block edge and blur radius follow the brush size, so a 20 % brush
/// produces a visibly coarse mosaic and a soft bokeh while a 1 % brush leaves
/// fine detail intact.
public struct EditorEffectGeometry: Equatable, Sendable {
    /// Mosaic block edge in source pixels.
    public let blockPx: Int
    /// Mosaic grid counts across the source width and height.
    public let grid: SIMD2<Float>
    /// Blur radius in image-UV units, per axis.
    public let blur: SIMD2<Float>
    /// Blend strength, 0…1.
    public let strength: Float

    public init(
        size: Float,
        strength: Float,
        sourceWidth: Int,
        sourceHeight: Int
    ) {
        let brush = min(
            max(size.isFinite ? size : EditorEffectLimits.defaultSize,
                EditorEffectLimits.minSize),
            EditorEffectLimits.maxSize
        )
        let width = Float(max(1, sourceWidth))
        let height = Float(max(1, sourceHeight))
        let block = max(2, Int((brush * width * 0.55).rounded()))
        let blurX = brush * 0.42
        blockPx = block
        grid = SIMD2<Float>(width / Float(block), height / Float(block))
        // A UV step of `blurX` spans the same number of source pixels on both
        // axes, so the blur stays circular on non-square photos.
        blur = SIMD2<Float>(blurX, blurX * width / height)
        self.strength = min(
            max(strength.isFinite ? strength : EditorEffectLimits.defaultStrength,
                0),
            100
        ) / 100
    }
}

/// One RGBA8 mask shared by both styles.
///
/// R = mosaic, G = blur, B is reserved and A is always 255. The mask keeps the
/// source aspect and is at most 1024 px on its longest side, so bilinear
/// sampling gives a soft edge without a heavy upload.
public struct EditorEffectMask: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var rgba: [UInt8]

    /// Sample R/G with clamp-to-edge bilinear, matching the texture's `LINEAR`
    /// filter and `CLAMP_TO_EDGE` wrap. Returns coverage 0…1 per style.
    public func coverage(at uv: SIMD2<Float>) -> SIMD2<Float> {
        guard width > 0, height > 0 else { return .zero }
        let x = min(max(uv.x, 0), 1) * Float(width) - 0.5
        let y = min(max(uv.y, 0), 1) * Float(height) - 0.5
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let tx = x - Float(x0)
        let ty = y - Float(y0)
        let x0i = min(max(x0, 0), width - 1)
        let y0i = min(max(y0, 0), height - 1)
        let x1i = min(max(x0 + 1, 0), width - 1)
        let y1i = min(max(y0 + 1, 0), height - 1)
        let at00 = (y0i * width + x0i) * 4
        let at10 = (y0i * width + x1i) * 4
        let at01 = (y1i * width + x0i) * 4
        let at11 = (y1i * width + x1i) * 4

        func channel(_ offset: Int) -> Float {
            let top = Float(rgba[at00 + offset])
                + (Float(rgba[at10 + offset]) - Float(rgba[at00 + offset])) * tx
            let bottom = Float(rgba[at01 + offset])
                + (Float(rgba[at11 + offset]) - Float(rgba[at01 + offset])) * tx
            return (top + (bottom - top) * ty) / 255
        }

        return SIMD2<Float>(channel(0), channel(1))
    }
}

/// Builds the shared RG mask of `src/core/effects.ts`.
enum EditorEffectMaskBuilder {
    /// The source-sized mask dimensions, capped on the longest side.
    static func dimensions(
        sourceWidth: Int,
        sourceHeight: Int
    ) -> (width: Int, height: Int)? {
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }
        let longest = max(sourceWidth, sourceHeight)
        let scale = min(
            1,
            Float(EditorEffectLimits.maskMax) / Float(longest)
        )
        return (
            max(1, Int((Float(sourceWidth) * scale).rounded())),
            max(1, Int((Float(sourceHeight) * scale).rounded()))
        )
    }

    static func makeMask(
        sourceWidth: Int,
        sourceHeight: Int
    ) -> EditorEffectMask? {
        guard let size = dimensions(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight
        ) else {
            return nil
        }
        var rgba = [UInt8](
            repeating: 0,
            count: size.width * size.height * 4
        )
        // The web fills alpha once for the whole mask. R and G stay zero
        // until a stamp writes them.
        for index in stride(from: 3, to: rgba.count, by: 4) {
            rgba[index] = 255
        }
        return EditorEffectMask(
            width: size.width,
            height: size.height,
            rgba: rgba
        )
    }

    /// Rasterise every stamp into one mask. Returns `nil` when nothing was
    /// painted, so the renderer keeps its byte-identical bypass.
    static func build(
        dabs: [EditorEffectDab],
        sourceWidth: Int,
        sourceHeight: Int
    ) -> EditorEffectMask? {
        guard !dabs.isEmpty,
              var mask = makeMask(
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight
              ) else {
            return nil
        }
        var painted = false
        for dab in dabs {
            guard let dab = dab.normalized else { continue }
            if stamp(dab, into: &mask) {
                painted = true
            }
        }
        return painted ? mask : nil
    }

    /// Stamp one dab into an existing mask.
    ///
    /// Channels accumulate with `max`, so overlapping strokes of the same kind
    /// do not darken or build up beyond full coverage. The outer 35 % of every
    /// stamp is a linear feather; the core is solid, which keeps a mosaic edge
    /// crisp but not aliased. Returns true when at least one pixel changed.
    @discardableResult
    static func stamp(
        _ dab: EditorEffectDab,
        into mask: inout EditorEffectMask
    ) -> Bool {
        let width = mask.width
        let height = mask.height
        guard width > 0, height > 0, mask.rgba.count == width * height * 4 else {
            return false
        }
        let channel = dab.kind == .mosaic ? 0 : 1
        // Radius is width-normalised in source space; the mask keeps the source
        // aspect, so the same pixel count is the same physical radius on both
        // axes.
        let radius = max(0.5, dab.radius * Float(width))
        let cx = dab.x * Float(width)
        let cy = dab.y * Float(height)
        let x0 = max(0, Int(floor(cx - radius)))
        let x1 = min(width - 1, Int(ceil(cx + radius)))
        let y0 = max(0, Int(floor(cy - radius)))
        let y1 = min(height - 1, Int(ceil(cy + radius)))
        guard x1 >= x0, y1 >= y0 else { return false }
        let invRadius = 1 / radius
        let feather: Float = 0.35
        var painted = false

        for y in y0...y1 {
            let dy = Float(y) + 0.5 - cy
            let row = y * width
            for x in x0...x1 {
                let dx = Float(x) + 0.5 - cx
                let distance = (dx * dx + dy * dy).squareRoot() * invRadius
                if distance >= 1 { continue }
                let coverage = min(1, (1 - distance) / feather)
                let value = UInt8(
                    min(max((coverage * 255).rounded(), 0), 255)
                )
                let at = (row + x) * 4
                if value > mask.rgba[at + channel] {
                    mask.rgba[at + channel] = value
                    painted = true
                }
            }
        }
        return painted
    }
}

/// The CPU port of the shader's mosaic/blur region pass.
///
/// The mask is sampled at the warped source UV, exactly like `main.glsl`: the
/// mosaic reads one texel in the centre of each grid cell, the blur averages
/// nine taps, and both mix into the source colour before detail and beauty.
struct EditorEffectKernel {
    let mask: EditorEffectMask
    let geometry: EditorEffectGeometry

    init?(
        mask: EditorEffectMask?,
        size: Float,
        strength: Float,
        sourceWidth: Int,
        sourceHeight: Int
    ) {
        guard let mask, mask.width > 0, mask.height > 0 else { return nil }
        let geometry = EditorEffectGeometry(
            size: size,
            strength: strength,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight
        )
        // The shader skips the whole block below 0.0001 strength, and so does
        // the renderer's byte-identical bypass.
        guard geometry.strength > 0.0001 else { return nil }
        self.mask = mask
        self.geometry = geometry
    }

    func apply(
        _ rgb: SIMD3<Float>,
        uv: SIMD2<Float>,
        source: BeautySampleSource
    ) -> SIMD3<Float> {
        let region = mask.coverage(at: uv)
        let strength = geometry.strength
        var effected = rgb

        if region.x > 0.001 {
            // One sample in the centre of each cell; the grid counts cells
            // across the whole source, so a block keeps its physical size at
            // any render resolution.
            let cell = SIMD2<Float>(
                (uv.x * geometry.grid.x).rounded(.down) + 0.5,
                (uv.y * geometry.grid.y).rounded(.down) + 0.5
            ) / geometry.grid
            let block = source.sample(
                SIMD2<Float>(
                    min(max(cell.x, 0), 1),
                    min(max(cell.y, 0), 1)
                )
            )
            effected += (block - effected)
                * SIMD3<Float>(repeating: region.x * strength)
        }

        if region.y > 0.001 {
            let ox = SIMD2<Float>(geometry.blur.x, 0)
            let oy = SIMD2<Float>(0, geometry.blur.y)
            var sum = source.sample(uv)
            sum += source.sample(uv + ox)
            sum += source.sample(uv - ox)
            sum += source.sample(uv + oy)
            sum += source.sample(uv - oy)
            sum += source.sample(uv + ox + oy)
            sum += source.sample(uv + ox - oy)
            sum += source.sample(uv - ox + oy)
            sum += source.sample(uv - ox - oy)
            let blurred = sum / SIMD3<Float>(repeating: 9)
            effected += (blurred - effected)
                * SIMD3<Float>(repeating: region.y * strength)
        }

        return effected
    }
}
