import CoreGraphics
import Foundation

/// The collage layout contract shared with the web client.
///
/// `layouts.json` stores every layout on a 12 × 12 unit grid, so a third of
/// the frame is exactly `4/12` and two clients that read the same file cannot
/// disagree about a cell edge. A cell is a rectangle; the rounded corners are
/// applied at render time, which keeps the geometry testable without a canvas.
public struct CollageRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// One layout of the rail: 2…9 rectangles in draw order.
public struct CollageLayout: Equatable, Sendable {
    public let id: String
    /// Normalized to the square frame, 0…1.
    public let cells: [CollageRect]

    public var cellCount: Int { cells.count }

    public init(id: String, cells: [CollageRect]) {
        self.id = id
        self.cells = cells
    }
}

/// The source crop and destination box of one photo inside its cell.
public struct CollageCover: Equatable, Sendable {
    public var sx: Double
    public var sy: Double
    public var sw: Double
    public var sh: Double
    public var dx: Double
    public var dy: Double
    public var dw: Double
    public var dh: Double

    public static let zero = CollageCover(
        sx: 0,
        sy: 0,
        sw: 0,
        sh: 0,
        dx: 0,
        dy: 0,
        dw: 0,
        dh: 0
    )
}

/// How one photo sits inside its cell.
///
/// `zoom` 1 covers the cell exactly; larger values crop in. The offsets are a
/// fraction of the slack: `-1` shows the left/top edge, `+1` the right/bottom
/// edge, and `0` centres the photo. The renderer clamps both ends, so a cell
/// can never show the background through a pan.
public struct CollageCellState: Codable, Equatable, Sendable {
    /// Index into the source list the host hands to the renderer.
    public var source: Int
    public var zoom: Double
    public var offsetX: Double
    public var offsetY: Double

    public init(
        source: Int = 0,
        zoom: Double = 1,
        offsetX: Double = 0,
        offsetY: Double = 0
    ) {
        self.source = source
        self.zoom = zoom
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    private enum CodingKeys: String, CodingKey {
        case source, zoom, offsetX, offsetY
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The web stores the source as a number; reading it as a Double here
        // truncates a hand-edited 2.9 the same way `Math.floor` does.
        let rawSource = try container.decodeIfPresent(
            Double.self,
            forKey: .source
        )
        if let rawSource, rawSource.isFinite, abs(rawSource) < 1e9 {
            source = Int(rawSource.rounded(.towardZero))
        } else {
            source = 0
        }
        zoom = try container.decodeIfPresent(Double.self, forKey: .zoom) ?? 1
        offsetX = try container.decodeIfPresent(
            Double.self,
            forKey: .offsetX
        ) ?? 0
        offsetY = try container.decodeIfPresent(
            Double.self,
            forKey: .offsetY
        ) ?? 0
    }
}

/// The editable collage document.
public struct CollageState: Codable, Equatable, Sendable {
    public var layout: String
    /// Gutter between and around the cells, a fraction of the frame side.
    public var gap: Double
    /// Corner radius, a fraction of the shorter side of each cell.
    public var radius: Double
    public var background: String
    public var cells: [CollageCellState]

    public init(
        layout: String,
        gap: Double = Collage.defaultGap,
        radius: Double = 0,
        background: String = Collage.defaultBackground,
        cells: [CollageCellState] = []
    ) {
        self.layout = layout
        self.gap = gap
        self.radius = radius
        self.background = background
        self.cells = cells
    }

    private enum CodingKeys: String, CodingKey {
        case layout, gap, radius, background, cells
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layout = try container.decodeIfPresent(String.self, forKey: .layout)
            ?? ""
        gap = try container.decodeIfPresent(Double.self, forKey: .gap)
            ?? Collage.defaultGap
        radius = try container.decodeIfPresent(Double.self, forKey: .radius)
            ?? 0
        background = try container.decodeIfPresent(
            String.self,
            forKey: .background
        ) ?? Collage.defaultBackground
        cells = try container.decodeIfPresent(
            [CollageCellState].self,
            forKey: .cells
        ) ?? []
    }
}

/// The collage engine: the shared catalog, the geometry and the renderer.
public enum Collage {
    public static let minCells = 2
    public static let maxCells = 9
    /// 6 % of the frame side is the widest gutter the rail offers.
    public static let maxGap = 0.06
    /// 0.5 makes a cell a capsule; larger values are clamped per cell.
    public static let maxRadius = 0.5
    public static let maxZoom = 4.0
    public static let defaultGap = 0.012
    public static let defaultBackground = "#ffffff"

    /// Every valid layout of the shared spec, in rail order.
    public static let layouts: [CollageLayout] = loadLayouts()

    /// The layout with this id, or nil when the spec does not name it.
    public static func layout(id: String) -> CollageLayout? {
        lookup[id]
    }

    /// Every layout that holds exactly `count` photos.
    public static func layouts(for count: Int) -> [CollageLayout] {
        layouts.filter { $0.cellCount == count }
    }

    /// The gap shrinks the whole grid by `gap` and every cell by another
    /// `gap` on each side, so the outer border and the gutters all measure one
    /// gap.
    public static func cellRects(
        layout: CollageLayout,
        gap: Double
    ) -> [CollageRect] {
        let gutter = clamp(finite(gap, 0), 0, maxGap)
        let scale = 1 - gutter
        return layout.cells.map { cell in
            CollageRect(
                x: gutter + cell.x * scale,
                y: gutter + cell.y * scale,
                width: max(0, cell.width * scale - gutter),
                height: max(0, cell.height * scale - gutter)
            )
        }
    }

    /// Convenience for callers holding only the layout id.
    public static func cellRects(layoutID: String, gap: Double) -> [CollageRect] {
        guard let layout = layout(id: layoutID) else { return [] }
        return cellRects(layout: layout, gap: gap)
    }

    /// Cover-fit one source inside a cell.
    ///
    /// The scale is the larger of the two cover ratios, so at `zoom` 1 the
    /// photo always fills the cell and only the overflowing axis is cropped.
    /// The pan is expressed as a fraction of the slack, which keeps both ends
    /// reachable and never exposes the background.
    public static func cover(
        sourceWidth: Double,
        sourceHeight: Double,
        cellWidth: Double,
        cellHeight: Double,
        zoom: Double = 1,
        offsetX: Double = 0,
        offsetY: Double = 0
    ) -> CollageCover {
        guard sourceWidth.isFinite,
              sourceHeight.isFinite,
              cellWidth.isFinite,
              cellHeight.isFinite,
              sourceWidth > 0,
              sourceHeight > 0,
              cellWidth > 0,
              cellHeight > 0 else {
            return .zero
        }
        let zoomValue = clamp(finite(zoom, 1), 1, maxZoom)
        let panX = clamp(finite(offsetX, 0), -1, 1)
        let panY = clamp(finite(offsetY, 0), -1, 1)
        let scale = max(
            cellWidth / sourceWidth,
            cellHeight / sourceHeight
        ) * zoomValue
        let dw = sourceWidth * scale
        let dh = sourceHeight * scale
        let dx = (cellWidth - dw) * (1 + panX) / 2
        let dy = (cellHeight - dh) * (1 + panY) / 2
        let sw = min(sourceWidth, cellWidth / scale)
        let sh = min(sourceHeight, cellHeight / scale)
        let sx = clamp(
            -dx / scale,
            0,
            max(0, sourceWidth - sw)
        )
        let sy = clamp(
            -dy / scale,
            0,
            max(0, sourceHeight - sh)
        )
        return CollageCover(
            sx: sx,
            sy: sy,
            sw: sw,
            sh: sh,
            dx: dx,
            dy: dy,
            dw: dw,
            dh: dh
        )
    }

    /// Normalize an untrusted collage document.
    ///
    /// The layout decides the cell count: extra cells are trimmed and missing
    /// ones are filled, so changing two photos to a three-cell layout cannot
    /// leave the renderer with a hole. A document whose layout is unknown
    /// keeps its cell count when a layout offers it, otherwise it falls back
    /// to the first layout.
    public static func normalize(_ state: CollageState) -> CollageState {
        let target = layout(id: state.layout)
            ?? layouts(for: state.cells.count).first
            ?? layouts.first
        guard let target else {
            return CollageState(
                layout: "",
                gap: defaultGap,
                radius: 0,
                background: defaultBackground,
                cells: []
            )
        }
        let cells = target.cells.enumerated().map { index, _ in
            let cell = index < state.cells.count
                ? state.cells[index]
                : CollageCellState(source: index)
            return CollageCellState(
                source: max(0, cell.source),
                zoom: clamp(finite(cell.zoom, 1), 1, maxZoom),
                offsetX: clamp(finite(cell.offsetX, 0), -1, 1),
                offsetY: clamp(finite(cell.offsetY, 0), -1, 1)
            )
        }
        return CollageState(
            layout: target.id,
            gap: clamp(finite(state.gap, defaultGap), 0, maxGap),
            radius: clamp(finite(state.radius, 0), 0, maxRadius),
            background: normalizeBackground(state.background),
            cells: cells
        )
    }

    /// A fresh document: the first cell per photo, one source each.
    public static func defaultState(
        layoutID: String = "duo-split"
    ) -> CollageState {
        let target = layout(id: layoutID) ?? layouts.first
        guard let target else {
            return normalize(CollageState(layout: ""))
        }
        return CollageState(
            layout: target.id,
            gap: defaultGap,
            radius: 0,
            background: defaultBackground,
            cells: target.cells.enumerated().map { index, _ in
                CollageCellState(source: index)
            }
        )
    }

    // MARK: - Spec loading

    private static let lookup: [String: CollageLayout] = {
        var result: [String: CollageLayout] = [:]
        for layout in layouts where result[layout.id] == nil {
            result[layout.id] = layout
        }
        return result
    }()

    private struct LayoutFile: Decodable {
        let version: Int
        let unit: Double?
        let layouts: [RawLayout]
    }

    private struct RawLayout: Decodable {
        let id: String
        let cells: [[Double]]
    }

    private static func loadLayouts() -> [CollageLayout] {
        // `.copy("Resources")` keeps the folder in the bundle; the flat lookup
        // is a fallback for a toolchain that flattens copied directories.
        let url = Bundle.module.url(
            forResource: "layouts",
            withExtension: "json",
            subdirectory: "Resources"
        ) ?? Bundle.module.url(
            forResource: "layouts",
            withExtension: "json"
        )
        guard let url else {
            assertionFailure("layouts.json is missing from the MNGEdit bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(LayoutFile.self, from: data)
            guard file.version == 1 else {
                assertionFailure(
                    "unsupported layouts.json version \(file.version)"
                )
                return []
            }
            let unit = file.unit.flatMap { value in
                value.isFinite && value > 0 ? value : nil
            } ?? 12
            var seen = Set<String>()
            var result: [CollageLayout] = []
            for raw in file.layouts {
                guard !raw.id.isEmpty, !seen.contains(raw.id) else { continue }
                guard raw.cells.count >= minCells,
                      raw.cells.count <= maxCells else {
                    continue
                }
                var cells: [CollageRect] = []
                var valid = true
                for rawCell in raw.cells {
                    guard rawCell.count == 4 else {
                        valid = false
                        break
                    }
                    let x = rawCell[0]
                    let y = rawCell[1]
                    let width = rawCell[2]
                    let height = rawCell[3]
                    guard x.isFinite,
                          y.isFinite,
                          width.isFinite,
                          height.isFinite,
                          width > 0,
                          height > 0,
                          x >= 0,
                          y >= 0,
                          x + width <= unit,
                          y + height <= unit else {
                        valid = false
                        break
                    }
                    cells.append(
                        CollageRect(
                            x: x / unit,
                            y: y / unit,
                            width: width / unit,
                            height: height / unit
                        )
                    )
                }
                guard valid else { continue }
                seen.insert(raw.id)
                result.append(CollageLayout(id: raw.id, cells: cells))
            }
            return result
        } catch {
            assertionFailure("layouts.json does not decode: \(error)")
            return []
        }
    }

    // MARK: - Helpers

    private static func normalizeBackground(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if text.count == 7,
           text.hasPrefix("#"),
           text.dropFirst().allSatisfy({ $0.isHexDigit }) {
            return text
        }
        if text.count == 4,
           text.hasPrefix("#"),
           text.dropFirst().allSatisfy({ $0.isHexDigit }) {
            let digits = Array(text.dropFirst())
            return "#\(digits[0])\(digits[0])\(digits[1])\(digits[1])"
                + "\(digits[2])\(digits[2])"
        }
        return defaultBackground
    }

    /// `Double.isFinite` plus the web's `finite(value, fallback)` behaviour.
    static func finite(_ value: Double, _ fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }

    static func clamp(_ value: Double, _ lower: Double, _ upper: Double)
        -> Double {
        min(max(value, lower), upper)
    }
}

/// Composite a collage from already rendered sources.
///
/// The host renders each cell (a child aurum state, an adjusted bitmap or a
/// plain photo) and passes the snapshots in source order; this pass only lays
/// them out, so preview and export share one geometry. The whole frame is
/// painted with the background first, which also makes an opaque JPEG export
/// impossible to get wrong.
public enum CollageRenderer {
    /// Composite the layout into a new image.
    ///
    /// This is the preview path: the host already holds decoded `CGImage`s,
    /// so a frame costs one draw instead of a copy of every source's RGBA
    /// bytes. `sources` keeps the original signature for the snapshot entry
    /// point and for hosts that render child aurum states.
    public static func renderImage(
        state: CollageState,
        images: [CGImage],
        size: Int
    ) -> CGImage? {
        renderImage(
            state: state,
            images: images.map { Optional($0) },
            size: size
        )
    }

    /// Composite already rendered sources into a snapshot.
    ///
    /// The conversion of every snapshot to a `CGImage` happens once, then the
    /// normal draw pass runs; both entry points share the same geometry and
    /// the same pixels.
    public static func render(
        state: CollageState,
        sources: [EditorSourceSnapshot],
        size: Int
    ) -> EditorSourceSnapshot? {
        let images: [CGImage?] = sources.map {
            EditorBitmap.cgImage(
                width: Int($0.width),
                height: Int($0.height),
                rgba: $0.rgba
            )
        }
        guard let image = renderImage(state: state, images: images, size: size),
              let output = EditorBitmap.topDownRGBA(from: image) else {
            return nil
        }
        return EditorSourceSnapshot(
            width: UInt32(output.width),
            height: UInt32(output.height),
            rgba: output.rgba
        )
    }

    private static func renderImage(
        state: CollageState,
        images: [CGImage?],
        size: Int
    ) -> CGImage? {
        let next = Collage.normalize(state)
        let side = max(1, size)
        guard let layout = Collage.layout(id: next.layout) else { return nil }
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(color(from: next.background))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.interpolationQuality = .high

        let rects = Collage.cellRects(layout: layout, gap: next.gap)
        for (index, rect) in rects.enumerated() {
            let x0 = (rect.x * Double(side)).rounded()
            let top0 = (rect.y * Double(side)).rounded()
            let x1 = ((rect.x + rect.width) * Double(side)).rounded()
            let top1 = ((rect.y + rect.height) * Double(side)).rounded()
            let width = Int(x1 - x0)
            let height = Int(top1 - top0)
            guard width > 0, height > 0 else { continue }

            // Core Graphics keeps the origin at the bottom-left; the spec and
            // the raw buffer are top-down, so flip the cell's y once.
            let box = CGRect(
                x: x0,
                y: Double(side) - top1,
                width: Double(width),
                height: Double(height)
            )
            context.saveGState()
            let shortest = Double(min(width, height))
            let radius = min(next.radius * shortest, shortest / 2)
            if radius > 0.5 {
                context.addPath(
                    CGPath(
                        roundedRect: box,
                        cornerWidth: radius,
                        cornerHeight: radius,
                        transform: nil
                    )
                )
            } else {
                context.addRect(box)
            }
            context.clip()

            if index < next.cells.count {
                let cell = next.cells[index]
                if cell.source >= 0, cell.source < images.count,
                   let image = images[cell.source] {
                    draw(image, cell: cell, in: box, context: context)
                }
            }
            context.restoreGState()
        }

        return context.makeImage()
    }

    private static func draw(
        _ image: CGImage,
        cell: CollageCellState,
        in box: CGRect,
        context: CGContext
    ) {
        let cover = Collage.cover(
            sourceWidth: Double(image.width),
            sourceHeight: Double(image.height),
            cellWidth: box.width,
            cellHeight: box.height,
            zoom: cell.zoom,
            offsetX: cell.offsetX,
            offsetY: cell.offsetY
        )
        guard cover.sw > 0, cover.sh > 0 else { return }
        // `dx`/`dy` are top-left offsets inside the cell; the destination box
        // is placed against `box.maxY` so the draw stays upright after the
        // bottom-left flip above.
        let destination = CGRect(
            x: box.minX + cover.dx,
            y: box.maxY - cover.dy - cover.dh,
            width: cover.dw,
            height: cover.dh
        )
        context.draw(image, in: destination)
    }

    private static let deviceRGB = CGColorSpaceCreateDeviceRGB()

    private static func color(from hex: String) -> CGColor {
        let text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
        let components: [CGFloat] = [
            CGFloat((value >> 16) & 0xFF) / 255,
            CGFloat((value >> 8) & 0xFF) / 255,
            CGFloat(value & 0xFF) / 255,
            1,
        ]
        // The bitmap context uses Device RGB; staying in that space keeps
        // `#101010` at 16,16,16 instead of letting a generic-RGB conversion
        // lift it to 20,20,20.
        return CGColor(colorSpace: deviceRGB, components: components)
            ?? CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    }
}
