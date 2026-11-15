import Foundation

/// Resolves a UI tier to the engines that may run, best first.
///
/// Vision stays in every list: a model that is not installed, does not fit
/// memory, or fails to load must never make the background pass fail. The
/// caller stops at the first engine that returns a mask.
enum EditorAIEngineSelector {
    static func engines(
        for model: EditorAIModel,
        mode: EditorAIBackgroundMode,
        content: EditorAIContentHints
    ) -> [any EditorAISegmentationEngine] {
        // Phase one keeps the shipped Vision behaviour exact: Fast always
        // uses the fast person request, and the other tiers try the subject
        // model before the accurate person model. The Core ML engines are
        // inserted here once their catalog entries are enabled.
        switch model {
        case .fast:
            return [EditorVisionEngine(kind: .personFast)]
        case .balanced, .quality, .maximum:
            if mode == .person {
                return [EditorVisionEngine(kind: .personAccurate)]
            }
            return [
                EditorVisionEngine(kind: .subject),
                EditorVisionEngine(kind: .personAccurate),
            ]
        }
    }
}
