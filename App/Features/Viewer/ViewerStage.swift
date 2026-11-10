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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var image: UIImage?
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

    var body: some View {
        GeometryReader { proxy in
            stage(size: proxy.size)
                .onChange(of: item.id) { _, _ in
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
        } else {
            layer(size: size)
                .contentShape(Rectangle())
                .gesture(imageDragGesture(size: size))
                .simultaneousGesture(magnifyGesture)
        }
    }

    private func layer(size: CGSize) -> some View {
        let mediaHeight = isVideo ? max(1, size.height - 150) : size.height
        return ZStack {
            Color.black

            VStack(spacing: 0) {
                media(
                    size: CGSize(width: size.width, height: mediaHeight)
                )
                .frame(width: size.width, height: mediaHeight)

                if isVideo {
                    Color.clear
                        .frame(height: 150)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    @ViewBuilder
    private func media(size: CGSize) -> some View {
        if isVideo {
            ViewerVideo(
                client: client,
                server: server,
                item: item,
                live: false,
                autoplay: false
            )
            .id("video-\(item.id)")
            .frame(
                width: videoSize(in: size).width,
                height: videoSize(in: size).height
            )
            .scaleEffect(swipeScale)
            .offset(x: swipeX, y: swipeY)
            .opacity(swipeOpacity)
        } else if isLiveVideo {
            ViewerVideo(
                client: client,
                server: server,
                item: item,
                live: true,
                autoplay: true
            )
            .id("live-\(item.id)")
            .frame(
                width: videoSize(in: size).width,
                height: videoSize(in: size).height
            )
            .scaleEffect(swipeScale)
            .offset(x: swipeX, y: swipeY)
            .opacity(swipeOpacity)
        } else if let image {
            Image(uiImage: image)
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

    private func videoSize(in container: CGSize) -> CGSize {
        guard !shouldFill(container),
              item.width > 0,
              item.height > 0,
              container.width > 0,
              container.height > 0
        else {
            return container
        }
        let aspect = CGFloat(item.width) / CGFloat(item.height)
        if container.width / container.height > aspect {
            return CGSize(
                width: container.height * aspect,
                height: container.height
            )
        }
        return CGSize(
            width: container.width,
            height: container.width / aspect
        )
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

    /// Videos keep their native controls: no zoom or tap-to-hide handlers,
    /// but the PWA still allows swipe navigation and swipe-down dismissal.
    private func videoDragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                updateDrag(value, size: size, allowTap: false)
            }
            .onEnded { value in
                finishDrag(value, size: size, allowTap: false)
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
                handleTap(started: started, value: value)
            }
        case .ignored:
            break
        }
    }

    private func handleTap(
        started: Date?,
        value: DragGesture.Value
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
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                model.toggleChrome()
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
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
            swipeX = -CGFloat(direction) * size.width * 0.6
            swipeOpacity = 0
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 110_000_000)
            guard model.current?.id == id else { return }
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
    }

    // MARK: - Loading

    private func loadPreview() async {
        guard !item.isVideo else { return }
        let id = item.id
        image = nil

        if let preview = await PreviewCache.shared.image(
            for: item.previewPath,
            client: client
        ) {
            guard !Task.isCancelled, item.id == id else { return }
            image = preview
            return
        }

        guard !Task.isCancelled, item.id == id else { return }
        if let data = await ThumbCache.shared.data(
            for: item.thumbnailPath(size: 360),
            client: client
        ), let thumbnail = UIImage(data: data) {
            guard !Task.isCancelled, item.id == id else { return }
            image = thumbnail
        }

        // One delayed retry, matching `schedule_preview_retry`: the visible
        // thumbnail only switches after the preview has decoded.
        guard !Task.isCancelled, item.id == id else { return }
        try? await Task.sleep(nanoseconds: 4_500_000_000)
        guard !Task.isCancelled, item.id == id else { return }
        if let preview = await PreviewCache.shared.image(
            for: item.previewPath,
            client: client
        ) {
            guard !Task.isCancelled, item.id == id else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                image = preview
            }
        }
    }
}
