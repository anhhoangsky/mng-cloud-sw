import Foundation

/// One square thumbnail of the current photo with a filter applied.
///
/// The bytes are straight sRGB RGBA, row-major, top row first. The app turns
/// them into a `UIImage`; the cache keeps the bytes so the filter rail can be
/// rebuilt without rendering the photo again.
public struct EditorThumbnail: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

/// Renders the 128 px filter thumbnails of the filter rail.
///
/// This is the Swift counterpart of the web's `presetThumbnail`: a square
/// centre crop of the source photo, scaled down and colour-graded by one
/// filter. Thumbnails intentionally depend only on the loaded bitmap and the
/// filter, not on the current adjustments, portrait sliders or effect paint.
/// The web builds them from its frozen preview bitmap, so changing a slider
/// must not rebuild 29 thumbnails.
enum EditorThumbnailRenderer {
    /// The web's thumbnail edge, in pixels.
    static let side = 128

    /// Render one filter thumbnail from the base bitmap.
    static func render(
        filter: EditorFilter,
        source: EditorSourceSnapshot,
        side: Int = EditorThumbnailRenderer.side
    ) -> EditorThumbnail? {
        let limit = min(max(side, 16), 512)
        let expected = Int(source.width) * Int(source.height) * 4
        guard source.width > 0,
              source.height > 0,
              source.rgba.count == expected else {
            return nil
        }
        var editor: Editor
        do {
            editor = try Editor(
                width: source.width,
                height: source.height,
                rgba: source.rgba
            )
        } catch {
            return nil
        }
        // A centre square at 128 px matches the web's cover draw: the rail
        // shows a square card and never letterboxes a portrait or landscape.
        editor.setCrop(squareCrop(width: source.width, height: source.height))
        editor.setFilter(filter)
        let rgba = editor.renderPreview(maxSide: UInt32(limit))
        let size = editor.lastRenderSize
        guard let square = centreSquare(
            rgba,
            width: Int(size.width),
            height: Int(size.height)
        ) else {
            return nil
        }
        return EditorThumbnail(
            width: square.width,
            height: square.height,
            rgba: square.rgba
        )
    }

    /// Pixel-aligned centre square of an oriented image.
    ///
    /// The normalised edges are nudged inward by a ten-thousandth of a pixel.
    /// `Editor.cropPixels()` floors the left edge and ceils the right edge, so
    /// an exact boundary such as `0.2 × 300` would otherwise pick up an extra
    /// source column and turn a square crop into 181 × 180.
    static func squareCrop(width: UInt32, height: UInt32) -> EditorCrop {
        let w = Int(max(1, width))
        let h = Int(max(1, height))
        let side = min(w, h)
        if side == w, side == h {
            return .full
        }
        let x0 = (w - side) / 2
        let y0 = (h - side) / 2
        let inset: Float = 0.0001
        return EditorCrop(
            x: (Float(x0) + inset) / Float(w),
            y: (Float(y0) + inset) / Float(h),
            width: (Float(side) - 2 * inset) / Float(w),
            height: (Float(side) - 2 * inset) / Float(h)
        )
    }

    /// Trim the odd pixel column or row that rounding can leave after a
    /// downscale, so every thumbnail is a true square.
    static func centreSquare(
        _ rgba: [UInt8],
        width: Int,
        height: Int
    ) -> (width: Int, height: Int, rgba: [UInt8])? {
        guard width > 0,
              height > 0,
              rgba.count == width * height * 4 else {
            return nil
        }
        let side = min(width, height)
        if side == width, side == height {
            return (width, height, rgba)
        }
        let x0 = (width - side) / 2
        let y0 = (height - side) / 2
        var out = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            let source = ((y0 + y) * width + x0) * 4
            let destination = y * side * 4
            out.replaceSubrange(
                destination..<(destination + side * 4),
                with: rgba[source..<(source + side * 4)]
            )
        }
        return (side, side, out)
    }
}

/// A bounded cache of rendered filter thumbnails.
///
/// The cache is keyed by filter and source dimensions, so one instance can be
/// reused while a photo is open. The editor model replaces the whole cache
/// when the base bitmap changes (a new photo, an AI bake or an AI revert), so
/// an in-flight render of the old photo cannot pollute the new one; callers
/// that keep one instance can call `invalidate()` instead. The cache is
/// thread-safe: rendering happens off the main actor and the app may ask for
/// the whole rail at once.
public final class EditorThumbnailCache: @unchecked Sendable {
    /// The side used by the filter rail.
    public static let side = EditorThumbnailRenderer.side

    private let cache = NSCache<NSString, Box>()
    private let lock = NSLock()
    /// Bumped by `invalidate()`; a render that started before the bump must
    /// not write its stale bitmap back into the fresh cache.
    private var generation = 0
    /// The number of thumbnails rendered through this cache. Tests use it to
    /// prove a hit does not render and an invalidation does.
    private(set) var renderCount = 0

    private final class Box {
        let value: EditorThumbnail

        init(_ value: EditorThumbnail) {
            self.value = value
        }
    }

    public init(countLimit: Int = 64) {
        let limit = max(1, countLimit)
        cache.countLimit = limit
        cache.totalCostLimit = limit * Self.side * Self.side * 4
    }

    /// Drop every thumbnail and reject renders that started before the call.
    public func invalidate() {
        lock.lock()
        generation &+= 1
        cache.removeAllObjects()
        lock.unlock()
    }

    /// A cached thumbnail, or a freshly rendered one.
    public func thumbnail(
        for filter: EditorFilter,
        source: EditorSourceSnapshot,
        side: Int = EditorThumbnailCache.side
    ) -> EditorThumbnail? {
        let limit = min(max(side, 16), 512)
        let key = (
            "\(source.width)x\(source.height):"
                + "\(filter.rawValue):\(limit)"
        ) as NSString

        lock.lock()
        let startGeneration = generation
        if let box = cache.object(forKey: key) {
            let value = box.value
            lock.unlock()
            return value
        }
        lock.unlock()

        guard let thumbnail = EditorThumbnailRenderer.render(
            filter: filter,
            source: source,
            side: limit
        ) else {
            return nil
        }

        lock.lock()
        renderCount &+= 1
        if generation == startGeneration {
            cache.setObject(
                Box(thumbnail),
                forKey: key,
                cost: thumbnail.rgba.count
            )
        }
        lock.unlock()
        return thumbnail
    }
}
