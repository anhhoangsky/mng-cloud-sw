import CoreGraphics
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
        case .balanced: return "Vision · Chủ thể · Cân bằng"
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

    /// Blur and white can switch to a transparent background in the brush
    /// toolbar, exactly like the web's "Nền trong suốt" chip.
    var canBecomeTransparent: Bool {
        self == .blur || self == .replace
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

/// A brush-editable weight map, row 0 at the top, 0…255.
struct EditorAIMask: Sendable {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    static func zeros(width: Int, height: Int) -> EditorAIMask {
        EditorAIMask(
            width: width,
            height: height,
            bytes: [UInt8](repeating: 0, count: max(width * height, 0))
        )
    }
}

/// What the mask toolbar is refining.
enum EditorAIRefineTarget: Equatable, Sendable {
    case background(EditorAIBackgroundMode)
    case retouch(EditorAIRetouchMode)

    var isRetouch: Bool {
        if case .retouch = self { return true }
        return false
    }

    var isBackground: Bool {
        if case .background = self { return true }
        return false
    }
}

enum EditorAIBrushMode: String, CaseIterable, Identifiable, Sendable {
    case add
    case erase

    var id: String { rawValue }
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
    // MARK: - Masks

    /// Run Vision and return the soft mask only. The brush toolbar composites
    /// it, so the user can add/erase the edge before anything is baked.
    static func backgroundMask(
        source: EditorSourceSnapshot,
        mode: EditorAIBackgroundMode,
        model: EditorAIModel,
        report: @escaping @Sendable (String) async -> Void
    ) async throws -> EditorAIMask {
        try Task.checkCancellation()
        await report(
            mode == .person
                ? Strings.editorAISegmentingPerson
                : Strings.editorAISegmenting
        )
        let input = try makeImage(source)
        let maskImage: CIImage
        if mode == .person || model == .fast {
            maskImage = try personMask(image: input, fast: model == .fast)
        } else {
            do {
                maskImage = try foregroundMask(image: input)
            } catch EditorAIError.noSubject {
                // A photo without a liftable object can still contain a
                // person; MODNet is the sensible fallback on the phone.
                maskImage = try personMask(image: input, fast: false)
            }
        }
        try Task.checkCancellation()
        await report(Strings.editorAICompositing)
        return try makeMask(from: maskImage, maxSide: 1024)
    }

    /// Return the skin (or hair) weight map without baking the retouch. The
    /// five sliders and the brush stay live until "Hoàn tất".
    static func retouchMask(
        source: EditorSourceSnapshot,
        mode: EditorAIRetouchMode,
        report: @escaping @Sendable (String) async -> Void
    ) async throws -> EditorAIMask {
        try Task.checkCancellation()
        await report(Strings.editorAIFace)
        let input = try makeImage(source)
        let masks = try faceMasks(image: input, extent: input.extent)
        try Task.checkCancellation()
        await report(Strings.editorAIRetouchRunning)
        let selected = mode == .hair ? masks.hair : masks.skin
        var mask = try makeMask(from: selected, maxSide: 1024)
        if mode == .blemish {
            // The web starts blemish with an empty mask: the user paints the
            // spots to heal with the brush.
            mask.bytes = [UInt8](
                repeating: 0,
                count: mask.width * mask.height
            )
        }
        return mask
    }

    // MARK: - Preview and bake

    static func backgroundPreview(
        source: EditorSourceSnapshot,
        mask: EditorAIMask,
        mode: EditorAIBackgroundMode,
        transparent: Bool,
        blurStrength: Float,
        maxSide: CGFloat
    ) throws -> EditorSourceSnapshot {
        let input = try scaledImage(source, maxSide: maxSide)
        let output = try composeBackground(
            input: input,
            mask: try maskImage(mask),
            mode: mode,
            transparent: transparent,
            blurStrength: blurStrength
        )
        let preview = previewOutput(
            output,
            checkerboard: transparent || mode.keepsTransparency
        )
        return try snapshot(
            from: preview,
            width: Int(input.extent.width.rounded()),
            height: Int(input.extent.height.rounded())
        )
    }

    static func backgroundBake(
        source: EditorSourceSnapshot,
        mask: EditorAIMask,
        mode: EditorAIBackgroundMode,
        transparent: Bool,
        blurStrength: Float
    ) throws -> EditorSourceSnapshot {
        let input = try makeImage(source)
        let output = try composeBackground(
            input: input,
            mask: try maskImage(mask),
            mode: mode,
            transparent: transparent,
            blurStrength: blurStrength
        )
        return try snapshot(
            from: output,
            width: Int(source.width),
            height: Int(source.height)
        )
    }

    static func retouchPreview(
        source: EditorSourceSnapshot,
        mask: EditorAIMask,
        mode: EditorAIRetouchMode,
        strength: Float,
        tone: Float,
        hairColor: EditorAIHairColor,
        maxSide: CGFloat
    ) throws -> EditorSourceSnapshot {
        let input = try scaledImage(source, maxSide: maxSide)
        let output = composeRetouch(
            input: input,
            mask: try maskImage(mask),
            mode: mode,
            strength: strength,
            tone: tone,
            hairColor: hairColor
        )
        return try snapshot(
            from: output,
            width: Int(input.extent.width.rounded()),
            height: Int(input.extent.height.rounded())
        )
    }

    static func retouchBake(
        source: EditorSourceSnapshot,
        mask: EditorAIMask,
        mode: EditorAIRetouchMode,
        strength: Float,
        tone: Float,
        hairColor: EditorAIHairColor
    ) throws -> EditorSourceSnapshot {
        let input = try makeImage(source)
        let output = composeRetouch(
            input: input,
            mask: try maskImage(mask),
            mode: mode,
            strength: strength,
            tone: tone,
            hairColor: hairColor
        )
        return try snapshot(
            from: output,
            width: Int(source.width),
            height: Int(source.height)
        )
    }

    // MARK: - Composition

    private static func composeBackground(
        input: CIImage,
        mask: CIImage,
        mode: EditorAIBackgroundMode,
        transparent: Bool,
        blurStrength: Float
    ) throws -> CIImage {
        let extent = input.extent
        let scaledMask = scaleMask(mask, to: extent)
        let effective: EditorAIBackgroundMode = transparent ? .remove : mode
        let background: CIImage
        switch effective {
        case .remove, .person:
            background = CIImage(
                color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
            )
            .cropped(to: extent)
        case .replace:
            background = CIImage(
                color: CIColor(red: 1, green: 1, blue: 1)
            )
            .cropped(to: extent)
        case .blur:
            // The sigma follows the image size so the preview and the
            // full-resolution bake look the same. The slider reaches a strong
            // portrait blur without turning the background into a flat wash.
            let side = min(extent.width, extent.height)
            let amount = CGFloat(min(max(blurStrength, 0), 1))
            let sigma = min(max(side * (0.004 + 0.026 * amount), 3), 180)
            background = input
                .clampedToExtent()
                .applyingGaussianBlur(sigma: sigma)
                .cropped(to: extent)
        }

        let filter = CIFilter.blendWithMask()
        filter.inputImage = input
        filter.backgroundImage = background
        filter.maskImage = scaledMask
        guard let output = filter.outputImage?.cropped(to: extent) else {
            throw EditorAIError.failed
        }
        return output
    }

    private static func composeRetouch(
        input: CIImage,
        mask: CIImage,
        mode: EditorAIRetouchMode,
        strength: Float,
        tone: Float,
        hairColor: EditorAIHairColor
    ) -> CIImage {
        let extent = input.extent
        let scaledMask = scaleMask(mask, to: extent)
        let amount = CGFloat(min(max(strength, 0), 1))
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
            let side = min(extent.width, extent.height)
            let sigma = min(max(side * (0.004 + 0.008 * amount), 4), 60)
            effect = input
                .clampedToExtent()
                .applyingGaussianBlur(sigma: sigma)
                .cropped(to: extent)
            blendStrength = 0.62 * amount
        case .blemish:
            let side = min(extent.width, extent.height)
            let sigma = min(max(side * (0.008 + 0.012 * amount), 8), 90)
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
            let tinted = tint(
                input,
                color: hairColor.components,
                amount: 0.62 * amount
            )
            effect = tinted
            blendStrength = 0.90 * amount
        }
        return blend(
            original: input,
            effect: effect,
            mask: scaledMask,
            strength: blendStrength,
            extent: extent
        )
    }

    private static func previewOutput(
        _ image: CIImage,
        checkerboard: Bool
    ) -> CIImage {
        guard checkerboard else { return image }
        let extent = image.extent
        let checker = CIFilter.checkerboardGenerator()
        checker.color0 = CIColor(red: 0.20, green: 0.20, blue: 0.22)
        checker.color1 = CIColor(red: 0.13, green: 0.13, blue: 0.15)
        checker.width = 18
        checker.sharpness = 1
        checker.center = CGPoint(x: extent.midX, y: extent.midY)
        guard let pattern = checker.outputImage?.cropped(to: extent) else {
            return image
        }
        let over = CIFilter.sourceOverCompositing()
        over.backgroundImage = pattern
        over.inputImage = image
        return (over.outputImage ?? image).cropped(to: extent)
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

    private static func scaledImage(
        _ source: EditorSourceSnapshot,
        maxSide: CGFloat
    ) throws -> CIImage {
        let input = try makeImage(source)
        let extent = input.extent
        let side = max(extent.width, extent.height)
        guard maxSide > 0, side > maxSide else { return input }
        let scale = maxSide / side
        let width = max(1, (extent.width * scale).rounded())
        let height = max(1, (extent.height * scale).rounded())
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        return input
            .transformed(
                by: CGAffineTransform(scaleX: scale, y: scale)
            )
            .cropped(to: target)
    }

    /// The mask as a top-down Core Image bitmap. The brush stores the same
    /// row order, so the painted edge lands on the pixel under the finger.
    private static func maskImage(_ mask: EditorAIMask) throws -> CIImage {
        guard mask.width > 0,
              mask.height > 0,
              mask.bytes.count == mask.width * mask.height,
              let provider = CGDataProvider(
                data: Data(mask.bytes) as CFData
              ),
              let image = CGImage(
                width: mask.width,
                height: mask.height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: mask.width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.none.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw EditorAIError.failed
        }
        return CIImage(cgImage: image)
    }

    private static func makeMask(
        from image: CIImage,
        maxSide: Int
    ) throws -> EditorAIMask {
        let extent = image.extent
        guard extent.width >= 1, extent.height >= 1, maxSide > 0 else {
            throw EditorAIError.failed
        }
        let side = max(extent.width, extent.height)
        let scale = side > CGFloat(maxSide) ? CGFloat(maxSide) / side : 1
        let width = max(1, Int((extent.width * scale).rounded()))
        let height = max(1, Int((extent.height * scale).rounded()))
        let target = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(width),
            height: CGFloat(height)
        )
        let scaled = image
            .transformed(
                by: CGAffineTransform(scaleX: scale, y: scale)
            )
            .cropped(to: target)
        let context = makeContext()
        guard let cgImage = context.createCGImage(
            scaled,
            from: target,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        ), let converted = EditorBitmap.topDownRGBA(from: cgImage) else {
            throw EditorAIError.failed
        }
        guard converted.width == width, converted.height == height else {
            throw EditorAIError.failed
        }
        var bytes = [UInt8](repeating: 0, count: width * height)
        let count = min(bytes.count, converted.width * converted.height)
        var index = 0
        while index < count {
            bytes[index] = converted.rgba[index * 4]
            index += 1
        }
        return EditorAIMask(width: width, height: height, bytes: bytes)
    }

    private static func snapshot(
        from image: CIImage,
        width: Int,
        height: Int
    ) throws -> EditorSourceSnapshot {
        guard width > 0, height > 0 else { throw EditorAIError.failed }
        let extent = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(width),
            height: CGFloat(height)
        )
        let context = makeContext()
        guard let cgImage = context.createCGImage(
            image.cropped(to: extent),
            from: extent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        ), let converted = EditorBitmap.topDownRGBA(from: cgImage) else {
            throw EditorAIError.failed
        }
        return EditorSourceSnapshot(
            width: UInt32(converted.width),
            height: UInt32(converted.height),
            rgba: converted.rgba
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
}
