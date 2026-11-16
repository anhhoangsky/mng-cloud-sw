import Foundation

enum EditorAIModelTier: String, Codable, Sendable {
    case balanced
    case quality
    case maximum
    case retouch
}

enum EditorAIModelKind: String, Codable, Sendable {
    case segmentation
    case faceParsing
}

/// The normalisation baked into `EditorAIModelRuntime.tensor`.
enum EditorAIPreprocess: String, Codable, Sendable {
    /// `(x / 255 - 0.5) / 0.5`, MODNet's portrait matting input.
    case modnet
    /// ImageNet mean/std, used by BiRefNet and BiSeNet.
    case imagenet
    /// `(x - 128) / 256` with x in 0…255, ISNet's input.
    case isnet
}

enum EditorAIAlphaSemantics: String, Codable, Sendable {
    /// The graph already returns alpha in 0…1.
    case alpha01
    /// The graph returns logits; the runtime applies a sigmoid.
    case logitsSigmoid
    /// `sigmoid(hair - max(other))`; zero below 0.5 like the web.
    case hairAlpha
}

/// A pinned, downloadable model. The catalog is embedded in the app: the
/// SHA-256 below is the trust anchor, so a compromised CDN cannot swap the
/// weights for different bytes.
struct EditorAIModelDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let version: String
    let displayName: String
    let tier: EditorAIModelTier
    let kind: EditorAIModelKind
    let archiveURL: URL
    let archiveSHA256: String
    let archiveBytes: Int64
    let installedBytes: Int64
    let license: String
    let licenseURL: URL
    let inputName: String
    let outputName: String
    let inputWidth: Int
    let inputHeight: Int
    let preprocess: EditorAIPreprocess
    let outputSemantics: EditorAIAlphaSemantics
    let estimatedPeakMB: Int
    let minimumAvailableMB: Int
    let requiresWiFi: Bool
    let minRAMGB: Int
    let webModelID: String?

    var packageDirectoryName: String { "\(id).mlpackage" }
    var compiledDirectoryName: String { "\(id).mlmodelc" }

    var archiveMB: Int {
        Int((Double(archiveBytes) / 1_048_576).rounded(.up))
    }

    var installedMB: Int {
        Int((Double(installedBytes) / 1_048_576).rounded(.up))
    }
}

/// The models that have been converted, published and pinned. Every tier with
/// an archive can download it; Maximum additionally falls back to the Quality
/// model before Vision. Adding an entry here without a real archive would make
/// the download button fail and the tier label lie.
enum EditorAIModelCatalog {
    static let modnet = EditorAIModelDescriptor(
        id: "modnet-fp16",
        version: "1.0.0+28165a4",
        displayName: "MODNet 512",
        tier: .balanced,
        kind: .segmentation,
        archiveURL: URL(
            string: "https://github.com/anhhoangsky/mng-cloud-sw/releases/download/ai-models-v1/modnet-fp16.mlpackage.zip"
        )!,
        archiveSHA256: "d256da371068e6b57d2b7f6a8cd24b828b85fbf80a2e7f5a8edd6832d8401adb",
        archiveBytes: 11_912_923,
        installedBytes: 13_108_826,
        license: "Apache-2.0",
        licenseURL: URL(string: "https://github.com/ZHKKKe/MODNet")!,
        inputName: "image",
        outputName: "alpha",
        inputWidth: 512,
        inputHeight: 512,
        preprocess: .modnet,
        outputSemantics: .alpha01,
        estimatedPeakMB: 250,
        minimumAvailableMB: 400,
        requiresWiFi: false,
        minRAMGB: 4,
        webModelID: "modnet-fp16"
    )

    static let birefnet = EditorAIModelDescriptor(
        id: "birefnet-lite-512-fp16",
        version: "1.0.0+aa62cd87",
        displayName: "BiRefNet Lite 512",
        tier: .quality,
        kind: .segmentation,
        archiveURL: URL(
            string: "https://github.com/anhhoangsky/mng-cloud-sw/releases/download/ai-models-v2/birefnet-lite-512-fp16.mlpackage.zip"
        )!,
        archiveSHA256: "34383a43ee5dc63f254229e98d0fb442434f63995530f159244779555a1103d0",
        archiveBytes: 82_130_533,
        installedBytes: 92_903_810,
        license: "MIT",
        licenseURL: URL(string: "https://github.com/ZhengPeng7/BiRefNet")!,
        inputName: "input_image",
        outputName: "output_image",
        inputWidth: 512,
        inputHeight: 512,
        preprocess: .imagenet,
        outputSemantics: .alpha01,
        estimatedPeakMB: 800,
        minimumAvailableMB: 1_200,
        requiresWiFi: true,
        minRAMGB: 4,
        webModelID: "birefnet-lite-512-fp16"
    )

    static let isnet = EditorAIModelDescriptor(
        id: "isnet-fp16",
        version: "1.0.0+b6764e20",
        displayName: "ISNet 1024",
        tier: .maximum,
        kind: .segmentation,
        archiveURL: URL(
            string: "https://github.com/anhhoangsky/mng-cloud-sw/releases/download/ai-models-v3/isnet-fp16.mlpackage.zip"
        )!,
        archiveSHA256: "7523bfe2d761a9742ac2115994611951261c2173624696d1cd00f7e21d1f0027",
        archiveBytes: 81_796_242,
        installedBytes: 88_257_802,
        license: "Apache-2.0",
        licenseURL: URL(string: "https://github.com/xuebinqin/DIS")!,
        inputName: "input",
        outputName: "output",
        inputWidth: 1024,
        inputHeight: 1024,
        preprocess: .isnet,
        outputSemantics: .alpha01,
        estimatedPeakMB: 900,
        minimumAvailableMB: 1_350,
        requiresWiFi: true,
        minRAMGB: 4,
        webModelID: "isnet-fp16"
    )

    static let bisenetHair = EditorAIModelDescriptor(
        id: "bisenet-hair",
        version: "1.0.0+4f0632b",
        displayName: "BiSeNet tóc 512",
        tier: .retouch,
        kind: .faceParsing,
        archiveURL: URL(
            string: "https://github.com/anhhoangsky/mng-cloud-sw/releases/download/ai-models-v1/bisenet-hair.mlpackage.zip"
        )!,
        archiveSHA256: "c72fec2b926e8913e027476734c4f6911d276201ff75b538116baefb3fe1b0f1",
        archiveBytes: 24_368_691,
        installedBytes: 26_350_885,
        license: "MIT",
        licenseURL: URL(string: "https://github.com/yakhyo/face-parsing")!,
        inputName: "image",
        outputName: "alpha",
        inputWidth: 512,
        inputHeight: 512,
        preprocess: .imagenet,
        outputSemantics: .hairAlpha,
        estimatedPeakMB: 450,
        minimumAvailableMB: 700,
        requiresWiFi: false,
        minRAMGB: 4,
        webModelID: "face-parsing-bisenet"
    )

    static let all: [EditorAIModelDescriptor] = [
        modnet,
        birefnet,
        isnet,
        bisenetHair,
    ]

    static func descriptor(id: String) -> EditorAIModelDescriptor? {
        all.first { $0.id == id }
    }

    /// The background models a tier may try, best first. Maximum falls back
    /// to the Quality model when its own model is absent or denied by the
    /// memory/thermal guard; every list still ends at Vision in the selector.
    static func segmentationModels(
        for tier: EditorAIModelTier
    ) -> [EditorAIModelDescriptor] {
        let primary = all.filter {
            $0.tier == tier && $0.kind == .segmentation
        }
        guard tier == .maximum else { return primary }
        let fallback = all.filter {
            $0.tier == .quality && $0.kind == .segmentation
        }
        return primary + fallback
    }

    /// The model a tier offers to download. A tier may have more than one
    /// installed fallback, but only the best one is proposed.
    static func segmentationModel(
        for tier: EditorAIModelTier
    ) -> EditorAIModelDescriptor? {
        segmentationModels(for: tier).first
    }
}
