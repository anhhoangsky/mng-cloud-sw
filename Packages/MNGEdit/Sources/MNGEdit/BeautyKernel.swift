import Foundation

/// The four portrait sliders of the web editor in normalised units.
///
/// `smoothSkin`, `skinTexture` and `blemish` are 0…1; `skinTone` is −1…1.
/// The web shader skips the portrait pass when smoothing, blemish and tone are
/// all below 0.001, and so does this kernel: `skinTexture` only modulates a
/// smoothing that is already active.
struct BeautyParameters: Equatable, Sendable {
    var smoothSkin: Float
    var blemish: Float
    var skinTexture: Float
    var skinTone: Float

    init(
        smoothSkin: Float = 0,
        blemish: Float = 0,
        skinTexture: Float = 0,
        skinTone: Float = 0
    ) {
        self.smoothSkin = smoothSkin
        self.blemish = blemish
        self.skinTexture = skinTexture
        self.skinTone = skinTone
    }

    /// Mirror of the shader's early-out at 0.001 in normalised units.
    var isIdentity: Bool {
        let total = abs(smoothSkin) + abs(blemish) + abs(skinTone)
        return !total.isFinite || total < 0.001
    }

    func clamped() -> BeautyParameters {
        func value(_ input: Float, _ low: Float, _ high: Float) -> Float {
            guard input.isFinite else { return 0 }
            return min(max(input, low), high)
        }
        return BeautyParameters(
            smoothSkin: value(smoothSkin, 0, 1),
            blemish: value(blemish, 0, 1),
            skinTexture: value(skinTexture, 0, 1),
            skinTone: value(skinTone, -1, 1)
        )
    }
}

/// One skin/feature mask in the layout of the web beauty bundle:
/// R = skin, G = protected features (eyes, brows, hair, beard), B = lips,
/// A = 255.
///
/// The mask lives in the stored source photo, exactly like the web texture and
/// the Vision face boxes, so the renderer can sample it with the same UV it
/// uses for the source pixels.
public struct EditorBeautyMask: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]

    public init?(width: Int, height: Int, rgba: [UInt8]) {
        guard width > 0,
              height > 0,
              rgba.count == width * height * 4 else {
            return nil
        }
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    /// Bilinear sample with clamp-to-edge, matching the `LINEAR` filter and
    /// `CLAMP_TO_EDGE` wrap of the web mask texture.
    public func sample(_ uv: SIMD2<Float>) -> SIMD3<Float> {
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

        return SIMD3<Float>(channel(0), channel(1), channel(2))
    }

    /// Average channel weights, the same numbers `beautyMaskStats` reports in
    /// the web test page.
    public var statistics: EditorBeautyMaskStatistics {
        guard !rgba.isEmpty else {
            return EditorBeautyMaskStatistics(skin: 0, protect: 0, lips: 0)
        }
        var skin = 0
        var protect = 0
        var lips = 0
        var index = 0
        while index + 3 < rgba.count {
            skin += Int(rgba[index])
            protect += Int(rgba[index + 1])
            lips += Int(rgba[index + 2])
            index += 4
        }
        let count = max(1, width * height * 255)
        return EditorBeautyMaskStatistics(
            skin: Double(skin) / Double(count),
            protect: Double(protect) / Double(count),
            lips: Double(lips) / Double(count)
        )
    }
}

public struct EditorBeautyMaskStatistics: Equatable, Sendable {
    public var skin: Double
    public var protect: Double
    public var lips: Double

    public init(skin: Double, protect: Double, lips: Double) {
        self.skin = skin
        self.protect = protect
        self.lips = lips
    }
}

/// Builds the R/G/B beauty mask of `src/beauty/mask.ts`.
///
/// Face boxes are the same normalised, top-down boxes Vision reports and the
/// web server returns. The source is downscaled to `maxSize` first (640 is
/// enough for a 1080 px preview and keeps a 20 MP photo cheap), then the mask
/// is built at that resolution and feathered with the web's separable box
/// blur. The result is resolution-independent because the shader samples it by
/// UV.
public enum EditorBeautyMaskBuilder {
    public static func build(
        sourceWidth: Int,
        sourceHeight: Int,
        rgba: [UInt8],
        faces: [EditorFaceBox] = [],
        maxSize: Int = 640,
        feather: Int = 2
    ) -> EditorBeautyMask? {
        guard sourceWidth > 0,
              sourceHeight > 0,
              rgba.count == sourceWidth * sourceHeight * 4 else {
            return nil
        }
        let boundedMax = min(max(maxSize, 64), 2048)
        let scale = min(
            1,
            Float(boundedMax) / Float(max(1, max(sourceWidth, sourceHeight)))
        )
        let width = max(1, Int((Float(sourceWidth) * scale).rounded()))
        let height = max(1, Int((Float(sourceHeight) * scale).rounded()))
        let resized = resize(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            rgba: rgba,
            width: width,
            height: height
        )

        let boxes = faces
            .filter { $0.width > 0 && $0.height > 0 }
            .sorted { ($0.confidence ?? 0) > ($1.confidence ?? 0) }
            .prefix(4)
        let items: [Face] = boxes.map { face in
            Face(
                x: face.x,
                y: face.y,
                w: face.width,
                h: face.height,
                cx: face.x + face.width / 2,
                cy: face.y + face.height / 2,
                rx: face.width * 0.62,
                ry: face.height * 0.72,
                luma: faceLuma(
                    resized.rgba,
                    width: width,
                    height: height,
                    face: face
                )
            )
        }
        let reference = sampleSkin(
            resized.rgba,
            width: width,
            height: height,
            faces: Array(boxes)
        )

        var out = [UInt8](repeating: 0, count: width * height * 4)
        out.withUnsafeMutableBufferPointer { pixels in
            resized.rgba.withUnsafeBufferPointer { source in
                for py in 0..<height {
                    let v = (Float(py) + 0.5) / Float(height)
                    for px in 0..<width {
                        let u = (Float(px) + 0.5) / Float(width)
                        let at = (py * width + px) * 4
                        let r = Float(source[at]) / 255
                        let g = Float(source[at + 1]) / 255
                        let b = Float(source[at + 2]) / 255
                        let y = luma(r, g, b)
                        let cr = 0.5 + 0.5 * r - 0.418688 * g - 0.081312 * b
                        let cb = 0.5 - 0.168736 * r - 0.331264 * g + 0.5 * b

                        let lumaGate = smoothstep(0.06, 0.18, y)
                            * (1 - smoothstep(0.93, 1.0, y))
                        let chroma: Float
                        if let reference {
                            let dcr = cr - reference.cr
                            let dcb = cb - reference.cb
                            let distance = (dcr * dcr + dcb * dcb).squareRoot()
                            chroma = (1 - smoothstep(0.035, 0.085, distance)) * lumaGate
                        } else {
                            chroma =
                                smoothstep(0.50, 0.55, cr) * (1 - smoothstep(0.68, 0.72, cr))
                                * smoothstep(0.30, 0.34, cb) * (1 - smoothstep(0.46, 0.50, cb))
                                * lumaGate
                        }

                        var face = Float(0)
                        var protect = Float(0)
                        var lips = Float(0)
                        var best: Face?
                        var bestWeight = Float(0)
                        for item in items {
                            let dx = (u - item.cx) / max(0.0001, item.rx)
                            let dy = (v - item.cy) / max(0.0001, item.ry)
                            let weight = 1 - smoothstep(
                                0.72,
                                1.0,
                                (dx * dx + dy * dy).squareRoot()
                            )
                            if weight > bestWeight {
                                bestWeight = weight
                                best = item
                            }
                            face = max(face, weight)
                        }

                        if let best {
                            let lu = (u - best.x) / max(0.0001, best.w)
                            let lv = (v - best.y) / max(0.0001, best.h)
                            // Facial hair, brows and eyes are much darker than
                            // the face median. A relative threshold keeps dark
                            // skin from being treated as hair.
                            let dark = 1 - smoothstep(
                                best.luma * 0.46,
                                best.luma * 0.72,
                                y
                            )
                            let eyeL = ellipse(lu, lv, 0.32, 0.42, 0.14, 0.095) * dark
                            let eyeR = ellipse(lu, lv, 0.68, 0.42, 0.14, 0.095) * dark
                            let browL = ellipse(lu, lv, 0.32, 0.31, 0.19, 0.06) * dark
                            let browR = ellipse(lu, lv, 0.68, 0.31, 0.19, 0.06) * dark
                            let hair =
                                ellipse(lu, lv, 0.5, 0.1, 0.5, 0.14) * dark
                                + ellipse(lu, lv, 0.04, 0.5, 0.16, 0.5) * dark
                                + ellipse(lu, lv, 0.96, 0.5, 0.16, 0.5) * dark
                            let beard = ellipse(lu, lv, 0.5, 0.84, 0.36, 0.18) * dark
                            lips =
                                ellipse(lu, lv, 0.5, 0.7, 0.17, 0.075)
                                * smoothstep(0.05, 0.16, r - max(g, b))
                            protect = clamp01(
                                max(eyeL, max(eyeR, max(browL, max(browR, max(hair, max(beard, lips * 0.55))))))
                            )
                        }

                        let gate = items.isEmpty ? Float(1) : max(0.3, face)
                        let skin = clamp01(chroma * gate * (1 - protect))
                        pixels[at] = UInt8(min(max((skin * 255).rounded(), 0), 255))
                        pixels[at + 1] = UInt8(min(max((protect * 255).rounded(), 0), 255))
                        pixels[at + 2] = UInt8(min(max((lips * 255).rounded(), 0), 255))
                        pixels[at + 3] = 255
                    }
                }
            }
        }

        boxBlur(
            &out,
            width: width,
            height: height,
            radius: min(max(feather, 0), 8)
        )
        return EditorBeautyMask(width: width, height: height, rgba: out)
    }

    private struct Face {
        var x: Float
        var y: Float
        var w: Float
        var h: Float
        var cx: Float
        var cy: Float
        var rx: Float
        var ry: Float
        var luma: Float
    }

    private struct SkinReference {
        var cr: Float
        var cb: Float
    }

    private static func resize(
        sourceWidth: Int,
        sourceHeight: Int,
        rgba: [UInt8],
        width: Int,
        height: Int
    ) -> (rgba: [UInt8], width: Int, height: Int) {
        if width == sourceWidth && height == sourceHeight {
            return (rgba, width, height)
        }
        var out = [UInt8](repeating: 0, count: width * height * 4)
        let scaleX = Float(sourceWidth) / Float(width)
        let scaleY = Float(sourceHeight) / Float(height)
        rgba.withUnsafeBufferPointer { source in
            out.withUnsafeMutableBufferPointer { pixels in
                for y in 0..<height {
                    let sy = (Float(y) + 0.5) * scaleY - 0.5
                    for x in 0..<width {
                        let sx = (Float(x) + 0.5) * scaleX - 0.5
                        let at = (y * width + x) * 4
                        let value = bilinear(
                            source,
                            sourceWidth: sourceWidth,
                            sourceHeight: sourceHeight,
                            x: sx,
                            y: sy
                        )
                        pixels[at] = value.x
                        pixels[at + 1] = value.y
                        pixels[at + 2] = value.z
                        pixels[at + 3] = value.w
                    }
                }
            }
        }
        return (out, width, height)
    }

    private static func bilinear(
        _ pixels: UnsafeBufferPointer<UInt8>,
        sourceWidth: Int,
        sourceHeight: Int,
        x: Float,
        y: Float
    ) -> SIMD4<UInt8> {
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let tx = x - Float(x0)
        let ty = y - Float(y0)
        let x0i = min(max(x0, 0), sourceWidth - 1)
        let y0i = min(max(y0, 0), sourceHeight - 1)
        let x1i = min(max(x0 + 1, 0), sourceWidth - 1)
        let y1i = min(max(y0 + 1, 0), sourceHeight - 1)
        let at00 = (y0i * sourceWidth + x0i) * 4
        let at10 = (y0i * sourceWidth + x1i) * 4
        let at01 = (y1i * sourceWidth + x0i) * 4
        let at11 = (y1i * sourceWidth + x1i) * 4

        func blend(_ offset: Int) -> UInt8 {
            let top = Float(pixels[at00 + offset])
                + (Float(pixels[at10 + offset]) - Float(pixels[at00 + offset])) * tx
            let bottom = Float(pixels[at01 + offset])
                + (Float(pixels[at11 + offset]) - Float(pixels[at01 + offset])) * tx
            let value = top + (bottom - top) * ty
            return UInt8(min(max(value.rounded(), 0), 255))
        }
        return SIMD4<UInt8>(blend(0), blend(1), blend(2), blend(3))
    }

    private static func faceLuma(
        _ data: [UInt8],
        width: Int,
        height: Int,
        face: EditorFaceBox
    ) -> Float {
        var values: [Float] = []
        values.reserveCapacity(49)
        let cx = face.x + face.width / 2
        let cy = face.y + face.height / 2
        let rx = face.width * 0.42
        let ry = face.height * 0.42
        for row in 0..<7 {
            for col in 0..<7 {
                let u = (Float(col) + 0.5) / 7
                let v = (Float(row) + 0.5) / 7
                let px = Int(((cx + (u * 2 - 1) * rx) * Float(width - 1)).rounded())
                let py = Int(((cy + (v * 2 - 1) * ry) * Float(height - 1)).rounded())
                guard px >= 0, py >= 0, px < width, py < height else { continue }
                let at = (py * width + px) * 4
                values.append(
                    luma(
                        Float(data[at]) / 255,
                        Float(data[at + 1]) / 255,
                        Float(data[at + 2]) / 255
                    )
                )
            }
        }
        return values.isEmpty ? 0.55 : median(values)
    }

    private static func sampleSkin(
        _ data: [UInt8],
        width: Int,
        height: Int,
        faces: [EditorFaceBox]
    ) -> SkinReference? {
        var crs: [Float] = []
        var cbs: [Float] = []
        let points: [(Float, Float)] = [(0.3, 0.62), (0.7, 0.62), (0.5, 0.26)]
        for face in faces {
            for point in points {
                let cx = Int(((face.x + point.0 * face.width) * Float(width - 1)).rounded())
                let cy = Int(((face.y + point.1 * face.height) * Float(height - 1)).rounded())
                for dy in -2...2 {
                    for dx in -2...2 {
                        let px = cx + dx
                        let py = cy + dy
                        guard px >= 0, py >= 0, px < width, py < height else { continue }
                        let at = (py * width + px) * 4
                        let r = Float(data[at]) / 255
                        let g = Float(data[at + 1]) / 255
                        let b = Float(data[at + 2]) / 255
                        crs.append(0.5 + 0.5 * r - 0.418688 * g - 0.081312 * b)
                        cbs.append(0.5 - 0.168736 * r - 0.331264 * g + 0.5 * b)
                    }
                }
            }
        }
        guard crs.count >= 12 else { return nil }
        return SkinReference(cr: median(crs), cb: median(cbs))
    }

    private static func boxBlur(
        _ data: inout [UInt8],
        width: Int,
        height: Int,
        radius: Int
    ) {
        guard radius >= 1, width > 0, height > 0 else { return }
        var temp = [UInt8](repeating: 0, count: data.count)
        let span = radius * 2 + 1

        data.withUnsafeBufferPointer { source in
            temp.withUnsafeMutableBufferPointer { target in
                for y in 0..<height {
                    for channel in 0..<3 {
                        var sum = 0
                        for x in -radius...radius {
                            let sx = min(width - 1, max(0, x))
                            sum += Int(source[(y * width + sx) * 4 + channel])
                        }
                        for x in 0..<width {
                            let at = (y * width + x) * 4 + channel
                            target[at] = UInt8(min(max((sum + span / 2) / span, 0), 255))
                            let outX = min(width - 1, max(0, x - radius))
                            let inX = min(width - 1, max(0, x + radius + 1))
                            sum += Int(source[(y * width + inX) * 4 + channel])
                            sum -= Int(source[(y * width + outX) * 4 + channel])
                        }
                    }
                }
            }
        }

        temp.withUnsafeBufferPointer { source in
            data.withUnsafeMutableBufferPointer { target in
                for x in 0..<width {
                    for channel in 0..<3 {
                        var sum = 0
                        for y in -radius...radius {
                            let sy = min(height - 1, max(0, y))
                            sum += Int(source[(sy * width + x) * 4 + channel])
                        }
                        for y in 0..<height {
                            let at = (y * width + x) * 4 + channel
                            target[at] = UInt8(min(max((sum + span / 2) / span, 0), 255))
                            let outY = min(height - 1, max(0, y - radius))
                            let inY = min(height - 1, max(0, y + radius + 1))
                            sum += Int(source[(inY * width + x) * 4 + channel])
                            sum -= Int(source[(outY * width + x) * 4 + channel])
                        }
                    }
                }
            }
        }
    }

    private static func ellipse(
        _ u: Float,
        _ v: Float,
        _ cu: Float,
        _ cv: Float,
        _ ru: Float,
        _ rv: Float
    ) -> Float {
        let du = (u - cu) / max(0.0001, ru)
        let dv = (v - cv) / max(0.0001, rv)
        return 1 - smoothstep(0.72, 1.05, (du * du + dv * dv).squareRoot())
    }

    private static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count >> 1]
    }

    private static func clamp01(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}

/// A `[UInt8]` source buffer prepared for the beauty taps.
///
/// The renderer already has the pixels borrowed for the whole pass; passing
/// this view keeps every tap a bilinear read instead of a new array.
struct BeautySampleSource {
    let width: Int
    let height: Int
    let pixels: UnsafeBufferPointer<UInt8>

    /// One source texel in UV units, the shader's `u_texel`.
    var texel: SIMD2<Float> {
        SIMD2<Float>(1 / Float(max(1, width)), 1 / Float(max(1, height)))
    }

    func sample(_ uv: SIMD2<Float>) -> SIMD3<Float> {
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
            let top = Float(pixels[at00 + offset])
                + (Float(pixels[at10 + offset]) - Float(pixels[at00 + offset])) * tx
            let bottom = Float(pixels[at01 + offset])
                + (Float(pixels[at11 + offset]) - Float(pixels[at01 + offset])) * tx
            return (top + (bottom - top) * ty) / 255
        }
        return SIMD3<Float>(channel(0), channel(1), channel(2))
    }
}

/// Port of section 4 of `src/core/shader/modules/main.glsl`.
///
/// `apply(_:uv:source:)` is called once per output pixel after the face warp
/// and before the colour pipeline. All tap offsets are UV distances, not pixel
/// distances, so the preview and the full-resolution export show the same
/// smoothing around the same facial features.
struct BeautyKernel: Sendable {
    let parameters: BeautyParameters
    let mask: EditorBeautyMask?
    let faces: [BeautyFace]

    struct BeautyFace: Sendable {
        var center: SIMD2<Float>
        var half: SIMD2<Float>
    }

    init(
        parameters: BeautyParameters,
        mask: EditorBeautyMask?,
        anchors: [EditorFaceAnchor]
    ) {
        self.parameters = parameters.clamped()
        self.mask = mask
        self.faces = FaceWarp.normalize(anchors).prefix(4).map { anchor in
            let box = anchor.box
            return BeautyFace(
                center: SIMD2<Float>(
                    box.x + box.width / 2,
                    box.y + box.height / 2
                ),
                half: SIMD2<Float>(
                    max(box.width * 0.62, 0.0001),
                    max(box.height * 0.72, 0.0001)
                )
            )
        }
    }

    var isIdentity: Bool { parameters.isIdentity }

    /// Frozen tap offsets: allocating these inside the pixel loop turned every
    /// preview frame into hundreds of thousands of small arrays.
    private static let smoothOffsets: [SIMD2<Float>] = [
        SIMD2(0.0045, 0),
        SIMD2(-0.0045, 0),
        SIMD2(0, 0.0045),
        SIMD2(0, -0.0045),
        SIMD2(0.0045, 0.0045),
        SIMD2(-0.0045, 0.0045),
        SIMD2(0.0045, -0.0045),
        SIMD2(-0.0045, -0.0045),
    ]

    private static let blemishOffsets: [SIMD2<Float>] = [
        SIMD2(0.011, 0),
        SIMD2(-0.011, 0),
        SIMD2(0, 0.011),
        SIMD2(0, -0.011),
        SIMD2(0.011, 0.011),
        SIMD2(-0.011, 0.011),
        SIMD2(0.011, -0.011),
        SIMD2(-0.011, -0.011),
    ]

    /// Apply the four sliders to one sampled source colour.
    ///
    /// `base` is the already sampled source pixel, `uv` its position in stored
    /// source UV. `source` supplies the neighbouring taps.
    func apply(
        _ base: SIMD3<Float>,
        uv: SIMD2<Float>,
        source: BeautySampleSource
    ) -> SIMD3<Float> {
        guard !isIdentity else { return base }
        let sampledMask = mask?.sample(uv)
        let skin = sampledMask?.x ?? skinWeight(base, uv)
        let protect = sampledMask?.y ?? 0
        let lips = sampledMask?.z ?? 0
        let amount = min(max(skin * (1 - protect), 0), 1)
        guard amount > 0.01 else { return base }

        let baseLuma = luma(base)
        var c = base

        if parameters.smoothSkin > 0.001 {
            let invSigma2: Float = 1 / (0.045 * 0.045)
            var acc = c
            var weightSum = Float(1)
            for offset in Self.smoothOffsets {
                let tap = source.sample(uv + offset)
                let delta = luma(tap) - baseLuma
                let weight = exp(-delta * delta * invSigma2)
                acc += tap * weight
                weightSum += weight
            }
            let soft = acc / weightSum
            let detail = length(base - soft)
            let keep = smoothstep(0.025, 0.14, detail)
            // skinTexture 0 = strongest smoothing, 1 = keep pores.
            let preserve = mix(0.35, 0.95, parameters.skinTexture)
            let strength = amount * parameters.smoothSkin * 0.92
            c = mix(base, soft, strength * (1 - keep * preserve))
            c += (base - soft) * (parameters.skinTexture * 0.3 * strength)
        }

        if parameters.blemish > 0.001 {
            // Spot removal deliberately averages across the blemish edge, so
            // it does not use the edge-aware weights that preserve features.
            var average = SIMD3<Float>(repeating: 0)
            for offset in Self.blemishOffsets {
                average += source.sample(uv + offset)
            }
            average = average / Float(8)
            let dark = smoothstep(0.02, 0.07, luma(average) - baseLuma)
            let delta = c - average
            let red = smoothstep(
                0.035,
                0.11,
                delta.x - max(delta.y, delta.z)
            )
            let spot = max(dark, red * 0.85)
            c = mix(
                c,
                average,
                amount * parameters.blemish * spot * 0.85
            )
        }

        if abs(parameters.skinTone) > 0.001 {
            let target = parameters.skinTone > 0
                ? c * SIMD3<Float>(1.035, 1.005, 0.965)
                : c * SIMD3<Float>(0.975, 1.0, 1.025)
            let tone = amount * abs(parameters.skinTone) * 0.7 * (1 - lips * 0.45)
            c = mix(c, target, tone)
        }
        return SIMD3<Float>(
            min(max(c.x, 0), 1),
            min(max(c.y, 0), 1),
            min(max(c.z, 0), 1)
        )
    }

    /// Port of `skinWeight` in `portrait.glsl`, used when no R/G/B mask is
    /// attached (or when a caller never built one).
    private func skinWeight(
        _ color: SIMD3<Float>,
        _ uv: SIMD2<Float>
    ) -> Float {
        let y = luma(color)
        let cb = -0.168736 * color.x - 0.331264 * color.y + 0.5 * color.z + 0.5
        let cr = 0.5 * color.x - 0.418688 * color.y - 0.081312 * color.z + 0.5
        let chroma =
            smoothstep(0.30, 0.38, cr) * (1 - smoothstep(0.60, 0.70, cr))
            * smoothstep(0.28, 0.36, cb) * (1 - smoothstep(0.54, 0.64, cb))
            * smoothstep(0.10, 0.22, y) * (1 - smoothstep(0.90, 1.0, y))
        var face = Float(0)
        for item in faces {
            let p = (uv - item.center) / item.half
            face = max(face, 1 - smoothstep(0.72, 1.0, length(p)))
        }
        return min(max(max(chroma, face * 0.9), 0), 1)
    }

    private func luma(_ color: SIMD3<Float>) -> Float {
        0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z
    }

    private func length(_ value: SIMD2<Float>) -> Float {
        (value.x * value.x + value.y * value.y).squareRoot()
    }

    private func length(_ value: SIMD3<Float>) -> Float {
        (value.x * value.x + value.y * value.y + value.z * value.z).squareRoot()
    }

    private func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }

    private func mix(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ t: Float
    ) -> SIMD3<Float> {
        a + (b - a) * t
    }

    private func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        guard edge1 > edge0 else { return value < edge0 ? 0 : 1 }
        let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

private func luma(_ color: SIMD3<Float>) -> Float {
    0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z
}

private func luma(_ r: Float, _ g: Float, _ b: Float) -> Float {
    0.2126 * r + 0.7152 * g + 0.0722 * b
}

private func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
    guard edge1 > edge0 else { return value < edge0 ? 0 : 1 }
    let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
