import Foundation
import MNGEdit
import MNGKit
import Observation
import UIKit

/// Image editor for one library item.
///
/// The pixels never leave the device before the export: the source is decoded
/// locally, the edits run through the `MNGEdit` pipeline and only the encoded
/// result is uploaded to `POST /items/{id}/edit`.
@MainActor
@Observable
final class EditorModel {
    enum Tab: String, CaseIterable, Identifiable {
        case crop
        case adjust
        case filter

        var id: String { rawValue }
    }

    enum SaveMode: String, CaseIterable, Identifiable {
        case overwrite
        case copy

        var id: String { rawValue }
    }

    /// The nine sliders, in the order of the web editor.
    enum Adjustment: String, CaseIterable, Identifiable {
        case brightness
        case contrast
        case saturation
        case exposure
        case warmth
        case tint
        case highlights
        case shadows
        case vignette

        var id: String { rawValue }

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
            case .vignette: return Strings.editorVignette
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
            case .vignette: adjustments.vignette = value
            }
        }
    }

    /// The crop aspect presets of the web editor.
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

    var onToast: ((String) -> Void)?
    var onSaved: (() -> Void)?
    var onUnauthorized: (() -> Void)?

    @ObservationIgnored private var editor: Editor?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var loadSeq = 0

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
            mode = .overwrite
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
        editor = nil
        preview = nil
        item = nil
        state = .idle
    }

    // MARK: - Geometry

    func selectTab(_ tab: Tab) {
        self.tab = tab
    }

    func selectMode(_ mode: SaveMode) {
        self.mode = mode
    }

    func rotate(_ delta: Int) {
        guard var editor else { return }
        let next = (Int(editor.rotation) + delta + 4) % 4
        editor.setGeometry(rotate: UInt8(next), flipH: flipH, flipV: flipV)
        self.editor = editor
        rotation = UInt8(next)
        crop = .full
        aspect = .free
        renderPreview()
    }

    func flip(horizontal: Bool) {
        guard var editor else { return }
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

    func resetCrop() {
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

    func resetAdjustments() {
        adjustments = .zero
        applyAdjustments()
    }

    func setFilter(_ filter: EditorFilter) {
        self.filter = filter
        applyAdjustments()
    }

    private func applyAdjustments() {
        guard var editor else { return }
        editor.setAdjustments(adjustments)
        editor.setFilter(filter)
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

    /// Upload an image that was edited outside the native pipeline, for
    /// example by the Aurum web editor. The route is the same one the native
    /// export uses, so the server needs no new endpoint.
    ///
    /// Returns `true` when the edit was stored.
    @discardableResult
    func saveExternal(
        item: Item,
        data: Data,
        filename: String,
        mime: String
    ) async -> Bool {
        do {
            let response = try await client.saveEdit(
                id: item.id,
                data: data,
                filename: filename,
                mime: mime,
                mode: mode.rawValue
            )
            let message = response.message.trimmingCharacters(in: .whitespacesAndNewlines)
            onToast?(message.isEmpty ? Strings.editorSaved : message)
            onSaved?()
            return true
        } catch let error as APIError {
            if error.status == 401 {
                onUnauthorized?()
                return false
            }
            onToast?(error.message)
            return false
        } catch {
            onToast?(Strings.editorSaveFailed)
            return false
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
