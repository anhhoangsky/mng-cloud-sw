import Foundation

/// One detected face of a photo.
///
/// The box is normalised to the photo, so the editor can place it on the
/// image it loaded. The server found the faces with its own media-AI
/// worker; no face data ever leaves the box.
public struct FaceBox: Decodable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double
    /// How sure the detector was.
    public let confidence: Double

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try container.decodeIfPresent(Double.self, forKey: .y) ?? 0
        w = try container.decodeIfPresent(Double.self, forKey: .w) ?? 0
        h = try container.decodeIfPresent(Double.self, forKey: .h) ?? 0
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case x, y, w, h, confidence
    }
}

/// What the editor may offer for one photo.
///
/// The AI is optional: the runtime and the models live on the server, so
/// the panel only appears where they are installed.
public struct EditorConfig: Decodable, Equatable, Sendable {
    public let id: Int64
    public let faces: [FaceBox]
    /// The 4× upscale and the models are installed.
    public let ai: Bool
    /// The 67 MB model is installed; it needs WebGPU.
    public let aiHigh: Bool
    /// The optional skin mask is installed.
    public let beauty: Bool

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int64.self, forKey: .id) ?? 0
        faces = try container.decodeIfPresent([FaceBox].self, forKey: .faces) ?? []
        ai = try container.decodeIfPresent(Bool.self, forKey: .ai) ?? false
        aiHigh = try container.decodeIfPresent(Bool.self, forKey: .aiHigh) ?? false
        beauty = try container.decodeIfPresent(Bool.self, forKey: .beauty) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id, faces, ai, aiHigh, beauty
    }
}
