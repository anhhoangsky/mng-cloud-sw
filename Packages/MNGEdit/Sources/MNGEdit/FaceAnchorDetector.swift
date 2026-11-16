#if canImport(Vision) && canImport(CoreGraphics)
import CoreGraphics
import Vision

/// Turns Vision's face landmarks into the anchor layout of `FaceWarp`.
///
/// The web editor accepts a 4×4 RGBA8 texture with one row per face: eye and
/// mouth positions in face-local `-1…1`, then their radii in `0…0.6`. This
/// adapter produces exactly that data on the Swift side, so both clients warp
/// the same eyes/nose/mouth instead of falling back to the generic defaults.
///
/// Vision reports boxes in a bottom-left origin and landmark points relative
/// to the face box. Both are flipped here to the top-down orientation the
/// editor uses.
public enum FaceAnchorDetector {
    /// Detect up to four faces, strongest first, in an oriented image.
    public static func anchors(in image: CGImage) throws -> [EditorFaceAnchor] {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(
            cgImage: image,
            orientation: .up,
            options: [:]
        )
        try handler.perform([request])
        let faces = request.results ?? []
        return FaceWarp.normalize(faces.compactMap(anchor(for:)))
    }

    private struct Region {
        var center: SIMD2<Float>
        var radius: SIMD2<Float>
    }

    private static func anchor(for face: VNFaceObservation) -> EditorFaceAnchor? {
        let box = face.boundingBox
        guard box.width > 0.01, box.height > 0.01 else { return nil }
        let editorBox = EditorFaceBox(
            x: Float(box.minX),
            // Vision's origin is bottom-left, the editor's is top-left.
            y: Float(1 - box.maxY),
            width: Float(box.width),
            height: Float(box.height),
            confidence: Float(face.confidence)
        )

        let landmarks = face.landmarks
        let eyes = [landmarks?.leftEye, landmarks?.rightEye]
            .compactMap { region($0, padding: 1.15) }
            // Anatomical left/right is not the same as image left/right; the
            // smaller x is always the eye on the left of the photo.
            .sorted { $0.center.x < $1.center.x }
        let nose = region(landmarks?.nose, padding: 1.20)
        let mouth = region(landmarks?.outerLips, padding: 1.15)

        return EditorFaceAnchor(
            box: editorBox,
            eyeLeft: eyes.first?.center,
            eyeRight: eyes.count > 1 ? eyes[1].center : nil,
            nose: nose?.center,
            mouth: mouth?.center,
            eyeLeftRadius: eyes.first?.radius,
            eyeRightRadius: eyes.count > 1 ? eyes[1].radius : nil,
            noseRadius: nose?.radius,
            mouthRadius: mouth?.radius
        )
    }

    /// Centre and half-extent of a landmark region in face-local units.
    private static func region(
        _ region: VNFaceLandmarkRegion2D?,
        padding: Float
    ) -> Region? {
        guard let points = region?.normalizedPoints, !points.isEmpty else {
            return nil
        }
        var minX = Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        var sumX: Float = 0
        var sumY: Float = 0
        for point in points {
            let x = Float(point.x)
            // Vision is bottom-up; the editor is top-down.
            let y = 1 - Float(point.y)
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
            sumX += x
            sumY += y
        }
        let count = Float(points.count)
        let center = SIMD2<Float>(
            min(max(sumX / count * 2 - 1, -1), 1),
            min(max(sumY / count * 2 - 1, -1), 1)
        )
        // A span of `extent` in face-box units maps to `2·extent` in the
        // face-local space, so the half-extent is just `extent`.
        let radius = SIMD2<Float>(
            min(max((maxX - minX) * padding, 0.02), 0.6),
            min(max((maxY - minY) * padding, 0.02), 0.6)
        )
        return Region(center: center, radius: radius)
    }
}
#endif
