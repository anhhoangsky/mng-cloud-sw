import CoreGraphics
import Foundation
import MNGEdit

/// Runs one downloaded segmentation graph over the whole photo.
///
/// The frame is letterboxed into the model's square input and the alpha is
/// cropped back to the original aspect before it becomes a brush mask. There
/// is deliberately no tiling: MODNet and the general mattes need the whole
/// subject for their global context, and a 1024-pixel mask is enough for the
/// brush and the full-resolution bake.
struct EditorCoreMLEngine: EditorAISegmentationEngine {
    let descriptor: EditorAIModelDescriptor

    var id: String { "coreml-\(descriptor.id)" }
    var modelID: String? { descriptor.id }
    var requiresDownload: Bool { true }

    func isAvailable() async -> Bool {
        await EditorAIModelStore.shared.isInstalled(descriptor)
    }

    func prepare() async throws {
        try await EditorAIModelRuntime.shared.prepare(descriptor)
    }

    func unload() async {
        await EditorAIModelRuntime.shared.unload()
    }

    func segment(
        _ request: EditorAISegmentationRequest
    ) async throws -> EditorAISegmentationResult {
        guard await isAvailable() else {
            throw EditorAIEngineFallback.notInstalled(descriptor.id)
        }
        guard descriptor.inputWidth == descriptor.inputHeight else {
            throw EditorAIEngineFallback.inferenceFailed("input-size")
        }

        let letterbox: (buffer: EditorAIPixelBuffer, content: CGRect)
        do {
            letterbox = try EditorAIPixelBuffer.letterboxed(
                request.source,
                side: descriptor.inputWidth
            )
        } catch {
            throw EditorAIEngineFallback.inferenceFailed("input")
        }

        let alpha: EditorAIModelRuntime.Alpha
        do {
            alpha = try await EditorAIModelRuntime.shared.alpha(
                descriptor,
                input: letterbox.buffer
            )
        } catch let fallback as EditorAIEngineFallback {
            throw fallback
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw EditorAIEngineFallback.inferenceFailed("prediction")
        }
        try Task.checkCancellation()

        // A portrait matte that returns nothing is a no-subject result, not a
        // valid empty mask: drop to the Vision subject/person engines.
        let coverage = alpha.values.reduce(0, +)
            / Float(max(alpha.values.count, 1))
        guard coverage > 0.0005 else {
            throw EditorAIEngineFallback.inferenceFailed("empty-mask")
        }

        let mask: EditorAIMask
        do {
            let plane = try EditorAIImage.alphaImage(
                alpha.values,
                width: alpha.width,
                height: alpha.height
            )
            // The letterbox content rect is top-down; Core Image's origin is
            // bottom-left, so the crop is flipped once here and never again.
            let content = letterbox.content
            let crop = CGRect(
                x: content.minX,
                y: CGFloat(alpha.height) - content.maxY,
                width: content.width,
                height: content.height
            )
            let normalized = plane
                .cropped(to: crop)
                .transformed(
                    by: CGAffineTransform(
                        translationX: -crop.minX,
                        y: -crop.minY
                    )
                )
            let target = CGRect(
                x: 0,
                y: 0,
                width: CGFloat(request.source.width),
                height: CGFloat(request.source.height)
            )
            mask = try EditorAIImage.makeMask(
                from: EditorAIImage.scaleMask(normalized, to: target),
                maxSide: 1024
            )
        } catch {
            throw EditorAIEngineFallback.inferenceFailed("mask")
        }

        return EditorAISegmentationResult(
            mask: mask,
            engineID: id,
            modelID: descriptor.id,
            inferenceMilliseconds: alpha.inferenceMilliseconds,
            usedFallback: false
        )
    }
}
