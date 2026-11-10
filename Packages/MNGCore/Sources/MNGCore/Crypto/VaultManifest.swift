import Foundation

/// Decoded native vault manifest (`mng-vault/v1`).
///
/// Unknown JSON fields are ignored and missing optional/default fields fall
/// back to the same values as the Rust `serde` model.
public struct VaultManifest: Codable, Equatable {
    public var version: UInt32
    public var uid: String
    public var name: String
    public var created: Int64
    public var updated: Int64
    public var folders: [VaultFolder]
    public var files: [VaultFile]

    public init(
        version: UInt32 = 0,
        uid: String = "",
        name: String = "",
        created: Int64 = 0,
        updated: Int64 = 0,
        folders: [VaultFolder] = [],
        files: [VaultFile] = []
    ) {
        self.version = version
        self.uid = uid
        self.name = name
        self.created = created
        self.updated = updated
        self.folders = folders
        self.files = files
    }

    private enum CodingKeys: String, CodingKey {
        case version, uid, name, created, updated, folders, files
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(UInt32.self, forKey: .version) ?? 0
        uid = try container.decodeIfPresent(String.self, forKey: .uid) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        created = try container.decodeIfPresent(Int64.self, forKey: .created) ?? 0
        updated = try container.decodeIfPresent(Int64.self, forKey: .updated) ?? 0
        folders = try container.decodeIfPresent([VaultFolder].self, forKey: .folders) ?? []
        files = try container.decodeIfPresent([VaultFile].self, forKey: .files) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(uid, forKey: .uid)
        try container.encode(name, forKey: .name)
        try container.encode(created, forKey: .created)
        try container.encode(updated, forKey: .updated)
        try container.encode(folders, forKey: .folders)
        try container.encode(files, forKey: .files)
    }
}

public struct VaultFolder: Codable, Equatable {
    public var id: String
    public var name: String
    public var parent: String?
    public var created: Int64

    public init(
        id: String = "",
        name: String = "",
        parent: String? = nil,
        created: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.parent = parent
        self.created = created
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, parent, created
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        parent = try container.decodeIfPresent(String.self, forKey: .parent)
        created = try container.decodeIfPresent(Int64.self, forKey: .created) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        if let parent {
            try container.encode(parent, forKey: .parent)
        } else {
            try container.encodeNil(forKey: .parent)
        }
        try container.encode(created, forKey: .created)
    }
}

public struct VaultFile: Codable, Equatable {
    public var id: String
    /// Opaque file name inside the Seafile blob library. It never contains the
    /// user-visible name.
    public var remote: String
    /// Seafile file id returned by the commit step.
    public var fileID: String
    public var name: String
    public var folder: String?
    public var size: Int64
    public var mime: String
    public var kind: String
    public var created: Int64
    public var added: Int64
    public var chunks: [VaultChunk]
    public var thumb: String?
    public var thumbMime: String
    public var width: Int64
    public var height: Int64
    public var duration: Double

    public init(
        id: String = "",
        remote: String = "",
        fileID: String = "",
        name: String = "",
        folder: String? = nil,
        size: Int64 = 0,
        mime: String = "",
        kind: String = "",
        created: Int64 = 0,
        added: Int64 = 0,
        chunks: [VaultChunk] = [],
        thumb: String? = nil,
        thumbMime: String = "",
        width: Int64 = 0,
        height: Int64 = 0,
        duration: Double = 0
    ) {
        self.id = id
        self.remote = remote
        self.fileID = fileID
        self.name = name
        self.folder = folder
        self.size = size
        self.mime = mime
        self.kind = kind
        self.created = created
        self.added = added
        self.chunks = chunks
        self.thumb = thumb
        self.thumbMime = thumbMime
        self.width = width
        self.height = height
        self.duration = duration
    }

    private enum CodingKeys: String, CodingKey {
        case id, remote
        case fileID = "file_id"
        case name, folder, size, mime, kind, created, added, chunks, thumb
        case thumbMime
        case width, height, duration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        remote = try container.decodeIfPresent(String.self, forKey: .remote) ?? ""
        fileID = try container.decodeIfPresent(String.self, forKey: .fileID) ?? ""
        name = try container.decode(String.self, forKey: .name)
        folder = try container.decodeIfPresent(String.self, forKey: .folder)
        size = try container.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        mime = try container.decodeIfPresent(String.self, forKey: .mime) ?? ""
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        created = try container.decodeIfPresent(Int64.self, forKey: .created) ?? 0
        added = try container.decodeIfPresent(Int64.self, forKey: .added) ?? 0
        chunks = try container.decodeIfPresent([VaultChunk].self, forKey: .chunks) ?? []
        thumb = try container.decodeIfPresent(String.self, forKey: .thumb)
        thumbMime = try container.decodeIfPresent(String.self, forKey: .thumbMime) ?? ""
        width = try container.decodeIfPresent(Int64.self, forKey: .width) ?? 0
        height = try container.decodeIfPresent(Int64.self, forKey: .height) ?? 0
        duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(remote, forKey: .remote)
        try container.encode(fileID, forKey: .fileID)
        try container.encode(name, forKey: .name)
        if let folder {
            try container.encode(folder, forKey: .folder)
        } else {
            try container.encodeNil(forKey: .folder)
        }
        try container.encode(size, forKey: .size)
        try container.encode(mime, forKey: .mime)
        try container.encode(kind, forKey: .kind)
        try container.encode(created, forKey: .created)
        try container.encode(added, forKey: .added)
        try container.encode(chunks, forKey: .chunks)
        if let thumb {
            try container.encode(thumb, forKey: .thumb)
        } else {
            try container.encodeNil(forKey: .thumb)
        }
        try container.encode(thumbMime, forKey: .thumbMime)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(duration, forKey: .duration)
    }
}

public struct VaultChunk: Codable, Equatable {
    public var id: String
    public var size: Int64

    public init(id: String = "", size: Int64 = 0) {
        self.id = id
        self.size = size
    }

    private enum CodingKeys: String, CodingKey {
        case id, size
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        size = try container.decodeIfPresent(Int64.self, forKey: .size) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(size, forKey: .size)
    }
}

/// Drop entries without an id or name, mirroring the legacy reader.
public func sanitizeManifest(_ manifest: inout VaultManifest) {
    manifest.files.removeAll { $0.id.isEmpty || $0.name.isEmpty }
    manifest.folders.removeAll { $0.id.isEmpty || $0.name.isEmpty }
}
