import AVFoundation
import AVKit
import MNGCore
import MNGKit
import SwiftUI
import UIKit

/// Preview of one decrypted vault file: image, video or text.
struct VaultPreviewSheet: View {
    let model: ShellModel

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    private var state: VaultModel { model.vault }
    private var file: VaultFile? { state.previewFile }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                if !state.previewNote.isEmpty {
                    Text(state.previewNote)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.text4)
                        .padding(.vertical, 8)
                }
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(file?.name ?? Strings.vaultPreviewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Strings.close) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onDisappear {
            player?.pause()
            state.closePreview()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.preview {
        case .idle:
            placeholder(icon: "lock", title: Strings.vaultPreviewTitle)
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text(state.previewNote)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.text3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .image(let bytes):
            ScrollView([.vertical, .horizontal]) {
                if let image = UIImage(data: bytes) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(12)
                } else {
                    placeholder(icon: "photo", title: Strings.vaultPreviewUnsupported)
                }
            }
        case .video(let url):
            VideoPreview(url: url, player: $player)
        case .text(let text):
            ScrollView {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        case .file:
            placeholder(icon: "doc", title: Strings.vaultPreviewUnsupported)
        case .failed(let message):
            placeholder(icon: "exclamationmark.triangle", title: message)
        }
    }

    private func placeholder(icon: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Palette.text4)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Palette.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Plays one decrypted video file from the temporary folder.
private struct VideoPreview: View {
    let url: URL
    @Binding var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            let item = AVPlayer(url: url)
            player = item
            item.play()
        }
        .onDisappear {
            player?.pause()
        }
    }
}
