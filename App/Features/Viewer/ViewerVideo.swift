import AVFoundation
import Combine
import MNGKit
import Observation
import SwiftUI
import UIKit

/// AVPlayer wrapper for one viewer video (or Live Photo companion).
///
/// The PWA's `<video>` sends the session cookie automatically. `AVURLAsset`
/// does not, so the cookies for the media URL are passed explicitly through
/// `AVURLAssetHTTPCookiesKey`; Range requests and buffering are left to
/// AVFoundation. A single failed load is retried after 800 ms, matching the
/// legacy `video_retry` handler.
///
/// The controller is owned by the viewer stage, not by the player view: the
/// stage has to start and pause the video from its own gestures. Loading a
/// new item replaces the current one, so the stage never pauses a player that
/// a fresh load already took over.
@MainActor
@Observable
final class ViewerVideoController {
    let player = AVPlayer()

    private(set) var hasStarted = false
    private(set) var waiting = false
    private(set) var isPlaying = false
    /// Size the player renders at, rotation included. A portrait clip stored
    /// as 1920x1080 reports 1080x1920 here, so the viewer can size it right.
    private(set) var presentationSize: CGSize = .zero
    private(set) var isMuted = false

    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var url: URL?
    /// The item currently loaded into `player`. A page change tears the old
    /// clip down; the id guard keeps the newly started page from being
    /// stopped when SwiftUI calls the old view's `onDisappear` afterwards.
    @ObservationIgnored private var loadedItemID: Int64?
    @ObservationIgnored private var loadedLive = false
    @ObservationIgnored private var cookies: [HTTPCookie] = []
    @ObservationIgnored private var retried = false
    /// Live Photo companions loop like the native Live Photo.
    @ObservationIgnored private var loops = false
    @ObservationIgnored private var audioActive = false
    @ObservationIgnored private var pausedInBackground = false

    func load(
        itemID: Int64,
        url: URL,
        cookies: [HTTPCookie],
        autoplay: Bool,
        loops: Bool = false,
        muted: Bool = false
    ) {
        self.url = url
        self.loadedItemID = itemID
        self.loadedLive = loops
        self.cookies = cookies
        self.loops = loops
        retried = false
        hasStarted = autoplay
        isMuted = muted
        presentationSize = .zero
        rebuild(autoplay: autoplay)
    }

    func play() {
        activateAudio()
        hasStarted = true
        player.play()
    }

    func pause() {
        player.pause()
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            play()
        }
    }

    /// The app went to the background: remember that it was playing so it can
    /// continue where it stopped.
    func enterBackground() {
        guard isPlaying else { return }
        pausedInBackground = true
        player.pause()
    }

    func enterForeground() {
        guard pausedInBackground else { return }
        pausedInBackground = false
        player.play()
    }

    /// Stop a clip when the viewer leaves its page. The item id guard means a
    /// late `onDisappear` from the outgoing view cannot tear down the video
    /// that the next page just loaded.
    func stopIfCurrent(itemID: Int64, live: Bool? = nil) {
        guard loadedItemID == itemID else { return }
        // The same Live Photo can swap its still for the companion stream; a
        // late `onDisappear` from the previous mode must not stop the new one.
        if let live, loadedLive != live {
            return
        }
        teardown()
    }

    func teardown() {
        cancellables.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
        loadedItemID = nil
        loadedLive = false
        url = nil
        waiting = false
        hasStarted = false
        isPlaying = false
        presentationSize = .zero
        deactivateAudio()
    }

    private func rebuild(autoplay: Bool) {
        guard let url else { return }
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetHTTPCookiesKey: cookies]
        )
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 5
        player.replaceCurrentItem(with: item)
        player.isMuted = isMuted
        observe(item)
        if autoplay {
            activateAudio()
            player.play()
        }
    }

    private func observe(_ item: AVPlayerItem) {
        cancellables.removeAll()

        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if status == .failed {
                        self.handleFailure()
                        return
                    }
                    if status == .readyToPlay {
                        let size = item.presentationSize
                        if size.width > 0, size.height > 0 {
                            self.presentationSize = size
                        }
                    }
                }
            }
            .store(in: &cancellables)

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.waiting = status == .waitingToPlayAtSpecifiedRate
                    self.isPlaying = status == .playing
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.loops else { return }
                    self.player.seek(to: .zero)
                    self.player.play()
                }
            }
            .store(in: &cancellables)
    }

    private func handleFailure() {
        guard !retried, let url else { return }
        retried = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, self.url == url else { return }
            self.rebuild(autoplay: self.hasStarted)
        }
    }

    private func activateAudio() {
        guard !audioActive else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
        audioActive = true
    }

    private func deactivateAudio() {
        guard audioActive else { return }
        audioActive = false
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}

/// Bare `AVPlayerLayer` surface.
///
/// `AVKit.VideoPlayer` ships its own transport controls, which swallow the
/// taps and pinches the viewer needs. A plain layer keeps every gesture ours
/// and lets the viewer draw its own play/pause affordance, the way the native
/// Photos viewer does.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

final class PlayerSurfaceView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // Safe: `layerClass` pins the layer type.
        layer as! AVPlayerLayer
    }
}

/// Native video surface with the PWA's thumbnail poster and LIVE autoplay.
struct ViewerVideo: View {
    let client: MNGAPIClient
    /// Passed in from the shell: `MNGAPIClient.server` is actor-isolated, so a
    /// synchronous media URL lookup cannot read it from the main actor.
    let server: MNGServer
    let item: Item
    let live: Bool
    let autoplay: Bool
    /// Owned by the stage so the viewer can drive the playback.
    let controller: ViewerVideoController
    /// Reports the size the player renders at, rotation included.
    var onPresentationSize: ((CGSize) -> Void)? = nil

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if controller.hasStarted {
                PlayerLayerView(player: controller.player)
                    .background(Color.black)
            } else {
                poster
            }

            if controller.waiting {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.15)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.black)
        .onAppear {
            load()
        }
        .onDisappear {
            // Swiping from a video (or turning a Live Photo off) removes this
            // view while the shared controller would otherwise keep playing.
            controller.stopIfCurrent(itemID: item.id, live: live)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                controller.enterForeground()
            } else {
                controller.enterBackground()
            }
        }
        .onChange(of: controller.presentationSize) { _, size in
            guard size.width > 0, size.height > 0 else { return }
            onPresentationSize?(size)
        }
    }

    private var poster: some View {
        ZStack {
            ThumbnailView(
                client: client,
                path: item.thumbnailPath(size: 360),
                contentMode: .fit,
                placeholder: Color.black
            )

            Image(systemName: "play.fill")
                .font(Font.mng(22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(.black.opacity(0.42), in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.28), lineWidth: 0.5)
                }
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel(Strings.viewerPlay)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            controller.play()
        }
    }

    private func load() {
        guard let url = server.mediaURL(item.mediaPath(live: live)) else {
            return
        }
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        // A Live Photo companion plays muted, like the native Live Photo.
        controller.load(
            itemID: item.id,
            url: url,
            cookies: cookies,
            autoplay: autoplay,
            loops: live,
            muted: live
        )
    }
}
