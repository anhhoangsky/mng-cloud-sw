import XCTest
@testable import MNGEdit

/// The portrait sliders through the real `Editor` render path, against a
/// synthetic face with the same normalised geometry as `test-beauty.html`:
/// cheek grain, dark eyes/brows, red lips and one dark blemish.
final class BeautyKernelRenderTests: XCTestCase {
    private let size = 256
    private let face = EditorFaceBox(
        x: 0.2,
        y: 0.12,
        width: 0.6,
        height: 0.76,
        confidence: 1
    )

    private struct Portrait {
        var rgba: [UInt8]
        var mask: EditorBeautyMask
    }

    // MARK: - Fixture

    private func portrait() throws -> Portrait {
        var rgba = [UInt8](repeating: 0, count: size * size * 4)
        var random = LCG(seed: 0x5EED_1234)
        let faceRect = (
            x0: face.x,
            y0: face.y,
            x1: face.x + face.width,
            y1: face.y + face.height
        )
        let blemish = SIMD2<Float>(0.34, 0.62)

        for y in 0..<size {
            for x in 0..<size {
                let u = (Float(x) + 0.5) / Float(size)
                let v = (Float(y) + 0.5) / Float(size)
                var color = SIMD3<Int>(36, 48, 51)

                let hairCenter = SIMD2<Float>(
                    face.x + face.width / 2,
                    face.y + face.height * 0.36
                )
                if ellipse(u, v, hairCenter, SIMD2(face.width * 0.58, face.height * 0.55)) {
                    color = SIMD3(23, 17, 14)
                }
                if u >= face.x + face.width * 0.36,
                   u <= face.x + face.width * 0.64,
                   v >= face.y + face.height * 0.82,
                   v <= face.y + face.height * 1.22 {
                    color = SIMD3(191, 133, 97)
                }
                let faceCenter = SIMD2<Float>(
                    face.x + face.width / 2,
                    face.y + face.height / 2
                )
                if ellipse(u, v, faceCenter, SIMD2(face.width * 0.44, face.height * 0.5)) {
                    color = SIMD3(201, 143, 107)
                }
                if ellipse(
                    u, v,
                    SIMD2(face.x + face.width * 0.32, face.y + face.height * 0.31),
                    SIMD2(face.width * 0.11, face.height * 0.045)
                ) || ellipse(
                    u, v,
                    SIMD2(face.x + face.width * 0.68, face.y + face.height * 0.31),
                    SIMD2(face.width * 0.11, face.height * 0.045)
                ) {
                    color = SIMD3(44, 28, 22)
                }
                if ellipse(
                    u, v,
                    SIMD2(face.x + face.width * 0.32, face.y + face.height * 0.42),
                    SIMD2(face.width * 0.075, face.height * 0.05)
                ) || ellipse(
                    u, v,
                    SIMD2(face.x + face.width * 0.68, face.y + face.height * 0.42),
                    SIMD2(face.width * 0.075, face.height * 0.05)
                ) {
                    color = SIMD3(26, 17, 20)
                }
                if ellipse(
                    u, v,
                    SIMD2(face.x + face.width * 0.5, face.y + face.height * 0.7),
                    SIMD2(face.width * 0.1, face.height * 0.035)
                ) {
                    color = SIMD3(168, 79, 82)
                }

                if u >= faceRect.x0, u <= faceRect.x1,
                   v >= faceRect.y0, v <= faceRect.y1 {
                    let noise = (random.nextFloat() - 0.5) * 18
                    color = SIMD3(
                        clamp(Int(Float(color.x) + noise), 0, 255),
                        clamp(Int(Float(color.y) + noise), 0, 255),
                        clamp(Int(Float(color.z) + noise), 0, 255)
                    )
                }

                let spotRadius = Float(5) / 512
                let dx = (u - blemish.x) / spotRadius
                let dy = (v - blemish.y) / spotRadius
                if dx * dx + dy * dy <= 1 {
                    color = SIMD3(138, 58, 50)
                }

                let offset = (y * size + x) * 4
                rgba[offset] = UInt8(color.x)
                rgba[offset + 1] = UInt8(color.y)
                rgba[offset + 2] = UInt8(color.z)
                rgba[offset + 3] = 255
            }
        }

        let mask = try XCTUnwrap(
            EditorBeautyMaskBuilder.build(
                sourceWidth: size,
                sourceHeight: size,
                rgba: rgba,
                faces: [face],
                maxSize: 512,
                feather: 2
            )
        )
        return Portrait(rgba: rgba, mask: mask)
    }

    private func editor(
        _ portrait: Portrait,
        adjustments: EditorAdjustments = .zero,
        mask: EditorBeautyMask? = nil,
        anchors: [EditorFaceAnchor] = []
    ) throws -> Editor {
        var editor = try Editor(
            width: UInt32(size),
            height: UInt32(size),
            rgba: portrait.rgba
        )
        editor.setFaceAnchors(anchors)
        editor.setBeautyMask(mask)
        editor.setAdjustments(adjustments)
        return editor
    }

    private func render(_ editor: Editor) -> [UInt8] {
        var copy = editor
        return copy.renderPreview(maxSide: UInt32(size))
    }

    // MARK: - Mask

    func testMaskBuilderFindsSkinAndProtectsFeatures() throws {
        let portrait = try portrait()
        let mask = portrait.mask
        XCTAssertEqual(mask.width, size)
        XCTAssertEqual(mask.height, size)

        let stats = mask.statistics
        XCTAssertGreaterThan(stats.skin, 0.05)
        XCTAssertGreaterThan(stats.protect, 0.005)
        XCTAssertGreaterThan(stats.lips, 0.001)

        let cheek = mask.sample(SIMD2<Float>(0.64, 0.58))
        XCTAssertGreaterThan(cheek.x, 0.5, "the cheek must be skin")
        XCTAssertLessThan(cheek.y, 0.2, "the cheek must not be protected")

        let eye = mask.sample(SIMD2<Float>(0.392, 0.439))
        XCTAssertGreaterThan(eye.y, 0.5, "the eye must be protected")
    }

    // MARK: - Identity

    func testNeutralBeautyWithMaskIsByteIdentical() throws {
        let portrait = try portrait()
        let plain = render(
            try editor(portrait, mask: nil, anchors: [])
        )
        let masked = render(
            try editor(
                portrait,
                mask: portrait.mask,
                anchors: [EditorFaceAnchor(box: face)]
            )
        )
        XCTAssertEqual(plain, masked)
    }

    func testZeroMaskIsIdentityEvenWithEverySliderAtMaximum() throws {
        let portrait = try portrait()
        let zero = try XCTUnwrap(
            EditorBeautyMask(
                width: 64,
                height: 64,
                rgba: [UInt8](repeating: 0, count: 64 * 64 * 4)
            )
        )
        let baseline = render(try editor(portrait, mask: nil))
        let beauty = render(
            try editor(
                portrait,
                adjustments: EditorAdjustments(
                    smoothSkin: 100,
                    blemish: 100,
                    skinTexture: 0,
                    skinTone: 100
                ),
                mask: zero,
                anchors: [EditorFaceAnchor(box: face)]
            )
        )
        XCTAssertEqual(baseline, beauty)
    }

    // MARK: - Smoothing

    func testSmoothingLowersCheekTextureAndProtectsTheEyes() throws {
        let portrait = try portrait()
        let anchor = EditorFaceAnchor(box: face)
        let neutral = render(
            try editor(portrait, mask: portrait.mask, anchors: [anchor])
        )
        let flat = render(
            try editor(
                portrait,
                adjustments: EditorAdjustments(smoothSkin: 100, skinTexture: 0),
                mask: portrait.mask,
                anchors: [anchor]
            )
        )
        let keep = render(
            try editor(
                portrait,
                adjustments: EditorAdjustments(smoothSkin: 100, skinTexture: 100),
                mask: portrait.mask,
                anchors: [anchor]
            )
        )

        let cheekFlat = roiDiff(
            flat, neutral,
            u0: 0.64 - 0.08, v0: 0.58 - 0.05,
            u1: 0.64 + 0.08, v1: 0.58 + 0.05
        )
        let eyeFlat = roiDiff(
            flat, neutral,
            u0: 0.34, v0: 0.38,
            u1: 0.45, v1: 0.49
        )
        XCTAssertGreaterThan(cheekFlat, 1.0, "the cheek did not change")
        XCTAssertLessThan(
            eyeFlat,
            cheekFlat * 0.5,
            "the eye was smoothed through the protect channel"
        )

        let flatVariance = lumaVariance(flat, u: 0.64, v: 0.58, radius: 9)
        let keepVariance = lumaVariance(keep, u: 0.64, v: 0.58, radius: 9)
        XCTAssertLessThan(
            flatVariance,
            keepVariance,
            "skinTexture=0 must smooth more than skinTexture=100"
        )
    }

    func testBlemishRemovalRaisesTheSpotLuma() throws {
        let portrait = try portrait()
        let anchor = EditorFaceAnchor(box: face)
        let neutral = render(
            try editor(portrait, mask: portrait.mask, anchors: [anchor])
        )
        let healed = render(
            try editor(
                portrait,
                adjustments: EditorAdjustments(
                    smoothSkin: 0,
                    blemish: 100,
                    skinTexture: 55
                ),
                mask: portrait.mask,
                anchors: [anchor]
            )
        )
        let before = lumaAt(neutral, u: 0.34, v: 0.62)
        let after = lumaAt(healed, u: 0.34, v: 0.62)
        XCTAssertGreaterThan(
            after,
            before + 8,
            "the dark blemish was not lifted (before \(before), after \(after))"
        )
    }

    func testSkinToneWarmsTheCheekWithoutMovingTheBackground() throws {
        let portrait = try portrait()
        let anchor = EditorFaceAnchor(box: face)
        let neutral = render(
            try editor(portrait, mask: portrait.mask, anchors: [anchor])
        )
        let warm = render(
            try editor(
                portrait,
                adjustments: EditorAdjustments(skinTone: 80),
                mask: portrait.mask,
                anchors: [anchor]
            )
        )
        let before = rgbAt(neutral, u: 0.64, v: 0.58)
        let after = rgbAt(warm, u: 0.64, v: 0.58)
        XCTAssertGreaterThan(after.r, before.r)
        XCTAssertLessThan(after.b, before.b)

        // The top-left corner is outside the face and outside the skin chroma.
        XCTAssertEqual(
            Array(neutral[0..<4]),
            Array(warm[0..<4])
        )
    }

    // MARK: - Preview/export

    func testPreviewAndExportMatchWithTheMask() throws {
        let portrait = try portrait()
        var editor = try editor(
            portrait,
            adjustments: EditorAdjustments(smoothSkin: 55, skinTexture: 55),
            mask: portrait.mask,
            anchors: [EditorFaceAnchor(box: face)]
        )
        let preview = editor.renderPreview(maxSide: UInt32(size))
        let png = try editor.renderExport(format: .png, quality: 100)
        let decoded = try XCTUnwrap(EditorImageDecoder.decode(png))
        XCTAssertEqual(Int(decoded.width), size)
        XCTAssertEqual(Int(decoded.height), size)
        let psnr = psnr(preview, decoded.rgba)
        XCTAssertGreaterThan(
            psnr,
            45,
            "preview and export diverged with the beauty mask (PSNR \(psnr))"
        )
    }

    func testBeautySlidersSurviveJSONRoundTripAndClamp() throws {
        let json = """
        {"smoothSkin":40,"blemish":-20,"skinTexture":120,"skinTone":-35}
        """
        let parsed = try EditorAdjustments.parse(json: json)
        XCTAssertEqual(parsed.smoothSkin, 40)
        XCTAssertEqual(parsed.blemish, 0)
        XCTAssertEqual(parsed.skinTexture, 100)
        XCTAssertEqual(parsed.skinTone, -35)
        XCTAssertTrue(parsed.isColorIdentity)
        XCTAssertFalse(parsed.isBeautyIdentity)

        let encoded = try JSONEncoder().encode(parsed)
        let decoded = try JSONDecoder().decode(EditorAdjustments.self, from: encoded)
        XCTAssertEqual(decoded, parsed)

        let clamped = parsed.clamped()
        XCTAssertEqual(clamped.smoothSkin, 40)
        XCTAssertEqual(clamped.blemish, 0)
        XCTAssertEqual(clamped.skinTexture, 100)
        XCTAssertEqual(clamped.skinTone, -35)
        XCTAssertTrue(clamped.isColorIdentity)
        XCTAssertFalse(clamped.isBeautyIdentity)

        let neutral = EditorAdjustments(skinTexture: 100)
        XCTAssertTrue(neutral.isBeautyIdentity)
    }

    // MARK: - Helpers

    private func ellipse(
        _ u: Float,
        _ v: Float,
        _ center: SIMD2<Float>,
        _ radius: SIMD2<Float>
    ) -> Bool {
        let du = (u - center.x) / radius.x
        let dv = (v - center.y) / radius.y
        return du * du + dv * dv <= 1
    }

    private func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
        min(max(value, low), high)
    }

    private func roiDiff(
        _ a: [UInt8],
        _ b: [UInt8],
        u0: Float,
        v0: Float,
        u1: Float,
        v1: Float
    ) -> Double {
        let x0 = max(0, Int((u0 * Float(size)).rounded()))
        let x1 = min(size, Int((u1 * Float(size)).rounded()))
        let y0 = max(0, Int((v0 * Float(size)).rounded()))
        let y1 = min(size, Int((v1 * Float(size)).rounded()))
        var sum = 0.0
        var count = 0
        for y in y0..<max(y0 + 1, y1) {
            for x in x0..<max(x0 + 1, x1) {
                let at = (y * size + x) * 4
                sum += Double(abs(Int(a[at]) - Int(b[at])))
                    + Double(abs(Int(a[at + 1]) - Int(b[at + 1])))
                    + Double(abs(Int(a[at + 2]) - Int(b[at + 2])))
                count += 3
            }
        }
        return sum / Double(max(1, count))
    }

    private func lumaVariance(
        _ image: [UInt8],
        u: Float,
        v: Float,
        radius: Int
    ) -> Double {
        let cx = Int((u * Float(size)).rounded())
        let cy = Int((v * Float(size)).rounded())
        var sum = 0.0
        var sum2 = 0.0
        var count = 0
        for y in max(0, cy - radius)...min(size - 1, cy + radius) {
            for x in max(0, cx - radius)...min(size - 1, cx + radius) {
                let value = lumaAt(image, x: x, y: y)
                sum += value
                sum2 += value * value
                count += 1
            }
        }
        let mean = sum / Double(max(1, count))
        return sum2 / Double(max(1, count)) - mean * mean
    }

    private func lumaAt(_ image: [UInt8], u: Float, v: Float) -> Double {
        let x = min(size - 1, Int((u * Float(size)).rounded()))
        let y = min(size - 1, Int((v * Float(size)).rounded()))
        return lumaAt(image, x: x, y: y)
    }

    private func lumaAt(_ image: [UInt8], x: Int, y: Int) -> Double {
        let at = (y * size + x) * 4
        return 0.2126 * Double(image[at])
            + 0.7152 * Double(image[at + 1])
            + 0.0722 * Double(image[at + 2])
    }

    private func rgbAt(
        _ image: [UInt8],
        u: Float,
        v: Float
    ) -> (r: Double, g: Double, b: Double) {
        let x = min(size - 1, Int((u * Float(size)).rounded()))
        let y = min(size - 1, Int((v * Float(size)).rounded()))
        let at = (y * size + x) * 4
        return (
            Double(image[at]),
            Double(image[at + 1]),
            Double(image[at + 2])
        )
    }

    private func psnr(_ a: [UInt8], _ b: [UInt8]) -> Double {
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }
        var sum = 0.0
        var index = 0
        while index < count {
            for channel in 0..<3 {
                let delta = Double(a[index + channel]) - Double(b[index + channel])
                sum += delta * delta
            }
            index += 4
        }
        let mse = sum / Double((count / 4) * 3)
        return mse == 0 ? .infinity : 10 * log10((255 * 255) / mse)
    }

    private struct LCG {
        var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func nextFloat() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let bits = UInt32(truncatingIfNeeded: state >> 33)
            return Float(bits) / Float(UInt32.max)
        }
    }
}
