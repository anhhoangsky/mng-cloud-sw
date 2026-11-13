import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import MNGEdit
import Vision

/// The native equivalent of the web editor's AI tab engines.
///
/// The browser downloads ONNX segmentation and retouch models. The phone uses
/// the models already shipped with iOS: Vision's subject/person segmentation
/// and face landmarks, then Core Image for the compositing. Everything runs on
/// the device; no pixels leave it before the normal edit upload.
enum EditorAIModel: String, CaseIterable, Identifiable, Sendable {
    case quality
    case balanced
    case fast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quality: return Strings.editorAIModelQuality
        case .balanced: return Strings.editorAIModelBalanced
        case .fast: return Strings.editorAIModelFast
        }
    }

    var detail: String {
        switch self {
        case .quality: return "Vision · Chủ thể · Viền tóc mịn"
        case .balanced: return "Vision · Người · Cân bằng"
        case .fast: return "Vision · Người · Nhanh"
        }
    }
}

enum EditorAIBackgroundMode: String, CaseIterable, Identifiable, Sendable {
    case remove
    case person
    case blur
    case replace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remove: return Strings.editorAIBgRemove
        case .person: return Strings.editorAIBgPerson
        case .blur: return Strings.editorAIBgBlur
        case .replace: return Strings.editorAIBgReplace
        }
    }

    var icon: String {
        switch self {
        case .remove: return "eraser"
        case .person: return "person.crop.rectangle"
        case .blur: return "camera.filters"
        case .replace: return "rectangle.fill"
        }
    }

    var isPrimary: Bool { self == .remove }

    var keepsTransparency: Bool {
        self == .remove || self == .person
    }
}

enum EditorAIRetouchMode: String, CaseIterable, Identifiable, Sendable {
    case whiten
    case smooth
    case blemish
    case tone
    case hair

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whiten: return Strings.editorAIRetouchWhiten
        case .smooth: return Strings.editorAIRetouchSmooth
        case .blemish: return Strings.editorAIRetouchBlemish
        case .tone: return Strings.editorAIRetouchTone
        case .hair: return Strings.editorAIRetouchHair
        }
    }

    var icon: String {
        switch self {
        case .whiten: return "wand.and.stars"
        case .smooth: return "sparkles"
        case .blemish: return "bandage"
        case .tone: return "circle.lefthalf.filled"
        case .hair: return "paintbrush.pointed"
        }
    }

    var isPrimary: Bool { self == .whiten }

    var usesTone: Bool { self == .tone }
    var usesHairColor: Bool { self == .hair }
}

enum EditorAIHairColor: String, CaseIterable, Identifiable, Sendable {
    case espresso
    case black
    case chestnut
    case caramel
    case auburn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .espresso: return Strings.editorAIHairEspresso
        case .black: return Strings.editorAIHairBlack
        case .chestnut: return Strings.editorAIHairChestnut
        case .caramel: return Strings.editorAIHairCaramel
        case .auburn: return Strings.editorAIHairAuburn
        }
    }

    /// sRGB components of the dye tint.
    var components: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        switch self {
        case .espresso: return (0.20, 0.13, 0.09)
        case .black: return (0.07, 0.07, 0.08)
        case .chestnut: return (0.35, 0.20, 0.12)
        case .caramel: return (0.62, 0.42, 0.22)
        case .auburn: return (0.45, 0.15, 0.10)
        }
    }
}

enum EditorAIError: LocalizedError {
    case noSubject
    case noFace
    case cancelled
    case failed

    var errorDescription: String? {
        switch self {
        case .noSubject: return Strings.editorAINoSubject
        case .noFace: return Strings.editorAINoFace
        case .cancelled: return Strings.editorAICancelled
        case .failed: return Strings.editorAIFailed
        }
    }
}

enum EditorAIService {
    // MARK: - Background

    static func background(
        source: EditorSourceSnapshot,
        mode: EditorAIBackgroundMode,
        model: EditorAIModel,
        report: @escaping @Sendable (String) async -> Void
    ) async throws -> EditorSourceSnapshot {
        try Task.checkCancellation()
        await report(
            mode == .person
                ? Strings.editorAISegmentingPerson
                : Strings.editorAISegmenting
        )
        let context = makeContext()
        let input = try makeImage(source)
        let extent = input.extent
        try Task.checkCancellation()

        let mask: CIImage
        if mode == .person || model == .fast {
            mask = try personMask(image: input, fast: model == .fast)
        } else {
            mask = try foregroundMask(image: input)
        }
        try Task.checkCancellation()
        await report(Strings.editorAICompositing)

        let scaledMask = scaleMask(mask, to: extent)
        let background: CIImage
        switch mode {
        case .remove, .person:
            background = CIImage(
                color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
            )
            .cropped(to: extent)
        case .replace:
            background = CIImage(color: CIColor(red: 1, green: 1, blue: 1))
                .cropped(to: extent)
        case .blur:
            let side = min(extent.width, extent.height)
            let sigma = min(max(side * 0.010, 8), 48)
            background = input
                .clampedToExtent()
                .applyingGaussianBlur(sigma: sigma)
                .cropped(to: extent)
        }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = input
        blend.backgroundImage = background
        blend.maskImage = scaledMask
        guard let output = blend.outputImage?.cropped(to: extent) else {
            throw EditorAIError.failed
        }
        try Task.checkCancellation()
        await report(Strings.editorAIApplying)
        return try snapshot(from: output, width: Int(source.width),
                            height: Int(source.height), context: context)
    }

    // MARK: - Retouch

    static func retouch(
        source: EditorSourceSnapshot,
        mode: EditorAIRetouchMode,
        strength: Float,
        tone: Float,
        hairColor: EditorAIHairColor,
        report: @escaping @Sendable (String) async -> Void
    ) async throws -> EditorSourceSnapshot {
        try Task.checkCancellation()
        await report(Strings.editorAIFace)
        let context = makeContext()
        let input = try makeImage(source)
        let extent = input.extent
        let amount = CGFloat(min(max(strength, 0), 1))
        try Task.checkCancellation()

        let masks = try faceMasks(image: input, extent: extent)
        try Task.checkCancellation()
        await report(Strings.editorAIRetouchRunning)

        let skinMask = scaleMask(masks.skin, to: extent)
        let effect: CIImage
        let blendStrength: CGFloat
        switch mode {
        case .whiten:
            effect = input
                .applyingFilter(
                    "CIColorControls",
                    parameters: [
                        kCIInputBrightnessKey: 0.055 * amount,
                        kCIInputSaturationKey: 1 - 0.10 * amount,
                    ]
                )
                .applyingFilter(
                    "CIExposureAdjust",
                    parameters: [kCIInputEVKey: 0.18 * amount]
                )
            blendStrength = amount
        case .smooth:
            let sigma = 5 + 9 * amount
            effect = input
                .clampedToExtent()
                .applyingGaussianBlur(sigma: sigma)
                .cropped(to: extent)
            blendStrength = 0.62 * amount
        case .blemish:
            let sigma = 10 + 10 * amount
            effect = input
                .clampedToExtent()
                .applyingGaussianBlur(sigma: sigma)
                .cropped(to: extent)
            blendStrength = 0.82 * amount
        case .tone:
            effect = temperature(
                input,
                warmth: CGFloat(min(max(tone, -1), 1)),
                amount: amount
            )
            blendStrength = 0.90 * amount
        case .hair:
            let hairMask = scaleMask(masks.hair, to: extent)
            let tinted = tint(
                input,
                color: hairColor.components,
                amount: 0.62 * amount
            )
            effect = tinted
            let blended = blend(
                original: input,
                effect: tinted,
                mask: hairMask,
                strength: 0.90 * amount,
                extent: extent
            )
            try Task.checkCancellation()
            await report(Strings.editorAIApplying)
            return try snapshot(
                from: blended,
                width: Int(source.width),
                height: Int(source.height),
                context: context
            )
        }

        let output = blend(
            original: input,
            effect: effect,
            mask: skinMask,
            strength: blendStrength,
            extent: extent
        )
        try Task.checkCancellation()
        await report(Strings.editorAIApplying)
        return try snapshot(
            from: output,
            width: Int(source.width),
            height: Int(source.height),
            context: context
        )
    }

    // MARK: - Vision masks

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

    private struct FaceMasks {
        var skin: CIImage
        var hair: CIImage
    }

    private static func faceMasks(
        image: CIImage,
        extent: CGRect
    ) throws -> FaceMasks {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        let request = VNDetectFaceLandmarksRequest()
        try handler.perform([request])
        let faces = request.results ?? []
        guard !faces.isEmpty else { throw EditorAIError.noFace }

        let longest = max(extent.width, extent.height)
        let scale = min(1, 1024 / max(longest, 1))
        let maskWidth = max(1, Int((extent.width * scale).rounded()))
        let maskHeight = max(1, Int((extent.height * scale).rounded()))
        let size = CGSize(width: CGFloat(maskWidth), height: CGFloat(maskHeight))

        func pixels(_ rect: CGRect) -> CGRect {
            CGRect(
                x: rect.minX * size.width,
                y: rect.minY * size.height,
                width: rect.width * size.width,
                height: rect.height * size.height
            )
        }

        func regionRect(
            _ region: VNFaceLandmarkRegion2D?,
            face: VNFaceObservation
        ) -> CGRect? {
            guard let points = region?.normalizedPoints, !points.isEmpty else {
                return nil
            }
            var minX = CGFloat(1)
            var minY = CGFloat(1)
            var maxX = CGFloat(0)
            var maxY = CGFloat(0)
            for point in points {
                minX = min(minX, point.x)
                minY = min(minY, point.y)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y)
            }
            let box = face.boundingBox
            let rect = CGRect(
                x: box.minX + minX * box.width,
                y: box.minY + minY * box.height,
                width: (maxX - minX) * box.width,
                height: (maxY - minY) * box.height
            )
            let padded = rect.insetBy(
                dx: -max(rect.width * 0.24, 0.004),
                dy: -max(rect.height * 0.24, 0.004)
            )
            return pixels(padded)
        }

        let skinContext = makeMaskContext(width: maskWidth, height: maskHeight)
        let hairContext = makeMaskContext(width: maskWidth, height: maskHeight)
        for face in faces {
            let box = face.boundingBox
            let faceRect = pixels(box)
            let expanded = faceRect.insetBy(
                dx: -faceRect.width * 0.08,
                dy: -faceRect.height * 0.10
            )
            // The skin mask is the face box; the eyes and the lips are
            // punched out so the whiten/smooth pass cannot wash them out.
            fill(skinContext, expanded, white: true)

            // The hair ellipse covers the crown and the sides of the head.
            // The face and the features are punched out afterwards, so the
            // dye cannot reach the skin or the neck below the chin.
            let hairRect = CGRect(
                x: faceRect.midX - faceRect.width * 0.75,
                y: faceRect.maxY - faceRect.height * 0.62,
                width: faceRect.width * 1.50,
                height: faceRect.height * 0.90
            )
            fill(hairContext, hairRect, white: true)

            let features = [
                regionRect(face.landmarks?.leftEye, face: face),
                regionRect(face.landmarks?.rightEye, face: face),
                regionRect(face.landmarks?.outerLips, face: face),
            ]
            for feature in features.compactMap({ $0 }) {
                fill(skinContext, feature, white: false)
                fill(hairContext, feature, white: false)
            }
            fill(hairContext, expanded, white: false)
        }

        guard let skinImage = skinContext.makeImage(),
              let hairImage = hairContext.makeImage() else {
            throw EditorAIError.failed
        }
        let feather = max(1.5, CGFloat(maskWidth) * 0.006)
        let maskExtent = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(maskWidth),
            height: CGFloat(maskHeight)
        )
        let skin = CIImage(cgImage: skinImage)
            .applyingGaussianBlur(sigma: feather)
            .cropped(to: maskExtent)
        let hair = CIImage(cgImage: hairImage)
            .applyingGaussianBlur(sigma: feather)
            .cropped(to: maskExtent)
        return FaceMasks(skin: skin, hair: hair)
    }

    // MARK: - Core Image helpers

    private static func makeContext() -> CIContext {
        CIContext(options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .outputColorSpace: CGColorSpaceCreateDeviceRGB(),
        ])
    }

    private static func makeImage(
        _ source: EditorSourceSnapshot
    ) throws -> CIImage {
        guard source.width > 0, source.height > 0 else {
            throw EditorAIError.failed
        }
        let expected = Int(source.width) * Int(source.height) * 4
        guard source.rgba.count == expected,
              let provider = CGDataProvider(
                data: Data(source.rgba) as CFData
              ),
              let cgImage = CGImage(
                width: Int(source.width),
                height: Int(source.height),
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: Int(source.width) * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.last.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw EditorAIError.failed
        }
        return CIImage(cgImage: cgImage)
    }

    private static func snapshot(
        from image: CIImage,
        width: Int,
        height: Int,
        context: CIContext
    ) throws -> EditorSourceSnapshot {
        guard width > 0, height > 0 else { throw EditorAIError.failed }
        let extent = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(width),
            height: CGFloat(height)
        )
        let cropped = image.cropped(to: extent)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let cgImage = context.createCGImage(
            cropped,
            from: extent,
            format: .RGBA8,
            colorSpace: colorSpace
        ) else {
            throw EditorAIError.failed
        }

        // Draw through a flipped CTM so row 0 of the buffer is the top row,
        // the row order `EditorSourceSnapshot` and `MNGEdit` expect. The
        // CIContext bitmap overload uses Core Image's bottom-up space, which
        // would otherwise flip the photo after every AI pass.
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let bitmap = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }
            bitmap.interpolationQuality = .none
            bitmap.setShouldAntialias(false)
            bitmap.translateBy(x: 0, y: CGFloat(height))
            bitmap.scaleBy(x: 1, y: -1)
            bitmap.draw(cgImage, in: extent)
            return true
        }
        guard drawn else { throw EditorAIError.failed }
        unpremultiply(&bytes)
        return EditorSourceSnapshot(
            width: UInt32(width),
            height: UInt32(height),
            rgba: bytes
        )
    }

    private static func scaleMask(
        _ mask: CIImage,
        to extent: CGRect
    ) -> CIImage {
        let scaleX = extent.width / max(mask.extent.width, 1)
        let scaleY = extent.height / max(mask.extent.height, 1)
        return mask
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: extent)
    }

    private static func blend(
        original: CIImage,
        effect: CIImage,
        mask: CIImage,
        strength: CGFloat,
        extent: CGRect
    ) -> CIImage {
        let clamped = min(max(strength, 0), 1)
        let matrix = CIFilter.colorMatrix()
        matrix.rVector = CIVector(x: clamped, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: clamped, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: clamped, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.inputImage = mask
        let weighted = matrix.outputImage ?? mask

        let filter = CIFilter.blendWithMask()
        filter.inputImage = effect
        filter.backgroundImage = original
        filter.maskImage = weighted
        return (filter.outputImage ?? original).cropped(to: extent)
    }

    private static func temperature(
        _ image: CIImage,
        warmth: CGFloat,
        amount: CGFloat
    ) -> CIImage {
        let scale = 0.12 * amount
        let warm = min(max(warmth, -1), 1)
        let matrix = CIFilter.colorMatrix()
        matrix.rVector = CIVector(x: 1 + scale * warm, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 1 + scale * 0.15, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 1 - scale * warm, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.inputImage = image
        return matrix.outputImage ?? image
    }

    private static func tint(
        _ image: CIImage,
        color: (red: CGFloat, green: CGFloat, blue: CGFloat),
        amount: CGFloat
    ) -> CIImage {
        let t = min(max(amount, 0), 1)
        let matrix = CIFilter.colorMatrix()
        matrix.rVector = CIVector(x: 1 - t, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 1 - t, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 1 - t, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.biasVector = CIVector(
            x: color.red * t,
            y: color.green * t,
            z: color.blue * t,
            w: 0
        )
        matrix.inputImage = image
        return matrix.outputImage ?? image
    }

    // MARK: - Mask drawing

    private static func makeMaskContext(
        width: Int,
        height: Int
    ) -> CGContext {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    private static func fill(
        _ context: CGContext,
        _ rect: CGRect,
        white: Bool
    ) {
        guard rect.width > 0, rect.height > 0 else { return }
        context.setFillColor(gray: white ? 1 : 0, alpha: 1)
        context.fillEllipse(in: rect)
    }

    private static func unpremultiply(_ pixels: inout [UInt8]) {
        var index = 0
        while index + 3 < pixels.count {
            let alpha = Int(pixels[index + 3])
            if alpha > 0, alpha < 255 {
                pixels[index] = UInt8(
                    min(255, Int(pixels[index]) * 255 / alpha)
                )
                pixels[index + 1] = UInt8(
                    min(255, Int(pixels[index + 1]) * 255 / alpha)
                )
                pixels[index + 2] = UInt8(
                    min(255, Int(pixels[index + 2]) * 255 / alpha)
                )
            }
            index += 4
        }
    }
}
