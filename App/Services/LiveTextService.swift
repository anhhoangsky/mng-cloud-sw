import UIKit
import Vision

/// Reads the text of a photo with the Vision framework.
///
/// This is the same recognizer the system uses for the "Live Text" button in
/// the Photos app: a long press on a photo reads whatever text is written on
/// it. Vietnamese is requested first so accents are read correctly.
@MainActor
final class LiveTextService {
    static let shared = LiveTextService()

    private init() {}

    func recognize(_ image: UIImage) async -> LiveTextOutcome {
        guard let cgImage = image.cgImage else { return .failed }
        do {
            let lines = try await Task.detached(priority: .userInitiated) {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["vi-VN", "en-US"]
                let handler = VNImageRequestHandler(
                    cgImage: cgImage,
                    orientation: .up,
                    options: [:]
                )
                try handler.perform([request])
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                return observations.compactMap { $0.topCandidates(1).first?.string }
            }.value
            guard !lines.isEmpty else { return .empty }
            return .text(lines.joined(separator: "\n"))
        } catch {
            return .failed
        }
    }
}
