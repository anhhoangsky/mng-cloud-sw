import CoreGraphics
import ImageIO
import XCTest
@testable import MNGEdit

final class EditorTests: XCTestCase {
    private func pixels(_ width: Int, _ height: Int) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(width * height * 4)
        for index in 0..<(width * height) {
            let x = index % width
            let y = index / width
            out.append(UInt8((x * 17 + 3) % 256))
            out.append(UInt8((y * 29 + 7) % 256))
            out.append(UInt8(((x + y) * 11) % 256))
            out.append(255)
        }
        return out
    }

    /// The decoder has to keep the rows in the order of the image.
    ///
    /// A picture whose top half is blue and whose bottom half is red is
    /// written as a PNG and read back. The first row of the buffer has to
    /// be the blue one, otherwise the editor shows the photo upside down.
    func testTheDecoderKeepsTheRowsTopDown() throws {
        let width = 64
        let height = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return XCTFail("the context could not be made")
        }
        // The context draws from the bottom left, so the blue half is the
        // top of the picture.
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        guard let image = context.makeImage() else {
            return XCTFail("the image could not be made")
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return XCTFail("the destination could not be made")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return XCTFail("the picture could not be written")
        }

        guard let decoded = EditorImageDecoder.decode(data as Data) else {
            return XCTFail("the picture could not be read")
        }
        XCTAssertEqual(decoded.width, UInt32(width))
        XCTAssertEqual(decoded.height, UInt32(height))
        // The first row is the blue one. The exact values move a little,
        // because the picture is written in the colour space of the display
        // and read back in the one of the device, so the hue is what counts.
        let first = Array(decoded.rgba[0..<4])
        XCTAssertGreaterThan(first[2], first[0] + 40)
        // The row in the middle is the red one.
        let middle = (height / 2) * width * 4
        let middleRow = Array(decoded.rgba[middle..<(middle + 4)])
        XCTAssertGreaterThan(middleRow[0], middleRow[2] + 40)
    }

    func testRejectsInvalidBuffersAndDimensions() {
        XCTAssertThrowsError(try Editor(width: 0, height: 10, rgba: [])) { error in
            XCTAssertEqual(error as? MNGEditError, .invalidDimensions)
        }
        XCTAssertThrowsError(try Editor(width: 10, height: 10, rgba: [UInt8](repeating: 0, count: 10))) {
            XCTAssertEqual($0 as? MNGEditError, .invalidBuffer)
        }
        XCTAssertNoThrow(try Editor(width: 4, height: 4, rgba: [UInt8](repeating: 0, count: 64)))
    }

    func testCropNormalizationIsBounded() {
        let crop = EditorCrop(x: -1, y: 0.5, width: 4, height: 0.2)
        XCTAssertEqual(crop.x, 0)
        XCTAssertEqual(crop.y, 0.5)
        XCTAssertEqual(crop.width, 1)
        XCTAssertEqual(crop.height, 0.2)
        XCTAssertEqual(EditorCrop(x: .nan, y: 0, width: 1, height: 1), EditorCrop.full)
        XCTAssertEqual(EditorCrop(x: 0.9, y: 0.9, width: 0.9, height: 0.9).width, 0.1, accuracy: 0.000001)
    }

    func testTextRotationWrapsInsteadOfClamping() {
        // The handle can spin past the ±180° branch cut; the stored angle has
        // to keep turning instead of sticking at the limit.
        let layer = EditorTextLayer(id: "text", text: "A")
        XCTAssertEqual(
            EditorTextLayer(id: "text", rotation: 190).normalized().rotation,
            -170,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            EditorTextLayer(id: "text", rotation: 540).normalized().rotation,
            180,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            EditorTextLayer(id: "text", rotation: -190).normalized().rotation,
            170,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            EditorTextLayer(id: "text", rotation: 725).normalized().rotation,
            5,
            accuracy: 0.0001
        )
        XCTAssertEqual(layer.normalized().rotation, 0)
    }

    func testRotationMapsTheFirstSourcePixelToTheExpectedCorner() throws {
        let source: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255]

        var editor = try Editor(width: 2, height: 1, rgba: source)
        editor.setGeometry(rotate: 1, flipH: false, flipV: false)
        var rgba = editor.renderPreview()
        // 90 CW: the left pixel becomes the top row.
        XCTAssertEqual(Array(rgba[0..<4]), [255, 0, 0, 255])
        XCTAssertEqual(Array(rgba[4..<8]), [0, 255, 0, 255])

        var counter = try Editor(width: 2, height: 1, rgba: source)
        counter.setGeometry(rotate: 3, flipH: false, flipV: false)
        rgba = counter.renderPreview()
        // 90 CCW: the right pixel becomes the top row.
        XCTAssertEqual(Array(rgba[0..<4]), [0, 255, 0, 255])
        XCTAssertEqual(Array(rgba[4..<8]), [255, 0, 0, 255])
    }

    func testFlipsApplyAfterRotation() throws {
        let source: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255]

        var editor = try Editor(width: 2, height: 1, rgba: source)
        editor.setGeometry(rotate: 0, flipH: true, flipV: false)
        var rgba = editor.renderPreview()
        XCTAssertEqual(Array(rgba[0..<4]), [0, 255, 0, 255])
        XCTAssertEqual(Array(rgba[4..<8]), [255, 0, 0, 255])

        var rotated = try Editor(width: 2, height: 1, rgba: source)
        rotated.setGeometry(rotate: 1, flipH: true, flipV: false)
        rgba = rotated.renderPreview()
        // Rotated to green/red, then flipped vertically.
        XCTAssertEqual(Array(rgba[0..<4]), [255, 0, 0, 255])
        XCTAssertEqual(Array(rgba[4..<8]), [0, 255, 0, 255])
    }

    func testCropSelectsTheRequestedCornerAtFullResolution() throws {
        let source = pixels(4, 2)
        var editor = try Editor(width: 4, height: 2, rgba: source)
        editor.setCrop(EditorCrop(x: 0.5, y: 0, width: 0.5, height: 0.5))
        XCTAssertEqual(
            editor.cropPixels(),
            EditorCropPixels(x: 2, y: 0, width: 2, height: 1)
        )
        let rgba = editor.renderPreview()
        XCTAssertEqual(rgba.count, 2 * 4)
        XCTAssertEqual(Array(rgba[0..<4]), Array(source[(2 * 4)..<(3 * 4)]))
    }

    func testPreviewIsBoundedAndKeepsTheAspectRatio() throws {
        let source = pixels(400, 200)
        var editor = try Editor(width: 400, height: 200, rgba: source)
        let rgba = editor.renderPreview(maxSide: 100)
        XCTAssertEqual(editor.lastRenderSize.width, 100)
        XCTAssertEqual(editor.lastRenderSize.height, 50)
        XCTAssertEqual(rgba.count, 100 * 50 * 4)

        var rotated = try Editor(width: 400, height: 200, rgba: source)
        rotated.setGeometry(rotate: 1, flipH: false, flipV: false)
        let rotatedRGBA = rotated.renderPreview(maxSide: 100)
        XCTAssertEqual(rotated.lastRenderSize.width, 50)
        XCTAssertEqual(rotated.lastRenderSize.height, 100)
        XCTAssertEqual(rotatedRGBA.count, 50 * 100 * 4)
    }

    func testIdentityAdjustmentsDoNotChangePixels() throws {
        let source = pixels(3, 2)
        var editor = try Editor(width: 3, height: 2, rgba: source)
        XCTAssertEqual(editor.renderPreview(), source)
    }

    func testPerspectiveValuesAreClamped() throws {
        var editor = try Editor(
            width: 2,
            height: 2,
            rgba: [UInt8](repeating: 255, count: 16)
        )
        editor.setPerspective(x: 140, y: -160)
        XCTAssertEqual(editor.perspectiveXDegrees, 100)
        XCTAssertEqual(editor.perspectiveYDegrees, -100)

        editor.setPerspective(x: .nan, y: .infinity)
        XCTAssertEqual(editor.perspectiveXDegrees, 0)
        XCTAssertEqual(editor.perspectiveYDegrees, 0)
    }

    /// A stripe at a quarter of the frame has to move outwards on the axis
    /// whose positive direction grows that edge: Y grows the top, X the left.
    func testPositivePerspectivePullsTheTopAndLeftOutwards() throws {
        let side = 64
        let stripe = 14..<18
        var vertical: [UInt8] = []
        var horizontal: [UInt8] = []
        vertical.reserveCapacity(side * side * 4)
        horizontal.reserveCapacity(side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                vertical += stripe.contains(y)
                    ? [255, 0, 0, 255]
                    : [0, 0, 255, 255]
                horizontal += stripe.contains(x)
                    ? [255, 0, 0, 255]
                    : [0, 0, 255, 255]
            }
        }

        func stripeCenter(_ rgba: [UInt8], columns: Bool) -> Int {
            var best = -1
            var bestCount = 0
            for line in 0..<side {
                var count = 0
                for other in 0..<side {
                    let x = columns ? line : other
                    let y = columns ? other : line
                    let offset = (y * side + x) * 4
                    if rgba[offset] > 180 && rgba[offset + 2] < 80 {
                        count += 1
                    }
                }
                if count > bestCount {
                    bestCount = count
                    best = line
                }
            }
            return best
        }

        var up = try Editor(width: 64, height: 64, rgba: vertical)
        up.setPerspective(x: 0, y: 100)
        let upRow = stripeCenter(up.renderPreview(), columns: false)

        var down = try Editor(width: 64, height: 64, rgba: vertical)
        down.setPerspective(x: 0, y: -100)
        let downRow = stripeCenter(down.renderPreview(), columns: false)

        XCTAssertGreaterThanOrEqual(upRow, 0)
        XCTAssertLessThan(upRow, 12)
        XCTAssertGreaterThan(downRow, upRow + 2)

        var left = try Editor(width: 64, height: 64, rgba: horizontal)
        left.setPerspective(x: 100, y: 0)
        let leftColumn = stripeCenter(left.renderPreview(), columns: true)

        var right = try Editor(width: 64, height: 64, rgba: horizontal)
        right.setPerspective(x: -100, y: 0)
        let rightColumn = stripeCenter(right.renderPreview(), columns: true)

        XCTAssertGreaterThanOrEqual(leftColumn, 0)
        XCTAssertLessThan(leftColumn, 12)
        XCTAssertGreaterThan(rightColumn, leftColumn + 2)
    }

    func testAdjustmentsAreClampedAndParseJSON() throws {
        let adjustments = try EditorAdjustments.parse(
            json: #"{"brightness":900,"contrast":-900,"vignette":10}"#
        )
        XCTAssertEqual(adjustments.brightness, 100)
        XCTAssertEqual(adjustments.contrast, -100)
        XCTAssertEqual(adjustments.vignette, 10)
        XCTAssertThrowsError(try EditorAdjustments.parse(json: "not json"))
    }

    func testMonoFilterRemovesColorAndOtherFiltersPreserveAlpha() throws {
        let source: [UInt8] = [200, 40, 10, 128]
        var editor = try Editor(width: 1, height: 1, rgba: source)
        editor.setFilter(.mono)
        var rgba = editor.renderPreview()
        XCTAssertEqual(rgba[0], rgba[1])
        XCTAssertEqual(rgba[1], rgba[2])
        XCTAssertEqual(rgba[3], 128)

        var warm = try Editor(width: 1, height: 1, rgba: source)
        warm.setFilter(.warm)
        rgba = warm.renderPreview()
        XCTAssertGreaterThanOrEqual(rgba[0], 200)
        XCTAssertLessThanOrEqual(rgba[2], 10)
        XCTAssertEqual(rgba[3], 128)
    }

    func testExportsUseTheExpectedContainers() throws {
        let source = pixels(8, 6)
        let formats: [(EditorExportFormat, [UInt8])] = [
            (.jpeg, [0xFF, 0xD8]),
            (.png, [0x89, 0x50, 0x4E, 0x47]),
            (.webp, [0x52, 0x49, 0x46, 0x46]),
        ]
        for (format, prefix) in formats {
            if format == .webp, !format.isEncodable {
                throw XCTSkip("WebP encoding is not available on this platform")
            }
            var editor = try Editor(width: 8, height: 6, rgba: source)
            let encoded = try editor.renderExport(format: format, quality: 90)
            XCTAssertEqual(Array(encoded.prefix(prefix.count)), prefix, "\(format)")
            XCTAssertGreaterThan(encoded.count, 8)
        }
    }

    func testUnknownFilterAndFormatAreRejected() {
        XCTAssertThrowsError(try EditorFilter(key: "sepia")) { error in
            guard case .unknownFilter = error as? MNGEditError else {
                return XCTFail("expected an unknown filter error")
            }
        }
        XCTAssertThrowsError(try EditorExportFormat(key: "gif")) { error in
            guard case .unknownFormat = error as? MNGEditError else {
                return XCTFail("expected an unknown format error")
            }
        }
        XCTAssertEqual(try EditorExportFormat(key: "jpg"), .jpeg)
    }

    /// The AI passes swap the base bitmap but keep every edit above it.
    func testReplacingSourceKeepsTheEditState() throws {
        let original = pixels(4, 3)
        var editor = try Editor(width: 4, height: 3, rgba: original)
        editor.setGeometry(rotate: 1, flipH: true, flipV: false)
        editor.setFineRotation(12.5)
        editor.setPerspective(x: 14, y: -9)
        editor.setCrop(EditorCrop(x: 0, y: 0, width: 1, height: 0.5))
        editor.setAdjustments(
            EditorAdjustments(brightness: 18, contrast: -7, saturation: 9)
        )
        editor.setFilter(.warm)
        let text = EditorTextLayer(id: "caption", text: "Aurum")
        editor.setTextLayers([text])

        let snapshot = EditorSourceSnapshot(
            width: 4,
            height: 3,
            rgba: Array(pixels(4, 3).reversed())
        )
        let replaced = try editor.replacingSource(snapshot)

        XCTAssertEqual(replaced.width, 4)
        XCTAssertEqual(replaced.height, 3)
        XCTAssertEqual(replaced.rotation, 1)
        XCTAssertEqual(replaced.isFlippedHorizontally, true)
        XCTAssertEqual(replaced.isFlippedVertically, false)
        XCTAssertEqual(replaced.fineRotationDegrees, 12.5)
        XCTAssertEqual(replaced.perspectiveXDegrees, 14)
        XCTAssertEqual(replaced.perspectiveYDegrees, -9)
        XCTAssertEqual(replaced.currentCrop, editor.currentCrop)
        XCTAssertEqual(replaced.currentAdjustments, editor.currentAdjustments)
        XCTAssertEqual(replaced.currentFilter, .warm)
        XCTAssertEqual(replaced.textLayers, [text])
        XCTAssertEqual(replaced.outputSize().width, editor.outputSize().width)
        XCTAssertEqual(replaced.outputSize().height, editor.outputSize().height)
    }

    /// A transparent cut-out has to survive the snapshot round trip without
    /// losing its alpha or flipping its rows.
    func testReplacingSourceKeepsStraightAlpha() throws {
        var editor = try Editor(
            width: 3,
            height: 1,
            rgba: [UInt8](repeating: 0, count: 12)
        )
        let snapshot = EditorSourceSnapshot(
            width: 3,
            height: 1,
            rgba: [
                255, 0, 0, 255,
                0, 255, 0, 128,
                0, 0, 255, 0,
            ]
        )
        editor = try editor.replacingSource(snapshot)
        let rgba = editor.renderPreview()
        XCTAssertEqual(Array(rgba[0..<12]), snapshot.rgba)
    }
}
