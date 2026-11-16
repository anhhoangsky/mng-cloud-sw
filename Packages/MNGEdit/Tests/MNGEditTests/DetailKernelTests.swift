import XCTest
@testable import MNGEdit

/// Sections 1–3 of `main.glsl` through the real `Editor` render path:
/// edge-aware denoise, halo-limited clarity and noise-floored sharpening.
final class DetailKernelTests: XCTestCase {
    private let size = 96

    private func editor(
        _ rgba: [UInt8],
        adjustments: EditorAdjustments = .zero
    ) throws -> Editor {
        var editor = try Editor(
            width: UInt32(size),
            height: UInt32(size),
            rgba: rgba
        )
        editor.setAdjustments(adjustments)
        return editor
    }

    private func render(_ editor: Editor) -> [UInt8] {
        var copy = editor
        return copy.renderPreview(maxSide: UInt32(size))
    }

    private func flat(_ value: UInt8) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: size * size * 4)
        for index in 0..<(size * size) {
            let at = index * 4
            rgba[at] = value
            rgba[at + 1] = value
            rgba[at + 2] = value
            rgba[at + 3] = 255
        }
        return rgba
    }

    private func step(_ left: UInt8, _ right: UInt8) -> [UInt8] {
        var rgba = flat(left)
        for y in 0..<size {
            for x in (size / 2)..<size {
                let at = (y * size + x) * 4
                rgba[at] = right
                rgba[at + 1] = right
                rgba[at + 2] = right
            }
        }
        return rgba
    }

    private func noisyFlat(amplitude: Float) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: size * size * 4)
        var random = LCG(seed: 0xD371_2026)
        for index in 0..<(size * size) {
            let noise = (random.nextFloat() - 0.5) * amplitude
            let value = UInt8(
                min(max((0.5 + noise) * 255, 0), 255).rounded()
            )
            let at = index * 4
            rgba[at] = value
            rgba[at + 1] = value
            rgba[at + 2] = value
            rgba[at + 3] = 255
        }
        return rgba
    }

    private func noisyStep(_ left: UInt8, _ right: UInt8, amplitude: Float) -> [UInt8] {
        var rgba = step(left, right)
        var random = LCG(seed: 0x51DE_2026)
        for y in 0..<size {
            for x in 0..<size {
                let noise = (random.nextFloat() - 0.5) * amplitude
                let at = (y * size + x) * 4
                for channel in 0..<3 {
                    let value = Float(rgba[at + channel]) + noise
                    rgba[at + channel] = UInt8(
                        min(max(value, 0), 255).rounded()
                    )
                }
            }
        }
        return rgba
    }

    private func variance(_ image: [UInt8]) -> Double {
        var sum = 0.0
        var sum2 = 0.0
        let count = size * size
        for index in 0..<count {
            let value = Double(image[index * 4])
            sum += value
            sum2 += value * value
        }
        let mean = sum / Double(count)
        return sum2 / Double(count) - mean * mean
    }

    private func meanRed(
        _ image: [UInt8],
        x0: Int,
        x1: Int
    ) -> Double {
        var sum = 0.0
        var count = 0
        for y in 10..<(size - 10) {
            for x in x0..<x1 {
                sum += Double(image[(y * size + x) * 4])
                count += 1
            }
        }
        return sum / Double(max(1, count))
    }

    private func redRange(_ image: [UInt8], row: Int) -> (min: UInt8, max: UInt8) {
        var low: UInt8 = 255
        var high: UInt8 = 0
        for x in 0..<size {
            let value = image[(row * size + x) * 4]
            low = Swift.min(low, value)
            high = Swift.max(high, value)
        }
        return (low, high)
    }

    // MARK: - Identity

    func testNeutralDetailIsByteIdentical() throws {
        let source = noisyFlat(amplitude: 0.08)
        let baseline = render(try editor(source))
        XCTAssertEqual(baseline, source)

        // Beauty-only and reshape-only values must not wake the detail pass.
        let neutral = EditorAdjustments(smoothSkin: 40, faceSlim: 20)
        XCTAssertTrue(neutral.isDetailIdentity)
        XCTAssertTrue(EditorAdjustments(sharpen: 0, denoise: 0).isDetailIdentity)
    }

    func testFlatPhotoStaysNeutralWithClarityAndSharpen() throws {
        let source = flat(128)
        let baseline = render(try editor(source))
        let detailed = render(
            try editor(
                source,
                adjustments: EditorAdjustments(clarity: 100, sharpen: 100)
            )
        )
        XCTAssertEqual(baseline, detailed)
    }

    // MARK: - Denoise

    func testDenoiseLowersFlatNoiseAndKeepsTheEdge() throws {
        let noisy = noisyFlat(amplitude: 0.08)
        let before = variance(noisy)
        let cleaned = render(
            try editor(noisy, adjustments: EditorAdjustments(denoise: 100))
        )
        XCTAssertLessThan(
            variance(cleaned),
            before * 0.5,
            "denoise did not lower the flat noise variance"
        )

        let edge = noisyStep(64, 192, amplitude: 4)
        let edgeBefore = render(try editor(edge))
        let edgeAfter = render(
            try editor(edge, adjustments: EditorAdjustments(denoise: 100))
        )
        let leftBefore = meanRed(edgeBefore, x0: 10, x1: 30)
        let leftAfter = meanRed(edgeAfter, x0: 10, x1: 30)
        let rightBefore = meanRed(edgeBefore, x0: size - 30, x1: size - 10)
        let rightAfter = meanRed(edgeAfter, x0: size - 30, x1: size - 10)
        XCTAssertEqual(leftAfter, leftBefore, accuracy: 2)
        XCTAssertEqual(rightAfter, rightBefore, accuracy: 2)
        XCTAssertGreaterThan(
            rightAfter - leftAfter,
            100,
            "the edge was blurred through by the denoise taps"
        )
    }

    // MARK: - Clarity and sharpen

    func testClarityAndSharpenExpandALowContrastEdge() throws {
        let source = step(107, 148)
        let base = render(try editor(source))
        let clarity = render(
            try editor(source, adjustments: EditorAdjustments(clarity: 100))
        )
        let sharpen = render(
            try editor(source, adjustments: EditorAdjustments(sharpen: 100))
        )

        let baseRange = redRange(base, row: 40)
        let clarityRange = redRange(clarity, row: 40)
        let sharpenRange = redRange(sharpen, row: 40)
        let baseSpan = Int(baseRange.max) - Int(baseRange.min)
        let claritySpan = Int(clarityRange.max) - Int(clarityRange.min)
        let sharpenSpan = Int(sharpenRange.max) - Int(sharpenRange.min)
        XCTAssertGreaterThan(
            claritySpan,
            baseSpan + 15,
            "clarity did not raise the local contrast (base \(baseSpan), clarity \(claritySpan))"
        )
        XCTAssertGreaterThan(
            sharpenSpan,
            baseSpan + 15,
            "sharpen did not add an edge halo (base \(baseSpan), sharpen \(sharpenSpan))"
        )
    }

    func testSharpenHasANoiseFloor() throws {
        let source = noisyFlat(amplitude: 2.0 / 255)
        let before = variance(source)
        let sharpened = render(
            try editor(source, adjustments: EditorAdjustments(sharpen: 100))
        )
        XCTAssertLessThanOrEqual(
            variance(sharpened),
            before * 1.2,
            "sharpening amplified sub-noise-floor detail"
        )
    }

    func testCombinedDetailStaysInsideTheByteRange() throws {
        var source = flat(0)
        for y in 0..<size {
            for x in 0..<size {
                let value = UInt8(
                    (20 + 215 * x / max(1, size - 1))
                )
                let at = (y * size + x) * 4
                source[at] = value
                source[at + 1] = value
                source[at + 2] = value
            }
        }
        let detailed = render(
            try editor(
                source,
                adjustments: EditorAdjustments(
                    clarity: 100,
                    sharpen: 100,
                    denoise: 100
                )
            )
        )
        // Every channel is a byte, so the only real risk is a wrap-around;
        // a monotone ramp must stay monotone or plateau, never invert.
        var inversions = 0
        for y in 10..<(size - 10) {
            for x in 1..<size {
                let previous = detailed[(y * size + x - 1) * 4]
                let current = detailed[(y * size + x) * 4]
                if current + 2 < previous {
                    inversions += 1
                }
            }
        }
        XCTAssertEqual(inversions, 0, "clarity/sharpening wrapped the ramp")
    }

    // MARK: - Wiring

    func testPreviewAndExportMatchWithDetail() throws {
        let source = noisyStep(48, 200, amplitude: 3)
        var editor = try editor(
            source,
            adjustments: EditorAdjustments(
                clarity: 40,
                sharpen: 35,
                denoise: 30
            )
        )
        let preview = editor.renderPreview(maxSide: UInt32(size))
        let png = try editor.renderExport(format: .png, quality: 100)
        let decoded = try XCTUnwrap(EditorImageDecoder.decode(png))
        XCTAssertEqual(Int(decoded.width), size)
        XCTAssertEqual(Int(decoded.height), size)
        XCTAssertGreaterThan(
            psnr(preview, decoded.rgba),
            45,
            "preview and export diverged with the detail sliders"
        )
    }

    func testDetailSlidersSurviveJSONRoundTripAndClamp() throws {
        let json = """
        {"clarity":900,"sharpen":-20,"denoise":150}
        """
        let parsed = try EditorAdjustments.parse(json: json)
        XCTAssertEqual(parsed.clarity, 100)
        XCTAssertEqual(parsed.sharpen, 0)
        XCTAssertEqual(parsed.denoise, 100)
        XCTAssertTrue(parsed.isColorIdentity)
        XCTAssertFalse(parsed.isDetailIdentity)

        let defaults = try EditorAdjustments.parse(json: "{}")
        XCTAssertEqual(defaults.clarity, 0)
        XCTAssertEqual(defaults.sharpen, 0)
        XCTAssertEqual(defaults.denoise, 0)
        XCTAssertTrue(defaults.isDetailIdentity)

        let encoded = try JSONEncoder().encode(parsed)
        let decoded = try JSONDecoder().decode(EditorAdjustments.self, from: encoded)
        XCTAssertEqual(decoded, parsed)
        XCTAssertEqual(decoded.clamped(), parsed)
    }

    // MARK: - Helpers

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
