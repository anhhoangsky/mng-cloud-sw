import CoreGraphics
import Foundation
import ImageIO
import MNGEdit
import MNGKit
import Observation
import UIKit
import UniformTypeIdentifiers

/// State of the standalone collage screen.
///
/// The geometry and the pixels come from `MNGEdit.Collage`; this model only
/// owns the photo list, the decoded bitmaps and the coalesced preview loop.
/// Sources are downloaded through the authenticated `mediaData` path and
/// decoded to at most 1600 px, so nine photos stay around 90 MB instead of
/// keeping every original bitmap alive.
@MainActor
@Observable
final class CollageModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    let client: MNGAPIClient
    /// Called when the server rejects the session, so the shell can ask for
    /// the password again instead of leaving a dead screen open.
    var onUnauthorized: (() -> Void)?

    private(set) var phase: Phase = .loading
    /// The chosen photos, in cell order.
    private(set) var items: [Item] = []
    private(set) var images: [CGImage] = []
    private(set) var state: CollageState = Collage.defaultState()
    private(set) var preview: UIImage?
    private(set) var selected = 0
    private(set) var isLoadingPhotos = false
    private(set) var isExporting = false
    private(set) var hintVisible = true
    private(set) var message: String?
    /// The temporary PNG handed to the share sheet.
    private(set) var exportURL: URL?

    @ObservationIgnored private var started = false
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var renderGeneration = 0
    @ObservationIgnored private var interactive = false
    @ObservationIgnored private var hintTask: Task<Void, Never>?
    @ObservationIgnored private var messageTask: Task<Void, Never>?

    init(client: MNGAPIClient, seed: [Item]) {
        self.client = client
        items = Array(seed.prefix(Collage.maxCells))
    }

    var hasEnough: Bool { images.count >= Collage.minCells }
    var isLoading: Bool { phase == .loading }
    var canAdd: Bool {
        items.count < Collage.maxCells
            && !isLoading
            && !isLoadingPhotos
    }

    var selectedCell: CollageCellState? {
        guard selected >= 0, selected < state.cells.count else { return nil }
        return state.cells[selected]
    }

    var gapPercent: Double { state.gap * 100 }
    var radiusPercent: Double { state.radius * 100 }
    var zoomPercent: Double { (selectedCell?.zoom ?? 1) * 100 }

    /// The layouts that hold exactly the current number of photos.
    var layouts: [CollageLayout] {
        Collage.layouts(for: images.count)
    }

    // MARK: - Loading

    /// Decode the seeded photo. The picker appends from there.
    func start() async {
        guard !started else { return }
        started = true
        guard !items.isEmpty else {
            phase = .ready
            return
        }
        isLoadingPhotos = true
        let loaded = await load(items)
        isLoadingPhotos = false
        if loaded.unauthorized {
            onUnauthorized?()
            return
        }
        guard !loaded.photos.isEmpty else {
            // The seed could not be decoded. Drop it so the add sheet can
            // offer the very same photo again instead of hiding it.
            items = []
            images = []
            phase = .failed(Strings.collageLoadFail)
            return
        }
        if loaded.photos.count != items.count {
            show(Strings.collageLoadFail)
        }
        replace(loaded.photos)
        phase = .ready
    }

    /// Append picked photos, up to the nine-cell ceiling.
    func add(_ picked: [Item]) async {
        guard !picked.isEmpty, phase != .loading, !isLoadingPhotos else {
            return
        }
        let room = Collage.maxCells - items.count
        guard room > 0 else {
            show(Strings.collageMax)
            return
        }
        let limited = Array(picked.prefix(room))
        guard !limited.isEmpty else { return }
        isLoadingPhotos = true
        let loaded = await load(limited)
        isLoadingPhotos = false
        if loaded.unauthorized {
            onUnauthorized?()
            return
        }
        if loaded.photos.count != limited.count {
            show(Strings.collageLoadFail)
        }
        guard !loaded.photos.isEmpty else { return }
        append(loaded.photos)
        phase = .ready
    }

    private struct LoadedPhotos: @unchecked Sendable {
        let photos: [LoadedPhoto]
        let unauthorized: Bool
    }

    private struct LoadedPhoto: @unchecked Sendable {
        let item: Item
        let image: CGImage
    }

    private func load(_ picked: [Item]) async -> LoadedPhotos {
        let client = self.client
        let results = await withTaskGroup(
            of: (Int, LoadedPhotoResult).self
        ) { group in
            for (index, item) in picked.enumerated() {
                group.addTask {
                    (index, await Self.load(item, client: client))
                }
            }
            var slots = [LoadedPhotoResult?](
                repeating: nil,
                count: picked.count
            )
            for await (index, result) in group {
                guard index >= 0, index < slots.count else { continue }
                slots[index] = result
            }
            return slots.compactMap { $0 }
        }
        let unauthorized = results.contains { $0.unauthorized }
        let photos = results.compactMap { result -> LoadedPhoto? in
            guard let image = result.image else { return nil }
            return LoadedPhoto(item: result.item, image: image)
        }
        return LoadedPhotos(photos: photos, unauthorized: unauthorized)
    }

    private struct LoadedPhotoResult: @unchecked Sendable {
        let item: Item
        let image: CGImage?
        let unauthorized: Bool
    }

    /// One download + decode. Nonisolated so the network wait and the
    /// ImageIO thumbnail never run on the main actor.
    private nonisolated static func load(
        _ item: Item,
        client: MNGAPIClient
    ) async -> LoadedPhotoResult {
        do {
            let data = try await client.mediaData(path: item.mediaPath())
            return LoadedPhotoResult(
                item: item,
                image: decode(data),
                unauthorized: false
            )
        } catch let error as APIError {
            return LoadedPhotoResult(
                item: item,
                image: nil,
                unauthorized: error.status == 401
            )
        } catch {
            return LoadedPhotoResult(
                item: item,
                image: nil,
                unauthorized: false
            )
        }
    }

    /// Decode with the camera transform applied, downscaled to 1600 px.
    nonisolated static func decode(_ data: Data, maxSide: Int = 1600) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            nil
        ) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        )
    }

    // MARK: - Photo list

    /// A fresh document for the new count, keeping gap/radius/background.
    private func replace(_ photos: [LoadedPhoto]) {
        items = photos.map(\.item).prefix(Collage.maxCells).map { $0 }
        images = photos.map(\.image).prefix(Collage.maxCells).map { $0 }
        let count = images.count
        let current = Collage.layout(id: state.layout)
        let target = current?.cellCount == count
            ? current
            : Collage.layouts(for: count).first ?? current
        let base = target.map { Collage.defaultState(layoutID: $0.id) }
            ?? Collage.defaultState()
        state = Collage.normalize(
            CollageState(
                layout: base.layout,
                gap: state.gap,
                radius: state.radius,
                background: state.background,
                cells: base.cells
            )
        )
        selected = 0
        hintVisible = true
        if images.count >= Collage.minCells {
            startHintTimer()
        } else {
            hintTask?.cancel()
        }
        requestPreview()
    }

    /// Append while preserving the crop of the photos already on screen.
    private func append(_ photos: [LoadedPhoto]) {
        let wasEnough = hasEnough
        let previous = state.cells
        items.append(contentsOf: photos.map(\.item))
        images.append(contentsOf: photos.map(\.image))
        if let target = Collage.layouts(for: images.count).first {
            var cells = previous
            while cells.count < images.count {
                cells.append(CollageCellState(source: cells.count))
            }
            state = Collage.normalize(
                CollageState(
                    layout: target.id,
                    gap: state.gap,
                    radius: state.radius,
                    background: state.background,
                    cells: cells
                )
            )
        }
        selected = min(selected, max(0, state.cells.count - 1))
        if !wasEnough, hasEnough {
            hintVisible = true
            startHintTimer()
        }
        requestPreview()
    }

    // MARK: - Layout and cell controls

    func setLayout(_ id: String) {
        guard Collage.layout(id: id) != nil else { return }
        state = Collage.normalize(
            CollageState(
                layout: id,
                gap: state.gap,
                radius: state.radius,
                background: state.background,
                cells: state.cells
            )
        )
        selected = min(selected, max(0, state.cells.count - 1))
        requestPreview()
    }

    func setGap(percent: Double) {
        let gap = min(max(percent / 100, 0), Collage.maxGap)
        guard abs(gap - state.gap) > 1e-9 else { return }
        state.gap = gap
        requestPreview()
    }

    func setRadius(percent: Double) {
        let radius = min(max(percent / 100, 0), Collage.maxRadius)
        guard abs(radius - state.radius) > 1e-9 else { return }
        state.radius = radius
        requestPreview()
    }

    func setBackground(_ hex: String) {
        let normalized = Collage.normalize(
            CollageState(layout: state.layout, background: hex)
        ).background
        guard normalized != state.background else { return }
        state.background = normalized
        requestPreview()
    }

    func select(_ index: Int) {
        guard index >= 0, index < state.cells.count else { return }
        selected = index
    }

    /// The cell under a point normalized to the square stage.
    func cellIndex(at point: CGPoint) -> Int {
        guard let layout = Collage.layout(id: state.layout) else { return -1 }
        let x = Double(point.x)
        let y = Double(point.y)
        guard x >= 0, y >= 0, x <= 1, y <= 1 else { return -1 }
        let rects = Collage.cellRects(layout: layout, gap: state.gap)
        return rects.firstIndex { rect in
            x >= rect.x
                && x <= rect.x + rect.width
                && y >= rect.y
                && y <= rect.y + rect.height
        } ?? -1
    }

    func selectCell(at point: CGPoint) {
        let index = cellIndex(at: point)
        if index >= 0 { selected = index }
    }

    func setZoom(percent: Double) {
        guard selected >= 0, selected < state.cells.count else { return }
        let zoom = min(max(percent / 100, 1), Collage.maxZoom)
        guard abs(zoom - state.cells[selected].zoom) > 1e-9 else { return }
        state.cells[selected].zoom = zoom
        requestPreview()
    }

    func resetSelected() {
        guard selected >= 0, selected < state.cells.count else { return }
        state.cells[selected].zoom = 1
        state.cells[selected].offsetX = 0
        state.cells[selected].offsetY = 0
        requestPreview()
    }

    func resetCell(at point: CGPoint) {
        let index = cellIndex(at: point)
        guard index >= 0 else { return }
        selected = index
        resetSelected()
    }

    // MARK: - Gestures

    /// The web hides the hint on the first pointer-down, even when the touch
    /// only selects a cell and never moves.
    func noteInteraction() {
        hideHint()
    }

    func beginGesture() {
        hideHint()
        guard !interactive else { return }
        interactive = true
        requestPreview()
    }

    func endGesture() {
        guard interactive else { return }
        interactive = false
        requestPreview()
    }

    /// Pan the selected cell. `dx`/`dy` are view points and `side` is the
    /// drawn edge of the square, matching the web's slack-based mapping.
    func panSelected(dx: CGFloat, dy: CGFloat, side: CGFloat) {
        guard side > 0, selected >= 0, selected < state.cells.count else {
            return
        }
        guard let layout = Collage.layout(id: state.layout) else { return }
        let rects = Collage.cellRects(layout: layout, gap: state.gap)
        guard selected < rects.count else { return }
        let rect = rects[selected]
        let cell = state.cells[selected]
        guard cell.source >= 0, cell.source < images.count else { return }
        let image = images[cell.source]
        let cellWidth = rect.width * Double(side)
        let cellHeight = rect.height * Double(side)
        let cover = Collage.cover(
            sourceWidth: Double(image.width),
            sourceHeight: Double(image.height),
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            zoom: cell.zoom,
            offsetX: cell.offsetX,
            offsetY: cell.offsetY
        )
        let slackX = cover.dw - cellWidth
        if slackX > 0.5 {
            state.cells[selected].offsetX = min(
                max(cell.offsetX - (Double(dx) * 2) / slackX, -1),
                1
            )
        }
        let slackY = cover.dh - cellHeight
        if slackY > 0.5 {
            state.cells[selected].offsetY = min(
                max(cell.offsetY - (Double(dy) * 2) / slackY, -1),
                1
            )
        }
        requestPreview()
    }

    /// Relative pinch from the zoom at the moment the two fingers landed.
    func setPinchZoom(start: Double, magnification: Double) {
        guard selected >= 0, selected < state.cells.count else { return }
        let zoom = min(max(start * magnification, 1), Collage.maxZoom)
        guard abs(zoom - state.cells[selected].zoom) > 1e-9 else { return }
        state.cells[selected].zoom = zoom
        requestPreview()
    }

    // MARK: - Preview

    private struct RenderBox: @unchecked Sendable {
        let image: CGImage?
    }

    private struct RenderJob: @unchecked Sendable {
        let state: CollageState
        let images: [CGImage]
        let size: Int

        func run() -> RenderBox {
            RenderBox(
                image: CollageRenderer.renderImage(
                    state: state,
                    images: images,
                    size: size
                )
            )
        }
    }

    /// Coalesce preview requests: at most one render runs at a time and a
    /// burst of gestures collapses into the newest state.
    private func requestPreview() {
        renderGeneration &+= 1
        guard hasEnough else {
            preview = nil
            return
        }
        guard renderTask == nil else { return }
        renderTask = Task { [weak self] in
            guard let self else { return }
            await self.runPreviewLoop()
        }
    }

    private func runPreviewLoop() async {
        defer { renderTask = nil }
        var renderedGeneration = -1
        while !Task.isCancelled {
            let generation = renderGeneration
            guard generation != renderedGeneration else { return }
            renderedGeneration = generation
            guard hasEnough else {
                preview = nil
                return
            }
            // The gesture runs at 768 px so the finger keeps up; the release
            // rerenders the full 1024 px preview.
            let side = interactive ? 768 : 1024
            let job = RenderJob(
                state: state,
                images: images,
                size: side
            )
            let box = await Task.detached(priority: .userInitiated) {
                job.run()
            }.value
            guard !Task.isCancelled else { return }
            guard generation == renderGeneration else { continue }
            if let image = box.image {
                preview = UIImage(cgImage: image)
            }
            if generation == renderGeneration { return }
        }
    }

    // MARK: - Export

    func save() async {
        guard !isExporting, hasEnough else { return }
        hideHint()
        isExporting = true
        defer { isExporting = false }
        let job = ExportJob(state: state, images: images)
        guard let url = await Task.detached(priority: .userInitiated, operation: {
            job.run()
        }).value else {
            show(Strings.collageExportFail)
            return
        }
        exportURL = url
    }

    private struct ExportJob: @unchecked Sendable {
        let state: CollageState
        let images: [CGImage]

        func run() -> URL? {
            guard let rendered = CollageRenderer.renderImage(
                state: state,
                images: images,
                size: 2048
            ) else {
                return nil
            }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "collage-\(UUID().uuidString)",
                    isDirectory: true
                )
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                return nil
            }
            let url = directory.appendingPathComponent("collage.png")
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else {
                try? FileManager.default.removeItem(at: directory)
                return nil
            }
            CGImageDestinationAddImage(destination, rendered, nil)
            guard CGImageDestinationFinalize(destination) else {
                try? FileManager.default.removeItem(at: directory)
                return nil
            }
            return url
        }
    }

    /// Delete the temporary PNG once the share sheet has closed.
    func clearExport() {
        if let exportURL {
            try? FileManager.default.removeItem(
                at: exportURL.deletingLastPathComponent()
            )
        }
        exportURL = nil
    }

    // MARK: - Copy

    private func show(_ text: String) {
        messageTask?.cancel()
        message = text
        messageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }

    private func startHintTimer() {
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard !Task.isCancelled else { return }
            self?.hintVisible = false
        }
    }

    private func hideHint() {
        guard hintVisible else { return }
        hintVisible = false
        hintTask?.cancel()
    }

    /// Cancel in-flight work when the screen closes.
    func stop() {
        renderTask?.cancel()
        renderTask = nil
        hintTask?.cancel()
        hintTask = nil
        messageTask?.cancel()
        messageTask = nil
        clearExport()
    }
}
