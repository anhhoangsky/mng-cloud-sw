import Foundation

/// A streamed download written to a temporary file.
///
/// The caller owns `url` and should delete it after sharing. ZIP archives can
/// reach 2 GiB, so the client never buffers them in memory.
public struct DownloadedFile: @unchecked Sendable, Equatable, Identifiable {
    public let url: URL
    public let filename: String

    public var id: String { "\(filename)#\(url.path)" }

    public init(url: URL, filename: String) {
        self.url = url
        self.filename = filename
    }
}

/// Backwards-compatible name for the ZIP result.
public typealias DownloadedArchive = DownloadedFile
