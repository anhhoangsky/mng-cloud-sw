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
}
