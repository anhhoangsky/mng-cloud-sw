import CoreGraphics
import XCTest
@testable import MNGEdit

final class CollageTests: XCTestCase {
    // MARK: - Catalog

    func testCatalogLoadsTheSharedSpec() {
        let layouts = Collage.layouts
        XCTAssertEqual(layouts.count, 19)
        XCTAssertEqual(Set(layouts.map(\.id)).count, layouts.count)
        for count in Collage.minCells...Collage.maxCells {
            XCTAssertFalse(
                Collage.layouts(for: count).isEmpty,
                "no layout for \(count) photos"
            )
        }
    }

    func testEveryLayoutIsInsideAndCoversTheFrame() {
        for layout in Collage.layouts {
            XCTAssertEqual(layout.cellCount, layout.cells.count)
            XCTAssertGreaterThanOrEqual(layout.cellCount, Collage.minCells)
            XCTAssertLessThanOrEqual(layout.cellCount, Collage.maxCells)

            var area = 0.0
            for cell in layout.cells {
                XCTAssertGreaterThan(cell.width, 0)
                XCTAssertGreaterThan(cell.height, 0)
                XCTAssertGreaterThanOrEqual(cell.x, -1e-12)
                XCTAssertGreaterThanOrEqual(cell.y, -1e-12)
                XCTAssertLessThanOrEqual(cell.x + cell.width, 1 + 1e-12)
                XCTAssertLessThanOrEqual(cell.y + cell.height, 1 + 1e-12)
                area += cell.width * cell.height
            }
            XCTAssertEqual(area, 1, accuracy: 1e-9, layout.id)

            for first in 0..<layout.cells.count {
                for second in (first + 1)..<layout.cells.count {
                    let a = layout.cells[first]
                    let b = layout.cells[second]
                    let overlapWidth = min(
                        a.x + a.width,
                        b.x + b.width
                    ) - max(a.x, b.x)
                    let overlapHeight = min(
                        a.y + a.height,
                        b.y + b.height
                    ) - max(a.y, b.y)
                    XCTAssertFalse(
                        overlapWidth > 1e-12 && overlapHeight > 1e-12,
                        "\(layout.id) cells \(first) and \(second) overlap"
                    )
                }
            }
        }
    }

    func testLayoutLookupAndPhotoCounts() {
        XCTAssertEqual(Collage.layout(id: "nine-grid")?.cellCount, 9)
        XCTAssertNil(Collage.layout(id: "nine-grid-2"))
        XCTAssertEqual(Collage.layouts(for: 3).count, 4)
        XCTAssertTrue(Collage.layouts(for: 1).isEmpty)
    }

    // MARK: - Gap

    func testGapKeepsOneGutterEverywhere() {
        let none = Collage.cellRects(layoutID: "duo-split", gap: 0)
        assertRect(none[0], 0, 0, 0.5, 1)

        let gapped = Collage.cellRects(layoutID: "duo-split", gap: 0.04)
        assertRect(gapped[0], 0.04, 0.04, 0.44, 0.92)
        XCTAssertEqual(
            gapped[1].x - (gapped[0].x + gapped[0].width),
            0.04,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            gapped[1].x + gapped[1].width,
            0.96,
            accuracy: 1e-12
        )
    }

    func testGapClampsAndInvalidValuesFallBack() {
        let widest = Collage.cellRects(layoutID: "duo-split", gap: 1)
        XCTAssertEqual(
            widest[0].width,
            0.5 * (1 - Collage.maxGap) - Collage.maxGap,
            accuracy: 1e-12
        )
        assertRect(
            Collage.cellRects(layoutID: "duo-split", gap: -2)[0],
            0,
            0,
            0.5,
            1
        )
        assertRect(
            Collage.cellRects(layoutID: "duo-split", gap: .nan)[0],
            0,
            0,
            0.5,
            1
        )
        XCTAssertTrue(
            Collage.cellRects(layoutID: "missing", gap: 0).isEmpty
        )
    }

    func testEqualColumnsSurviveTheGap() {
        let trio = Collage.cellRects(layoutID: "trio-columns", gap: 0)
        for index in 0..<3 {
            XCTAssertEqual(trio[index].width, 1.0 / 3, accuracy: 1e-9)
        }

        let nine = Collage.cellRects(layoutID: "nine-grid", gap: 0.03)
        XCTAssertEqual(nine[0].width, nine[1].width, accuracy: 1e-12)
        XCTAssertEqual(nine[1].width, nine[2].width, accuracy: 1e-12)
        XCTAssertEqual(nine[0].height, nine[3].height, accuracy: 1e-12)
    }

    // MARK: - State

    func testDefaultStateMatchesTheWebDocument() {
        let state = Collage.defaultState()
        XCTAssertEqual(state.layout, "duo-split")
        XCTAssertEqual(state.cells.count, 2)
        XCTAssertEqual(state.cells[0].source, 0)
        XCTAssertEqual(state.cells[1].source, 1)
        XCTAssertEqual(state.gap, Collage.defaultGap)
        XCTAssertEqual(state.radius, 0)
        XCTAssertEqual(state.background, Collage.defaultBackground)
        XCTAssertEqual(Collage.defaultState(layoutID: "nope").layout,
                       Collage.layouts[0].id)
    }

    func testNormalizePadsTrimsAndClamps() throws {
        let padded = Collage.normalize(
            CollageState(layout: "nine-grid", cells: [
                CollageCellState(source: 7),
            ])
        )
        XCTAssertEqual(padded.cells.count, 9)
        XCTAssertEqual(padded.cells[0].source, 7)
        XCTAssertEqual(padded.cells[8].source, 8)

        let trimmed = Collage.normalize(
            CollageState(layout: "duo-split", cells: Array(
                repeating: CollageCellState(),
                count: 5
            ))
        )
        XCTAssertEqual(trimmed.cells.count, 2)

        let clamped = Collage.normalize(
            CollageState(
                layout: "duo-split",
                gap: 9,
                radius: 9,
                background: "#AbC",
                cells: [
                    CollageCellState(
                        source: -3,
                        zoom: 0.2,
                        offsetX: -8,
                        offsetY: 8
                    ),
                    CollageCellState(
                        source: 2,
                        zoom: 9,
                        offsetX: 8,
                        offsetY: -8
                    ),
                ]
            )
        )
        XCTAssertEqual(clamped.cells[0].zoom, 1)
        XCTAssertEqual(clamped.cells[1].zoom, Collage.maxZoom)
        XCTAssertEqual(clamped.cells[0].source, 0)
        XCTAssertEqual(clamped.cells[0].offsetX, -1)
        XCTAssertEqual(clamped.cells[0].offsetY, 1)
        XCTAssertEqual(clamped.cells[1].offsetX, 1)
        XCTAssertEqual(clamped.gap, Collage.maxGap)
        XCTAssertEqual(clamped.radius, Collage.maxRadius)
        XCTAssertEqual(clamped.background, "#aabbcc")
        XCTAssertEqual(
            Collage.normalize(
                CollageState(layout: "duo-split", background: "red")
            ).background,
            "#ffffff"
        )
    }

    func testUnknownLayoutKeepsTheCellCountWhenPossible() {
        let four = Collage.normalize(
            CollageState(layout: "missing", cells: Array(
                repeating: CollageCellState(),
                count: 4
            ))
        )
        XCTAssertEqual(four.cells.count, 4)
        XCTAssertEqual(Collage.layout(id: four.layout)?.cellCount, 4)

        let empty = Collage.normalize(CollageState(layout: "missing"))
        XCTAssertEqual(empty.layout, Collage.layouts[0].id)
        XCTAssertEqual(empty.cells.count, 2)
    }

    func testDecodingTruncatesSourceAndFillsDefaults() throws {
        let data = Data(
            #"{"layout":"duo-split","cells":[{"source":2.9,"zoom":9}]}"#
                .utf8
        )
        let decoded = try JSONDecoder().decode(CollageState.self, from: data)
        let normalized = Collage.normalize(decoded)
        XCTAssertEqual(normalized.cells[0].source, 2)
        XCTAssertEqual(normalized.cells[0].zoom, Collage.maxZoom)
        XCTAssertEqual(normalized.cells[1].source, 1)
        XCTAssertEqual(normalized.gap, Collage.defaultGap)
        XCTAssertEqual(normalized.background, "#ffffff")
    }

    // MARK: - Cover

    func testCoverCropsTheOverflowingAxis() {
        let wide = Collage.cover(
            sourceWidth: 100,
            sourceHeight: 100,
            cellWidth: 200,
            cellHeight: 100
        )
        XCTAssertEqual(wide.sw, 100, accuracy: 1e-12)
        XCTAssertEqual(wide.sh, 50, accuracy: 1e-12)
        XCTAssertEqual(wide.sy, 25, accuracy: 1e-12)
        XCTAssertGreaterThanOrEqual(wide.dw, 200)
        XCTAssertGreaterThanOrEqual(wide.dh, 100)

        let zoomed = Collage.cover(
            sourceWidth: 100,
            sourceHeight: 100,
            cellWidth: 200,
            cellHeight: 100,
            zoom: 2
        )
        XCTAssertEqual(zoomed.sw, 50, accuracy: 1e-12)
        XCTAssertEqual(zoomed.sh, 25, accuracy: 1e-12)
    }

    func testCoverPanReachesBothEdges() {
        let left = Collage.cover(
            sourceWidth: 100,
            sourceHeight: 100,
            cellWidth: 100,
            cellHeight: 200,
            offsetX: -1
        )
        let right = Collage.cover(
            sourceWidth: 100,
            sourceHeight: 100,
            cellWidth: 100,
            cellHeight: 200,
            offsetX: 1
        )
        XCTAssertEqual(left.sx, 0, accuracy: 1e-12)
        XCTAssertEqual(right.sx, 100 - right.sw, accuracy: 1e-12)

        let top = Collage.cover(
            sourceWidth: 100,
            sourceHeight: 200,
            cellWidth: 100,
            cellHeight: 100,
            offsetY: -1
        )
        let bottom = Collage.cover(
            sourceWidth: 100,
            sourceHeight: 200,
            cellWidth: 100,
            cellHeight: 100,
            offsetY: 1
        )
        XCTAssertEqual(top.sy, 0, accuracy: 1e-12)
        XCTAssertEqual(bottom.sy, 200 - bottom.sh, accuracy: 1e-12)
    }

    func testCoverDegeneratesAndClamps() {
        let portrait = Collage.cover(
            sourceWidth: 50,
            sourceHeight: 100,
            cellWidth: 200,
            cellHeight: 100
        )
        XCTAssertEqual(portrait.sw, 50, accuracy: 1e-12)
        XCTAssertEqual(portrait.sh, 25, accuracy: 1e-12)
        XCTAssertEqual(portrait.sy, 37.5, accuracy: 1e-12)

        let low = Collage.cover(
            sourceWidth: 100,
            sourceHeight: 100,
            cellWidth: 200,
            cellHeight: 100,
            zoom: 0.1
        )
        XCTAssertEqual(low.sw, 100, accuracy: 1e-12)
        XCTAssertEqual(low.sh, 50, accuracy: 1e-12)

        XCTAssertEqual(
            Collage.cover(
                sourceWidth: 0,
                sourceHeight: 0,
                cellWidth: 10,
                cellHeight: 10
            ),
            .zero
        )
        XCTAssertEqual(
            Collage.cover(
                sourceWidth: .nan,
                sourceHeight: 10,
                cellWidth: 10,
                cellHeight: 10
            ),
            .zero
        )
    }

    // MARK: - Renderer

    func testRenderPlacesSourcesLeftToRight() throws {
        let output = try render(
            CollageState(
                layout: "duo-split",
                gap: 0,
                radius: 0,
                background: "#101010"
            ),
            sources: [solid(255, 0, 0), solid(0, 255, 0)],
            size: 128
        )
        assertColor(output, 32, 64, 255, 0, 0)
        assertColor(output, 96, 64, 0, 255, 0)
    }

    func testRenderKeepsTopDownOrientation() throws {
        let output = try render(
            CollageState(
                layout: "duo-stack",
                gap: 0,
                radius: 0,
                background: "#101010"
            ),
            sources: [solid(255, 0, 0), solid(0, 0, 255)],
            size: 128
        )
        assertColor(output, 64, 32, 255, 0, 0)
        assertColor(output, 64, 96, 0, 0, 255)
    }

    func testRenderShowsTheBackgroundInGapsAndCorners() throws {
        let gapped = try render(
            CollageState(
                layout: "duo-split",
                gap: 0.1,
                radius: 0,
                background: "#101010"
            ),
            sources: [solid(255, 0, 0), solid(0, 255, 0)],
            size: 200
        )
        assertColor(gapped, 2, 100, 16, 16, 16)
        assertColor(gapped, 100, 100, 16, 16, 16)
        assertColor(gapped, 50, 100, 255, 0, 0)
        assertColor(gapped, 150, 100, 0, 255, 0)

        let rounded = try render(
            CollageState(
                layout: "duo-split",
                gap: 0,
                radius: Collage.maxRadius,
                background: "#101010"
            ),
            sources: [solid(255, 0, 0)],
            size: 200
        )
        assertColor(rounded, 1, 1, 16, 16, 16)
        assertColor(rounded, 50, 100, 255, 0, 0)
    }

    func testRenderKeepsMissingSourcesOnTheBackground() throws {
        let output = try render(
            CollageState(
                layout: "duo-split",
                gap: 0,
                radius: 0,
                background: "#101010"
            ),
            sources: [],
            size: 64
        )
        assertColor(output, 32, 32, 16, 16, 16)
    }

    func testRenderFillsEveryNineGridCell() throws {
        let palette: [(Int, Int, Int)] = [
            (230, 57, 70), (241, 250, 238), (168, 218, 220),
            (69, 123, 157), (29, 53, 87), (255, 183, 3),
            (251, 133, 0), (131, 56, 236), (58, 134, 255),
        ]
        let output = try render(
            CollageState(
                layout: "nine-grid",
                gap: 0,
                radius: 0,
                background: "#000000"
            ),
            sources: palette.map { solid($0.0, $0.1, $0.2) },
            size: 180
        )
        for index in 0..<9 {
            let x = 30 + (index % 3) * 60
            let y = 30 + (index / 3) * 60
            assertColor(
                output,
                x,
                y,
                palette[index].0,
                palette[index].1,
                palette[index].2
            )
        }
    }

    // MARK: - Image entry point

    /// The preview path draws decoded `CGImage`s directly; it must produce
    /// exactly the same bytes as the snapshot path, which is the one the
    /// existing callers and the web client's contract use.
    func testImageRenderMatchesTheSnapshotRender() throws {
        let state = CollageState(
            layout: "nine-grid",
            gap: 0.05,
            radius: 0.2,
            background: "#f3c77b"
        )
        let palette: [(Int, Int, Int)] = [
            (230, 57, 70), (241, 250, 238), (168, 218, 220),
            (69, 123, 157), (29, 53, 87), (255, 183, 3),
            (251, 133, 0), (131, 56, 236), (58, 134, 255),
        ]
        let sources = palette.map {
            solid($0.0, $0.1, $0.2, width: 90, height: 70)
        }
        let images = try sources.map { try image($0) }

        let expected = try render(state, sources: sources, size: 180)
        let rendered = try XCTUnwrap(
            CollageRenderer.renderImage(
                state: state,
                images: images,
                size: 180
            )
        )
        XCTAssertEqual(rendered.width, 180)
        XCTAssertEqual(rendered.height, 180)
        let output = try snapshot(rendered)
        XCTAssertEqual(output.width, 180)
        XCTAssertEqual(output.height, 180)
        XCTAssertEqual(output.rgba, expected.rgba)
    }

    func testImageRenderKeepsTopDownOrientation() throws {
        let images = [
            try image(solid(255, 0, 0)),
            try image(solid(0, 0, 255)),
        ]
        let rendered = try XCTUnwrap(
            CollageRenderer.renderImage(
                state: CollageState(
                    layout: "duo-stack",
                    gap: 0,
                    radius: 0,
                    background: "#101010"
                ),
                images: images,
                size: 128
            )
        )
        let output = try snapshot(rendered)
        assertColor(output, 64, 32, 255, 0, 0)
        assertColor(output, 64, 96, 0, 0, 255)
    }

    func testImageRenderKeepsMissingSourcesOnTheBackground() throws {
        let rendered = try XCTUnwrap(
            CollageRenderer.renderImage(
                state: CollageState(
                    layout: "duo-split",
                    gap: 0,
                    radius: 0,
                    background: "#101010"
                ),
                images: [try image(solid(255, 0, 0))],
                size: 64
            )
        )
        let output = try snapshot(rendered)
        assertColor(output, 16, 32, 255, 0, 0)
        assertColor(output, 48, 32, 16, 16, 16)
    }

    // MARK: - Helpers

    private func assertRect(
        _ rect: CollageRect,
        _ x: Double,
        _ y: Double,
        _ width: Double,
        _ height: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(rect.x, x, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(rect.y, y, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(
            rect.width,
            width,
            accuracy: 1e-12,
            file: file,
            line: line
        )
        XCTAssertEqual(
            rect.height,
            height,
            accuracy: 1e-12,
            file: file,
            line: line
        )
    }

    private func solid(
        _ red: Int,
        _ green: Int,
        _ blue: Int,
        width: Int = 64,
        height: Int = 64
    ) -> EditorSourceSnapshot {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for index in stride(from: 0, to: rgba.count, by: 4) {
            rgba[index] = UInt8(red)
            rgba[index + 1] = UInt8(green)
            rgba[index + 2] = UInt8(blue)
            rgba[index + 3] = 255
        }
        return EditorSourceSnapshot(
            width: UInt32(width),
            height: UInt32(height),
            rgba: rgba
        )
    }

    private func render(
        _ state: CollageState,
        sources: [EditorSourceSnapshot],
        size: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> EditorSourceSnapshot {
        try XCTUnwrap(
            CollageRenderer.render(
                state: state,
                sources: sources,
                size: size
            ),
            file: file,
            line: line
        )
    }

    private func image(
        _ snapshot: EditorSourceSnapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> CGImage {
        try XCTUnwrap(
            EditorBitmap.cgImage(
                width: Int(snapshot.width),
                height: Int(snapshot.height),
                rgba: snapshot.rgba
            ),
            file: file,
            line: line
        )
    }

    /// Read a rendered image back into the snapshot shape the pixel helpers
    /// use, so the image entry point is checked with the same asserts as the
    /// snapshot entry point.
    private func snapshot(
        _ image: CGImage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> EditorSourceSnapshot {
        let output = try XCTUnwrap(
            EditorBitmap.topDownRGBA(from: image),
            file: file,
            line: line
        )
        return EditorSourceSnapshot(
            width: UInt32(output.width),
            height: UInt32(output.height),
            rgba: output.rgba
        )
    }

    private func assertColor(
        _ snapshot: EditorSourceSnapshot,
        _ x: Int,
        _ y: Int,
        _ red: Int,
        _ green: Int,
        _ blue: Int,
        tolerance: Int = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let width = Int(snapshot.width)
        let offset = (y * width + x) * 4
        guard offset >= 0, offset + 3 < snapshot.rgba.count else {
            XCTFail("pixel out of bounds", file: file, line: line)
            return
        }
        let got = (
            Int(snapshot.rgba[offset]),
            Int(snapshot.rgba[offset + 1]),
            Int(snapshot.rgba[offset + 2]),
            Int(snapshot.rgba[offset + 3])
        )
        XCTAssertEqual(got.3, 255, "alpha", file: file, line: line)
        XCTAssertLessThanOrEqual(
            abs(got.0 - red),
            tolerance,
            "red at \(x),\(y)",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            abs(got.1 - green),
            tolerance,
            "green at \(x),\(y)",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            abs(got.2 - blue),
            tolerance,
            "blue at \(x),\(y)",
            file: file,
            line: line
        )
    }
}
