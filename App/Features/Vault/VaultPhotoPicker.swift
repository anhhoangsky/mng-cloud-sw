import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Photo picker for the vault.
///
/// `PHPickerViewController` runs out of process, so the app never asks for
/// photo library permission, and `suggestedName` keeps the original file name
/// of the picked photo or video.
struct VaultPhotoPicker: UIViewControllerRepresentable {
    /// One picked photo or video. The file representation is preferred; some
    /// formats only expose the bytes, so the data fallback is kept.
    struct Picked {
        let name: String
        let mime: String
        let url: URL?
        let data: Data?
    }

    let onPick: (Picked) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
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
        private let onPick: (Picked) -> Void

        init(onPick: @escaping (Picked) -> Void) {
            self.onPick = onPick
        }

        func picker(
            _ picker: PHPickerViewController,
            didFinishPicking results: [PHPickerResult]
        ) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }

            let name = provider.suggestedName
                ?? "IMG_\(Int(Date().timeIntervalSince1970)).jpg"
            let identifier = provider.registeredTypeIdentifiers.first
                ?? UTType.image.identifier
            let mime = UTType(identifier)?.preferredMIMEType ?? "image/jpeg"

            provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
                if let url {
                    let directory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("mng-vault-pick", isDirectory: true)
                    try? FileManager.default.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                    let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
                    let target = directory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(ext)
                    if (try? FileManager.default.copyItem(at: url, to: target)) != nil {
                        DispatchQueue.main.async { [onPick] in
                            onPick(
                                Picked(
                                    name: name,
                                    mime: mime,
                                    url: target,
                                    data: nil
                                )
                            )
                        }
                        return
                    }
                }
                // Some formats have no file representation; fall back to the
                // in-memory bytes.
                provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                    guard let data else { return }
                    DispatchQueue.main.async { [onPick] in
                        onPick(
                            Picked(
                                name: name,
                                mime: mime,
                                url: nil,
                                data: data
                            )
                        )
                    }
                }
            }
        }
    }
}
