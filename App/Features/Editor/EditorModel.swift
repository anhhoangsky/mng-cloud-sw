import Foundation
import MNGEdit
import MNGKit
import Observation
import UIKit

/// Image editor for one library item.
///
/// The editor is the Aurum release, ported to the phone: the same presets,
/// the same adjustments and the same layout as the browser, but the pixels
/// are rendered on the device and never leave it before the export. The
/// source is decoded locally, the edits run through the `MNGEdit` pipeline
/// and only the encoded result is uploaded to `POST /items/{id}/edit`.
@MainActor
@Observable
final class EditorModel {
    /// The tabs of the editor, in the order of the Aurum release.
    enum Tab: String, CaseIterable, Identifiable {
        case adjust
        case filter
        case crop

        var id: String { rawValue }
    }

    enum SaveMode: String, CaseIterable, Identifiable {
        case overwrite
        case copy

        var id: String { rawValue }
    }

    /// The groups of the adjustments, the order the Aurum release uses.
    enum AdjustmentGroup: String, CaseIterable, Identifiable {
        case light
        case color
        case effect

        var id: String { rawValue }
    }

    /// The sliders of the editor.
    enum Adjustment: String, CaseIterable, Identifiable {
        case brightness
        case exposure
        case contrast
        case highlights
        case shadows
        case whites
        case blacks
        case saturation
        case vibrance
        case warmth
        case tint
        case gamma
        case vignette

        var id: String { rawValue }

        var group: AdjustmentGroup {
            switch self {
            case .brightness, .exposure, .contrast, .highlights, .shadows, .whites, .blacks:
                return .light
            case .saturation, .vibrance, .warmth, .tint, .gamma:
                return .color
            case .vignette:
                return .effect
            }
        }

        var title: String {
            switch self {
            case .brightness: return Strings.editorBrightness
            case .contrast: return Strings.editorContrast
            case .saturation: return Strings.editorSaturation
            case .exposure: return Strings.editorExposure
            case .warmth: return Strings.editorWarmth
            case .tint: return Strings.editorTint
            case .highlights: return Strings.editorHighlights
            case .shadows: return Strings.editorShadows
            case .whites: return Strings.editorWhites
            case .blacks: return Strings.editorBlacks
            case .vibrance: return Strings.editorVibrance
            case .gamma: return Strings.editorGamma
            case .vignette: return Strings.editorVignette
            }
        }

        /// The name on the chip of the editor.
        var shortTitle: String {
            switch self {
            case .brightness: return Strings.editorBrightnessShort
            case .contrast: return Strings.editorContrastShort
            case .saturation: return Strings.editorSaturationShort
            case .exposure: return Strings.editorExposureShort
            case .warmth: return Strings.editorWarmthShort
            case .tint: return Strings.editorTintShort
            case .highlights: return Strings.editorHighlightsShort
            case .shadows: return Strings.editorShadowsShort
            case .whites: return Strings.editorWhitesShort
            case .blacks: return Strings.editorBlacksShort
            case .vibrance: return Strings.editorVibranceShort
            case .gamma: return Strings.editorGammaShort
            case .vignette: return Strings.editorVignetteShort
            }
        }

        func value(in adjustments: EditorAdjustments) -> Float {
            switch self {
            case .brightness: return adjustments.brightness
            case .contrast: return adjustments.contrast
            case .saturation: return adjustments.saturation
            case .exposure: return adjustments.exposure
            case .warmth: return adjustments.warmth
            case .tint: return adjustments.tint
            case .highlights: return adjustments.highlights
            case .shadows: return adjustments.shadows
            case .whites: return adjustments.whites
            case .blacks: return adjustments.blacks
            case .vibrance: return adjustments.vibrance
            case .gamma: return adjustments.gamma
            case .vignette: return adjustments.vignette
            }
        }

        func set(_ value: Float, in adjustments: inout EditorAdjustments) {
            switch self {
            case .brightness: adjustments.brightness = value
            case .contrast: adjustments.contrast = value
            case .saturation: adjustments.saturation = value
            case .exposure: adjustments.exposure = value
            case .warmth: adjustments.warmth = value
            case .tint: adjustments.tint = value
            case .highlights: adjustments.highlights = value
            case .shadows: adjustments.shadows = value
            case .whites: adjustments.whites = value
            case .blacks: adjustments.blacks = value
            case .vibrance: adjustments.vibrance = value
            case .gamma: adjustments.gamma = value
            case .vignette: adjustments.vignette = value
            }
        }
    }

    /// The crop aspect presets of the editor.
    enum Aspect: String, CaseIterable, Identifiable {
        case free
        case square
        case fourThree
        case threeFour
        case sixteenNine
        case nineSixteen

        var id: String { rawValue }

        var title: String {
            switch self {
            case .free: return Strings.editorAspectFree
            case .square: return "1:1"
            case .fourThree: return "4:3"
            case .threeFour: return "3:4"
            case .sixteenNine: return "16:9"
            case .nineSixteen: return "9:16"
            }
        }

        /// Width divided by height; `nil` keeps the current rectangle.
        var ratio: Float? {
            switch self {
            case .free: return nil
            case .square: return 1
            case .fourThree: return 4.0 / 3.0
            case .threeFour: return 3.0 / 4.0
            case .sixteenNine: return 16.0 / 9.0
            case .nineSixteen: return 9.0 / 16.0
            }
        }
    }

    enum State: Equatable {
        case idle
        case loading
        case ready
        case saving
        case failed(String)
    }

    /// One step of the history.
    struct Snapshot: Equatable {
        var adjustments: EditorAdjustments
        var filter: EditorFilter
        var crop: EditorCrop
        var rotation: UInt8
        var flipH: Bool
        var flipV: Bool
    }

    let client: MNGAPIClient

    private(set) var state: State = .idle
    private(set) var item: Item?
    private(set) var preview: UIImage?
    private(set) var tab: Tab = .adjust
    private(set) var rotation: UInt8 = 0
    private(set) var flipH = false
    private(set) var flipV = false
    private(set) var crop: EditorCrop = .full
    private(set) var adjustments: EditorAdjustments = .zero
    private(set) var filter: EditorFilter = .original
    private(set) var mode: SaveMode = .overwrite
    private(set) var aspect: Aspect = .free
    /// The adjustment the pane shows.
    private(set) var activeAdjustment: Adjustment = .brightness
    /// The thumbnails of the presets, one per filter.
    private(set) var filterThumbnails: [EditorFilter: UIImage] = [:]
    /// The history of the edits.
    private(set) var canUndo = false
    private(set) var canRedo = false

    var onToast: ((String) -> Void)?
    var onSaved: (() -> Void)?
    var onUnauthorized: (() -> Void)?

    @ObservationIgnored private var editor: Editor?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var loadSeq = 0
    @ObservationIgnored private var undoStack: [Snapshot] = []
    @ObservationIgnored private var redoStack: [Snapshot] = []
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?

    init(client: MNGAPIClient) {
        self.client = client
    }

    // MARK: - Lifecycle

    /// Load the original image and prepare the editor.
    func open(item: Item) async {
        loadSeq &+= 1
        let seq = loadSeq
        state = .loading
        self.item = item
        do {
            let file = try await client.mediaFile(
                path: item.mediaPath(),
                suggestedName: item.name
            )
            defer {
                try? FileManager.default.removeItem(
                    at: file.url.deletingLastPathComponent()
                )
            }
            let data = try Data(contentsOf: file.url)
            guard let decoded = EditorImageDecoder.decode(data) else {
                state = .failed(Strings.editorUnsupported)
                return
            }
            guard seq == loadSeq else { return }
            let editor = try Editor(
                width: decoded.width,
                height: decoded.height,
                rgba: decoded.rgba
            )
            self.editor = editor
            rotation = 0
            flipH = false
            flipV = false
            crop = .full
            adjustments = .zero
            filter = .original
            aspect = .free
            activeAdjustment = .brightness
            undoStack = []
            redoStack = []
            filterThumbnails = [:]
            state = .ready
            renderPreview()
        } catch let error as APIError {
            guard seq == loadSeq else { return }
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            state = .failed(error.message)
        } catch {
            guard seq == loadSeq else { return }
            state = .failed(Strings.editorUnsupported)
        }
    }

    func close() {
        loadSeq &+= 1
        renderTask?.cancel()
        renderTask = nil
        thumbnailTask?.cancel()
        thumbnailTask = nil
        editor = nil
        preview = nil
        item = nil
        filterThumbnails = [:]
        state = .idle
    }

    // MARK: - Geometry

    func selectTab(_ tab: Tab) {
        self.tab = tab
        if tab == .filter, filterThumbnails.isEmpty {
            renderFilterThumbnails()
        }
    }

    func selectMode(_ mode: SaveMode) {
        self.mode = mode
    }

    func selectAdjustment(_ adjustment: Adjustment) {
        activeAdjustment = adjustment
    }

    func rotate(_ delta: Int) {
        guard var editor else { return }
        pushHistory()
        let next = (Int(editor.rotation) + delta + 4) % 4
        editor.setGeometry(rotate: UInt8(next), flipH: flipH, flipV: flipV)
        self.editor = editor
        rotation = UInt8(next)
        crop = .full
        aspect = .free
        renderPreview()
    }

    /// Set the angle of the photo, in quarter turns.
    func setRotation(_ value: Int) {
        guard var editor else { return }
        let next = ((value % 4) + 4) % 4
        guard next != Int(editor.rotation) else { return }
        pushHistory()
        editor.setGeometry(rotate: UInt8(next), flipH: flipH, flipV: flipV)
        self.editor = editor
        rotation = UInt8(next)
        crop = .full
        aspect = .free
        renderPreview()
    }

    func flip(horizontal: Bool) {
        guard var editor else { return }
        pushHistory()
        if horizontal {
            flipH.toggle()
        } else {
            flipV.toggle()
        }
        editor.setGeometry(rotate: rotation, flipH: flipH, flipV: flipV)
        self.editor = editor
        renderPreview()
    }

    // MARK: - Crop

    func setCrop(_ crop: EditorCrop) {
        self.crop = crop
    }

    func commitCrop() {
        pushHistory()
    }

    func resetCrop() {
        pushHistory()
        crop = .full
        aspect = .free
    }

    /// Apply one aspect preset to the current rectangle.
    func applyAspect(_ aspect: Aspect) {
        guard let ratio = aspect.ratio else {
            self.aspect = .free
            return
        }
        self.aspect = aspect
        var rect = crop
        // Keep the centre of the current rectangle.
        let centerX = rect.x + rect.width / 2
        let centerY = rect.y + rect.height / 2
        var width = rect.width
        var height = width / ratio
        if height > 1 {
            height = 1
            width = height * ratio
        }
        if width > 1 {
            width = 1
            height = width / ratio
        }
        rect.width = width
        rect.height = height
        rect.x = min(max(centerX - width / 2, 0), 1 - width)
        rect.y = min(max(centerY - height / 2, 0), 1 - height)
        crop = EditorCrop(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    // MARK: - Adjustments and filters

    func setAdjustment(_ key: Adjustment, value: Float) {
        var values = adjustments
        key.set(value, in: &values)
        adjustments = values
        applyAdjustments()
    }

    /// Move the slider of the adjustment that is on screen.
    func setActiveAdjustment(value: Float) {
        setAdjustment(activeAdjustment, value: value)
    }

    func resetAdjustments() {
        pushHistory()
        adjustments = .zero
        applyAdjustments()
    }

    func setFilter(_ filter: EditorFilter) {
        pushHistory()
        self.filter = filter
        applyAdjustments()
    }

    /// Analyse the photo and set the adjustments that fit it.
    func applyAutoTune() {
        guard let preview, editor != nil else { return }
        pushHistory()
        guard let analysis = EditorModel.analyse(preview) else { return }
        var values = adjustments
        values.brightness = analysis.brightness
        values.contrast = analysis.contrast
        values.saturation = analysis.saturation
        adjustments = values
        applyAdjustments()
    }

    /// Read the photo and guess the adjustments that fit it.
    ///
    /// The photo is brought into a small bitmap, the middle grey of the
    /// histogram is measured and the colours are counted.
    private static func analyse(_ image: UIImage) -> (
        brightness: Float,
        contrast: Float,
        saturation: Float
    )? {
        guard let cgImage = image.cgImage else { return nil }
        let width = 64
        let height = max(Int((CGFloat(cgImage.height) / CGFloat(cgImage.width)) * 64), 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var sum: Double = 0
        var sumSquares: Double = 0
        var saturationSum: Double = 0
        var count = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            let luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            sum += luma
            sumSquares += luma * luma
            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            saturationSum += maximum > 0 ? (maximum - minimum) / maximum : 0
            count += 1
        }
        guard count > 0 else { return nil }
        let mean = sum / count
        let variance = max(sumSquares / count - mean * mean, 0)
        let deviation = variance.squareRoot()
        let saturation = saturationSum / count
        // A photo that is too dark or too flat is lifted, the rest is left
        // alone.
        let brightness = Float(min(max((0.5 - mean) * 90, -35), 35))
        let contrast = Float(min(max((0.22 - deviation) * 120, -12), 24))
        let saturationValue = Float(min(max((0.28 - saturation) * 90, -10), 20))
        return (brightness, contrast, saturationValue)
    }

    private func applyAdjustments() {
        guard var editor else { return }
        editor.setAdjustments(adjustments)
        editor.setFilter(filter)
        self.editor = editor
        renderPreview()
    }

    // MARK: - History

    /// Remember the state before a change, so it can be undone.
    private func pushHistory() {
        undoStack.append(
            Snapshot(
                adjustments: adjustments,
                filter: filter,
                crop: crop,
                rotation: rotation,
                flipH: flipH,
                flipV: flipV
            )
        )
        if undoStack.count > 60 {
            undoStack.removeFirst()
        }
        redoStack = []
        canUndo = !undoStack.isEmpty
        canRedo = false
    }

    func undo() {
        guard var editor, let previous = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        apply(previous, to: &editor)
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func redo() {
        guard var editor, let next = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        apply(next, to: &editor)
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func currentSnapshot() -> Snapshot {
        Snapshot(
            adjustments: adjustments,
            filter: filter,
            crop: crop,
            rotation: rotation,
            flipH: flipH,
            flipV: flipV
        )
    }

    private func apply(_ snapshot: Snapshot, to editor: inout Editor) {
        adjustments = snapshot.adjustments
        filter = snapshot.filter
        crop = snapshot.crop
        rotation = snapshot.rotation
        flipH = snapshot.flipH
        flipV = snapshot.flipV
        aspect = .free
        editor.setGeometry(rotate: rotation, flipH: flipH, flipV: flipV)
        editor.setAdjustments(adjustments)
        editor.setFilter(filter)
        editor.setCrop(crop)
        self.editor = editor
        renderPreview()
    }

    // MARK: - Saving

    /// Encode the edited image and upload it back to the item.
    func save() async {
        guard let item, let editor else { return }
        guard state != .saving else { return }
        state = .saving
        let format = EditorModel.exportFormat(for: item)
        var prepared = editor
        prepared.setCrop(crop)
        do {
            let data = try await Task.detached(priority: .userInitiated) { [prepared] in
                var copy = prepared
                return try copy.renderExport(format: format, quality: 92)
            }.value
            let response = try await client.saveEdit(
                id: item.id,
                data: data,
                filename: exportName(for: item, format: format),
                mime: format.mime,
                mode: mode.rawValue
            )
            state = .ready
            let message = response.message.trimmingCharacters(in: .whitespacesAndNewlines)
            onToast?(message.isEmpty ? Strings.editorSaved : message)
            onSaved?()
        } catch let error as APIError {
            state = .ready
            if error.status == 401 {
                onUnauthorized?()
                return
            }
            onToast?(error.message)
        } catch {
            state = .ready
            onToast?(Strings.editorSaveFailed)
        }
    }

    /// The web editor keeps the source container: PNG stays PNG, WebP stays
    /// WebP and everything else becomes JPEG.
    static func exportFormat(for item: Item) -> EditorExportFormat {
        let mime = item.mime.lowercased()
        if mime == "image/png" {
            return .png
        }
        if mime == "image/webp", EditorExportFormat.webp.isEncodable {
            return .webp
        }
        return .jpeg
    }

    private func exportName(for item: Item, format: EditorExportFormat) -> String {
        let base = (item.name as NSString).deletingPathExtension
        let suffix = (item.name as NSString).pathExtension
        if suffix.lowercased() == format.fileExtension {
            return item.name
        }
        return base.isEmpty ? "edit.\(format.fileExtension)" : "\(base).\(format.fileExtension)"
    }

    // MARK: - Preview

    /// Re-render the preview off the main actor.
    private func renderPreview() {
        guard let editor else { return }
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            // Debounce slider moves so the preview does not flicker.
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled else { return }
            let rendered = await Task.detached(priority: .userInitiated) { [editor] in
                var copy = editor
                // The preview shows the whole oriented image; the crop is drawn
                // as an overlay and applied on export.
                copy.setCrop(.full)
                let rgba = copy.renderPreview(maxSide: 1200)
                return (
                    rgba: rgba,
                    width: copy.lastRenderSize.width,
                    height: copy.lastRenderSize.height
                )
            }.value
            guard !Task.isCancelled else { return }
            guard let image = EditorModel.image(
                from: rendered.rgba,
                width: rendered.width,
                height: rendered.height
            ) else {
                return
            }
            await MainActor.run {
                self?.preview = image
            }
        }
    }

    /// Render the small preview of every preset, so the pane of the filters
    /// shows what the photo looks like.
    private func renderFilterThumbnails() {
        guard let editor else { return }
        thumbnailTask?.cancel()
        thumbnailTask = Task { [weak self] in
            let rendered = await Task.detached(priority: .userInitiated) { [editor] in
                var thumbnails: [EditorFilter: (rgba: [UInt8], width: UInt32, height: UInt32)] = [:]
                for filter in EditorFilter.allCases {
                    var copy = editor
                    copy.setFilter(filter)
                    copy.setCrop(.full)
                    let rgba = copy.renderPreview(maxSide: 180)
                    thumbnails[filter] = (
                        rgba: rgba,
                        width: copy.lastRenderSize.width,
                        height: copy.lastRenderSize.height
                    )
                }
                return thumbnails
            }.value
            guard !Task.isCancelled else { return }
            var images: [EditorFilter: UIImage] = [:]
            for (filter, rendered) in rendered {
                guard let image = EditorModel.image(
                    from: rendered.rgba,
                    width: rendered.width,
                    height: rendered.height
                ) else {
                    continue
                }
                images[filter] = image
            }
            await MainActor.run {
                self?.filterThumbnails = images
            }
        }
    }

    /// Build a UIImage from straight RGBA bytes.
    static func image(
        from rgba: [UInt8],
        width: UInt32,
        height: UInt32
    ) -> UIImage? {
        let expected = Int(width) * Int(height) * 4
        guard width > 0, height > 0, rgba.count == expected else { return nil }
        let buffer = rgba
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(buffer) as CFData),
              let cgImage = CGImage(
                width: Int(width),
                height: Int(height),
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: Int(width) * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
