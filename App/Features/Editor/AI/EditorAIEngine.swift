import Foundation
import MNGEdit

/// What the selector knows about the photo before it picks an engine.
///
/// The flags are evidence, not requirements: a person photo still runs the
/// subject model first if the user picked the general tier, and a landscape
/// is never handed to BEN2 without the Vision no-subject gate.
struct EditorAIContentHints: Equatable, Sendable {
    var hasPerson = false
    var hasFace = false
}

struct EditorAISegmentationRequest: Sendable {
    let source: EditorSourceSnapshot
    let mode: EditorAIBackgroundMode
    let hints: EditorAIContentHints
    let report: @Sendable (String) async -> Void
}

struct EditorAISegmentationResult: Sendable {
    let mask: EditorAIMask
    /// The engine that actually produced the mask, for the result metadata
    /// and the benchmark CSV.
    let engineID: String
    let modelID: String?
    let inferenceMilliseconds: Double
    let usedFallback: Bool
}

/// One way to turn a photo into a brush mask.
///
/// The protocol deliberately has no shared mutable state: engines are value
/// types, and the model-backed engine owns its `MLModel` behind its own
/// serial queue. That keeps the Vision path free of model bookkeeping.
protocol EditorAISegmentationEngine: Sendable {
    var id: String { get }
    var modelID: String? { get }
    var requiresDownload: Bool { get }
    func isAvailable() async -> Bool
    func prepare() async throws
    func segment(
        _ request: EditorAISegmentationRequest
    ) async throws -> EditorAISegmentationResult
    func unload() async
}

extension EditorAISegmentationEngine {
    var modelID: String? { nil }
    var requiresDownload: Bool { false }
    func prepare() async throws {}
    func unload() async {}
}

/// Errors that mean "try the next engine" rather than "the pass failed".
/// A missing download is recoverable with Vision; a cancelled task is not.
enum EditorAIEngineFallback: Error {
    case notInstalled(String)
    case unavailable(String)
    case inferenceFailed(String)
}
