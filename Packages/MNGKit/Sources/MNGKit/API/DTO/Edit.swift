import Foundation

/// Answer of `POST /items/{id}/edit`.
public struct EditResponse: Decodable, Equatable, Sendable {
    public let ok: Bool
    /// `overwrite` or `copy`.
    public let mode: String
    /// Id of the edited item.
    public let id: Int64
    public let message: String

    public init(
        ok: Bool = false,
        mode: String = "overwrite",
        id: Int64 = 0,
        message: String = ""
    ) {
        self.ok = ok
        self.mode = mode
        self.id = id
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.mngValue(.ok, default: false)
        mode = try container.mngValue(.mode, default: "overwrite")
        id = try container.mngValue(.id, default: 0)
        message = try container.mngValue(.message, default: "")
    }

    private enum CodingKeys: String, CodingKey {
        case ok, mode, id, message
    }
}
