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
        case text
        case crop

        var id: String { rawValue }
    }

    enum SaveMode: String, CaseIterable, Identifiable {
        case overwrite
        case copy

        var id: String { rawValue }

        /// The label of the action in the export sheet, the same words the
        /// web editor uses.
        var title: String {
            self == .overwrite
                ? Strings.editorSaveOverwrite
                : Strings.editorSaveCopy
        }
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

    /// The crop aspect presets of the editor, the same rail as the web's
    /// `ASPECTS` (including the viewport-shaped `screen` preset).
    enum Aspect: String, CaseIterable, Identifiable {
        case free
        case square
        case fourThree
        case threeFour
        case sixteenNine
        case nineSixteen
        case screen

        var id: String { rawValue }

        var title: String {
            switch self {
            case .free: return Strings.editorAspectFree
            case .square: return "1:1"
            case .fourThree: return "4:3"
            case .threeFour: return "3:4"
            case .sixteenNine: return "16:9"
            case .nineSixteen: return "9:16"
            case .screen: return Strings.editorCropScreen
            }
        }

        /// Width divided by height. The screen preset takes the aspect of the
        /// stage, so it needs the viewport; `nil` keeps the current rectangle.
        func ratio(viewport: CGSize = .zero) -> Float? {
            switch self {
            case .free: return nil
            case .square: return 1
            case .fourThree: return 4.0 / 3.0
            case .threeFour: return 3.0 / 4.0
            case .sixteenNine: return 16.0 / 9.0
            case .nineSixteen: return 9.0 / 16.0
            case .screen:
                guard viewport.width > 0, viewport.height > 0 else { return 1 }
                return Float(viewport.width / viewport.height)
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

    /// The category rail of the filter pane.
    enum FilterCategory: String, CaseIterable, Identifiable {
        case all
        case root
        case meitu
        case xingtu
        case lr
        case mono

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return Strings.editorFilterCatAll
            case .root: return Strings.editorFilterCatRoot
            case .meitu: return Strings.editorFilterCatMeitu
            case .xingtu: return Strings.editorFilterCatXingtu
            case .lr: return Strings.editorFilterCatLr
            case .mono: return Strings.editorFilterCatMono
            }
        }

        func includes(_ filter: EditorFilter) -> Bool {
            switch self {
            case .all: return true
            case .root: return filter.category == .root
            case .meitu: return filter.category == .meitu
            case .xingtu: return filter.category == .xingtu
            case .lr: return filter.category == .lr
            case .mono: return filter.category == .mono
            }
        }
    }

    /// The four quick styles of the text pane.
    enum TextStyle: String, CaseIterable, Identifiable {
        case title
        case bold
        case caption
        case outline

        var id: String { rawValue }

        var title: String {
            switch self {
            case .title: return Strings.editorTextTitle
            case .bold: return Strings.editorTextTitleBold
            case .caption: return Strings.editorTextCaption
            case .outline: return Strings.editorTextOutlineStyle
            }
        }
    }

    /// One step of the history.
    struct Snapshot: Equatable {
        var adjustments: EditorAdjustments
        var filter: EditorFilter
        var crop: EditorCrop
        var rotation: UInt8
        var fineRotation: Float
        var perspectiveX: Float
        var perspectiveY: Float
        var flipH: Bool
        var flipV: Bool
        var texts: [EditorTextLayer]
    }

    /// A filter/tune combination the person saved from the filter pane.
    ///
    /// It follows the web model (`UserPreset` in `ui.ts`): the tone plus the
    /// adjustment values, a name and the creation date, stored locally and
    /// capped at 24 entries.
    struct UserPreset: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var createdAt: Double
        var filterRaw: String
        var adjustments: EditorAdjustments

        var filter: EditorFilter {
            EditorFilter(rawValue: filterRaw) ?? .original
        }
    }

    let client: MNGAPIClient

    private(set) var state: State = .idle
    private(set) var item: Item?
    private(set) var preview: UIImage?
    /// The untouched photo, shown while the person holds the compare button.
    private(set) var originalPreview: UIImage?
    private(set) var tab: Tab = .adjust
    private(set) var rotation: UInt8 = 0
    /// The fine angle of the crop rotation, in degrees, −180…180. This is the
    /// web's continuous rotation; `rotation` stays the quarter turn.
    private(set) var fineRotation: Float = 0
    /// The web editor's 3D perspective sliders, -100…100. Positive Y grows
    /// the top edge, positive X grows the left edge.
    private(set) var perspectiveX: Float = 0
    private(set) var perspectiveY: Float = 0
    private(set) var flipH = false
    private(set) var flipV = false
    private(set) var crop: EditorCrop = .full
    private(set) var adjustments: EditorAdjustments = .zero
    private(set) var filter: EditorFilter = .original
    private(set) var mode: SaveMode = .overwrite
    /// The quality of a JPEG or WebP export, 10…100.
    private(set) var saveQuality = 92
    private(set) var aspect: Aspect = .free
    /// The adjustment the pane shows.
    private(set) var activeAdjustment: Adjustment = .brightness
    /// The category of the filter rail.
    private(set) var filterCategory: FilterCategory = .all
    /// The tone-tune section of the filter pane.
    private(set) var tuneOpen = false
    private(set) var tuneKey: Adjustment = .brightness
    /// The text layers over the photo, in draw order.
    private(set) var texts: [EditorTextLayer] = []
    private(set) var selectedTextId: String?
    /// The thumbnails of the presets, one per filter.
    private(set) var filterThumbnails: [EditorFilter: UIImage] = [:]
    /// The saved filter presets, newest first, like the web's `userPresets`.
    private(set) var userPresets: [UserPreset] = []
    /// The saved preset currently applied, so a second tap can restore the
    /// state from before it was applied.
    private(set) var activeSavedPresetId: String?
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
    /// The moment of the last step of the history, so the steps of a slider
    /// can be merged.
    @ObservationIgnored private var lastHistoryAt: TimeInterval = 0
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?
    /// Bumped on every preview request. One render loop at a time reads the
    /// latest state, so a burst of slider events cannot queue dozens of
    /// renders: the loop finishes the frame in flight and renders again.
    @ObservationIgnored private var previewGeneration = 0
    /// The snapshot taken when a slider, crop ruler or text gesture started.
    /// While it is set the changes only update the preview; releasing the
    /// finger commits one undo step with this snapshot.
    @ObservationIgnored private var editTransaction: Snapshot?
    /// The state before a saved preset was applied, for the on/off toggle.
    @ObservationIgnored private var savedReturnState: (
        filter: EditorFilter,
        adjustments: EditorAdjustments
    )?
    private static let userPresetKey = "aurum:user-presets:v1"

    init(client: MNGAPIClient) {
        self.client = client
        userPresets = EditorModel.loadUserPresets()
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
            fineRotation = 0
            perspectiveX = 0
            perspectiveY = 0
            flipH = false
            flipV = false
            crop = .full
            adjustments = .zero
            filter = .original
            mode = .overwrite
            saveQuality = 92
            aspect = .free
            activeAdjustment = .brightness
            filterCategory = .all
            tuneOpen = false
            tuneKey = .brightness
            texts = []
            selectedTextId = nil
            undoStack = []
            redoStack = []
            editTransaction = nil
            activeSavedPresetId = nil
            savedReturnState = nil
            preview = nil
            originalPreview = nil
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
        editTransaction = nil
        activeSavedPresetId = nil
        savedReturnState = nil
        editor = nil
        preview = nil
        originalPreview = nil
        item = nil
        filterThumbnails = [:]
        state = .idle
    }

    // MARK: - Geometry

    func selectTab(_ tab: Tab) {
        let previous = self.tab
        self.tab = tab
        if tab == .filter, filterThumbnails.isEmpty {
            renderFilterThumbnails()
        }
        // Inside the crop tab the stage shows the whole oriented photo with
        // the frame on top. Every other tab shows the cropped output, so the
        // rectangle has to be applied (or undone) when the tab changes.
        if previous != tab, previous == .crop || tab == .crop {
            renderPreview()
        }
    }

    func selectMode(_ mode: SaveMode) {
        self.mode = mode
    }

    /// Choose the quality of the next JPEG or WebP export.
    func setSaveQuality(_ value: Int) {
        saveQuality = min(max(value, 10), 100)
    }

    // MARK: - Export sheet

    /// The container of the export: the source keeps its own format, exactly
    /// like the web editor, which is only offered the type of the item.
    var exportFormat: EditorExportFormat {
        item.map { EditorModel.exportContainer(for: $0) } ?? .jpeg
    }

    var exportFormatLabel: String {
        switch exportFormat {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .webp: return "WebP"
        }
    }

    /// The name the server receives, with the extension of the container.
    var exportFileName: String {
        guard let item else {
            return "edit.\(exportFormat.fileExtension)"
        }
        return exportName(for: item, format: exportFormat)
    }

    /// The size of the full-resolution export, after the crop.
    var exportSize: (width: UInt32, height: UInt32) {
        guard var copy = editor else { return (0, 0) }
        copy.setCrop(crop)
        return copy.outputSize()
    }

    /// The estimate the export sheet shows, using the same rough byte rates
    /// as the web editor.
    var exportEstimate: String {
        let size = exportSize
        let pixels = Double(size.width) * Double(size.height)
        guard pixels > 0 else { return "0 KB" }
        let quality = Double(saveQuality) / 100
        let bytes: Double
        switch exportFormat {
        case .png:
            // PNG is lossless: the quality has no effect.
            bytes = pixels * 2.2
        case .webp:
            bytes = pixels * (0.08 + quality * 0.18)
        case .jpeg:
            bytes = pixels * (0.08 + quality * 0.22)
        }
        if bytes < 1024 * 1024 {
            return "\(max(1, Int((bytes / 1024).rounded()))) KB"
        }
        return String(format: "%.1f MB", bytes / (1024 * 1024))
    }

    func selectAdjustment(_ adjustment: Adjustment) {
        activeAdjustment = adjustment
    }

    /// The filters of the active category, in the Aurum catalog order.
    var visibleFilters: [EditorFilter] {
        EditorFilter.allCases.filter { filterCategory.includes($0) }
    }

    func selectFilterCategory(_ category: FilterCategory) {
        filterCategory = category
    }

    // MARK: - Tone tuning

    func toggleTune() {
        tuneOpen.toggle()
    }

    func selectTuneKey(_ key: Adjustment) {
        tuneKey = key
    }

    /// Write the tune slider back into the same adjustments as the Adjust tab.
    func setTune(value: Float) {
        let clamped = tuneKey == .vignette
            ? min(max(value, 0), 100)
            : value
        setAdjustment(tuneKey, value: clamped)
    }

    /// Clear the seven tone sliders in one history step.
    func resetTune() {
        let keys: [Adjustment] = [
            .brightness, .contrast, .saturation,
            .warmth, .tint, .vibrance, .vignette,
        ]
        guard keys.contains(where: { $0.value(in: adjustments) != 0 }) else {
            return
        }
        pushHistory()
        var values = adjustments
        for key in keys {
            key.set(0, in: &values)
        }
        adjustments = values
        applyAdjustments()
    }

    // MARK: - Text layers

    var selectedText: EditorTextLayer? {
        texts.first { $0.id == selectedTextId }
    }

    func selectText(_ id: String?) {
        selectedTextId = id
    }

    /// Add a layer with the web's staggered default position and open it for
    /// editing.
    @discardableResult
    func addText() -> EditorTextLayer? {
        guard state == .ready else { return nil }
        let index = texts.count
        let x = 0.5 + Float((index % 3) - 1) * 0.06
        let y = 0.42 + Float(index % 4) * 0.08
        return addText(x: x, y: y)
    }

    @discardableResult
    func addText(x: Float, y: Float) -> EditorTextLayer? {
        guard state == .ready else { return nil }
        pushHistory()
        let layer = EditorTextLayer(
            id: UUID().uuidString,
            x: min(max(x, 0.05), 0.95),
            y: min(max(y, 0.05), 0.95)
        )
        texts.append(layer)
        selectedTextId = layer.id
        applyTexts()
        return layer
    }

    /// Mutate one layer. Slider and drag changes are merged into one history
    /// step while they follow each other.
    func updateText(
        _ id: String,
        coalescing: Bool = true,
        _ mutate: (inout EditorTextLayer) -> Void
    ) {
        guard let index = texts.firstIndex(where: { $0.id == id }) else {
            return
        }
        pushHistory(coalescing: coalescing)
        var layer = texts[index]
        mutate(&layer)
        texts[index] = layer.normalized()
        applyTexts()
    }

    func updateSelectedText(
        coalescing: Bool = true,
        _ mutate: (inout EditorTextLayer) -> Void
    ) {
        guard let id = selectedTextId else { return }
        updateText(id, coalescing: coalescing, mutate)
    }

    func deleteSelectedText() {
        guard let id = selectedTextId,
              let index = texts.firstIndex(where: { $0.id == id }) else {
            return
        }
        pushHistory()
        texts.remove(at: index)
        selectedTextId = texts.first?.id
        applyTexts()
    }

    func duplicateSelectedText() {
        guard let source = selectedText,
              let index = texts.firstIndex(where: { $0.id == source.id }) else {
            return
        }
        pushHistory()
        var copy = source
        copy.id = UUID().uuidString
        copy.x = min(max(copy.x + 0.05, 0), 1)
        copy.y = min(max(copy.y + 0.05, 0), 1)
        texts.insert(copy, at: index + 1)
        selectedTextId = copy.id
        applyTexts()
    }

    /// The four quick styles of the web text pane.
    func applyTextStyle(_ style: TextStyle) {
        updateSelectedText(coalescing: false) { layer in
            switch style {
            case .title:
                layer.font = .sys
                layer.bold = true
                layer.italic = false
                layer.size = 0.11
                layer.outline = false
                layer.shadow = true
                layer.color = "#ffffff"
            case .bold:
                layer.font = .heavy
                layer.bold = true
                layer.size = 0.09
                layer.outline = false
                layer.shadow = false
            case .caption:
                layer.font = .sys
                layer.bold = false
                layer.italic = false
                layer.size = 0.045
                layer.outline = false
                layer.shadow = false
            case .outline:
                layer.font = .heavy
                layer.bold = true
                layer.size = 0.09
                layer.outline = true
                layer.shadow = false
                layer.color = "#ffffff"
            }
        }
    }

    private func applyTexts() {
        guard var editor else { return }
        editor.setTextLayers(texts)
        self.editor = editor
    }

    /// The opacity ruler of the text pane (the web uses 10…100%).
    func setTextOpacity(_ percent: Float) {
        updateSelectedText { layer in
            layer.opacity = min(max(percent / 100, 0.1), 1)
        }
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

    /// Set the continuous angle of the crop rotation, −180…180°. The quarter
    /// turns stay untouched, so the ±90° buttons and the fine ruler can be
    /// combined exactly like the web editor.
    func setFineRotation(_ value: Float) {
        guard var editor else { return }
        var next = value.truncatingRemainder(dividingBy: 360)
        if next > 180 { next -= 360 }
        if next < -180 { next += 360 }
        guard abs(next - fineRotation) > 0.01 else { return }
        // The ruler drag is one history step, opened by `beginEdit`.
        pushHistory(coalescing: true)
        fineRotation = next
        editor.setFineRotation(next)
        self.editor = editor
        renderPreview()
    }

    /// Set one axis of the 3D perspective correction. The slider drag opens
    /// a transaction in the view, so a whole drag is one undo step.
    func setPerspective(vertical: Bool, value: Float) {
        guard var editor else { return }
        let next = value.isFinite ? min(max(value, -100), 100) : 0
        let previous = vertical ? perspectiveY : perspectiveX
        guard abs(next - previous) > 0.01 else { return }
        pushHistory(coalescing: true)
        if vertical {
            perspectiveY = next
        } else {
            perspectiveX = next
        }
        editor.setPerspective(x: perspectiveX, y: perspectiveY)
        self.editor = editor
        renderPreview()
    }

    /// Reset one perspective axis, or both when the reset button belongs to
    /// the ratio/rotation mode. The crop itself is untouched.
    func resetPerspective(vertical: Bool? = nil) {
        guard var editor else { return }
        let x: Float
        let y: Float
        switch vertical {
        case .some(true):
            x = perspectiveX
            y = 0
        case .some(false):
            x = 0
            y = perspectiveY
        case .none:
            x = 0
            y = 0
        }
        guard x != perspectiveX || y != perspectiveY else { return }
        pushHistory()
        perspectiveX = x
        perspectiveY = y
        editor.setPerspective(x: x, y: y)
        self.editor = editor
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

    /// A crop drag changed the rectangle: open the transaction so the whole
    /// gesture is one undo step.
    func beginCropEdit() {
        beginEdit()
    }

    func resetCrop() {
        guard crop != .full || aspect != .free else { return }
        pushHistory()
        crop = .full
        aspect = .free
    }

    /// Apply one aspect preset to the current rectangle.
    ///
    /// The crop is normalized to the image, so the pixel ratio has to be
    /// converted first: `width / height` of a 1:1 frame on a 3:2 photo is
    /// `2/3`, not `1`. The frame is centred and as large as possible, the
    /// way the web's `setAspect` resets `scale` to 1.
    func applyAspect(_ aspect: Aspect, viewport: CGSize = .zero) {
        guard let ratio = aspect.ratio(viewport: viewport) else {
            self.aspect = .free
            return
        }
        if self.aspect == aspect {
            return
        }
        pushHistory()
        self.aspect = aspect
        let oriented = editor?.orientedSize() ?? (width: 1, height: 1)
        let normalized = ratio
            * Float(max(oriented.height, 1))
            / Float(max(oriented.width, 1))
        let width: Float = normalized >= 1 ? 1 : normalized
        let height: Float = normalized >= 1 ? 1 / normalized : 1
        crop = EditorCrop(
            x: (1 - width) / 2,
            y: (1 - height) / 2,
            width: width,
            height: height
        )
    }

    /// Tap the active preset again to return to the free frame, the web's
    /// reset-on-second-tap. The screen preset is only ignored by the guard in
    /// `applyAspect`, never here.
    func selectAspect(_ aspect: Aspect, viewport: CGSize = .zero) {
        if self.aspect == aspect, aspect != .free {
            resetCrop()
            return
        }
        applyAspect(aspect, viewport: viewport)
    }

    /// Reset the quarter turns and the fine angle. The crop is cleared when
    /// the oriented geometry changes under the normalized rectangle.
    func resetRotation() {
        guard var editor else { return }
        guard rotation != 0 || abs(fineRotation) > 0.01 else { return }
        pushHistory()
        let quarterChanged = rotation != 0
        rotation = 0
        fineRotation = 0
        editor.setGeometry(rotate: 0, flipH: flipH, flipV: flipV)
        editor.setFineRotation(0)
        self.editor = editor
        if quarterChanged {
            crop = .full
            aspect = .free
        }
        renderPreview()
    }

    // MARK: - Adjustments and filters

    func setAdjustment(_ key: Adjustment, value: Float) {
        // A drag of the slider is one step of the history, not one per
        // pixel, so the steps close to each other are merged.
        pushHistory(coalescing: true)
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

    /// Reset one slider, the web's gold value chip: tapping it clears the
    /// adjustment that is on screen without touching the others.
    func resetAdjustment(_ key: Adjustment) {
        guard key.value(in: adjustments) != 0 else { return }
        pushHistory()
        var values = adjustments
        key.set(0, in: &values)
        adjustments = values
        applyAdjustments()
    }

    func setFilter(_ filter: EditorFilter) {
        // Picking a tone by hand leaves the saved-preset toggle.
        activeSavedPresetId = nil
        savedReturnState = nil
        // Tapping the active tone again removes it, exactly like the web rail;
        // "Nguyên bản" is the off state and never toggles itself.
        if self.filter == filter, filter != .original {
            pushHistory()
            self.filter = .original
            applyAdjustments()
            return
        }
        pushHistory()
        self.filter = filter
        applyAdjustments()
    }

    // MARK: - Saved presets

    /// Save the current tone and tune under a name, the web's
    /// `saveCurrentPreset`. An empty name falls back to a time-stamped
    /// "Bộ lọc HH:mm", duplicates are refused and the list stops at 24.
    @discardableResult
    func saveUserPreset(named rawName: String) -> Bool {
        guard state == .ready else { return false }
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        if trimmed.isEmpty {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "vi_VN")
            formatter.dateFormat = "HH:mm"
            name = "\(Strings.editorFilterTab) \(formatter.string(from: Date()))"
        } else {
            name = trimmed
        }
        if userPresets.contains(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            onToast?(Strings.editorPresetExists)
            return false
        }
        let preset = UserPreset(
            id: "u\(Int(Date().timeIntervalSince1970 * 1000))",
            name: name,
            createdAt: Date().timeIntervalSince1970 * 1000,
            filterRaw: filter.rawValue,
            adjustments: adjustments
        )
        userPresets.insert(preset, at: 0)
        if userPresets.count > 24 {
            userPresets.removeLast(userPresets.count - 24)
        }
        EditorModel.storeUserPresets(userPresets)
        onToast?(Strings.editorPresetSaved)
        return true
    }

    /// Apply a saved preset, or restore the state from before it when the
    /// same preset is tapped again. The saved thumbnail is an on/off switch,
    /// exactly like the web's `applyUserPreset`.
    func applyUserPreset(_ preset: UserPreset) {
        guard state == .ready else { return }
        if activeSavedPresetId == preset.id {
            pushHistory()
            activeSavedPresetId = nil
            if let restore = savedReturnState {
                filter = restore.filter
                adjustments = restore.adjustments
            } else {
                filter = .original
            }
            savedReturnState = nil
            applyAdjustments()
            onToast?(Strings.editorPresetReset)
            return
        }
        pushHistory()
        savedReturnState = (filter: filter, adjustments: adjustments)
        activeSavedPresetId = preset.id
        filter = preset.filter
        adjustments = preset.adjustments
        applyAdjustments()
        onToast?(Strings.editorPresetApplied)
    }

    func deleteUserPreset(_ presetID: String) {
        guard userPresets.contains(where: { $0.id == presetID }) else {
            return
        }
        userPresets.removeAll { $0.id == presetID }
        if activeSavedPresetId == presetID {
            activeSavedPresetId = nil
            savedReturnState = nil
        }
        EditorModel.storeUserPresets(userPresets)
        onToast?(Strings.editorPresetDeleted)
    }

    private static func loadUserPresets() -> [UserPreset] {
        guard let data = UserDefaults.standard.data(forKey: userPresetKey),
              let decoded = try? JSONDecoder().decode([UserPreset].self, from: data)
        else {
            return []
        }
        return Array(
            decoded
                .filter {
                    !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                .prefix(24)
        )
    }

    private static func storeUserPresets(_ presets: [UserPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: userPresetKey)
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
    ///
    /// The steps of a slider are merged when they follow each other
    /// closely, so a drag of the slider is one step and not hundreds.
    private func pushHistory(coalescing: Bool = false) {
        // A gesture owns one history step: while its transaction is open the
        // changes only update the preview, and `endEdit` commits the snapshot.
        guard editTransaction == nil else { return }
        if coalescing {
            let now = Date().timeIntervalSince1970
            if now - lastHistoryAt < 0.9 {
                return
            }
            lastHistoryAt = now
        } else {
            lastHistoryAt = Date().timeIntervalSince1970
        }
        undoStack.append(
            Snapshot(
                adjustments: adjustments,
                filter: filter,
                crop: crop,
                rotation: rotation,
                fineRotation: fineRotation,
                perspectiveX: perspectiveX,
                perspectiveY: perspectiveY,
                flipH: flipH,
                flipV: flipV,
                texts: texts
            )
        )
        if undoStack.count > 60 {
            undoStack.removeFirst()
        }
        redoStack = []
        canUndo = !undoStack.isEmpty
        canRedo = false
    }

    // MARK: - Edit transactions

    /// Open the transaction of a gesture: remember where the edit started so
    /// the whole drag is one undo step, while every change still renders live.
    func beginEdit() {
        guard editTransaction == nil else { return }
        editTransaction = currentSnapshot()
    }

    /// Close the transaction and record the one undo step it produced.
    func endEdit() {
        guard let start = editTransaction else { return }
        editTransaction = nil
        guard currentSnapshot() != start else { return }
        undoStack.append(start)
        if undoStack.count > 60 {
            undoStack.removeFirst()
        }
        redoStack = []
        lastHistoryAt = Date().timeIntervalSince1970
        canUndo = true
        canRedo = false
        // The live drag renders at a smaller size; the release gets the full
        // quality preview.
        renderPreview()
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
            fineRotation: fineRotation,
            perspectiveX: perspectiveX,
            perspectiveY: perspectiveY,
            flipH: flipH,
            flipV: flipV,
            texts: texts
        )
    }

    private func apply(_ snapshot: Snapshot, to editor: inout Editor) {
        adjustments = snapshot.adjustments
        filter = snapshot.filter
        crop = snapshot.crop
        rotation = snapshot.rotation
        fineRotation = snapshot.fineRotation
        perspectiveX = snapshot.perspectiveX
        perspectiveY = snapshot.perspectiveY
        flipH = snapshot.flipH
        flipV = snapshot.flipV
        texts = snapshot.texts
        selectedTextId = snapshot.texts.first?.id
        aspect = .free
        editor.setGeometry(rotate: rotation, flipH: flipH, flipV: flipV)
        editor.setFineRotation(fineRotation)
        editor.setPerspective(x: perspectiveX, y: perspectiveY)
        editor.setAdjustments(adjustments)
        editor.setFilter(filter)
        editor.setCrop(crop)
        editor.setTextLayers(texts)
        self.editor = editor
        renderPreview()
    }

    // MARK: - Saving

    /// Encode the edited image and upload it back to the item.
    ///
    /// `mode` is the one the person picked in the export sheet: overwrite the
    /// original, or keep it and store the edit next to it. The source
    /// container decides the format; the quality only matters to JPEG/WebP.
    @discardableResult
    func save(
        mode: SaveMode = .overwrite,
        quality: Int = 92
    ) async -> Bool {
        guard let item, let editor else { return false }
        guard state != .saving else { return false }
        state = .saving
        self.mode = mode
        saveQuality = min(max(quality, 10), 100)
        let format = EditorModel.exportContainer(for: item)
        let qualityByte = UInt8(saveQuality)
        var prepared = editor
        prepared.setCrop(crop)
        prepared.setTextLayers(texts)
        do {
            let data = try await Task.detached(priority: .userInitiated) { [prepared] in
                var copy = prepared
                return try copy.renderExport(
                    format: format,
                    quality: qualityByte
                )
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
            let fallback = mode == .copy
                ? Strings.editorSavedCopy
                : Strings.editorSaved
            onToast?(message.isEmpty ? fallback : message)
            onSaved?()
            return true
        } catch let error as APIError {
            state = .ready
            if error.status == 401 {
                onUnauthorized?()
                return false
            }
            onToast?(error.message)
            return false
        } catch {
            state = .ready
            onToast?(Strings.editorSaveFailed)
            return false
        }
    }

    /// The web editor keeps the source container: PNG stays PNG, WebP stays
    /// WebP and everything else becomes JPEG.
    static func exportContainer(for item: Item) -> EditorExportFormat {
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
        guard editor != nil else { return }
        previewGeneration &+= 1
        guard renderTask == nil else { return }
        renderTask = Task { [weak self] in
            guard let self else { return }
            await self.runPreviewLoop()
        }
    }

    /// Render the newest state, then keep going while requests arrived during
    /// the frame that just finished. There is never more than one render in
    /// flight, so dragging a slider stays responsive instead of backlogged.
    private func runPreviewLoop() async {
        defer { renderTask = nil }
        while !Task.isCancelled {
            guard let editor else { return }
            let generation = previewGeneration
            // Inside the crop tab the whole photo is shown under the frame;
            // everywhere else the preview is the cropped output, so the text
            // coordinates line up with what will be exported.
            let crop = tab == .crop ? EditorCrop.full : self.crop
            let pristine = editor.currentAdjustments.isIdentity
                && editor.currentFilter == .original
                && rotation == 0
                && abs(fineRotation) < 0.01
                && abs(perspectiveX) < 0.01
                && abs(perspectiveY) < 0.01
                && !flipH
                && !flipV
                && crop == .full
                && texts.isEmpty
            // A gesture renders smaller frames; the release rerenders at the
            // full preview quality.
            let side: UInt32 = editTransaction != nil ? 720 : 1200
            let rendered = await Task.detached(priority: .userInitiated) {
                [editor, crop] in
                var copy = editor
                copy.setCrop(crop)
                let rgba = copy.renderPreview(maxSide: side)
                return (
                    rgba: rgba,
                    width: copy.lastRenderSize.width,
                    height: copy.lastRenderSize.height
                )
            }.value
            guard !Task.isCancelled else { return }
            if let image = EditorModel.image(
                from: rendered.rgba,
                width: rendered.width,
                height: rendered.height
            ) {
                if pristine, originalPreview == nil {
                    originalPreview = image
                }
                preview = image
            }
            if generation == previewGeneration {
                return
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
