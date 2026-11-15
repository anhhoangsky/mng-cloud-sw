import CoreGraphics
import CoreImage
import Foundation
import MNGEdit
import Vision

/// A face box in the image's own coordinates.
///
/// `rect` is normalised to 0…1 with the origin at the top-left, because the
/// editor's snapshots and masks are top-down. Vision reports bottom-left
/// normalised boxes, so the conversion happens once, here.
struct EditorAIFaceBox: Equatable, Sendable {
    let rect: CGRect

    var area: CGFloat { rect.width * rect.height }

    /// The same box in the pixel space of a mask or buffer.
    func pixels(width: Int, height: Int) -> CGRect {
        CGRect(
            x: rect.minX * CGFloat(width),
            y: rect.minY * CGFloat(height),
            width: rect.width * CGFloat(width),
            height: rect.height * CGFloat(height)
        )
    }

    static func vision(_ observation: VNFaceObservation) -> EditorAIFaceBox {
        let box = observation.boundingBox
        return EditorAIFaceBox(
            rect: CGRect(
                x: box.minX,
                y: 1 - box.maxY,
                width: box.width,
                height: box.height
            )
        )
    }
}

/// One inexpensive Vision pass that tells the selector what the photo holds.
///
/// The web picks its model from a device probe only; the phone also checks
/// the content, because MODNet is a portrait matte and must not run on a
/// landscape just to return an empty alpha. The probe never throws: a Vision
/// failure simply means "no evidence", and the selector keeps Vision first.
enum EditorAIContentProbe {
    static func hints(for source: EditorSourceSnapshot) async -> EditorAIContentHints {
        if Task.isCancelled { return EditorAIContentHints() }
        guard let image = try? EditorAIImage.scaledImage(
            source,
            maxSide: 1024
        ) else {
            return EditorAIContentHints()
        }
        return hints(in: image)
    }

    static func hints(in image: CIImage) -> EditorAIContentHints {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        // Full bodies as well as upper bodies: a distant person still makes
        // the portrait matte the right choice for the balanced tier.
        let human = VNDetectHumanRectanglesRequest()
        human.upperBodyOnly = false
        let face = VNDetectFaceRectanglesRequest()
        do {
            try handler.perform([human, face])
        } catch {
            return EditorAIContentHints()
        }
        let humans = human.results ?? []
        let faces = (face.results ?? [])
            .sorted { lhs, rhs in
                lhs.boundingBox.width * lhs.boundingBox.height
                    > rhs.boundingBox.width * rhs.boundingBox.height
            }
            .map(EditorAIFaceBox.vision)
        var hints = EditorAIContentHints()
        hints.hasPerson = !humans.isEmpty || !faces.isEmpty
        hints.hasFace = !faces.isEmpty
        hints.faces = faces
        return hints
    }
}
