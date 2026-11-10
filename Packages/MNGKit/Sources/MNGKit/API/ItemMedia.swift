import Foundation

/// Path helpers for the media endpoints returned in every `Item` payload.
///
/// The strings in `Item.thumb`, `preview`, `media` and `download` are
/// origin-relative paths (for example `/api/v1/items/42/thumb?v=3`). These
/// helpers add the same query parameters as the PWA while keeping the server's
/// path untouched.
public extension Item {
    /// Thumbnail path with the requested edge size, matching `thumb_url()` in
    /// `ui/src/components/shell.rs`.
    func thumbnailPath(size: Int) -> String {
        let base = thumb.isEmpty ? "/api/v1/items/\(id)/thumb?v=3" : thumb
        let separator = base.contains("?") ? "&" : "?"
        return "\(base)\(separator)size=\(max(1, size))"
    }

    /// Full-size preview path, with the same 360px fallback as the PWA.
    var previewPath: String {
        preview.isEmpty ? "/api/v1/items/\(id)/preview?v=3" : preview
    }

    /// Media path for a video or a Live Photo companion.
    func mediaPath(live: Bool = false) -> String {
        let base = media.isEmpty ? "/api/v1/items/\(id)/media" : media
        guard live else { return base }
        let separator = base.contains("?") ? "&" : "?"
        return "\(base)\(separator)live=1"
    }

    /// Original-download path (`?download=1`).
    var downloadPath: String {
        download.isEmpty ? "/api/v1/items/\(id)/media?download=1" : download
    }
}

public extension MNGServer {
    /// Resolve an origin-relative path from an item payload.
    ///
    /// Only absolute paths are accepted; this prevents a malformed server
    /// response from turning into an off-origin request.
    func mediaURL(_ path: String) -> URL? {
        guard path.hasPrefix("/"), !path.hasPrefix("//") else {
            return nil
        }
        return try? originURL(path: path)
    }
}
