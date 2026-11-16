import Foundation
import MNGEdit

/// One one-tap portrait chain from `specs/presets.json`.
///
/// The JSON is the cross-client contract: the web editor imports the same
/// file, applies only the keys a preset names, and leaves every other slider
/// where the person put it. `App/Resources/presets.json` is a byte-for-byte
/// copy of the spec; keep the two in sync when the spec changes.
struct ChainPreset: Codable, Identifiable, Equatable, Sendable {
    struct Chain: Codable, Equatable, Sendable {
        /// The filter id, when the preset wants one.
        var filter: String?
        /// Adjustment values by their web key. Missing keys stay untouched.
        var adjust: [String: Float]?
    }

    var id: String
    var name: String
    var nameEn: String?
    var group: String
    var icon: String?
    /// `portrait` is the only surface today; the field keeps the spec honest.
    var when: String?
    var chain: Chain

    /// The app ships Vietnamese first, like the rest of the shell.
    var title: String { name }
}

/// Loads the bundled preset catalogue once.
enum ChainPresetCatalog {
    static let all: [ChainPreset] = load()

    private struct Document: Codable {
        var version: Int?
        var presets: [ChainPreset]
    }

    private static func load() -> [ChainPreset] {
        guard let url = Bundle.main.url(
            forResource: "presets",
            withExtension: "json"
        ), let data = try? Data(contentsOf: url) else {
            return []
        }
        guard let document = try? JSONDecoder().decode(
            Document.self,
            from: data
        ) else {
            return []
        }
        return document.presets
    }
}
