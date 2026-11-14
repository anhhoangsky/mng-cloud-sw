# Native AI engine — architecture and model plan

Status: **audit complete, design proposed, no native model code yet.** The
numbers below are from the web's ONNX models on a desktop CPU plus the bundled
sample images. iPhone numbers still require the protocol in
[`AI_BENCHMARK.md`](AI_BENCHMARK.md); Vision subject lifting does not run in
the Simulator.

## 1. Summary

The native AI tab runs Apple Vision for every model tier. The web runs
different models per tier, and its Quality tier is ISNet 1024, not Vision and
not BiRefNet. That is the structural reason the phone's cut-outs look less
detailed than the web's.

The fix is not "replace Vision". Vision stays the zero-download fast engine.
A Core ML runtime is added beside it, with the same on-demand model lifecycle
as the web: pinned download, SHA-256, on-device compile/cache, explicit
fallback, and no model bytes in the IPA.

Audit conclusions:

1. **ISNet remains the best all-round model** on real photos and is the exact
   web Quality target, but its weights are **not license-clean** (the HF card
   says AGPL-3.0; the DIS repo's Apache-2.0 covers code and the evaluation
   metric, not the distributed weights). Do not ship it without written
   permission.
2. **BiRefNet Lite (MIT)** has the cleanest halo and contour of the
   license-clean models. Hair is slightly softer than ISNet, but it is a safe
   default for the Quality tier and is already the web's Balanced model.
3. **BEN2 (MIT)** is the closest license-clean hair quality to ISNet. It is
   also 219 MB, 14–19 s per image on desktop CPU, and it cuts scenery on
   no-subject photos. It belongs only in Maximum, behind a Vision no-subject
   gate.
4. **InSPyReNet Swin-B (Apache-2.0)** is rejected: worst halo by 2–6×, softest
   edge, selects scenery on landscapes, 15–18 s on desktop CPU, and its
   `GatherND`/`ScatterND` graph is conversion-hostile.
5. **MODNet (Apache-2.0)** is small and fast but portrait-only, with a visible
   halo and lost strands. Use it only for the Balanced person path.
6. The **hair retouch gap is separate** from background removal. The web uses
   BiSeNet hair class 17 on a 1.9× face-width crop; the native code uses a face
   ellipse. BiSeNet is MIT and conversion-friendly, so it is the first model to
   port.

Decision: four native tiers.

| Tier | Primary engine | Fallback | Download |
|---|---|---|---|
| Fast | Vision person/subject | — | 0 |
| Balanced | MODNet 512 for people, Vision subject otherwise | Vision | 13 MB optional |
| Quality | BiRefNet Lite 512 | Vision subject, then person | 98 MB on demand |
| Maximum | BEN2 1024 (ISNet 1024 only after license clearance) | BiRefNet, then Vision | 219 MB on demand |

BiSeNet hair parsing upgrades retouch in every tier. ISNet stays an optional,
hidden "Web parity" model until the license question is resolved.

## 2. What the web actually runs

The web has two independent AI subsystems. The native refactor has to cover
both; the background model table alone is not enough.

### 2.1 Background removal / matting (`src/ai-engine`)

| Web UI | Model id | Input | Download | License | Native plan |
|---|---|---|---|---|---|
| Quality (default) | `isnet-fp16` | 1024×1024 | 88,116,798 B | AGPL-3.0 per HF card; DIS code Apache-2.0, weights unclear | **Blocked.** Optional Web-parity model after clearance |
| Balanced | `birefnet-lite-512-fp16` | 512×512 | 98,484,532 B | MIT | Quality tier |
| Fast | `modnet-fp16` | shortest edge 512, H/W multiple of 32 | 12,984,781 B | Apache-2.0 (verify artifact) | Balanced person path |
| Person mode | forces `modnet-fp16` | as above | 12,984,781 B | Apache-2.0 | Balanced person path |

Pinned metadata lives in `aurum-repo/src/ai-engine/registry.ts`. The web
default is ISNet; the phone's current model picker never downloads a model and
maps every tier to Vision.

### 2.2 Retouch (`src/ai-retouch`)

| Task | Web model | Input | Download | License | Native plan |
|---|---|---|---|---|---|
| Face detection | BlazeFace | 128×128 | 535,842 B | **unknown** on the pinned mirror | Replaced by Vision face detection |
| Hair mask | BiSeNet face parsing | 512×512 face crop | 53,205,364 B | MIT | Port to Core ML, all tiers |
| Skin / whiten / smooth / tone | BlazeFace + CPU YCbCr/ellipse heuristics | — | — | — | Keep native heuristic; web is heuristic too |

The native hair mask is a face-box ellipse with feature punch-outs
(`EditorAIService.faceMasks`). The web's BiSeNet mask follows the real hair,
including ponytails and flyaways. This is the largest retouch parity gap.

## 3. Measured audit

All local results use the same five bundled images and the pinned model bytes.
The scripts live in `D:\rk3229\ai-audit\` (`compare_web_models.py`,
`compare_ben2.py`, `compare_inspyrenet.py`, `metrics_all.py`, `zoom_all.py`).
They are audit tools, not committed app code.

### 3.1 DIS-TE1, 30 samples (desktop CPU, from the web benchmark docs)

| Model | IoU | Dice | Boundary F (2px) | Alpha MAE | Median |
|---|---|---|---|---|---|
| ISNet fp16 1024 | 0.9221 | 0.9575 | 0.8301 | 0.0079 | 2314 ms |
| BiRefNet Lite 512 | 0.7725 | 0.8388 | 0.5646 | 0.0135 | 2903 ms |
| MODNet fp16 | 0.1405 | 0.1958 | 0.1264 | 0.1116 | 450 ms |

MODNet is out-of-domain on DIS (portrait matting model, general saliency
ground truth), so its low score does not mean it is useless for people. It
does mean it must not be the general Quality model.

### 3.2 Same-image audit

`halo` = mean alpha in a 6 px ring just outside the 0.5 contour. Lower is
better; a clean matte leaves the ring near zero. `soft` = fraction of pixels in
the 0.02–0.98 transition band, shown for context. `edge` = mean alpha gradient
inside that band; it is not a standalone quality score because a hard cut also
raises it.

| Image | Model | Coverage | Soft | Halo | Edge |
|---|---|---|---|---|---|
| portrait | ISNet 1024 | 0.508 | 0.0097 | **0.043** | 0.247 |
| portrait | BiRefNet Lite 512 | 0.508 | 0.0129 | **0.028** | 0.357 |
| portrait | BEN2 1024 | 0.504 | 0.0109 | 0.041 | 0.227 |
| portrait | MODNet | 0.509 | 0.0241 | 0.056 | 0.192 |
| portrait | InSPyReNet 1024 | 0.523 | 0.0616 | **0.250** | 0.045 |
| photo-64 | ISNet 1024 | 0.264 | 0.0364 | 0.126 | 0.085 |
| photo-64 | BiRefNet Lite 512 | 0.277 | 0.0146 | **0.046** | 0.241 |
| photo-64 | BEN2 1024 | 0.277 | 0.0160 | 0.064 | 0.128 |
| photo-64 | MODNet | 0.279 | 0.0474 | 0.134 | 0.076 |
| photo-64 | InSPyReNet 1024 | 0.292 | 0.0567 | **0.234** | 0.036 |
| photo-pug | ISNet 1024 | 0.276 | 0.0402 | 0.123 | 0.081 |
| photo-pug | BiRefNet Lite 512 | 0.278 | 0.0135 | **0.038** | 0.329 |
| photo-pug | BEN2 1024 | 0.274 | 0.0281 | 0.100 | 0.141 |
| photo-pug | MODNet | 0.292 | 0.0447 | 0.124 | 0.102 |
| photo-pug | InSPyReNet 1024 | 0.307 | 0.0815 | **0.314** | 0.035 |

Visual zoom (full-size crops in `ai-audit/out/hair-zoom-all-*.jpg`):

- **ISNet** keeps the finest flyaway hair and gives the cleanest overall
  portrait cut. Its halo is visible on the backlit woman but is local.
- **BiRefNet Lite** has the cleanest contour and lowest halo, but is slightly
  softer on the wispy strands and keeps a little background near the ear on the
  suit portrait.
- **BEN2** is close to ISNet on hair and fur, with a low halo. Its no-subject
  behaviour is the problem, not its edge quality.
- **MODNet** leaves a clear halo and loses strands; it is a speed model.
- **InSPyReNet** leaves a broad glow around the head and shoulders and is the
  softest model in the set. It is not a Quality upgrade.

### 3.3 No-subject behaviour

`sample-portrait.jpg` is actually a flat vector landscape, which makes it a
useful semantic test. `photo-river.jpg` is a landscape photo.

| Image | ISNet | BiRefNet | BEN2 | MODNet | InSPyReNet |
|---|---|---|---|---|---|
| photo-river coverage | **0.000** | **0.000** | 0.675 | 0.143 | 0.054 |
| sample-portrait coverage | 0.035 (clouds) | **0.000** | 0.200 | 0.172 | 0.381 |

ISNet and BiRefNet correctly return an empty mask; BEN2 and InSPyReNet cut
scenery, and MODNet false-positives. The native engine therefore needs a
Vision no-subject gate before any general model, not just a coverage
threshold.

### 3.4 License matrix

| Model | Upstream license | Artifact license | Ship? |
|---|---|---|---|
| ISNet general use | DIS code Apache-2.0; weights no explicit license | HF card AGPL-3.0 | **No, until written permission** |
| BiRefNet Lite 512 | MIT | MIT (studioludens mirror) | Yes |
| MODNet | Apache-2.0 | Apache-2.0 (Xenova mirror; verify file) | Yes |
| BEN2 | MIT | MIT (PramaLLC / onnx-community) | Yes |
| InSPyReNet | MIT | Apache-2.0 (PinkPixel mirror) | Rejected on quality |
| BiSeNet face parsing | MIT | MIT (jbrownkramer mirror) | Yes |
| BlazeFace mirror | MediaPipe Apache-2.0 | **unknown** on pinned mirror | Do not ship; use Vision |

## 4. Decision

### 4.1 Tier table

| Tier | Label | Engine order | Why |
|---|---|---|---|
| Fast | Nhanh | Vision person (fast) → Vision subject | Instant, zero download, person path is the common case |
| Balanced | Cân bằng | MODNet 512 (person) → Vision subject | 13 MB, fast neural matting; no model needed for non-people |
| Quality | Chất lượng | BiRefNet Lite 512 → Vision subject → Vision person | Best license-clean halo/contour; general subjects |
| Maximum | Tối đa | ISNet 1024 (licensed only) → BEN2 1024 → BiRefNet → Vision | Best hair the device can run; explicit memory/thermal gate |

Quality is not expected to be pixel-identical to web Quality, because web
Quality is ISNet. Quality targets the best license-clean general cut-out.
Maximum is the native/web parity tier: if ISNet is licensed it becomes the
first entry and gives exact web-quality output; until then BEN2 is the closest
license-clean model and the benchmark records the gap.

The picker gains a fourth case, `maximum`, with a detail string naming the
actual engine (for example `BEN2 1024 · Tối đa`). The existing
`quality / balanced / fast` raw values stay unchanged for state restoration.
Picker order stays best-to-fastest: Tối đa, Chất lượng, Cân bằng, Nhanh; the
default stays `.quality`. When the selected model is not installed,
Quality/Maximum show a download sheet with size, license and Wi-Fi
requirement; they do not silently run Vision without telling the user. If the
user declines or is offline, the pass runs on Vision and the result metadata
records the fallback.

### 4.2 Engine resolution

```
resolve(mode, content, device):
  fast      -> [vision]
  balanced  -> content.hasPerson ? [modnet, vision] : [vision]
  quality   -> [birefnet, vision]
  maximum   -> [isnetIfLicensed, ben2, birefnet, vision]
                .filter(installed && fitsMemory && thermalAllows)
```

`content.hasPerson` comes from `VNDetectHumanRectanglesRequest` (fast) plus
the existing face detector when it already ran. For Quality/Maximum on a
non-person image, run the Vision foreground request first as a **no-subject
gate**:

- no instances → throw `noSubject` before loading a 98–219 MB model;
- instances → run the specialist model, with the Vision mask kept as the
  fallback if the model fails.

This gate costs one Vision pass on landscapes and product shots, but it stops
BEN2/InSPyReNet-style scenery cut-outs and avoids the download/inference cost
on photos with nothing to lift. On person photos the gate is skipped.

### 4.3 Why not the other models

- **InSPyReNet**: rejected on measured halo, softness, scenery selection, CPU
  time and conversion risk. Apache-2.0 is not a reason to ship a worse matte.
- **ISNet as default**: license blocked. Keep the exact web bytes and hash in
  the catalog behind a `licenseCleared` flag so enabling it later is a
  one-line change, not a rewrite.
- **Full BiRefNet / BiRefNet HR / BEN2 4K**: too large for the download and
  memory budget on an A14 device. Revisit only after the benchmark shows
  headroom.
- **SAM / MobileSAM**: promptable segmentation is a different interaction; not
  a replacement for one-tap background removal.
- **Real-ESRGAN / NAFNet**: out of scope for this round; the web retouch
  registry lists them as separate tasks.

## 5. Architecture

### 5.1 Module layout

New files under `App/Features/Editor/AI/`:

| File | Responsibility |
|---|---|
| `EditorAIEngine.swift` | `EditorAISegmentationEngine` protocol, request/result, engine id, timings |
| `EditorAIEngineSelector.swift` | Tier → ordered engine list, content gates, capability checks |
| `EditorVisionEngine.swift` | Existing Vision foreground/person code extracted unchanged |
| `EditorCoreMLEngine.swift` | Model load, preprocessing, prediction, alpha extraction, unload |
| `EditorAIModelCatalog.swift` | Embedded pinned descriptors; no remote manifest |
| `EditorAIModelStore.swift` | Download, SHA-256 verify, staging, compile, cache, LRU evict |
| `EditorAIMemoryGuard.swift` | `os_proc_available_memory`, thermal/power checks, model budgets |
| `EditorAIMaskOps.swift` | Resize, feather, top-down mask conversion, asymmetric test helpers |
| `EditorFaceParsingEngine.swift` | BiSeNet hair crop, logits, hair probability, crop mapping |
| `EditorAIBenchmark.swift` | DEBUG-only matrix runner and CSV/mask export |

`EditorAIService` stays the public facade. `EditorModel`, the brush toolbar and
the bake path keep calling `backgroundMask` / `retouchMask`; only the internals
change. This keeps the existing brush, live preview, undo and JPEG-alpha
behaviour intact.

### 5.2 Protocol

```swift
struct EditorAISegmentationRequest: Sendable {
    let source: EditorSourceSnapshot
    let mode: EditorAIBackgroundMode
    let content: EditorAIContentHints
    let report: @Sendable (String) async -> Void
}

struct EditorAISegmentationResult: Sendable {
    let mask: EditorAIMask
    let engineID: String
    let modelVersion: String?
    let inferenceMS: Double
    let usedFallback: Bool
}

protocol EditorAISegmentationEngine: Sendable {
    var id: String { get }
    var requiresDownload: Bool { get }
    func isAvailable() async -> Bool
    func prepare() async throws
    func segment(_ request: EditorAISegmentationRequest) async throws
        -> EditorAISegmentationResult
    func unload() async
}
```

The result records the engine and version so the UI, the benchmark CSV and
support reports can state what actually ran. The current code already reports
progress strings; the protocol keeps that callback.

### 5.3 Preprocessing and output contract

All models use an `MLMultiArray` input in NCHW float32. Core ML image inputs
with scale/bias cannot express ImageNet per-channel mean/std without an extra
layer, so preprocessing stays explicit and reviewable.

| Engine | Input | Normalisation | Output |
|---|---|---|---|
| Vision | source CIImage | none | soft mask; `noSubject` if no instances |
| MODNet | shortest edge 512, H/W multiple of 32 | RGB/255, mean=std=0.5 | alpha `[0,1]` direct |
| BiRefNet Lite | 512×512 | RGB/255, ImageNet mean/std | logits → sigmoid |
| BEN2 | 1024×1024 | RGB/255, ImageNet mean/std | alpha `[0,1]` direct |
| ISNet | 1024×1024 | `(x-128)/256` | alpha `[0,1]` direct; no sigmoid |
| BiSeNet | 512×512 face crop | RGB/255, ImageNet mean/std | 19 logits; class 17 hair |

The ISNet output range was verified locally: min 0.0, max ~1.0, mean 0.265.
Applying a sigmoid would collapse it to 0.5–0.73 and destroy the matte; this
is a required regression test.

Mask post-processing mirrors the web: bilinear resize to the source, optional
1 px feather when `preserveHair`, no threshold. The native brush still receives
a mask capped at 1024 px on the long side, which is the existing memory
contract. Do not tile global models; their receptive field and pyramid blending
produce seams. Tiling is reserved for a future LaMa/inpainting model.

### 5.4 Orientation and row order

`EditorSourceSnapshot` is top-down RGBA. Build the Core ML input from that
buffer directly (or from a CGImage created with a top-down provider), never
from a CIImage whose origin is bottom-left, unless the coordinate transform is
explicit. The output `MLMultiArray` is row-major top-down; copy it into
`EditorAIMask.bytes` without flipping.

Required unit test: a mask with a white rectangle in the **top-left** must
remain top-left through preprocessing, inference-output conversion,
`EditorAIMask`, and `maskImage`. The existing `EditorBitmap.topDownRGBA` fixed
the earlier flip; the Core ML path needs the same guard.

### 5.5 Concurrency and cancellation

- One inference at a time via an `actor EditorAIInferenceQueue`, matching the
  web's serial queue and the A14 memory budget.
- `MLModel.prediction` is synchronous and not cancellable mid-run. Run it off
  the main actor, check `Task.isCancelled` before and after, and discard the
  result if the user cancelled. Never leave a stale mask in the brush.
- Keep at most one `MLModel` loaded. Unload on memory warning, on leaving the
  AI tab, and before loading a different tier. Keep the compiled `.mlmodelc`
  on disk so reload is fast.
- Model load is the cold-start cost; measure it separately from inference.

## 6. Model store

### 6.1 Catalog

The catalog is embedded in the app (Swift structs), not fetched at runtime.
This makes the SHA-256 pins trustworthy even if the CDN is compromised and
avoids a remote-code path. Each descriptor carries:

```swift
struct EditorAIModelDescriptor: Codable, Sendable {
    let id: String                 // "ben2-fp16"
    let version: String            // "1.0.0+<upstream-rev>"
    let displayName: String
    let tier: EditorAIModelTier
    let kind: EditorAIModelKind    // segmentation | faceParsing
    let archiveURL: URL            // HTTPS, pinned
    let archiveSHA256: String
    let archiveBytes: Int64
    let installedBytes: Int64      // uncompressed budget
    let license: String
    let licenseURL: URL
    let inputWidth: Int
    let inputHeight: Int
    let outputSemantics: String    // "alpha01" | "logitsSigmoid" | "bisenet19"
    let estimatedPeakMB: Int
    let minimumAvailableMB: Int
    let requiresWiFi: Bool
    let minOS: String
    let minRAMGB: Int
    let webModelID: String?        // exact parity mapping when it exists
}
```

Initial entries:

| id | version | tier | archive | license | parity |
|---|---|---|---|---|---|
| `modnet-fp16` | `1.0.0+28165a4` | balanced | TBD (checkpoint 26,255,603 B) | Apache-2.0 | web Fast |
| `birefnet-lite-512-fp16` | `1.0.0+962e679` | quality | 98,484,532 B | MIT | web Balanced |
| `ben2-fp16` | `1.0.0` | maximum | 219,121,675 B | MIT | closest to web Quality |
| `bisenet-hair` | `1.0.0+4f0632b` | retouch | TBD (checkpoint 55,361,505 B) | MIT | web hair |
| `isnet-fp16` | `1.0.0` | maximum (gated) | 88,116,798 B | blocked | exact web Quality |

The sizes above are the upstream web artifacts until the conversion job runs.
`models.json` pins the exact source bytes and hashes; the Core ML archives will
have their own `archiveSha256` and `archiveBytes`, recorded in the conversion
metadata and then in the app catalog. The native handsets must never use the
web pins as archive hashes.

### 6.2 Download, verify, install

1. Check free disk: `archiveBytes * 2.5 + 200 MB`.
2. Download to
   `Application Support/AIModels/<id>/<version>.staging/` with a background
   `URLSession`, progress callbacks and resume data.
3. Stream the bytes through `CryptoKit.SHA256`; compare to the embedded hash
   before accepting anything. A mismatch deletes the staging directory and
   surfaces `checksumMismatch`.
4. Unpack the `.mlpackage` archive (zip + ZIPFoundation, or AppleArchive if we
   want no dependency; decide in the conversion spike) and validate the file
   list against the descriptor.
5. Move into `Application Support/AIModels/<id>/<version>/` with
   `FileManager.replaceItemAt` (atomic on the same volume), then write
   `installed.json` as the commit marker.
6. Set `isExcludedFromBackup = true` on the model directory; a 219 MB model
   must not be uploaded to iCloud.
7. Compile on first use with `MLModel.compileModel(at:)`, move the resulting
   `.mlmodelc` next to the package, and load it. If compile or load fails,
   mark the version corrupt, delete it, and offer a re-download.

Wi-Fi policy: models over 50 MB require Wi-Fi unless the user explicitly
confirms cellular. Downloading is always user-initiated, shows the size and
license, and is cancellable. No pixels leave the device.

### 6.3 Cache, versioning, eviction

- Directory per model id, subdirectory per version. A `current.json` pointer
  selects the installed version; a failed new install never deletes the
  working one.
- `lastUsedAt` is updated on load. Eviction is LRU by tier budget: keep the
  Fast/Balanced models (zero or small), evict old Quality/Maximum versions when
  total model storage exceeds 600 MB or free disk is low.
- Never evict the model currently loaded or the version selected by the user.
- A catalog version bump prompts an update in the AI pane; the old version is
  removed only after the new one verifies and loads.
- Recompile is automatic if the `.mlmodelc` is missing (for example after an
  OS update), with a progress state.

### 6.4 Security, privacy, App Review

- HTTPS only; ATS default. SHA-256 is verified on the exact archive bytes.
- The catalog is embedded, so there is no remote manifest to tamper with. If a
  remote catalog is added later, sign it with an Ed25519 key and keep the
  public key in the app.
- Model weights are data, but review guideline 2.5.2 still applies to
  executable code. Keep conversion in our CI, download only model artifacts,
  and do not download or evaluate scripts. Document this in the review notes.
- No analytics, no mask upload, no remote inference. The existing
  "AI chạy trên máy, ảnh không rời thiết bị" promise stays true.
- Show model name, upstream license and attribution in Settings → AI models,
  and store `LICENSE.txt` beside the weights.

## 7. Memory, thermal and battery

- **Memory gate.** Before loading a model, read `os_proc_available_memory()`.
  Require `available >= estimatedPeakMB * 1.5`; otherwise downgrade one tier
  and tell the user which engine ran. Initial budgets (to be replaced by device
  measurements): MODNet 250 MB, BiSeNet 450 MB, BiRefNet 800 MB, BEN2 2,000 MB,
  ISNet 900 MB.
- **Thermal gate.** `ProcessInfo.processInfo.thermalState`:
  - `.nominal` → allow the selected tier;
  - `.fair` → allow Quality, skip Maximum;
  - `.serious` → Balanced/Vision only;
  - `.critical` → Vision only.
  Observe `thermalStateDidChangeNotification` and show a non-blocking hint
  instead of failing silently.
- **Low Power Mode.** `ProcessInfo.isLowPowerModeEnabled` → Vision only unless
  the user explicitly keeps the selected tier.
- **Memory warning.** `UIApplication.didReceiveMemoryWarningNotification`
  unloads the `MLModel`; the next pass reloads from the compiled cache.
- **Battery.** No background inference. A single editor pass is short; the
  benchmark records battery delta and Instruments energy for 30 consecutive
  Quality/Maximum runs. Do not promise a battery number before measuring.
- **Device tiers.** iPhone 12 Pro Max (6 GB) is the reference. BEN2 requires
  `minRAMGB: 6`; on 4 GB devices Maximum resolves to BiRefNet. The UI states
  the resolved engine, so "Tối đa" never silently becomes Vision on a device
  that cannot run it.

## 8. Hair retouch parity (BiSeNet)

The web path in `src/ai-retouch/engine.ts`:

1. BlazeFace detects the face; crop side =
   `min(max(faceWidth * 1.9, faceHeight * 2.5), imageWidth, imageHeight)`.
2. Crop centre x = face centre x; crop y =
   `clamp(faceCentreY - faceHeight * 0.32 - side / 2, 0, imageHeight - side)`.
3. Resize the crop to 512×512, RGB/255, ImageNet mean/std, NCHW.
4. BiSeNet returns 19 class logits. Hair probability is
   `sigmoid(hairLogit - max(otherLogits))`, clamped to 0 below the decision
   boundary. Class 18 (hat) is deliberately ignored.
5. Resize the hair map back into the crop rectangle on the full source.

Native implementation uses **Vision face detection instead of BlazeFace**:
the mirror's BlazeFace license is unknown, and Vision is already running for
skin masks, so the two masks stay aligned. Use the same 1.9×/2.5×/0.32 crop
ratios and the same one-vs-best sigmoid. The model's input is a top-down crop,
so the mask maps straight back into `EditorAIMask` without a flip.

Fallback: if BiSeNet is not installed or Vision finds no face, keep the
current ellipse for hair and the face-box heuristic for skin. The retouch
sliders and bake path do not change. A future "hair quality" pass can expand
the crop to 2.2× for long hair, but only after the device benchmark shows it
does not pull in clothing; parity first.

Skin/whiten/smooth/tone stay heuristic. The web does not use a neural skin
segmenter for them, so there is no model-parity gap to close here.

## 9. Core ML conversion pipeline

Conversion runs on macOS in CI, never on the phone and never on Windows. The
Windows workstation can audit ONNX graphs and quality, but `coremltools`
requires macOS.

1. **Job:** GitHub Actions `macos-15`, Python 3.11, `coremltools` 9.0 and
   `torch` 2.7. coremltools 9 removed the ONNX importer, so the job rebuilds
   each model in PyTorch from its official checkpoint, proves it against the
   pinned fp32 ONNX reference, and converts the traced graph. The job uploads
   the archive as a build artifact; publishing it to the release CDN is a
   separate, manual step until the first benchmark passes.
2. **Format:** `mlprogram`, Float16 weights, fixed 512×512 input for the first
   version. The app letterboxes non-square images, runs the model and crops the
   alpha back. `EnumeratedShapes` can come after the device benchmark if the
   letterbox costs measurable quality.
3. **Validation:** two gates. The PyTorch graph must match ONNX almost
   exactly (max abs diff ≤ 2e-3, mean ≤ 5e-5; BiSeNet hair max 3e-7 on the
   golden portrait). The converted Core ML model is fp16, so it is checked for
   structure rather than bit equality: mean alpha drift ≤ 0.008, p99 ≤ 0.05,
   8-bit mean drift ≤ 1.5 levels and IoU ≥ 0.98 when the reference has at least
   0.5% foreground. Every run uses a synthetic geometric tensor plus the
   MediaPipe portrait fixture in `tools/ai/test-assets`.
4. **Pin:** record the archive SHA-256, uncompressed size, Core ML
   specification version, compute-unit results and conversion notes in the
   catalog. The app catalog is only updated after a successful CI run and a
   physical-device benchmark.
5. **Compute units:** try `.all` first; measure ANE vs GPU. ISNet is the most
   ANE-friendly graph in the set (425 simple ops), though `Resize`/`Cast` may
   force partitions, so measure rather than assume. BiRefNet's 17,490-node
   graph with `GatherND`/`ScatterND` is a GPU/CPU candidate; if conversion or
   load fails, Quality falls back to BEN2/Vision and the catalog marks it
   unavailable. BEN2's transformer ops (`MultiHeadAttention`,
   `LayerNormalization`, `Erf`) need `mlprogram`; validate memory before
   shipping. Core ML uses Metal for its GPU partitions; do not write custom
   Metal kernels in v1. Add a custom Metal path only if the benchmark shows a
   model stuck on CPU and missing its budget.
6. **Fallbacks:** ONNX Runtime Mobile with the Core ML execution provider is a
   contingency only for a model that Core ML cannot convert. It adds app size
   and a second runtime; do not ship it for models that convert cleanly.

Conversion feasibility from the graph audit:

| Model | Nodes | Op types | Risk | Notes |
|---|---|---|---|---|
| ISNet | 425 | 8 | Low | Conv/Relu/MaxPool/Resize/Concat/Cast; fixed 1024 |
| MODNet | 525 | 20 | Low–medium | Dynamic H/W; InstanceNorm; use fixed/enumerated shapes |
| BiSeNet | — | — | Low | Fixed 512; standard conv net |
| BiRefNet Lite | 17,490 | 38 | High | `GatherND`/`ScatterND`; deform-conv workaround; GPU likely |
| BEN2 | 2,651 | 28 | Medium–high | Transformer ops; 1024; memory |
| InSPyReNet | 2,267 | 31 | High | `GatherND`/`ScatterND`; rejected on quality anyway |

## 10. Phases and acceptance

| Phase | Work | Acceptance |
|---|---|---|
| 0 | This audit and design | Numbers reproducible from `ai-audit/`; decisions reviewed |
| 1 | Extract Vision behind the protocol; add `maximum` case and strings; no behavior change | Existing AI flows produce the same masks; all tests pass; CI green |
| 2 | Model store + catalog + download sheet + SHA/compile/cache; MODNet; BiSeNet hair | SHA mismatch rejected; offline fallback works; hair mask follows a ponytail on device; no-face fallback unchanged |
| 3 | Balanced person path + Vision gates | Person mode uses MODNet when installed; no-subject returns `noSubject`; warm time < 700 ms |
| 4 | Quality BiRefNet | Halo not worse than Vision; hair not worse than Vision; < 2.5 s and < 1.2 GB on iPhone 12 Pro Max; fallback works |
| 5 | Maximum BEN2 | Hair at least BiRefNet quality; < 5 s and < 2.2 GB; 20 consecutive runs without jetsam; thermal downgrade works |
| 6 | Device benchmark and parity report | `AI_BENCHMARK.md` protocol run; results appended; PARITY/DEVICE_CHECKS updated |
| 7 | Optional ISNet Web-parity model | Only after written license clearance; exact web bytes and hash; benchmark shows parity |

Phase 2 is the highest-value first ship: BiSeNet closes the visible hair-retouch
gap, and MODNet is small enough to validate the whole download/compile/cache
path without a 200 MB artifact. Do not start with BEN2.

## 11. Risks and open questions

1. **ISNet license.** The only exact web-parity path. Request written
   permission or a commercial license; do not ship the weights on the HF card's
   AGPL-3.0 terms without review.
2. **BiRefNet conversion.** The deform-conv workaround is community-proven but
   not trivial. If the conversion job cannot produce a stable model, Quality
   falls back to BEN2 (if converted) or Vision, and the tier description must
   say so.
3. **BEN2 on A14.** 219 MB and a 1024 transformer may exceed the 6 GB device's
   comfortable memory or the 5 s budget. The benchmark decides; the fallback
   chain is ready.
4. **Core ML packaging.** `.mlpackage` is a directory. Choose zip +
   ZIPFoundation or AppleArchive in the conversion spike; do not block the
   store design on it.
5. **App Review.** Downloaded model weights are data, but keep conversion in
   CI and document that no executable code is downloaded. Do not fetch scripts
   or manifests that can change behavior.
6. **Label semantics.** Native Quality = BiRefNet (web Balanced) and native
   Maximum = BEN2/ISNet (web Quality). Detail strings must name the engine so
   users do not compare labels across platforms. Consider aligning the web
   labels in a later round.
7. **BlazeFace license.** Avoid the unknown mirror; Vision face detection is
   the native face source. If Vision's box differs from BlazeFace enough to
   change the hair crop, tune the crop ratios against the web output on device.
8. **JPEG alpha.** Existing limitation: `POST /items/{id}/edit` cannot store a
   transparent cut-out for JPEG items. The export sheet already warns; not
   changed by this design.
9. **Simulator.** Vision subject lifting and ANE do not run in the Simulator.
   All quality and performance gates are device-only.

## 12. References

- Web background registry: `aurum-repo/src/ai-engine/registry.ts`
- Web background runtime: `aurum-repo/src/ai-engine/engine.ts`,
  `models.ts`, `memory.ts`, `mask.ts`
- Web retouch registry/runtime: `aurum-repo/src/ai-retouch/registry.ts`,
  `engine.ts`, `models.ts`
- Web UI labels: `aurum-repo/src/ui/ui.ts`
- Web DIS benchmarks: `aurum-repo/docs/ai-engine/benchmark/results/`
- Native service: `mng-cloud-sw/App/Features/Editor/EditorAIService.swift`
- Native state/UI: `EditorModel.swift`, `EditorView.swift`
- Native bitmap contract: `Packages/MNGEdit/Sources/MNGEdit/EditorBitmap.swift`
- Audit scripts and output: `D:\rk3229\ai-audit\`
- Device protocol: [`AI_BENCHMARK.md`](AI_BENCHMARK.md)
