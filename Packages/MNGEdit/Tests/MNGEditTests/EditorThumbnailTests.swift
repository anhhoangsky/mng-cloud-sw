import Foundation
import XCTest
@testable import MNGEdit

/// The 128 px filter thumbnails: square centre crop, filter-graded, and cached
/// until the base bitmap changes.
final class EditorThumbnailTests: XCTestCase {
    private func snapshot(
        _ width: Int,
        _ height: Int,
        _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8)
    ) -> EditorSourceSnapshot {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let (r, g, b) = pixel(x, y)
                rgba[offset] = r
                rgba[offset + 1] = g
                rgba[offset + 2] = b
            }
        }
        return EditorSourceSnapshot(
            width: UInt32(width),
            height: UInt32(height),
            rgba: rgba
        )
    }

    private func gradient(_ width: Int, _ height: Int) -> EditorSourceSnapshot {
        snapshot(width, height) { x, y in
            (
                UInt8(x * 255 / max(1, width - 1)),
                UInt8(y * 255 / max(1, height - 1)),
                128
            )
        }
    }

    private func offset(_ thumbnail: EditorThumbnail, x: Int, y: Int) -> Int {
        (y * thumbnail.width + x) * 4
    }

    func testThumbnailIsSquareAndAtMost128() throws {
        let thumbnail = try XCTUnwrap(
            EditorThumbnailRenderer.render(
                filter: .original,
                source: gradient(300, 180)
            )
        )
        XCTAssertEqual(thumbnail.width, 128)
        XCTAssertEqual(thumbnail.height, 128)
        XCTAssertEqual(thumbnail.rgba.count, 128 * 128 * 4)
    }

    func testSmallSourceStaysSquareAndSmall() throws {
        let thumbnail = try XCTUnwrap(
            EditorThumbnailRenderer.render(
                filter: .original,
                source: gradient(64, 32)
            )
        )
        XCTAssertEqual(thumbnail.width, 32)
        XCTAssertEqual(thumbnail.height, 32)
        XCTAssertLessThanOrEqual(thumbnail.width, 128)
        XCTAssertEqual(thumbnail.rgba.count, 32 * 32 * 4)
    }

    func testSquareCropIsPixelAligned() throws {
        func cropPixels(
            _ crop: EditorCrop,
            width: UInt32,
            height: UInt32
        ) throws -> EditorCropPixels {
            var editor = try Editor(
                width: width,
                height: height,
                rgba: [UInt8](
                    repeating: 255,
                    count: Int(width * height * 4)
                )
            )
            editor.setCrop(crop)
            return editor.cropPixels()
        }

        let landscape = EditorThumbnailRenderer.squareCrop(
            width: 300,
            height: 180
        )
        XCTAssertEqual(
            try cropPixels(landscape, width: 300, height: 180),
            EditorCropPixels(x: 60, y: 0, width: 180, height: 180)
        )

        let portrait = EditorThumbnailRenderer.squareCrop(
            width: 180,
            height: 300
        )
        XCTAssertEqual(
            try cropPixels(portrait, width: 180, height: 300),
            EditorCropPixels(x: 0, y: 60, width: 180, height: 180)
        )

        let square = EditorThumbnailRenderer.squareCrop(
            width: 120,
            height: 120
        )
        XCTAssertEqual(square, .full)
        XCTAssertEqual(
            try cropPixels(square, width: 120, height: 120),
            EditorCropPixels(x: 0, y: 0, width: 120, height: 120)
        )
    }

    func testThumbnailCentreCropsTheSource() throws {
        // Left half red, right half blue. The 64 px centre square of this
        // 128x64 source keeps the middle 32 px of the red half and the first
        // 32 px of the blue half.
        let source = snapshot(128, 64) { x, _ in
            x < 64 ? (220, 20, 20) : (20, 20, 220)
        }
        let thumbnail = try XCTUnwrap(
            EditorThumbnailRenderer.render(filter: .original, source: source)
        )
        XCTAssertEqual(thumbnail.width, 64)
        XCTAssertEqual(thumbnail.height, 64)

        let left = offset(thumbnail, x: 0, y: 32)
        XCTAssertGreaterThan(thumbnail.rgba[left], thumbnail.rgba[left + 2])
        let right = offset(thumbnail, x: 63, y: 32)
        XCTAssertGreaterThan(thumbnail.rgba[right + 2], thumbnail.rgba[right])
    }

    func testMonoThumbnailIsGrey() throws {
        let thumbnail = try XCTUnwrap(
            EditorThumbnailRenderer.render(
                filter: .mono,
                source: gradient(96, 64)
            )
        )
        let centre = offset(thumbnail, x: 48, y: 32)
        let red = Int(thumbnail.rgba[centre])
        let green = Int(thumbnail.rgba[centre + 1])
        let blue = Int(thumbnail.rgba[centre + 2])
        XCTAssertLessThanOrEqual(abs(red - green), 1)
        XCTAssertLessThanOrEqual(abs(green - blue), 1)
    }

    func testCacheRendersOnceAndInvalidates() throws {
        let source = gradient(96, 96)
        let cache = EditorThumbnailCache()
        let first = try XCTUnwrap(
            cache.thumbnail(for: .original, source: source)
        )
        XCTAssertEqual(cache.renderCount, 1)
        let second = try XCTUnwrap(
            cache.thumbnail(for: .original, source: source)
        )
        XCTAssertEqual(cache.renderCount, 1)
        XCTAssertEqual(first, second)

        // A different filter is a different key.
        _ = cache.thumbnail(for: .mono, source: source)
        XCTAssertEqual(cache.renderCount, 2)

        cache.invalidate()
        let third = try XCTUnwrap(
            cache.thumbnail(for: .original, source: source)
        )
        XCTAssertEqual(cache.renderCount, 3)
        XCTAssertEqual(first, third)
    }

    func testCacheKeepsFiltersSeparate() throws {
        let source = gradient(80, 80)
        let cache = EditorThumbnailCache()
        let original = try XCTUnwrap(
            cache.thumbnail(for: .original, source: source)
        )
        let mono = try XCTUnwrap(
            cache.thumbnail(for: .mono, source: source)
        )
        XCTAssertNotEqual(original, mono)
        XCTAssertEqual(cache.renderCount, 2)
    }
}
