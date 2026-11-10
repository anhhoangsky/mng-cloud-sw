import AVFoundation
import AVKit
import Combine
import MNGKit
import Observation
import SwiftUI

/// AVPlayer wrapper for one viewer video (or Live Photo companion).
///
/// The PWA's `<video>` sends the session cookie automatically. `AVURLAsset`
/// does not, so the cookies for the media URL are passed explicitly through
/// `AVURLAssetHTTPCookiesKey`; Range requests and buffering are left to
/// AVFoundation. A single failed load is retried after 800 ms, matching the
/// legacy `video_retry` handler.
@MainActor
@Observable
final class ViewerVideoController {
    let player = AVPlayer()

    private(set) var hasStarted = false
    private(set) var waiting = false

    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var url: URL?
    @ObservationIgnored private var cookies: [HTTPCookie] = []
    @ObservationIgnored private var retried = false

    func load(url: URL, cookies: [HTTPCookie], autoplay: Bool) {
        self.url = url
        self.cookies = cookies
        retried = false
        hasStarted = autoplay
        rebuild(autoplay: autoplay)
    }

    func play() {
        hasStarted = true
        player.play()
    }

    func pause() {
        player.pause()
    }

    func teardown() {
        cancellables.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
        waiting = false
        hasStarted = false
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
        observe(item)
        if autoplay {
            player.play()
        }
    }

    private func observe(_ item: AVPlayerItem) {
        cancellables.removeAll()

        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard status == .failed else { return }
                Task { @MainActor [weak self] in
                    self?.handleFailure()
                }
            }
            .store(in: &cancellables)

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.waiting = status == .waitingToPlayAtSpecifiedRate
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

    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = ViewerVideoController()
    @State private var audioActive = false

    var body: some View {
        ZStack {
            if controller.hasStarted {
                VideoPlayer(player: controller.player)
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
            if autoplay {
                activateAudio()
            }
            load()
        }
        .onDisappear {
            controller.teardown()
            deactivateAudio()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if controller.hasStarted {
                    activateAudio()
                }
            } else {
                controller.pause()
                deactivateAudio()
            }
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
                .font(.mng(22, weight: .semibold))
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
        .onTapGesture {
            activateAudio()
            controller.play()
        }
        .accessibilityElement()
        .accessibilityLabel(Strings.viewerPlay)
        .accessibilityAddTraits(.isButton)
    }

    private func load() {
        guard let url = server.mediaURL(item.mediaPath(live: live)) else {
            return
        }
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        controller.load(url: url, cookies: cookies, autoplay: autoplay)
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
