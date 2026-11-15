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
        // Fast is the shipped Vision path and never downloads anything.
        if model == .fast {
            return [EditorVisionEngine(kind: .personFast)]
        }

        let person = EditorVisionEngine(kind: .personAccurate)
        let subject = EditorVisionEngine(kind: .subject)
        let coreML = model.modelTier
            .flatMap(EditorAIModelCatalog.segmentationModel(for:))
            .map(EditorCoreMLEngine.init(descriptor:))

        // Balanced runs MODNet, a portrait matte. It only runs when the probe
        // actually saw a person; on a landscape the Vision subject lift is
        // better. Quality and Maximum are general mattes, so they are not
        // gated on a face or a body.
        let requiresPerson = model == .balanced
        let useModel = coreML != nil && (!requiresPerson || content.hasPerson)

        if mode == .person {
            var engines: [any EditorAISegmentationEngine] = []
            if useModel, let coreML {
                engines.append(coreML)
            }
            engines.append(person)
            return engines
        }

        var engines: [any EditorAISegmentationEngine] = []
        if useModel, let coreML {
            engines.append(coreML)
        }
        engines.append(subject)
        engines.append(person)
        return engines
    }
}
