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
    /// ImageNet mean/std, used by BiRefNet, BEN2 and BiSeNet.
    case imagenet
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

/// The models that have been converted, published and pinned. Quality and
/// Maximum stay on Vision until BiRefNet and BEN2 have their own successful
/// conversion runs; adding an entry here without a real archive would make
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
        bisenetHair,
    ]

    static func descriptor(id: String) -> EditorAIModelDescriptor? {
        all.first { $0.id == id }
    }

    /// The background model a tier wants, if it has one. `.quality` and
    /// `.maximum` return nil until their archives are published.
    static func segmentationModel(
        for tier: EditorAIModelTier
    ) -> EditorAIModelDescriptor? {
        all.first {
            $0.tier == tier && $0.kind == .segmentation
        }
    }
}
