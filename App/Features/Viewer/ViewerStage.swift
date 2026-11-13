import ImageIO
import MNGKit
import SwiftUI
import UIKit

/// Full-screen media stage: aspect-fit media, pinch/double-tap zoom, pan,
/// swipe-down dismiss and horizontal navigation. The gesture maths mirrors the
/// pointer handlers in `ui/src/components/shell.rs`.
struct ViewerStage: View {
    let model: ViewerModel
    let client: MNGAPIClient
    let server: MNGServer
    let item: Item
    let chromeHidden: Bool
    /// Reports the outcome of a Live Text recognition started by a long press.
    var onLiveText: ((LiveTextOutcome) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var image: UIImage?
    /// The item the bitmap in `image` belongs to. Keeping this apart from the
    /// view's `item` stops the previous photo from flashing while the next
    /// preview is being resolved.
    @State private var imageID: Int64?
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var scaleBase: CGFloat = 1
    @State private var offsetBase: CGSize = .zero
    @State private var dragMode: DragMode = .idle
    @State private var dragStarted: Date?
    @State private var swipeX: CGFloat = 0
    @State private var swipeY: CGFloat = 0
    @State private var swipeScale: CGFloat = 1
    @State private var swipeOpacity: CGFloat = 1
    @State private var pinching = false
    @State private var lastTap = Date.distantPast
    @State private var tapSequence = 0
    @State private var tapTask: Task<Void, Never>?
    /// Aspect ratio the player renders at. It wins over the stored dimensions
    /// because a portrait clip is stored as 1920x1080 with a rotation.
    @State private var videoAspect: CGFloat = 0
    /// Owned here so the viewer can draw the play/pause affordance over the
    /// video without reaching into the player view.
    @State private var videoController = ViewerVideoController()

    private enum DragMode {
        case idle
        case pan
        case horizontal
        case vertical
        case ignored
    }

    private var isVideo: Bool { item.isVideo }
    private var isLiveVideo: Bool { item.live && model.liveMode }
    private var isPlayingVideo: Bool { isVideo || isLiveVideo }

    /// Width divided by height of the media as it is displayed.
    private var mediaAspect: CGFloat {
        if isPlayingVideo {
            if videoAspect > 0 { return videoAspect }
            guard item.width > 0, item.height > 0 else { return 16.0 / 9.0 }
            return CGFloat(item.width) / CGFloat(item.height)
        }
        guard item.width > 0, item.height > 0 else { return 1.0 }
        return CGFloat(item.width) / CGFloat(item.height)
    }

    var body: some View {
        GeometryReader { proxy in
            stage(size: proxy.size)
                .onChange(of: item.id) { oldID, _ in
                    // Changing pages must stop the previous clip. The guard
                    // inside the controller keeps a video that just started
                    // on the new page from being torn down.
                    videoController.stopIfCurrent(itemID: oldID)
                    resetInteraction()
                }
                .onChange(of: model.liveMode) { _, _ in
                    resetInteraction()
                }
                .task(id: item.id) {
                    await loadPreview()
                }
                .onDisappear {
                    tapTask?.cancel()
                    videoController.teardown()
                }
        }
        .background(Color.black)
    }

    @ViewBuilder
    private func stage(size: CGSize) -> some View {
        if isPlayingVideo {
            layer(size: size)
                .contentShape(Rectangle())
                .simultaneousGesture(videoDragGesture(size: size))
                .simultaneousGesture(magnifyGesture)
        } else {
            layer(size: size)
                .contentShape(Rectangle())
                .gesture(imageDragGesture(size: size))
                .simultaneousGesture(magnifyGesture)
                // A long press reads the text of the photo, the way iOS Photos
                // does. It never reaches the tap handler: a hold lasts longer
                // than the 0.45 s a tap may take.
                .onLongPressGesture(minimumDuration: 0.5) {
                    recognizeLiveText()
                }
        }
    }

    /// The media fills the whole stage. The chrome floats on top of it, so a
    /// video is no longer squeezed into a band above the filmstrip.
    private func layer(size: CGSize) -> some View {
        ZStack {
            Color.black

            media(size: size)
                .frame(width: size.width, height: size.height)

            if isPlayingVideo {
                pausedIndicator
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// The play badge of a paused video. It only reports the state: a tap
    /// anywhere on the video starts or pauses it.
    @ViewBuilder
    private var pausedIndicator: some View {
        if videoController.hasStarted, !videoController.isPlaying {
            Image(systemName: "play.fill")
                .font(Font.mng(26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(.black.opacity(0.42), in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.26), lineWidth: 0.5)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func media(size: CGSize) -> some View {
        if isVideo {
            ViewerVideo(
                client: client,
                server: server,
                item: item,
                live: false,
                autoplay: false,
                controller: videoController,
                onPresentationSize: { presentation in
                    guard presentation.width > 0, presentation.height > 0 else { return }
                    videoAspect = presentation.width / presentation.height
                }
            )
            .id("video-\(item.id)")
            .aspectRatio(mediaAspect, contentMode: .fit)
            .scaleEffect(scale * swipeScale)
            .offset(
                x: offset.width + swipeX,
                y: offset.height + swipeY
            )
            .opacity(swipeOpacity)
        } else if isLiveVideo {
            ViewerVideo(
                client: client,
                server: server,
                item: item,
                live: true,
                autoplay: true,
                controller: videoController,
                onPresentationSize: { presentation in
                    guard presentation.width > 0, presentation.height > 0 else { return }
                    videoAspect = presentation.width / presentation.height
                }
            )
            .id("live-\(item.id)")
            .aspectRatio(mediaAspect, contentMode: .fit)
            .scaleEffect(scale * swipeScale)
            .offset(
                x: offset.width + swipeX,
                y: offset.height + swipeY
            )
            .opacity(swipeOpacity)
        } else if let displayImage {
            Image(uiImage: displayImage)
                .resizable()
                .aspectRatio(contentMode: shouldFill(size) ? .fill : .fit)
                .frame(width: size.width, height: size.height)
                .clipped()
                .scaleEffect(scale * swipeScale)
                .offset(
                    x: offset.width + swipeX,
                    y: offset.height + swipeY
                )
                .opacity(swipeOpacity)
                .accessibilityLabel(item.name)
        } else {
            Color.clear
                .frame(width: size.width, height: size.height)
        }
    }

    /// The bitmap to draw for the current page.
    ///
    /// A bitmap that belongs to the previous item is never drawn again: on a
    /// page change the cached preview (or the thumbnail the timeline already
    /// downloaded) stands in on the first frame, then `loadPreview` upgrades
    /// it. This removes the black flash that used to follow every swipe.
    private var displayImage: UIImage? {
        if imageID == item.id, let image {
            return image
        }
        if let preview = PreviewCache.shared.cachedImage(for: item.previewPath) {
            return preview
        }
        return ThumbCache.shared.cachedImage(for: item.thumbnailPath(size: 360))
            ?? ThumbCache.shared.cachedImage(for: item.thumbnailPath(size: 160))
    }

    /// PWA `is-fill`: once the chrome is hidden and the photo already matches
    /// the screen within 4%, let it cover the viewport instead of letterboxing.
    private func shouldFill(_ size: CGSize) -> Bool {
        guard chromeHidden,
              item.width > 0,
              item.height > 0,
              size.width > 0,
              size.height > 0
        else {
            return false
        }
        let mediaAspect = Double(item.width) / Double(item.height)
        let viewAspect = Double(size.width) / Double(size.height)
        return abs(mediaAspect / viewAspect - 1) <= 0.04
    }

    // MARK: - Gestures

    private func imageDragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                updateDrag(value, size: size, allowTap: true)
            }
            .onEnded { value in
                finishDrag(value, size: size, allowTap: true)
            }
    }

    /// Videos keep the same gestures as photos: a tap hides the chrome, a
    /// double tap zooms and a swipe navigates. The bare player layer has no
    /// controls of its own, so nothing competes with them.
    private func videoDragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                updateDrag(value, size: size, allowTap: true)
            }
            .onEnded { value in
                finishDrag(value, size: size, allowTap: true)
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if !pinching {
                    pinching = true
                    dragMode = .ignored
                    dragStarted = nil
                    scaleBase = scale
                    swipeX = 0
                    swipeY = 0
                    swipeScale = 1
                    swipeOpacity = 1
                }
                scale = min(5, max(1, scaleBase * value.magnification))
            }
            .onEnded { _ in
                pinching = false
                if scale <= 1.02 {
                    resetZoom()
                } else {
                    scaleBase = scale
                    offsetBase = offset
                }
            }
    }

    private func updateDrag(
        _ value: DragGesture.Value,
        size: CGSize,
        allowTap: Bool
    ) {
        guard !pinching else { return }

        if dragStarted == nil {
            dragStarted = Date()
            dragMode = .idle
            offsetBase = offset
        }

        let dx = value.translation.width
        let dy = value.translation.height

        if dragMode == .idle {
            guard (dx * dx + dy * dy).squareRoot() >= 10 else { return }
            if allowTap, scale > 1.02 {
                dragMode = .pan
                offsetBase = offset
            } else if abs(dx) > abs(dy) * 1.15 {
                dragMode = .horizontal
                // Give the neighbouring preview as much of the drag as
                // possible to download and decode before the release.
                prefetchNeighbors()
            } else if dy > 0, abs(dy) > abs(dx) * 1.15 {
                dragMode = .vertical
            } else {
                dragMode = .ignored
                return
            }
        }

        switch dragMode {
        case .pan:
            offset = CGSize(
                width: offsetBase.width + dx,
                height: offsetBase.height + dy
            )
        case .vertical:
            let progress = max(0, dy)
            swipeY = progress
            swipeScale = max(0.72, 1 - progress / max(1, size.height) * 1.6)
            swipeOpacity = max(0.35, 1 - progress / max(1, size.height * 0.9))
        case .horizontal:
            swipeX = dx
            swipeOpacity = max(
                0.7,
                1 - abs(dx) / max(1, size.width) * 0.5
            )
        case .idle, .ignored:
            break
        }
    }

    private func finishDrag(
        _ value: DragGesture.Value,
        size: CGSize,
        allowTap: Bool
    ) {
        let started = dragStarted
        let mode = dragMode
        dragStarted = nil
        dragMode = .idle

        guard !pinching else { return }

        switch mode {
        case .pan:
            offsetBase = offset
        case .vertical:
            let dy = value.translation.height
            let threshold = max(size.height * 0.2, 96)
            if dy >= threshold {
                model.close()
            } else {
                snapBack()
            }
        case .horizontal:
            let dx = value.translation.width
            let direction = dx < 0 ? 1 : -1
            let canMove = direction > 0 ? model.canGoNext : model.canGoPrevious
            let threshold = max(size.width * 0.16, 56)
            if canMove, abs(dx) >= threshold {
                advance(direction, size: size)
            } else {
                snapBack()
            }
        case .idle:
            if allowTap {
                if isPlayingVideo {
                    handleTap(started: started, value: value, action: .videoPlayback)
                } else {
                    handleTap(started: started, value: value, action: .chrome)
                }
            }
        case .ignored:
            break
        }
    }

    /// A tap on a video plays or pauses it. When the chrome is hidden the tap
    /// brings it back instead, so the person can always get out of the
    /// full-screen mode.
    private func toggleVideoPlayback() {
        if chromeHidden {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                model.toggleChrome()
            }
            return
        }
        videoController.togglePlayback()
    }

    /// What a single tap does. A double tap always zooms.
    private enum TapAction {
        case chrome
        case videoPlayback
    }

    private func handleTap(
        started: Date?,
        value: DragGesture.Value,
        action: TapAction
    ) {
        let dx = value.translation.width
        let dy = value.translation.height
        let moved = (dx * dx + dy * dy).squareRoot()
        guard moved <= 8,
              let started,
              Date().timeIntervalSince(started) <= 0.45
        else {
            return
        }

        let now = Date()
        if now.timeIntervalSince(lastTap) < 0.3 {
            lastTap = .distantPast
            tapSequence += 1
            tapTask?.cancel()
            tapTask = nil
            if scale > 1.02 {
                resetZoom()
            } else {
                zoomIn()
            }
            return
        }

        lastTap = now
        guard scale <= 1.02 else { return }

        tapSequence += 1
        let sequence = tapSequence
        tapTask?.cancel()
        tapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled,
                  tapSequence == sequence,
                  scale <= 1.02,
                  model.isOpen
            else {
                return
            }
            switch action {
            case .chrome:
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    model.toggleChrome()
                }
            case .videoPlayback:
                toggleVideoPlayback()
            }
        }
    }

    private func zoomIn() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            scale = 2.4
            offset = .zero
        }
        scaleBase = 2.4
        offsetBase = .zero
        swipeX = 0
        swipeY = 0
        swipeScale = 1
        swipeOpacity = 1
    }

    private func resetZoom() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            scale = 1
            offset = .zero
        }
        scaleBase = 1
        offsetBase = .zero
    }

    private func snapBack() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
            swipeX = 0
            swipeY = 0
            swipeScale = 1
            swipeOpacity = 1
        }
    }

    private func advance(_ direction: Int, size: CGSize) {
        let id = item.id
        // The destination was prefetched when this page loaded, so its bitmap
        // is normally already decoded. Install it while the outgoing page is
        // still off screen; the page change then draws the next photo on its
        // first frame instead of going through a black placeholder.
        let target = neighbor(direction)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
            swipeX = -CGFloat(direction) * size.width * 0.6
            swipeOpacity = 0
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 110_000_000)
            guard model.current?.id == id else { return }
            if let target, let cached = cachedImage(for: target) {
                image = cached
                imageID = target.id
            }
            if direction > 0 {
                model.goNext()
            } else {
                model.goPrevious()
            }
            swipeX = 0
            swipeY = 0
            swipeScale = 1
            swipeOpacity = 1
        }
    }

    /// The page a horizontal swipe would land on.
    private func neighbor(_ direction: Int) -> Item? {
        let items = model.items
        let index = model.index + direction
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    /// A bitmap that can be drawn immediately for a page. Previews come first;
    /// the 360px thumbnail is the fallback the timeline usually warmed.
    private func cachedImage(for item: Item) -> UIImage? {
        if let preview = PreviewCache.shared.cachedImage(for: item.previewPath) {
            return preview
        }
        return ThumbCache.shared.cachedImage(for: item.thumbnailPath(size: 360))
            ?? ThumbCache.shared.cachedImage(for: item.thumbnailPath(size: 160))
    }

    /// Warm the pages on either side of the current one. Called when a page
    /// opens and as soon as a horizontal swipe is recognised, so a release has
    /// a decoded bitmap waiting.
    private func prefetchNeighbors() {
        var paths: [String] = []
        for direction in [-1, 1] {
            guard let item = neighbor(direction), !item.isVideo else { continue }
            paths.append(item.previewPath)
        }
        PreviewCache.shared.prefetch(paths, client: client)
    }

    private func resetInteraction() {
        tapTask?.cancel()
        tapTask = nil
        tapSequence += 1
        lastTap = .distantPast
        scale = 1
        offset = .zero
        scaleBase = 1
        offsetBase = .zero
        swipeX = 0
        swipeY = 0
        swipeScale = 1
        swipeOpacity = 1
        dragMode = .idle
        dragStarted = nil
        pinching = false
        videoAspect = 0
    }

    // MARK: - Live Text

    /// Read the text of the photo with the Vision framework.
    private func recognizeLiveText() {
        guard let image else { return }
        onLiveText?(.working)
        Task { @MainActor in
            let outcome = await LiveTextService.shared.recognize(image)
            onLiveText?(outcome)
        }
    }

    // MARK: - Loading

    private func loadPreview() async {
        guard !item.isVideo else { return }
        let id = item.id

        // Never keep the previous page's bitmap on screen while a new preview
        // resolves. A cached neighbour is already decoded (see
        // `prefetchNeighbors`), so this normally fills on the first frame.
        if imageID != id {
            if let cached = cachedImage(for: item) {
                image = cached
                imageID = id
            } else {
                image = nil
                imageID = nil
            }
        }
        prefetchNeighbors()

        let preview = await PreviewCache.shared.image(
            for: item.previewPath,
            client: client
        )
        guard !Task.isCancelled, item.id == id else { return }
        var resolved = false
        if let preview {
            image = preview
            imageID = id
            resolved = true
        }

        // iOS decodes the HEIF family natively. When the generated preview is
        // missing, the original is decoded (off the main actor) instead of
        // leaving the page on a thumbnail. Reading the original on every HEIC
        // page made swiping compete for bandwidth and decode time with the
        // page the person was already looking at, so it is the fallback only.
        if !resolved, item.isHeif, let original = await loadOriginalImage() {
            guard !Task.isCancelled, item.id == id else { return }
            image = original
            imageID = id
            resolved = true
        }

        if !resolved, let thumbnail = await ThumbCache.shared.image(
            for: item.thumbnailPath(size: 360),
            client: client
        ) {
            guard !Task.isCancelled, item.id == id else { return }
            image = thumbnail
            imageID = id
        }

        guard !resolved, !Task.isCancelled, item.id == id else { return }

        // One delayed retry, matching `schedule_preview_retry`: the thumbnail
        // stays on screen and the preview replaces it without a cross-fade.
        try? await Task.sleep(nanoseconds: 4_500_000_000)
        guard !Task.isCancelled, item.id == id else { return }
        if let preview = await PreviewCache.shared.image(
            for: item.previewPath,
            client: client
        ) {
            guard !Task.isCancelled, item.id == id else { return }
            image = preview
            imageID = id
        }
    }

    /// Download the original file and decode it with ImageIO, which reads
    /// HEIC without any extra library.
    ///
    /// The pixels are downsampled to a size the viewer can zoom into, so a
    /// 48 megapixel original does not have to live in memory as one bitmap.
    private func loadOriginalImage() async -> UIImage? {
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
            return await Task.detached(priority: .userInitiated) {
                ViewerStage.decode(data)
            }.value
        } catch {
            return nil
        }
    }

    /// Decode an image file into a bounded bitmap.
    static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2400,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}

/// The outcome of a Live Text recognition.
enum LiveTextOutcome: Equatable {
    case working
    case text(String)
    case empty
    case failed
}
