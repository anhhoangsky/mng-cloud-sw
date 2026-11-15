import CoreML
import Foundation

/// Owns the one loaded `MLModel` and serialises inference.
///
/// The actor is the only place an `MLModel` or `MLMultiArray` lives, so the
/// rest of the app only passes value types across the concurrency boundary.
/// At most one model is resident; switching tiers releases the previous one.
actor EditorAIModelRuntime {
    static let shared = EditorAIModelRuntime()

    struct Alpha: Sendable {
        let values: [Float]
        let width: Int
        let height: Int
        let inferenceMilliseconds: Double
        let loadMilliseconds: Double
    }

    private struct Loaded {
        let key: String
        let model: MLModel
    }

    private var loaded: Loaded?

    func unload() {
        loaded = nil
    }

    /// Load the model without running inference. Used by the download flow to
    /// prove the artifact compiles and loads before the UI reports success.
    func prepare(_ descriptor: EditorAIModelDescriptor) async throws {
        _ = try await model(for: descriptor)
    }

    func alpha(
        _ descriptor: EditorAIModelDescriptor,
        input: EditorAIPixelBuffer
    ) async throws -> Alpha {
        try Task.checkCancellation()
        if let reason = EditorAIMemoryGuard.denialReason(for: descriptor) {
            // Give back the resident weights; the next allowed run reloads
            // them from the compiled cache.
            loaded = nil
            throw EditorAIEngineFallback.unavailable(reason)
        }

        let loadStart = ContinuousClock.now
        let model = try await model(for: descriptor)
        let loadMilliseconds = EditorAIClock.milliseconds(since: loadStart)

        let tensor = try Self.tensor(descriptor, buffer: input)
        let provider: MLFeatureProvider
        do {
            provider = try MLDictionaryFeatureProvider(
                dictionary: [
                    descriptor.inputName: MLFeatureValue(multiArray: tensor),
                ]
            )
        } catch {
            throw EditorAIEngineFallback.inferenceFailed("input")
        }

        let start = ContinuousClock.now
        let prediction: MLFeatureProvider
        do {
            prediction = try model.prediction(from: provider)
        } catch {
            throw EditorAIEngineFallback.inferenceFailed("prediction")
        }
        let inferenceMilliseconds = EditorAIClock.milliseconds(since: start)

        guard let output = prediction
            .featureValue(for: descriptor.outputName)?
            .multiArrayValue else {
            throw EditorAIEngineFallback.inferenceFailed("output")
        }
        let alpha = try Self.alphaValues(
            output,
            semantics: descriptor.outputSemantics
        )
        return Alpha(
            values: alpha.values,
            width: alpha.width,
            height: alpha.height,
            inferenceMilliseconds: inferenceMilliseconds,
            loadMilliseconds: loadMilliseconds
        )
    }

    // MARK: - Model lifecycle

    private func model(
        for descriptor: EditorAIModelDescriptor
    ) async throws -> MLModel {
        let key = "\(descriptor.id)@\(descriptor.version)"
        if let loaded, loaded.key == key { return loaded.model }
        loaded = nil

        let compiled: URL
        do {
            compiled = try await EditorAIModelStore.shared
                .compiledModelURL(descriptor)
        } catch let error as EditorAIModelStoreError {
            switch error {
            case .notInstalled:
                throw EditorAIEngineFallback.notInstalled(descriptor.id)
            default:
                throw EditorAIEngineFallback.unavailable("store")
            }
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let model: MLModel
        do {
            model = try MLModel(contentsOf: compiled, configuration: configuration)
        } catch {
            throw EditorAIEngineFallback.inferenceFailed("load")
        }
        loaded = Loaded(key: key, model: model)
        return model
    }

    // MARK: - Tensors

    private static func tensor(
        _ descriptor: EditorAIModelDescriptor,
        buffer: EditorAIPixelBuffer
    ) throws -> MLMultiArray {
        guard buffer.width == descriptor.inputWidth,
              buffer.height == descriptor.inputHeight else {
            throw EditorAIEngineFallback.inferenceFailed("input-size")
        }
        let plane = descriptor.inputWidth * descriptor.inputHeight
        let shape: [NSNumber] = [
            1,
            3,
            NSNumber(value: descriptor.inputHeight),
            NSNumber(value: descriptor.inputWidth),
        ]
        let array: MLMultiArray
        do {
            array = try MLMultiArray(shape: shape, dataType: .float32)
        } catch {
            throw EditorAIEngineFallback.inferenceFailed("tensor")
        }
        let pointer = array.dataPointer.bindMemory(
            to: Float.self,
            capacity: plane * 3
        )
        let rgba = buffer.rgba

        switch descriptor.preprocess {
        case .modnet:
            for index in 0..<plane {
                let pixel = index * 4
                pointer[index] = Float(rgba[pixel]) / 127.5 - 1
                pointer[plane + index] = Float(rgba[pixel + 1]) / 127.5 - 1
                pointer[plane * 2 + index] = Float(rgba[pixel + 2]) / 127.5 - 1
            }
        case .imagenet:
            let mean: [Float] = [0.485, 0.456, 0.406]
            let std: [Float] = [0.229, 0.224, 0.225]
            for index in 0..<plane {
                let pixel = index * 4
                for channel in 0..<3 {
                    pointer[channel * plane + index] = (
                        Float(rgba[pixel + channel]) / 255 - mean[channel]
                    ) / std[channel]
                }
            }
        }
        return array
    }

    private static func alphaValues(
        _ array: MLMultiArray,
        semantics: EditorAIAlphaSemantics
    ) throws -> (values: [Float], width: Int, height: Int) {
        let shape = array.shape.map { $0.intValue }
        guard shape.count >= 2 else {
            throw EditorAIEngineFallback.inferenceFailed("output-shape")
        }
        let height = shape[shape.count - 2]
        let width = shape[shape.count - 1]
        let count = array.count
        guard width > 0, height > 0, count == width * height else {
            throw EditorAIEngineFallback.inferenceFailed("output-channels")
        }
        var values = [Float](repeating: 0, count: count)
        // Float16 weights usually surface as a Float32 output array, but the
        // fp16 graph may hand back Float16 on newer runtimes. Accept both.
        switch array.dataType {
        case .float32:
            let pointer = array.dataPointer.bindMemory(
                to: Float.self,
                capacity: count
            )
            for index in 0..<count {
                values[index] = pointer[index]
            }
        case .float16:
            let pointer = array.dataPointer.bindMemory(
                to: Float16.self,
                capacity: count
            )
            for index in 0..<count {
                values[index] = Float(pointer[index])
            }
        default:
            throw EditorAIEngineFallback.inferenceFailed("output-type")
        }
        for index in 0..<count {
            var value = values[index]
            switch semantics {
            case .alpha01:
                break
            case .logitsSigmoid:
                value = 1 / (1 + expf(-value))
            case .hairAlpha:
                // The exported BiSeNet graph returns sigmoid(hair - best).
                // The web zeroes the ambiguous lower half; keep that here.
                value = value <= 0.5 ? 0 : value
            }
            values[index] = min(max(value, 0), 1)
        }
        return (values, width, height)
    }
}
