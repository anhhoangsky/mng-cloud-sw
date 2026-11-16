import Foundation

/// The three detail sliders of the web editor in normalised units.
///
/// `clarity` is −1…1, `sharpen` and `denoise` are 0…1. The shader skips each
/// step at 0.001; the three values are independent, exactly like
/// `u_clarity`, `u_sharpen` and `u_denoise`.
struct DetailParameters: Equatable, Sendable {
    var clarity: Float
    var sharpen: Float
    var denoise: Float

    init(clarity: Float = 0, sharpen: Float = 0, denoise: Float = 0) {
        self.clarity = clarity
        self.sharpen = sharpen
        self.denoise = denoise
    }

    var isIdentity: Bool {
        let total = abs(clarity) + abs(sharpen) + abs(denoise)
        return !total.isFinite || total < 0.001
    }

    func clamped() -> DetailParameters {
        func value(_ input: Float, _ low: Float, _ high: Float) -> Float {
            guard input.isFinite else { return 0 }
            return min(max(input, low), high)
        }
        return DetailParameters(
            clarity: value(clarity, -1, 1),
            sharpen: value(sharpen, 0, 1),
            denoise: value(denoise, 0, 1)
        )
    }
}

/// Port of sections 1–3 of `src/core/shader/modules/main.glsl`.
///
/// The three passes run after the face warp and the liquify field and before
/// the beauty pass and the colour stack. Every tap samples the original source
/// texture around the mapped UV, exactly like `texture2D(u_texture, uv + o)`
/// in the shader; the radii are source-pixel distances converted to UV through
/// the source size.
///
/// The web export renders with `u_quality = 1` (8 taps for denoise and
/// clarity), and the preview uses fewer taps on small canvases. This kernel
/// always uses the export path so the app's preview and its full-resolution
/// export smooth and sharpen the same area instead of diverging by zoom level.
struct DetailKernel: Sendable {
    let parameters: DetailParameters

    init(parameters: DetailParameters) {
        self.parameters = parameters.clamped()
    }

    var isIdentity: Bool { parameters.isIdentity }

    func apply(
        _ base: SIMD3<Float>,
        uv: SIMD2<Float>,
        source: BeautySampleSource
    ) -> SIMD3<Float> {
        var c = base
        var lc = luma(c)
        let texel = source.texel

        // 1. Edge-aware denoise.
        if parameters.denoise > 0.001 {
            let sigma = 0.022 + parameters.denoise * 0.09
            let invSigma2 = 1 / max(0.0001, sigma * sigma)
            var acc = c
            var weightSum: Float = 1
            let ox = texel.x * 2.5
            let oy = texel.y * 2.5

            func addTap(_ x: Float, _ y: Float) {
                let tap = source.sample(uv + SIMD2<Float>(x, y))
                let delta = luma(tap) - lc
                let weight = exp(-delta * delta * invSigma2)
                acc += tap * weight
                weightSum += weight
            }

            addTap(ox, 0)
            addTap(-ox, 0)
            addTap(0, oy)
            addTap(0, -oy)
            addTap(ox, oy)
            addTap(-ox, oy)
            addTap(ox, -oy)
            addTap(-ox, -oy)

            c = mix(c, acc / weightSum, parameters.denoise * 0.9)
            lc = luma(c)
        }

        // 2. Clarity: halo-limited local contrast on the original detail.
        if abs(parameters.clarity) > 0.001 {
            let ox = texel.x * 10
            let oy = texel.y * 10
            var blur = c
            blur += source.sample(uv + SIMD2<Float>(ox, 0))
            blur += source.sample(uv + SIMD2<Float>(-ox, 0))
            blur += source.sample(uv + SIMD2<Float>(0, oy))
            blur += source.sample(uv + SIMD2<Float>(0, -oy))
            blur += source.sample(uv + SIMD2<Float>(ox, oy))
            blur += source.sample(uv + SIMD2<Float>(-ox, oy))
            blur += source.sample(uv + SIMD2<Float>(ox, -oy))
            blur += source.sample(uv + SIMD2<Float>(-ox, -oy))
            blur /= 9

            let detail = min(max(lc - luma(blur), -0.18), 0.18)
            let mid = 1 - smoothstep(0.72, 1, lc) * 0.55
            c += SIMD3<Float>(
                repeating: detail * parameters.clarity * 1.25 * mid
            )
            lc = luma(c)
        }

        // 3. Small-radius sharpening with a noise floor.
        if parameters.sharpen > 0.001 {
            let ox = texel.x
            let oy = texel.y
            let localLuma =
                luma(source.sample(uv + SIMD2<Float>(ox, 0)))
                + luma(source.sample(uv + SIMD2<Float>(-ox, 0)))
                + luma(source.sample(uv + SIMD2<Float>(0, oy)))
                + luma(source.sample(uv + SIMD2<Float>(0, -oy)))
            let detail = min(max(lc - localLuma * 0.25, -0.2), 0.2)
            let mask = smoothstep(0.006, 0.022, abs(detail))
            c += SIMD3<Float>(
                repeating: detail * mask * parameters.sharpen * 2.2
            )
        }

        return c
    }
}

private func luma(_ color: SIMD3<Float>) -> Float {
    0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z
}

private func mix(_ start: SIMD3<Float>, _ end: SIMD3<Float>, _ amount: Float) -> SIMD3<Float> {
    start + (end - start) * amount
}

private func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
    guard edge1 > edge0 else { return value < edge0 ? 0 : 1 }
    let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
