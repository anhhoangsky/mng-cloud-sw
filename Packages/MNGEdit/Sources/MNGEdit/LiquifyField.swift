import Foundation

/// One free-liquify dab in stored-source UV space.
///
/// `dx`/`dy` is the drag displacement in UV units, not screen pixels, so a
/// 1080 px preview and a 6000 px export move the same detail. `radius` is
/// measured on the source width, exactly like the web editor's `LiquifyDab`.
public struct EditorLiquifyDab: Codable, Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var dx: Float
    public var dy: Float
    /// Brush radius in width-normalised UV units.
    public var radius: Float

    public init(x: Float, y: Float, dx: Float, dy: Float, radius: Float) {
        self.x = x
        self.y = y
        self.dx = dx
        self.dy = dy
        self.radius = radius
    }

    /// The web state limits. Non-finite and zero-drag dabs are dropped so the
    /// shader never sees NaN or an unbounded stroke.
    var normalized: EditorLiquifyDab? {
        guard x.isFinite, y.isFinite, dx.isFinite, dy.isFinite, radius.isFinite else {
            return nil
        }
        guard abs(dx) + abs(dy) >= 1e-6 else { return nil }
        return EditorLiquifyDab(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1),
            dx: min(max(dx, -0.25), 0.25),
            dy: min(max(dy, -0.25), 0.25),
            radius: min(max(radius, 0.002), EditorLiquifyLimits.maxRadius)
        )
    }
}

public enum EditorLiquifyLimits {
    /// The history keeps the newest dabs, like `MAX_LIQUIFY_DABS`.
    public static let maxDabs = 640
    /// Brush radius in width-normalised UV, the web's `MAX_LIQUIFY_RADIUS`.
    public static let maxRadius: Float = 0.35
    /// The largest displacement the RG field can encode.
    public static let maxShift: Float = 0.09
}

/// A tiny RGBA8 displacement field in the layout of `buildLiquifyField`.
///
/// RG encode the signed source-UV displacement as `128 + value/shift*127`, so
/// an untouched texel is exactly 128 and decodes to zero. B is reserved and A
/// is always 255.
struct EditorLiquifyField: Equatable, Sendable {
    let width: Int
    let height: Int
    let rgba: [UInt8]
    /// The maximum displacement encoded in RG, in source-UV units.
    let shift: Float

    init?(width: Int, height: Int, rgba: [UInt8], shift: Float) {
        guard width > 0,
              height > 0,
              shift.isFinite,
              shift > 0,
              rgba.count == width * height * 4 else {
            return nil
        }
        self.width = width
        self.height = height
        self.rgba = rgba
        self.shift = shift
    }

    /// Bilinear sample with clamp-to-edge, matching the web texture's `LINEAR`
    /// filter and `CLAMP_TO_EDGE` wrap. Returns the source-UV displacement.
    func displacement(at uv: SIMD2<Float>) -> SIMD2<Float> {
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
            return top + (bottom - top) * ty
        }

        // Undo the 8-bit encoding: (byte − 128) * shift / 127.
        let scale = shift / 127
        return SIMD2<Float>(
            (channel(0) - 128) * scale,
            (channel(1) - 128) * scale
        )
    }
}

/// Builds the RG displacement field of `src/core/liquify.ts`.
///
/// The field is deliberately tiny (64 px on the short axis). Bilinear sampling
/// turns the falloff into a smooth warp, and a 64×96 RGBA texture is 24 KB
/// even for a portrait.
enum EditorLiquifyFieldBuilder {
    static func build(
        dabs: [EditorLiquifyDab],
        sourceWidth: Int,
        sourceHeight: Int
    ) -> EditorLiquifyField? {
        guard !dabs.isEmpty, sourceWidth > 0, sourceHeight > 0 else {
            return nil
        }
        let width = 64
        let aspect = min(
            max(Float(sourceHeight) / Float(max(1, sourceWidth)), 0.05),
            20
        )
        let height = max(
            24,
            min(128, Int((Float(width) * aspect).rounded()))
        )
        let count = width * height
        var accX = [Float](repeating: 0, count: count)
        var accY = [Float](repeating: 0, count: count)

        for raw in dabs {
            guard let dab = raw.normalized else { continue }
            let radius = dab.radius
            // A radius measured on the source width becomes a larger UV
            // interval on the source height whenever the photo is portrait.
            let radiusY = radius / aspect
            let x0 = max(0, Int(floor((dab.x - radius) * Float(width))))
            let x1 = min(width - 1, Int(ceil((dab.x + radius) * Float(width))))
            let y0 = max(0, Int(floor((dab.y - radiusY) * Float(height))))
            let y1 = min(height - 1, Int(ceil((dab.y + radiusY) * Float(height))))
            guard x0 <= x1, y0 <= y1 else { continue }

            for iy in y0...y1 {
                let v = (Float(iy) + 0.5) / Float(height)
                let ny = (v - dab.y) / radiusY
                for ix in x0...x1 {
                    let u = (Float(ix) + 0.5) / Float(width)
                    let nx = (u - dab.x) / radius
                    let d2 = nx * nx + ny * ny
                    if d2 >= 1 { continue }
                    let falloff = 1 - d2
                    let weight = falloff * falloff
                    let index = iy * width + ix
                    accX[index] += dab.dx * weight
                    accY[index] += dab.dy * weight
                }
            }
        }

        var maxValue: Float = 0
        for index in 0..<count {
            maxValue = max(
                maxValue,
                max(abs(accX[index]), abs(accY[index]))
            )
        }
        if maxValue < 1e-6 { return nil }
        let shift = min(
            EditorLiquifyLimits.maxShift,
            maxValue * 1.02
        )
        var bytes = [UInt8](repeating: 0, count: count * 4)
        for index in 0..<count {
            let x = min(max(accX[index], -shift), shift)
            let y = min(max(accY[index], -shift), shift)
            let at = index * 4
            // 128 is the exact zero. 127 steps cover the signed range;
            // using 127.5 would give every untouched texel a 0.0003 UV shift,
            // visible as a one-pixel drift on a 6000 px export.
            bytes[at] = UInt8(
                min(max((128 + (x / shift) * 127).rounded(), 0), 255)
            )
            bytes[at + 1] = UInt8(
                min(max((128 + (y / shift) * 127).rounded(), 0), 255)
            )
            bytes[at + 2] = 0
            bytes[at + 3] = 255
        }
        return EditorLiquifyField(
            width: width,
            height: height,
            rgba: bytes,
            shift: shift
        )
    }
}
