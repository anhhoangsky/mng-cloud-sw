import CoreGraphics
import CoreImage
import Foundation
import MNGEdit

/// BiSeNet face parsing for the hair retouch.
///
/// The graph is a face parser, not a full-frame matte: it labels the hair,
/// face, hat and glasses of a face crop with far more precision than a skin
/// colour heuristic, but on a whole portrait it would mostly return labels
/// for a tiny face. This engine therefore reproduces the web's crop plan:
/// one generous square around each of the largest four faces, parsed one at a
/// time, then merged with `max` so a shared hair edge never gets brighter.
struct EditorFaceParsingEngine: Sendable {
    static let maximumFaces = 4
    static let maskSide = 1024

    let descriptor: EditorAIModelDescriptor

    var id: String { "coreml-\(descriptor.id)" }

    func isAvailable() async -> Bool {
        await EditorAIModelStore.shared.isInstalled(descriptor)
    }

    func prepare() async throws {
        try await EditorAIModelRuntime.shared.prepare(descriptor)
    }

    /// Return a top-down soft hair mask in the editor's brush contract.
    ///
    /// Throws when the model is not installed, no face yields usable hair, or
    /// the parser output is empty; the caller keeps the ellipse fallback.
    func hairMask(
        source: EditorSourceSnapshot,
        faces: [EditorAIFaceBox]
    ) async throws -> EditorAIMask {
        guard await isAvailable() else {
            throw EditorAIEngineFallback.notInstalled(descriptor.id)
        }
        guard descriptor.inputWidth == descriptor.inputHeight,
              descriptor.inputWidth > 0 else {
            throw EditorAIEngineFallback.inferenceFailed("input-size")
        }
        guard !faces.isEmpty else { throw EditorAIError.noFace }

        let sourceWidth = Int(source.width)
        let sourceHeight = Int(source.height)
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw EditorAIError.failed
        }
        let scale = min(
            1,
            CGFloat(Self.maskSide) / CGFloat(max(sourceWidth, sourceHeight))
        )
        let maskWidth = max(1, Int((CGFloat(sourceWidth) * scale).rounded()))
        let maskHeight = max(1, Int((CGFloat(sourceHeight) * scale).rounded()))

        let work: EditorAIPixelBuffer
        do {
            work = try EditorAIPixelBuffer(source: source).resized(
                width: maskWidth,
                height: maskHeight
            )
        } catch {
            throw EditorAIEngineFallback.inferenceFailed("input")
        }

        var merged = [UInt8](repeating: 0, count: maskWidth * maskHeight)
        var recognized = 0
        let ordered = faces
            .sorted { $0.area > $1.area }
            .prefix(Self.maximumFaces)

        for face in ordered {
            try Task.checkCancellation()
            let geometry = Self.crop(
                for: face,
                width: maskWidth,
                height: maskHeight
            )
            guard let geometry else { continue }

            let input: EditorAIPixelBuffer
            let alpha: EditorAIModelRuntime.Alpha
            do {
                input = try work
                    .cropped(
                        x: geometry.x,
                        y: geometry.y,
                        width: geometry.side,
                        height: geometry.side
                    )
                    .resized(
                        width: descriptor.inputWidth,
                        height: descriptor.inputHeight
                    )
                alpha = try await EditorAIModelRuntime.shared.alpha(
                    descriptor,
                    input: input
                )
            } catch let fallback as EditorAIEngineFallback {
                if case .notInstalled = fallback { throw fallback }
                continue
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
            recognized += Self.merge(
                alpha,
                into: &merged,
                maskWidth: maskWidth,
                x: geometry.x,
                y: geometry.y,
                side: geometry.side
            )
        }

        guard recognized > 0 else {
            throw EditorAIEngineFallback.inferenceFailed("no-face")
        }
        let total = merged.reduce(0) { $0 + Int($1) }
        guard total > max(16 * 255, Int(Double(maskWidth * maskHeight) * 0.0005 * 255)) else {
            // Nothing recognised: let the caller fall back to the ellipse.
            throw EditorAIEngineFallback.inferenceFailed("empty-mask")
        }

        let raw = EditorAIMask(
            width: maskWidth,
            height: maskHeight,
            bytes: merged
        )
        let extent = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(maskWidth),
            height: CGFloat(maskHeight)
        )
        do {
            // The web feathers the parsed hair mask by 2 px before handing it
            // to the compositor; the blur is applied in mask space.
            let soft = try EditorAIImage.maskImage(raw)
                .applyingGaussianBlur(sigma: 2)
                .cropped(to: extent)
            return try EditorAIImage.makeMask(from: soft, maxSide: Self.maskSide)
        } catch {
            throw EditorAIEngineFallback.inferenceFailed("mask")
        }
    }

    // MARK: - Geometry

    private struct Crop {
        let x: Int
        let y: Int
        let side: Int
    }

    /// The web's `hairFaceCrop`: a square 1.9 face-widths wide and 2.5
    /// face-heights tall, shifted up so the crown is inside, clamped to the
    /// photo. Working in mask pixels keeps every face at the same scale.
    private static func crop(
        for face: EditorAIFaceBox,
        width: Int,
        height: Int
    ) -> Crop? {
        let faceWidth = face.rect.width * CGFloat(width)
        let faceHeight = face.rect.height * CGFloat(height)
        guard faceWidth > 0, faceHeight > 0 else { return nil }
        let centerX = face.rect.midX * CGFloat(width)
        let centerY = face.rect.midY * CGFloat(height)
        let side = min(
            max(faceWidth * 1.9, faceHeight * 2.5),
            CGFloat(width),
            CGFloat(height)
        )
        guard side >= 8 else { return nil }
        let sidePixels = max(8, Int(side.rounded()))
        let x = min(
            max(0, Int((centerX - CGFloat(sidePixels) / 2).rounded())),
            max(0, width - sidePixels)
        )
        let y = min(
            max(
                0,
                Int(
                    (
                        centerY - faceHeight * 0.32
                            - CGFloat(sidePixels) / 2
                    ).rounded()
                )
            ),
            max(0, height - sidePixels)
        )
        return Crop(x: x, y: y, side: sidePixels)
    }

    // MARK: - Merge

    /// Bilinear resample of one face's alpha into the shared mask, keeping the
    /// maximum of overlapping crops. Returns the number of bytes written, so
    /// the caller can tell a successful parse from an empty one.
    private static func merge(
        _ alpha: EditorAIModelRuntime.Alpha,
        into mask: inout [UInt8],
        maskWidth: Int,
        x: Int,
        y: Int,
        side: Int
    ) -> Int {
        let modelWidth = alpha.width
        let modelHeight = alpha.height
        guard modelWidth > 0, modelHeight > 0,
              alpha.values.count == modelWidth * modelHeight,
              side > 0 else {
            return 0
        }
        var written = 0
        for row in 0..<side {
            let sourceY = (Float(row) + 0.5) / Float(side)
                * Float(modelHeight) - 0.5
            let maskRow = (y + row) * maskWidth + x
            for column in 0..<side {
                let sourceX = (Float(column) + 0.5) / Float(side)
                    * Float(modelWidth) - 0.5
                let value = sample(
                    alpha.values,
                    width: modelWidth,
                    height: modelHeight,
                    x: sourceX,
                    y: sourceY
                )
                let byte = UInt8(
                    (min(max(value, 0), 1) * 255).rounded()
                )
                let index = maskRow + column
                if index >= 0, index < mask.count, byte > mask[index] {
                    mask[index] = byte
                    if byte > 0 { written += 1 }
                } else if byte > 0 {
                    written += 1
                }
            }
        }
        return written
    }

    private static func sample(
        _ values: [Float],
        width: Int,
        height: Int,
        x: Float,
        y: Float
    ) -> Float {
        let clampedX = min(max(x, 0), Float(width - 1))
        let clampedY = min(max(y, 0), Float(height - 1))
        let x0 = Int(clampedX)
        let y0 = Int(clampedY)
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let fx = clampedX - Float(x0)
        let fy = clampedY - Float(y0)
        let top = values[y0 * width + x0] * (1 - fx)
            + values[y0 * width + x1] * fx
        let bottom = values[y1 * width + x0] * (1 - fx)
            + values[y1 * width + x1] * fx
        return top * (1 - fy) + bottom * fy
    }
}
