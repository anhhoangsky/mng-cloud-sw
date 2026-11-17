import Foundation
import XCTest
@testable import MNGEdit

/// The painted region effects through the real `Editor` render path.
///
/// The contract is the web one: dabs live in source UV, one R/G mask is shared
/// by mosaic and blur, the mask is capped at 1024 px and 1600 stamps, the
/// painted region changes while everything outside stays byte-identical, and
/// preview and export render the same pixels.
final class EditorEffectsTests: XCTestCase {
    private let side = 96

    private func gradient(_ width: Int, _ height: Int) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                rgba[offset] = UInt8(x * 255 / max(1, width - 1))
                rgba[offset + 1] = UInt8(y * 255 / max(1, height - 1))
                rgba[offset + 2] = 128
                rgba[offset + 3] = 255
            }
        }
        return rgba
    }

    private func checker(_ width: Int, _ height: Int, cell: Int) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let value: UInt8 = ((x / cell + y / cell) % 2) == 0
                    ? 235
                    : 20
                rgba[offset] = value
                rgba[offset + 1] = value
                rgba[offset + 2] = value
                rgba[offset + 3] = 255
            }
        }
        return rgba
    }

    private func editor(_ rgba: [UInt8], width: Int? = nil,
                        height: Int? = nil) throws -> Editor {
        try Editor(
            width: UInt32(width ?? side),
            height: UInt32(height ?? side),
            rgba: rgba
        )
    }

    private func render(_ editor: Editor) -> [UInt8] {
        var copy = editor
        return copy.renderPreview(
            maxSide: UInt32(max(Int(copy.width), Int(copy.height)))
        )
    }

    private func psnr(_ a: [UInt8], _ b: [UInt8]) -> Double {
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }
        var sum = 0.0
        var index = 0
        while index < count {
            for channel in 0..<3 {
                let delta = Double(a[index + channel])
                    - Double(b[index + channel])
                sum += delta * delta
            }
            index += 4
        }
        let mse = sum / Double((count / 4) * 3)
        return mse == 0 ? .infinity : 10 * log10((255 * 255) / mse)
    }

    // MARK: - State

    func testDefaultStateMatchesTheWeb() {
        let state = EditorEffectState().normalized
        XCTAssertEqual(state.dabs.count, 0)
        XCTAssertEqual(state.size, 0.08, accuracy: 0.000001)
        XCTAssertEqual(state.strength, 60, accuracy: 0.000001)
    }

    func testNormalizeClampsTheGlobalsAndDabs() {
        let state = EditorEffectState(
            dabs: [
                EditorEffectDab(
                    kind: .mosaic,
                    x: -1,
                    y: 2,
                    radius: 0
                ),
                EditorEffectDab(
                    kind: .blur,
                    x: .nan,
                    y: 0.5,
                    radius: 0.1
                ),
                EditorEffectDab(
                    kind: .blur,
                    x: 0.5,
                    y: 0.5,
                    radius: 1
                ),
            ],
            size: 1,
            strength: -5
        ).normalized
        XCTAssertEqual(state.size, 0.2, accuracy: 0.000001)
        XCTAssertEqual(state.strength, 0, accuracy: 0.000001)
        XCTAssertEqual(state.dabs.count, 2)
        XCTAssertEqual(state.dabs[0].x, 0)
        XCTAssertEqual(state.dabs[0].y, 1)
        XCTAssertEqual(state.dabs[0].radius, 0.002)
        XCTAssertEqual(state.dabs[1].radius, 0.2)
    }

    func testDabStateCapKeepsTheNewest() {
        let dabs = (0..<1700).map { index in
            EditorEffectDab(
                kind: index % 2 == 0 ? .mosaic : .blur,
                x: Float(index) / 1700,
                y: 0.5,
                radius: 0.01
            )
        }
        let state = EditorEffectState(
            dabs: dabs,
            size: 0.1,
            strength: 50
        ).normalized
        XCTAssertEqual(state.dabs.count, EditorEffectLimits.maxDabs)
        XCTAssertEqual(
            state.dabs.first?.x ?? -1,
            dabs[100].x,
            accuracy: 0.000001
        )
        XCTAssertEqual(
            state.dabs.last?.x ?? -1,
            dabs[1699].x,
            accuracy: 0.000001
        )
    }

    func testDabsRoundTripTheWebJSONShape() throws {
        let json = """
        [
          {"kind":"mosaic","x":0.25,"y":0.5,"radius":0.08},
          {"kind":"blur","x":0.75,"y":0.4,"radius":0.12}
        ]
        """
        let dabs = try JSONDecoder().decode(
            [EditorEffectDab].self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(dabs.count, 2)
        XCTAssertEqual(dabs[0].kind, .mosaic)
        XCTAssertEqual(dabs[0].x, 0.25)
        XCTAssertEqual(dabs[1].kind, .blur)
        XCTAssertEqual(dabs[1].radius, 0.12)

        let encoded = try JSONEncoder().encode(dabs)
        let decoded = try JSONDecoder().decode(
            [EditorEffectDab].self,
            from: encoded
        )
        XCTAssertEqual(decoded, dabs)

        var editor = try editor(gradient(side, side))
        editor.setEffectDabs(dabs)
        XCTAssertEqual(editor.currentEffectDabs, dabs)
        XCTAssertTrue(editor.hasEffects)
    }

    // MARK: - Mask

    func testMosaicWritesOnlyTheRedChannel() throws {
        let mask = try XCTUnwrap(
            EditorEffectMaskBuilder.build(
                dabs: [
                    EditorEffectDab(
                        kind: .mosaic,
                        x: 0.5,
                        y: 0.5,
                        radius: 0.2
                    ),
                ],
                sourceWidth: 400,
                sourceHeight: 400
            )
        )
        XCTAssertEqual(mask.width, 400)
        XCTAssertEqual(mask.height, 400)
        let centre = ((200 * 400) + 200) * 4
        XCTAssertEqual(mask.rgba[centre], 255)
        XCTAssertEqual(mask.rgba[centre + 1], 0)
        XCTAssertEqual(mask.rgba[centre + 2], 0)
        XCTAssertEqual(mask.rgba[centre + 3], 255)
        let coverage = mask.coverage(at: SIMD2<Float>(0.5, 0.5))
        XCTAssertEqual(coverage.x, 1, accuracy: 0.002)
        XCTAssertEqual(coverage.y, 0, accuracy: 0.002)
    }

    func testBlurWritesOnlyTheGreenChannel() throws {
        let mask = try XCTUnwrap(
            EditorEffectMaskBuilder.build(
                dabs: [
                    EditorEffectDab(
                        kind: .blur,
                        x: 0.5,
                        y: 0.5,
                        radius: 0.2
                    ),
                ],
                sourceWidth: 400,
                sourceHeight: 400
            )
        )
        let centre = ((200 * 400) + 200) * 4
        XCTAssertEqual(mask.rgba[centre], 0)
        XCTAssertEqual(mask.rgba[centre + 1], 255)
        XCTAssertEqual(mask.rgba[centre + 3], 255)
    }

    func testBothStylesShareOneMask() throws {
        let mask = try XCTUnwrap(
            EditorEffectMaskBuilder.build(
                dabs: [
                    EditorEffectDab(
                        kind: .mosaic,
                        x: 0.3,
                        y: 0.5,
                        radius: 0.15
                    ),
                    EditorEffectDab(
                        kind: .blur,
                        x: 0.7,
                        y: 0.5,
                        radius: 0.15
                    ),
                ],
                sourceWidth: 512,
                sourceHeight: 512
            )
        )
        let left = mask.coverage(at: SIMD2<Float>(0.3, 0.5))
        let right = mask.coverage(at: SIMD2<Float>(0.7, 0.5))
        XCTAssertGreaterThan(left.x, 0.9)
        XCTAssertEqual(left.y, 0, accuracy: 0.002)
        XCTAssertGreaterThan(right.y, 0.9)
        XCTAssertEqual(right.x, 0, accuracy: 0.002)
    }

    func testMaskFeathersTheOuterEdgeAndStaysEmptyOutside() throws {
        let mask = try XCTUnwrap(
            EditorEffectMaskBuilder.build(
                dabs: [
                    EditorEffectDab(
                        kind: .mosaic,
                        x: 0.5,
                        y: 0.5,
                        radius: 0.2
                    ),
                ],
                sourceWidth: 512,
                sourceHeight: 512
            )
        )
        // The radius is 102.4 px on the 512 px mask. The core is solid, the
        // outer 35 % is a linear feather and the rest stays empty.
        let centre = (256 * 512 + 256) * 4
        XCTAssertEqual(mask.rgba[centre], 255)
        let feathered = (256 * 512 + 337) * 4
        XCTAssertGreaterThan(mask.rgba[feathered], 0)
        XCTAssertLessThan(mask.rgba[feathered], 255)
        let outside = (256 * 512 + 400) * 4
        XCTAssertEqual(mask.rgba[outside], 0)
        XCTAssertEqual(
            mask.rgba[outside + 3],
            255,
            "alpha stays 255 across the whole mask, like the web upload"
        )
    }

    func testMaskLongestSideIsCappedAt1024() throws {
        let mask = try XCTUnwrap(
            EditorEffectMaskBuilder.build(
                dabs: [
                    EditorEffectDab(
                        kind: .mosaic,
                        x: 0.5,
                        y: 0.5,
                        radius: 0.2
                    ),
                ],
                sourceWidth: 2048,
                sourceHeight: 1024
            )
        )
        XCTAssertEqual(mask.width, EditorEffectLimits.maskMax)
        XCTAssertEqual(mask.height, 512)
    }

    func testEmptyDabsProduceNoMask() {
        XCTAssertNil(
            EditorEffectMaskBuilder.build(
                dabs: [],
                sourceWidth: 512,
                sourceHeight: 512
            )
        )
    }

    // MARK: - Geometry

    func testGeometryMatchesTheWebUniforms() {
        let geometry = EditorEffectGeometry(
            size: 0.1,
            strength: 50,
            sourceWidth: 512,
            sourceHeight: 256
        )
        // blockPx = max(2, round(0.1 × 512 × 0.55)) = 28
        XCTAssertEqual(geometry.blockPx, 28)
        XCTAssertEqual(geometry.grid.x, Float(512.0 / 28.0), accuracy: 0.00001)
        XCTAssertEqual(geometry.grid.y, Float(256.0 / 28.0), accuracy: 0.00001)
        XCTAssertEqual(geometry.blur.x, 0.042, accuracy: 0.000001)
        // A UV step of `blurX` spans the same pixels on both axes, so a blur
        // on a landscape photo stays circular.
        XCTAssertEqual(geometry.blur.y, 0.084, accuracy: 0.000001)
        XCTAssertEqual(geometry.strength, 0.5, accuracy: 0.000001)
    }

    // MARK: - Editor integration

    func testMosaicChangesOnlyInsideTheStamp() throws {
        let source = gradient(side, side)
        var editor = try editor(source)
        let baseline = render(editor)
        XCTAssertEqual(baseline, source)

        editor.setEffectSize(0.2)
        editor.setEffectStrength(100)
        editor.addEffectDab(
            EditorEffectDab(
                kind: .mosaic,
                x: 0.5,
                y: 0.5,
                radius: 0.25
            )
        )
        XCTAssertTrue(editor.hasEffects)
        XCTAssertEqual(editor.currentEffectDabs.count, 1)

        let painted = render(editor)
        XCTAssertEqual(
            Array(painted[0..<4]),
            Array(baseline[0..<4]),
            "the corner is outside the brush and must stay byte-identical"
        )
        let centre = ((side / 2) * side + side / 2) * 4
        XCTAssertNotEqual(
            Array(painted[centre..<centre + 3]),
            Array(baseline[centre..<centre + 3])
        )
    }

    func testMosaicCellsAreFlat() throws {
        var editor = try editor(gradient(side, side))
        editor.setEffectSize(0.2)
        editor.setEffectStrength(100)
        editor.addEffectDab(
            EditorEffectDab(
                kind: .mosaic,
                x: 0.5,
                y: 0.5,
                radius: 0.25
            )
        )
        let painted = render(editor)
        // blockPx is 11 on a 96 px source, so x 44…54 is one cell. Both points
        // sit in the solid core of the stamp.
        let y = side / 2
        let left = (y * side + 45) * 4
        let right = (y * side + 54) * 4
        XCTAssertEqual(painted[left], painted[right])
        XCTAssertEqual(painted[left + 1], painted[right + 1])
        XCTAssertEqual(painted[left + 2], painted[right + 2])

        // A neighbouring cell samples a different texel, so the edge between
        // cells is visible.
        let nextCell = (y * side + 56) * 4
        XCTAssertNotEqual(painted[left], painted[nextCell])
    }

    func testBlurLowersTheRegionEnergy() throws {
        let source = checker(64, 64, cell: 4)
        var editor = try editor(source, width: 64, height: 64)
        let baseline = render(editor)
        editor.setEffectSize(0.2)
        editor.setEffectStrength(100)
        editor.addEffectDab(
            EditorEffectDab(
                kind: .blur,
                x: 0.5,
                y: 0.5,
                radius: 0.2
            )
        )
        let blurred = render(editor)

        func energy(_ rgba: [UInt8]) -> Double {
            var sum = 0.0
            var count = 0
            for y in 26..<38 {
                for x in 26..<38 {
                    let offset = (y * 64 + x) * 4
                    let delta = Double(rgba[offset]) - Double(rgba[offset + 4])
                    sum += delta * delta
                    count += 1
                }
            }
            return count > 0 ? sum / Double(count) : 0
        }

        let before = energy(baseline)
        let after = energy(blurred)
        XCTAssertGreaterThan(before, 0)
        XCTAssertLessThan(
            after,
            before * 0.75,
            "the nine-tap blur must flatten fine detail inside the mask"
        )
    }

    func testStrengthZeroKeepsTheIdentityBytes() throws {
        let source = gradient(side, side)
        var editor = try editor(source)
        let baseline = render(editor)
        editor.setEffectDabs([
            EditorEffectDab(
                kind: .mosaic,
                x: 0.5,
                y: 0.5,
                radius: 0.2
            ),
        ])
        editor.setEffectStrength(0)
        XCTAssertEqual(editor.currentEffectStrength, 0)
        XCTAssertEqual(render(editor), baseline)

        editor.setEffectStrength(60)
        XCTAssertNotEqual(render(editor), baseline)
    }

    func testClearRestoresTheIdentityAndKeepsTheBrushSettings() throws {
        let source = gradient(side, side)
        var editor = try editor(source)
        let baseline = render(editor)
        editor.setEffectSize(0.15)
        editor.setEffectStrength(75)
        editor.setEffectDabs([
            EditorEffectDab(
                kind: .mosaic,
                x: 0.4,
                y: 0.5,
                radius: 0.1
            ),
            EditorEffectDab(
                kind: .blur,
                x: 0.6,
                y: 0.5,
                radius: 0.1
            ),
        ])
        XCTAssertNotEqual(render(editor), baseline)

        editor.clearEffects()
        XCTAssertFalse(editor.hasEffects)
        XCTAssertEqual(editor.currentEffectDabs, [])
        XCTAssertEqual(editor.currentEffectSize, 0.15)
        XCTAssertEqual(editor.currentEffectStrength, 75)
        XCTAssertEqual(render(editor), baseline)
    }

    func testIncrementalStampMatchesTheFullRebuild() throws {
        let first = EditorEffectDab(
            kind: .mosaic,
            x: 0.35,
            y: 0.4,
            radius: 0.2
        )
        let second = EditorEffectDab(
            kind: .blur,
            x: 0.6,
            y: 0.55,
            radius: 0.18
        )
        var rebuilt = try editor(gradient(side, side))
        rebuilt.setEffectDabs([first, second])

        var stamped = try editor(gradient(side, side))
        stamped.addEffectDab(first)
        stamped.addEffectDab(second)
        XCTAssertEqual(
            render(stamped),
            render(rebuilt),
            "a live stroke must rasterise the same mask as a reload"
        )
    }

    func testPreviewAndExportAgree() throws {
        var editor = try editor(gradient(side, side))
        editor.setEffectSize(0.18)
        editor.setEffectStrength(80)
        editor.setEffectDabs([
            EditorEffectDab(
                kind: .mosaic,
                x: 0.35,
                y: 0.45,
                radius: 0.2
            ),
            EditorEffectDab(
                kind: .blur,
                x: 0.65,
                y: 0.6,
                radius: 0.16
            ),
        ])
        let preview = render(editor)
        let png = try editor.renderExport(format: .png, quality: 100)
        let decoded = try XCTUnwrap(EditorImageDecoder.decode(png))
        XCTAssertEqual(Int(decoded.width), side)
        XCTAssertEqual(Int(decoded.height), side)
        XCTAssertGreaterThan(
            psnr(preview, decoded.rgba),
            45,
            "preview and export diverged with the effect brush"
        )
    }
}
