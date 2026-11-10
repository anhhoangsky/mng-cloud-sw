import Foundation

/// One file that will be encrypted into the vault.
///
/// The document picker hands over a file URL, the photo picker hands over the
/// bytes. Both are read in 4 MiB chunks so a large video never lands in memory
/// as a whole.
enum VaultUploadSource {
    case file(name: String, mime: String, size: Int64, url: URL)
    case memory(name: String, mime: String, data: Data)

    var name: String {
        switch self {
        case .file(let name, _, _, _): return name
        case .memory(let name, _, _): return name
        }
    }

    var mime: String {
        switch self {
        case .file(_, let mime, _, _): return mime
        case .memory(_, let mime, _): return mime
        }
    }

    var size: Int64 {
        switch self {
        case .file(_, _, let size, _): return size
        case .memory(_, _, let data): return Int64(data.count)
        }
    }
}
