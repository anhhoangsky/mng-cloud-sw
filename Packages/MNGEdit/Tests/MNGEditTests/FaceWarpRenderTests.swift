import CoreGraphics
import XCTest
@testable import MNGEdit

/// The reshape sliders through the real `Editor` render path: the preview and
/// the export both call `renderPreview`/`renderRGBA`, so these tests guard the
/// two promises of the port — a neutral slider is byte-identical, and a pixel
/// outside every face ellipse is never resampled.
final class FaceWarpRenderTests: XCTestCase {
    private let size = 96
    private let face = EditorFaceAnchor(
        box: EditorFaceBox(
            x: 0.25,
            y: 0.2,
            width: 0.5,
            height: 0.6,
            confidence: 0.9
        )
    )

    private func editor(
        anchors: [EditorFaceAnchor] = [],
        adjustments: EditorAdjustments = .zero
    ) throws -> Editor {
        var rgba = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                rgba[offset] = UInt8(x * 255 / (size - 1))
                rgba[offset + 1] = UInt8(y * 255 / (size - 1))
                rgba[offset + 2] = UInt8((x + y) * 255 / (2 * (size - 1)))
            }
        }
        var editor = try Editor(
            width: UInt32(size),
            height: UInt32(size),
            rgba: rgba
        )
        editor.setAdjustments(adjustments)
        editor.setFaceAnchors(anchors)
        return editor
    }

    private func render(_ editor: Editor) -> [UInt8] {
        var copy = editor
        return copy.renderPreview(maxSide: UInt32(size))
    }

    func testNeutralReshapeIsByteIdentical() throws {
        let plain = try editor(adjustments: .zero)
        let anchored = try editor(anchors: [face], adjustments: .zero)
        let a = render(plain)
        let b = render(anchored)
        XCTAssertEqual(a, b)
    }

    func testFaceSlimChangesTheCheeks() throws {
        let baseline = render(try editor(anchors: [face]))
        let slimmed = render(
            try editor(
                anchors: [face],
                adjustments: EditorAdjustments(faceSlim: 60)
            )
        )
        var changed = 0
        for index in stride(from: 0, to: baseline.count, by: 4) {
            if baseline[index] != slimmed[index]
                || baseline[index + 1] != slimmed[index + 1]
                || baseline[index + 2] != slimmed[index + 2] {
                changed += 1
            }
        }
        // A 60/100 slim covers a broad band across the face; a handful of
        // pixels would mean the slider never reached the renderer.
        XCTAssertGreaterThan(changed, 300)
    }

    func testPixelsOutsideTheFaceAreBitIdentical() throws {
        let baseline = render(try editor(anchors: [face]))
        let warped = render(
            try editor(
                anchors: [face],
                adjustments: EditorAdjustments(
                    faceSlim: 100,
                    jawline: 100,
                    chin: 100,
                    eyeSize: 100,
                    noseSize: 100,
                    mouthSize: 100
                )
            )
        )
        // The packed face ellipse reaches y 0.2…0.8 and x 0.25…0.75; the
        // top-left corner is outside it for every slider.
        for y in 0..<12 {
            for x in 0..<12 {
                let offset = (y * size + x) * 4
                XCTAssertEqual(
                    Array(baseline[offset..<(offset + 4)]),
                    Array(warped[offset..<(offset + 4)]),
                    "pixel \(x),\(y) outside the face was resampled"
                )
            }
        }
    }

    func testEyeAnchorsMoveTheEyeButNotTheCheek() throws {
        let anchor = EditorFaceAnchor(
            box: face.box,
            eyeLeft: SIMD2<Float>(-0.30, -0.20),
            eyeRight: SIMD2<Float>(0.30, -0.20),
            eyeLeftRadius: SIMD2<Float>(0.20, 0.15),
            eyeRightRadius: SIMD2<Float>(0.20, 0.15)
        )
        let baseline = render(try editor(anchors: [anchor]))
        let enlarged = render(
            try editor(
                anchors: [anchor],
                adjustments: EditorAdjustments(eyeSize: 70)
            )
        )

        func regionDiff(centerX: Int, centerY: Int, radius: Int = 3) -> Int {
            var changed = 0
            for y in (centerY - radius)...(centerY + radius) {
                for x in (centerX - radius)...(centerX + radius) {
                    let offset = (y * size + x) * 4
                    if baseline[offset] != enlarged[offset]
                        || baseline[offset + 1] != enlarged[offset + 1]
                        || baseline[offset + 2] != enlarged[offset + 2] {
                        changed += 1
                    }
                }
            }
            return changed
        }

        // Left eye at local (-0.30, -0.20) of the packed ellipse: for this
        // 0.5×0.6 box the half-size is (0.25, 0.3), so the eye sits at
        // (0.425, 0.44) in UV.
        let centre = SIMD2<Float>(
            face.box.x + face.box.width / 2,
            face.box.y + face.box.height / 2
        )
        let half = SIMD2<Float>(
            min(max(face.box.width * 0.62, 0.01), 1) / 1.24,
            min(max(face.box.height * 0.72, 0.01), 1) / 1.44
        )
        let eye = centre + SIMD2<Float>(-0.30, -0.20) * half
        let eyeX = Int(eye.x * Float(size))
        let eyeY = Int(eye.y * Float(size))
        XCTAssertGreaterThan(regionDiff(centerX: eyeX, centerY: eyeY), 0)

        // The cheek sits outside the measured eye radius: 48, 48 is the face
        // centre, well away from both eyes.
        XCTAssertEqual(regionDiff(centerX: 48, centerY: 48), 0)
    }

    func testReshapeSlidersSurviveJSONRoundTrip() throws {
        let json = "{\"brightness\":10,\"faceSlim\":40,\"eyeSize\":-20}"
        let parsed = try EditorAdjustments.parse(json: json)
        XCTAssertEqual(parsed.brightness, 10)
        XCTAssertEqual(parsed.faceSlim, 40)
        XCTAssertEqual(parsed.eyeSize, -20)
        XCTAssertEqual(parsed.noseSize, 0)

        let encoded = try JSONEncoder().encode(parsed)
        let decoded = try JSONDecoder().decode(EditorAdjustments.self, from: encoded)
        XCTAssertEqual(decoded, parsed)

        let clamped = EditorAdjustments(faceSlim: 500, chin: -900, mouthSize: .nan).clamped()
        XCTAssertEqual(clamped.faceSlim, 100)
        XCTAssertEqual(clamped.chin, -100)
        XCTAssertEqual(clamped.mouthSize, 0)
        XCTAssertTrue(clamped.isColorIdentity)
        XCTAssertFalse(clamped.isIdentity)
    }

    func testTheFrozenSamplerMatchesTheReferenceWarp() {
        for slim in [-100, -25, 0, 25, 100] {
            let warp = FaceWarp(
                parameters: FaceWarpParameters(
                    faceSlim: Float(slim),
                    jawline: 40,
                    chin: -30,
                    eyeSize: 55,
                    noseSize: 35,
                    mouthSize: -15
                ),
                anchors: [face]
            )
            let sampler = warp.makeSampler()
            for y in stride(from: Float(0), through: 1, by: 0.1) {
                for x in stride(from: Float(0), through: 1, by: 0.1) {
                    let point = SIMD2<Float>(x, y)
                    XCTAssertEqual(sampler.warp(point), warp.warp(point))
                }
            }
        }
    }
}
