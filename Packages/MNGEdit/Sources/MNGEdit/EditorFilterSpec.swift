import Foundation

/// One entry of the shared `specs/filters.json`.
///
/// The web build and the phone bundle the same file. It stores the final 3×3
/// matrix and offset of every tone, so both clients apply the same numbers
/// instead of rebuilding the recipe from two copies of the code.
public struct EditorFilterSpec: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let nameEn: String
    public let category: EditorFilterCategory
    /// Row-major 3×3 matrix, nine values.
    public let matrix: [Float]
    /// Per-channel offset, three values.
    public let offset: [Float]
    /// The Canvas2D approximation used by thumbnails and the fallback.
    public let css: String
    public let hint: String?

    public var isIdentity: Bool {
        matrix == [1, 0, 0, 0, 1, 0, 0, 0, 1]
            && offset == [0, 0, 0]
    }

    /// Every valid preset, in the order of the spec.
    public static let all: [EditorFilterSpec] = load()

    /// The preset with this id, or nil when the spec does not name it.
    public static func filter(id: String) -> EditorFilterSpec? {
        lookup[id]
    }

    private static let lookup: [String: EditorFilterSpec] = {
        var result: [String: EditorFilterSpec] = [:]
        for spec in all where result[spec.id] == nil {
            result[spec.id] = spec
        }
        return result
    }()

    private struct File: Decodable {
        let version: Int
        let filters: [EditorFilterSpec]
    }

    private static func load() -> [EditorFilterSpec] {
        // `.copy("Resources")` keeps the folder in the bundle; the flat lookup
        // is a fallback for a toolchain that flattens copied directories.
        let url = Bundle.module.url(
            forResource: "filters",
            withExtension: "json",
            subdirectory: "Resources"
        ) ?? Bundle.module.url(
            forResource: "filters",
            withExtension: "json"
        )
        guard let url else {
            assertionFailure("filters.json is missing from the MNGEdit bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(File.self, from: data)
            guard file.version == 1 else {
                assertionFailure(
                    "unsupported filters.json version \(file.version)"
                )
                return []
            }
            return file.filters.filter { spec in
                !spec.id.isEmpty
                    && spec.matrix.count == 9
                    && spec.offset.count == 3
                    && spec.matrix.allSatisfy { $0.isFinite }
                    && spec.offset.allSatisfy { $0.isFinite }
            }
        } catch {
            assertionFailure("filters.json does not decode: \(error)")
            return []
        }
    }
}
