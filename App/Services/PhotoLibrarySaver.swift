import MNGKit
import Photos
import UIKit

/// Saves photos into the system photo library.
///
/// The viewer can put a photo straight into the device's Photos app, the way
/// the native viewer does. The app already declares
/// `NSPhotoLibraryAddUsageDescription`, so the system prompt is the only
/// extra step.
enum PhotoLibrarySaver {
    /// Download one item and decode it with ImageIO, which reads HEIC too.
    static func loadImage(
        path: String,
        client: MNGAPIClient
    ) async -> UIImage? {
        do {
            let file = try await client.mediaFile(path: path, suggestedName: "photo")
            defer {
                try? FileManager.default.removeItem(
                    at: file.url.deletingLastPathComponent()
                )
            }
            let data = try Data(contentsOf: file.url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    /// Write the image into the photo library. Returns `true` on success.
    @discardableResult
    static func save(_ image: UIImage) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
