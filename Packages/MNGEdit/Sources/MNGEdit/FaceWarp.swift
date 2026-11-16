import Foundation

/// A face box normalised to the oriented photo (0…1).
///
/// The web editor packs these boxes as `[cx, cy, 0.62·w, 0.72·h]` ellipses for
/// its vertex shader. The Swift side keeps the readable box and applies the
/// same packing in `FaceWarp`, so both clients warp the identical region.
public struct EditorFaceBox: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float
    /// Vision confidence when available; the warp sorts the strongest first.
    public var confidence: Float?

    public init(
        x: Float,
        y: Float,
        width: Float,
        height: Float,
        confidence: Float? = nil
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.confidence = confidence
    }
}

/// One face plus the optional landmark anchors measured by Vision.
///
/// Positions and radii are face-local: `(-1…1)` across the packed ellipse for
/// positions, `0…0.6` for radii. They mirror the 4×4 anchor texture of the web
/// editor (`packFaceAnchors`), so a state produced by one client renders the
/// same reshape in the other.
public struct EditorFaceAnchor: Equatable, Sendable {
    public var box: EditorFaceBox
    public var eyeLeft: SIMD2<Float>?
    public var eyeRight: SIMD2<Float>?
    public var nose: SIMD2<Float>?
    public var mouth: SIMD2<Float>?
    public var eyeLeftRadius: SIMD2<Float>?
    public var eyeRightRadius: SIMD2<Float>?
    public var noseRadius: SIMD2<Float>?
    public var mouthRadius: SIMD2<Float>?

    public init(
        box: EditorFaceBox,
        eyeLeft: SIMD2<Float>? = nil,
        eyeRight: SIMD2<Float>? = nil,
        nose: SIMD2<Float>? = nil,
        mouth: SIMD2<Float>? = nil,
        eyeLeftRadius: SIMD2<Float>? = nil,
        eyeRightRadius: SIMD2<Float>? = nil,
        noseRadius: SIMD2<Float>? = nil,
        mouthRadius: SIMD2<Float>? = nil
    ) {
        self.box = box
        self.eyeLeft = eyeLeft
        self.eyeRight = eyeRight
        self.nose = nose
        self.mouth = mouth
        self.eyeLeftRadius = eyeLeftRadius
        self.eyeRightRadius = eyeRightRadius
        self.noseRadius = noseRadius
        self.mouthRadius = mouthRadius
    }
}

/// The six reshape sliders in editor units (-100…100), exactly the keys and
/// the meaning of `Adjustments` in the web editor.
public struct FaceWarpParameters: Codable, Equatable, Sendable {
    public var faceSlim: Float
    public var jawline: Float
    public var chin: Float
    public var eyeSize: Float
    public var noseSize: Float
    public var mouthSize: Float

    public init(
        faceSlim: Float = 0,
        jawline: Float = 0,
        chin: Float = 0,
        eyeSize: Float = 0,
        noseSize: Float = 0,
        mouthSize: Float = 0
    ) {
        self.faceSlim = faceSlim
        self.jawline = jawline
        self.chin = chin
        self.eyeSize = eyeSize
        self.noseSize = noseSize
        self.mouthSize = mouthSize
    }

    public static let zero = FaceWarpParameters()

    public var isIdentity: Bool {
        // The shader early-outs below 0.001 in normalised units, i.e. 0.1 in
        // editor units; using the same threshold keeps preview and export in
        // step instead of drifting at ±0.05.
        let total = abs(faceSlim) + abs(jawline) + abs(chin)
            + abs(eyeSize) + abs(noseSize) + abs(mouthSize)
        return !total.isFinite || total < 0.1
    }

    /// Clamp every slider to the editor range and turn NaN into 0.
    public func clamped() -> FaceWarpParameters {
        func value(_ input: Float) -> Float {
            guard input.isFinite else { return 0 }
            return min(max(input, -100), 100)
        }
        return FaceWarpParameters(
            faceSlim: value(faceSlim),
            jawline: value(jawline),
            chin: value(chin),
            eyeSize: value(eyeSize),
            noseSize: value(noseSize),
            mouthSize: value(mouthSize)
        )
    }
}

/// The inverse face warp of the web editor, ported from `geometry.glsl`.
///
/// `warp(_:)` answers one question: *which source pixel does this output pixel
/// sample?* The preview and the full-resolution export evaluate the same
/// function, so a reshape looks identical at every zoom, and the identity case
/// returns the input bit-for-bit (no reampling, no drift on a neutral slider).
///
/// The Metal kernel of the next step will compute the same displacement on the
/// GPU; this CPU implementation is the reference used by the XCTest fixtures.
public struct FaceWarp: Equatable, Sendable {
    public var parameters: FaceWarpParameters
    /// At most four faces, strongest first — the limit of the web shader.
    public var anchors: [EditorFaceAnchor]

    public init(parameters: FaceWarpParameters = .zero, anchors: [EditorFaceAnchor] = []) {
        self.parameters = parameters
        self.anchors = FaceWarp.normalise(anchors)
    }

    /// True when the warp must be skipped entirely.
    public var isIdentity: Bool {
        parameters.isIdentity || anchors.isEmpty
    }

    /// Port of `warpFace(vec2 uv)`.
    ///
    /// Positive values slim the face/jaw, lengthen the chin and enlarge the
    /// eyes, nose and mouth. The loop, the ellipse weighting and the constants
    /// are the ones of the web shader; changing one here means changing it
    /// there too, or the two clients stop matching.
    public func warp(_ uv: SIMD2<Float>) -> SIMD2<Float> {
        guard !isIdentity else { return uv }
        let values = parameters.clamped()
        let slim = values.faceSlim / 100
        let jaw = values.jawline / 100
        let chin = values.chin / 100
        let eyes = values.eyeSize / 100
        let nose = values.noseSize / 100
        let mouth = values.mouthSize / 100

        var point = uv
        for anchor in anchors.prefix(4) {
            let box = anchor.box
            let center = SIMD2<Float>(
                min(max(box.x + box.width / 2, 0), 1),
                min(max(box.y + box.height / 2, 0), 1)
            )
            // packFaceAnchors stores clamp(0.62·w, 0.01, 1) and the shader
            // divides it back by 1.24, so the minimum half-size is 0.01/1.24.
            let packed = SIMD2<Float>(
                min(max(min(max(box.width, 0), 1) * 0.62, 0.01), 1),
                min(max(min(max(box.height, 0), 1) * 0.72, 0.01), 1)
            )
            let half = SIMD2<Float>(packed.x / 1.24, packed.y / 1.44)
            let local = (point - center) / half
            let ellipse = min(max(1 - (local.x * local.x + local.y * local.y), 0), 1)
            if ellipse <= 0.0001 { continue }
            let soft = ellipse * ellipse

            let features = anchor.resolved
            // Horizontal squeeze: zero at the centre and at the face edge,
            // strongest across the cheeks. Jawline weights the lower half more.
            let squeeze = slim * 0.16
                + jaw * 0.14 * smoothstep(-0.05, 0.75, local.y)
            point.x += squeeze * local.x * soft * half.x

            // Chin: the lower centre samples slightly above, so the chin
            // visually extends downwards without pulling the background in.
            let chinBand = smoothstep(0, 0.65, local.y) * exp(-local.x * local.x * 3)
            point.y -= chin * 0.14 * chinBand * ellipse * half.y

            if abs(eyes) > 0.001 {
                point -= scaledAround(
                    local, features.eyeLeft, features.eyeLeftRadius,
                    center + features.eyeLeft * half, point, eyes * 0.28
                )
                point -= scaledAround(
                    local, features.eyeRight, features.eyeRightRadius,
                    center + features.eyeRight * half, point, eyes * 0.28
                )
            }
            if abs(nose) > 0.001 {
                point -= scaledAround(
                    local, features.nose, features.noseRadius,
                    center + features.nose * half, point, nose * 0.26
                )
            }
            if abs(mouth) > 0.001 {
                point -= scaledAround(
                    local, features.mouth, features.mouthRadius,
                    center + features.mouth * half, point, mouth * 0.24
                )
            }
        }
        return SIMD2<Float>(
            min(max(point.x, 0), 1),
            min(max(point.y, 0), 1)
        )
    }

    // MARK: - Internals

    private func scaledAround(
        _ local: SIMD2<Float>,
        _ feature: SIMD2<Float>,
        _ radius: SIMD2<Float>,
        _ origin: SIMD2<Float>,
        _ point: SIMD2<Float>,
        _ strength: Float
    ) -> SIMD2<Float> {
        let delta = SIMD2<Float>((local.x - feature.x) / radius.x, (local.y - feature.y) / radius.y)
        let falloff = min(max(1 - (delta.x * delta.x + delta.y * delta.y), 0), 1)
        let weight = falloff * falloff
        guard weight > 0.0001 else { return .zero }
        return (point - origin) * (strength * weight)
    }

    private func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        guard edge1 > edge0 else { return value < edge0 ? 0 : 1 }
        let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Sort and clamp like `packFaceAnchors`: valid boxes only, strongest
    /// first, at most four — the shader loop bound.
    private static func normalise(_ input: [EditorFaceAnchor]) -> [EditorFaceAnchor] {
        input
            .filter { $0.box.width.isFinite && $0.box.height.isFinite && $0.box.width > 0 && $0.box.height > 0 }
            .sorted {
                let areaA = $0.box.width * $0.box.height
                let areaB = $1.box.width * $1.box.height
                return ($0.box.confidence ?? areaA) > ($1.box.confidence ?? areaB)
            }
            .prefix(4)
            .map { anchor in
                var copy = anchor
                copy.box.x = min(max(anchor.box.x.isFinite ? anchor.box.x : 0, 0), 1)
                copy.box.y = min(max(anchor.box.y.isFinite ? anchor.box.y : 0, 0), 1)
                copy.box.width = min(max(anchor.box.width, 0), 1)
                copy.box.height = min(max(anchor.box.height, 0), 1)
                return copy
            }
    }
}

private extension EditorFaceAnchor {
    /// Feature positions/radii with the web defaults filled in.
    var resolved: FaceWarpResolvedFeatures {
        FaceWarpResolvedFeatures(
            eyeLeft: clampedPoint(eyeLeft, fallback: SIMD2(-0.34, -0.18)),
            eyeRight: clampedPoint(eyeRight, fallback: SIMD2(0.34, -0.18)),
            nose: clampedPoint(nose, fallback: SIMD2(0, 0.10)),
            mouth: clampedPoint(mouth, fallback: SIMD2(0, 0.40)),
            eyeLeftRadius: clampedRadius(eyeLeftRadius, fallback: SIMD2(0.22, 0.16)),
            eyeRightRadius: clampedRadius(eyeRightRadius, fallback: SIMD2(0.22, 0.16)),
            noseRadius: clampedRadius(noseRadius, fallback: SIMD2(0.20, 0.24)),
            mouthRadius: clampedRadius(mouthRadius, fallback: SIMD2(0.30, 0.16))
        )
    }

    func clampedPoint(_ value: SIMD2<Float>?, fallback: SIMD2<Float>) -> SIMD2<Float> {
        guard let value, value.x.isFinite, value.y.isFinite else { return fallback }
        return SIMD2(min(max(value.x, -1), 1), min(max(value.y, -1), 1))
    }

    func clampedRadius(_ value: SIMD2<Float>?, fallback: SIMD2<Float>) -> SIMD2<Float> {
        guard let value, value.x.isFinite, value.y.isFinite else {
            return SIMD2(max(fallback.x, 0.02), max(fallback.y, 0.02))
        }
        return SIMD2(max(min(value.x, 0.6), 0.02), max(min(value.y, 0.6), 0.02))
    }
}

/// Shared by `FaceWarp` and the extension above.
struct FaceWarpResolvedFeatures {
    var eyeLeft: SIMD2<Float>
    var eyeRight: SIMD2<Float>
    var nose: SIMD2<Float>
    var mouth: SIMD2<Float>
    var eyeLeftRadius: SIMD2<Float>
    var eyeRightRadius: SIMD2<Float>
    var noseRadius: SIMD2<Float>
    var mouthRadius: SIMD2<Float>
}
