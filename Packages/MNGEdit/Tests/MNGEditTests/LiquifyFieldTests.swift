import XCTest
@testable import MNGEdit

/// The free-liquify field through the real `Editor` render path.
///
/// The contract is the web one: dabs live in source UV, the RG field is
/// resolution independent, a dab moves the same detail in the preview and the
/// export, untouched pixels stay byte-identical, and clearing the dabs restores
/// the identity.
final class LiquifyFieldTests: XCTestCase {
    private let size = 96

    private func gradient(_ side: Int) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let offset = (y * side + x) * 4
                rgba[offset] = UInt8(x * 255 / max(1, side - 1))
                rgba[offset + 1] = UInt8(y * 255 / max(1, side - 1))
                rgba[offset + 2] = 128
                rgba[offset + 3] = 255
            }
        }
        return rgba
    }

    private func editor(_ rgba: [UInt8]) throws -> Editor {
        try Editor(
            width: UInt32(size),
            height: UInt32(size),
            rgba: rgba
        )
    }

    private func render(_ editor: Editor) -> [UInt8] {
        var copy = editor
        return copy.renderPreview(maxSide: UInt32(size))
    }

    // MARK: - Field builder

    func testFieldDimensionsFollowTheSourceAspect() throws {
        let dab = EditorLiquifyDab(
            x: 0.5,
            y: 0.5,
            dx: 0.02,
            dy: 0,
            radius: 0.2
        )

        let square = try XCTUnwrap(
            EditorLiquifyFieldBuilder.build(
                dabs: [dab],
                sourceWidth: 512,
                sourceHeight: 512
            )
        )
        XCTAssertEqual(square.width, 64)
        XCTAssertEqual(square.height, 64)

        let landscape = try XCTUnwrap(
            EditorLiquifyFieldBuilder.build(
                dabs: [dab],
                sourceWidth: 1000,
                sourceHeight: 500
            )
        )
        XCTAssertEqual(landscape.height, 32)

        let portrait = try XCTUnwrap(
            EditorLiquifyFieldBuilder.build(
                dabs: [dab],
                sourceWidth: 500,
                sourceHeight: 1000
            )
        )
        XCTAssertEqual(portrait.height, 128)

        // The field is clamped to 24…128 rows for extreme aspect ratios.
        let wide = try XCTUnwrap(
            EditorLiquifyFieldBuilder.build(
                dabs: [dab],
                sourceWidth: 4000,
                sourceHeight: 100
            )
        )
        XCTAssertEqual(wide.height, 24)
    }

    func testUntouchedTexelsAreExactlyNeutral() throws {
        let field = try XCTUnwrap(
            EditorLiquifyFieldBuilder.build(
                dabs: [
                    EditorLiquifyDab(
                        x: 0.5,
                        y: 0.5,
                        dx: 0.05,
                        dy: -0.02,
                        radius: 0.2
                    ),
                ],
                sourceWidth: 400,
                sourceHeight: 600
            )
        )
        // The corner texel is outside the brush and must encode zero as 128.
        XCTAssertEqual(field.rgba[0], 128)
        XCTAssertEqual(field.rgba[1], 128)
        XCTAssertEqual(field.rgba[2], 0)
        XCTAssertEqual(field.rgba[3], 255)

        let corner = field.displacement(at: SIMD2<Float>(0.01, 0.01))
        XCTAssertEqual(corner.x, 0, accuracy: 0.0001)
        XCTAssertEqual(corner.y, 0, accuracy: 0.0001)

        let centre = field.displacement(at: SIMD2<Float>(0.5, 0.5))
        XCTAssertGreaterThan(centre.x, 0.04)
        XCTAssertLessThan(centre.y, -0.015)

        // The shift is the stroke maximum times 1.02, capped at 0.09.
        XCTAssertEqual(field.shift, 0.051, accuracy: 0.0005)
        XCTAssertEqual(field.width, 64)
        XCTAssertEqual(field.height, 96)
    }

    func testBuilderDropsMalformedAndZeroDabs() {
        XCTAssertNil(
            EditorLiquifyFieldBuilder.build(
                dabs: [],
                sourceWidth: 100,
                sourceHeight: 100
            )
        )
        XCTAssertNil(
            EditorLiquifyFieldBuilder.build(
                dabs: [
                    EditorLiquifyDab(
                        x: 0.5,
                        y: 0.5,
                        dx: 0,
                        dy: 0,
                        radius: 0.2
                    ),
                ],
                sourceWidth: 100,
                sourceHeight: 100
            )
        )
        XCTAssertNil(
            EditorLiquifyFieldBuilder.build(
                dabs: [
                    EditorLiquifyDab(
                        x: .nan,
                        y: 0.5,
                        dx: 0.01,
                        dy: 0,
                        radius: 0.2
                    ),
                ],
                sourceWidth: 100,
                sourceHeight: 100
            )
        )
    }

    func testLargeDisplacementIsCappedToTheMaximumShift() throws {
        let field = try XCTUnwrap(
            EditorLiquifyFieldBuilder.build(
                dabs: [
                    EditorLiquifyDab(
                        x: 0.5,
                        y: 0.5,
                        dx: 0.25,
                        dy: 0,
                        radius: 0.3
                    ),
                ],
                sourceWidth: 500,
                sourceHeight: 500
            )
        )
        XCTAssertEqual(
            field.shift,
            EditorLiquifyLimits.maxShift,
            accuracy: 0.000001
        )
        let centre = field.displacement(at: SIMD2<Float>(0.5, 0.5))
        XCTAssertLessThanOrEqual(
            centre.x,
            EditorLiquifyLimits.maxShift + 0.0001
        )
    }

    // MARK: - Editor integration

    func testDabMovesTheCentreAndLeavesTheCornerAlone() throws {
        let source = gradient(size)
        var editor = try editor(source)
        let baseline = render(editor)
        XCTAssertEqual(baseline, source)

        editor.addLiquifyDab(
            EditorLiquifyDab(
                x: 0.5,
                y: 0.5,
                dx: 0.08,
                dy: 0,
                radius: 0.25
            )
        )
        XCTAssertTrue(editor.hasLiquify)
        XCTAssertEqual(editor.currentLiquifyDabs.count, 1)

        let warped = render(editor)
        XCTAssertEqual(
            Array(warped[0..<4]),
            Array(baseline[0..<4]),
            "the corner is outside the brush and must not move"
        )

        let centre = ((size / 2) * size + size / 2) * 4
        XCTAssertGreaterThan(
            warped[centre],
            baseline[centre],
            "a positive x push samples the gradient to the right"
        )
    }

    func testClearingTheDabsRestoresTheIdentityBytes() throws {
        let source = gradient(size)
        var editor = try editor(source)
        let baseline = render(editor)

        editor.setLiquifyDabs([
            EditorLiquifyDab(
                x: 0.4,
                y: 0.6,
                dx: -0.05,
                dy: 0.03,
                radius: 0.2
            ),
        ])
        XCTAssertNotEqual(render(editor), baseline)

        editor.clearLiquify()
        XCTAssertFalse(editor.hasLiquify)
        XCTAssertEqual(editor.currentLiquifyDabs, [])
        XCTAssertEqual(render(editor), baseline)
    }

    func testSetDabsClampsToTheWebLimitsAndKeepsTheNewest() throws {
        var editor = try editor(gradient(size))
        editor.setLiquifyDabs([
            EditorLiquifyDab(
                x: -1,
                y: 2,
                dx: 1,
                dy: -1,
                radius: 0
            ),
            EditorLiquifyDab(
                x: 0.5,
                y: 0.5,
                dx: 0,
                dy: 0,
                radius: 0.2
            ),
            EditorLiquifyDab(
                x: .nan,
                y: 0.5,
                dx: 0.1,
                dy: 0,
                radius: 0.2
            ),
        ])
        XCTAssertEqual(editor.currentLiquifyDabs.count, 1)
        let dab = try XCTUnwrap(editor.currentLiquifyDabs.first)
        XCTAssertEqual(dab.x, 0)
        XCTAssertEqual(dab.y, 1)
        XCTAssertEqual(dab.dx, 0.25)
        XCTAssertEqual(dab.dy, -0.25)
        XCTAssertEqual(dab.radius, 0.002)
    }

    func testDabHistoryKeepsOnlyTheNewest640() throws {
        var editor = try editor(gradient(size))
        let dabs = (0..<700).map { index in
            EditorLiquifyDab(
                x: Float(index % 100) / 100 + 0.005,
                y: 0.5,
                dx: 0.001,
                dy: 0,
                radius: 0.01
            )
        }
        editor.setLiquifyDabs(dabs)
        XCTAssertEqual(
            editor.currentLiquifyDabs.count,
            EditorLiquifyLimits.maxDabs
        )
        XCTAssertEqual(editor.currentLiquifyDabs.first?.x, dabs[60].x)
        XCTAssertEqual(editor.currentLiquifyDabs.last?.x, dabs[699].x)
    }

    // MARK: - Web state

    func testDabsRoundTripTheWebJSONShape() throws {
        let json = """
        [
          {"x":0.25,"y":0.5,"dx":-0.03,"dy":0.02,"radius":0.18},
          {"x":0.75,"y":0.4,"dx":0.01,"dy":-0.04,"radius":0.12}
        ]
        """
        let dabs = try JSONDecoder().decode(
            [EditorLiquifyDab].self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(dabs.count, 2)
        XCTAssertEqual(dabs[0].x, 0.25)
        XCTAssertEqual(dabs[0].dx, -0.03)
        XCTAssertEqual(dabs[1].radius, 0.12)

        let encoded = try JSONEncoder().encode(dabs)
        let decoded = try JSONDecoder().decode(
            [EditorLiquifyDab].self,
            from: encoded
        )
        XCTAssertEqual(decoded, dabs)

        var editor = try editor(gradient(size))
        editor.setLiquifyDabs(dabs)
        XCTAssertEqual(editor.currentLiquifyDabs, dabs)
        XCTAssertTrue(editor.hasLiquify)
    }
}
