import MNGKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The Live Photo companion.
///
/// Apple stores the motion part of a Live Photo as a QuickTime movie that
/// shares the stem of the still. The UTI is the one Photos registers for it,
/// not the generic `public.movie`.
enum LivePhoto {
    static let movieTypeIdentifier = "com.apple.quicktime-movie"
}

/// Photo picker for the cloud library.
///
/// `PHPickerViewController` runs out of process, so the app never asks for the
/// photo library permission. `suggestedName` keeps the original file name,
/// which is what the indexer uses to derive the capture date.
///
/// A Live Photo is picked as its still; when the provider also exposes the
/// paired movie, it is picked up as well. Both files share a stem, so the
/// worker pairs them into a Live Photo again.
struct BackupPicker: UIViewControllerRepresentable {
    /// One picked file, staged in the temporary directory.
    struct Picked {
        let name: String
        let mime: String
        let url: URL
        let size: Int64
    }

    let onPick: ([Picked]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 0
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: PHPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPick: ([Picked]) -> Void
        private let directory: URL

        init(onPick: @escaping ([Picked]) -> Void) {
            self.onPick = onPick
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("mng-backup-pick", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: base,
                withIntermediateDirectories: true
            )
            directory = base
        }

        func picker(
            _ picker: PHPickerViewController,
            didFinishPicking results: [PHPickerResult]
        ) {
            guard !results.isEmpty else {
                picker.dismiss(animated: true)
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                var picked: [Picked] = []
                for result in results {
                    picked.append(contentsOf: await self.load(result))
                }
                picker.dismiss(animated: true)
                self.onPick(picked)
            }
        }

        /// Load one picked item: the file itself and, for a Live Photo, the
        /// paired movie.
        private func load(_ result: PHPickerResult) async -> [Picked] {
            let provider = result.itemProvider
            let identifiers = provider.registeredTypeIdentifiers
            // A Live Photo registers both a still and its companion movie, so
            // the kind of the asset decides which one is the primary file.
            let isVideo = result.assetMediaType == .video
            let movieIdentifier = identifiers.first {
                UTType($0)?.conforms(to: .movie) == true
            }
            let imageIdentifier = identifiers.first {
                UTType($0)?.conforms(to: .image) == true
            }
            let primary = isVideo
                ? (movieIdentifier ?? identifiers.first)
                : (imageIdentifier ?? identifiers.first)
            guard let primary else { return [] }

            let name = provider.suggestedName
                ?? "IMG_\(Int(Date().timeIntervalSince1970)).jpg"
            let mime = UTType(primary)?.preferredMIMEType ?? "image/jpeg"
            guard let file = await stage(provider: provider, typeIdentifier: primary) else {
                return []
            }
            var picked = [
                Picked(
                    name: name,
                    mime: mime,
                    url: file.url,
                    size: file.size
                )
            ]

            if !isVideo, let companion = await stage(
                provider: provider,
                typeIdentifier: LivePhoto.movieTypeIdentifier
            ) {
                // The companion keeps the stem of the still, so the worker
                // pairs the two files into a Live Photo.
                picked.append(
                    Picked(
                        name: "\(MNGNames.stem(of: name)).mov",
                        mime: UTType(LivePhoto.movieTypeIdentifier)?.preferredMIMEType
                            ?? "video/quicktime",
                        url: companion.url,
                        size: companion.size
                    )
                )
            }
            return picked
        }

        /// Copy a provider's file representation into the temporary directory.
        ///
        /// The provider hands over a URL that only lives for the duration of
        /// its callback, so the copy has to happen right there. The
        /// modification time of the source is carried over, so a name without
        /// a date still resolves to the original capture time.
        private func stage(
            provider: NSItemProvider,
            typeIdentifier: String
        ) async -> (url: URL, size: Int64)? {
            await withCheckedContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                    guard let url else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let source = try? FileManager.default
                        .attributesOfItem(atPath: url.path)
                    let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
                    let target = self.directory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(ext)
                    guard (try? FileManager.default.copyItem(at: url, to: target)) != nil
                    else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let size = (source?[.size] as? NSNumber)?.int64Value ?? 0
                    if let source, let modified = source[.modificationDate] as? Date {
                        // Keep the source modification time, so a name without
                        // a date still resolves to the original capture time.
                        try? FileManager.default.setAttributes(
                            [.modificationDate: modified],
                            ofItemAtPath: target.path
                        )
                    }
                    continuation.resume(returning: (target, size))
                }
            }
        }
    }
}
