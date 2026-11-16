import CoreImage
import Foundation
import Vision

/// The bundled engine. It never downloads anything and is the fallback for
/// every model tier.
struct EditorVisionEngine: EditorAISegmentationEngine {
    enum Kind: String, Sendable {
        /// `VNGenerateForegroundInstanceMaskRequest`: any liftable subject.
        case subject
        /// `VNGeneratePersonSegmentationRequest` at the fast quality.
        case personFast = "person-fast"
        /// `VNGeneratePersonSegmentationRequest` at the accurate quality.
        case personAccurate = "person-accurate"
    }

    let kind: Kind

    var id: String { "vision-\(kind.rawValue)" }
    var requiresDownload: Bool { false }

    func isAvailable() async -> Bool { true }

    func segment(
        _ request: EditorAISegmentationRequest
    ) async throws -> EditorAISegmentationResult {
        let started = ContinuousClock.now
        let input = try EditorAIImage.makeImage(request.source)
        let maskImage: CIImage
        switch kind {
        case .subject:
            maskImage = try Self.foregroundMask(image: input)
        case .personFast:
            maskImage = try Self.personMask(image: input, fast: true)
        case .personAccurate:
            maskImage = try Self.personMask(image: input, fast: false)
        }
        try Task.checkCancellation()
        let mask = try EditorAIImage.makeMask(from: maskImage, maxSide: 1024)
        return EditorAISegmentationResult(
            mask: mask,
            engineID: id,
            modelID: nil,
            inferenceMilliseconds: EditorAIClock.milliseconds(since: started),
            usedFallback: false
        )
    }

    // MARK: - Vision requests

    private static func foregroundMask(image: CIImage) throws -> CIImage {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let result = request.results?.first,
              !result.allInstances.isEmpty else {
            throw EditorAIError.noSubject
        }
        let buffer = try result.generateScaledMaskForImage(
            forInstances: result.allInstances,
            from: handler
        )
        return CIImage(cvPixelBuffer: buffer)
    }

    private static func personMask(image: CIImage, fast: Bool) throws -> CIImage {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = fast ? .fast : .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw EditorAIError.noSubject
        }
        return CIImage(cvPixelBuffer: observation.pixelBuffer)
    }
}
