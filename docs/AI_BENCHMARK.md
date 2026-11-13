# Native AI benchmark protocol

Status: **plan.** No device numbers exist yet. This document defines how the
iPhone 12 Pro Max run is executed, what is measured, and what pass/fail means.
The architecture and model decisions are in
[`AI_NATIVE_ENGINE.md`](AI_NATIVE_ENGINE.md).

## 1. Goal

Answer four questions with measurements, not assumptions:

1. Does each tier actually improve mask quality over the current Vision-only
   output, especially hair, fur and thin/semi-transparent edges?
2. What are the warm latency, cold load, peak memory, thermal and battery costs
   on the reference device?
3. Does Maximum reach the web's ISNet-quality target closely enough to call it
   parity, and where does it still differ?
4. Do the download, cache, versioning, fallback and low-memory paths behave
   correctly on a real device, including airplane mode after install?

## 2. Device and build

- iPhone 12 Pro Max, 6 GB RAM, iOS 17.x or 18.x; record the exact version.
- Release build from `MNGCloud.xcodeproj` (`xcodegen generate` first), signed
  with a development team. The CI artifact is unsigned and simulator-only.
- Benchmark harness is compiled only in `DEBUG`, but the release build must be
  used for latency/memory/thermal numbers so optimization and assertion
  differences do not skew them. Use a `BENCHMARK` compilation condition if the
  harness must exist in release without shipping to users.
- Before each run: battery ≥ 80 %, Low Power Mode off, brightness 50 %, auto-lock
  disabled, other apps closed, 5 minutes idle after charging.
- Install the models over Wi-Fi first; run the performance matrix in airplane
  mode so no network stack wakes the radios.
- Cold run: terminate the app (swipe up), relaunch, run one image, record.
  Warm runs: same app session, same model loaded, 5 runs, report p50/p95.
- Avoid charging during thermal/battery runs; charging adds heat.

## 3. Test set

Store the set under `test-assets/ai-benchmark/` with a `SOURCES.md` that records
the origin and license of every file. Do not commit user photos. The current
bundled images are enough for a first pass; add the missing categories before
the final report.

| Category | Files | Ground truth | Purpose |
|---|---|---|---|
| General saliency | DIS-TE1 30 samples | official alpha | IoU/Dice/Boundary F/MAE; compare with the web benchmark |
| Portrait hair | `test-assets/portrait.jpg`, `demo/photo-64.jpg` | none; visual + halo | flyaway hair, backlight |
| Long hair / ponytail | one licensed portrait, to add | none; visual | the web BiSeNet crop and the native ellipse differ most here |
| Fur | `demo/photo-pug.jpg` | none; visual | fur fringe, blanket tassels |
| Semi-transparency | one veil/glass/smoke photo, to add | manual alpha where possible | soft alpha, not just a hard contour |
| No subject | `demo/photo-river.jpg`, `demo/sample-landscape.jpg` | empty | must return `noSubject`, not scenery |
| Illustration | `demo/sample-portrait.jpg` (actually a vector landscape) | empty | semantic out-of-domain test |
| Low light | one licensed portrait, to add | none; visual | noise and edge stability |

The DIS-TE1 files already have alpha ground truth and are the only set that
supports objective segmentation metrics. Hair/fur/veil shots are judged with a
blind A/B plus the halo/strand proxies below; do not present a proxy as a
ground-truth score.

## 4. Metrics

### 4.1 Quality

For DIS-TE1 (alpha ground truth):

- **IoU** and **Dice** at threshold 0.5.
- **Boundary F** with a 2 px tolerance.
- **Alpha MAE** over all pixels.
- **Boundary displacement**: mean Chamfer distance between predicted and
  ground-truth 0.5 contours, in source pixels.

For hair/fur/veil (no pixel ground truth):

- **Halo**: mean alpha in a 6 px ring just outside the 0.5 contour. Lower is
  better; a clean matte is near zero. This is the metric that exposed
  InSPyReNet's glow.
- **Strand retention**: two raters, blind, 1–5 per crop
  (1 = fused/blocky, 5 = individual flyaways preserved). Report the mean and
  the disagreement; do not hide a split.
- **Soft-band share**: fraction of pixels with 0.02 < alpha < 0.98. Context
  only; a large band can be correct hair or a blurry halo.
- **Edge gradient**: mean alpha gradient inside the transition band. Context
  only; a hard cut also scores high.

For no-subject images:

- `noSubject` result or coverage < 1 % is a pass. Any scenery cut-out is a
  fail, even if it looks plausible.

### 4.2 Performance

- **Cold load**: app launch → model compiled/loaded and first prediction
  started. Record separately from inference.
- **Preprocess / inference / postprocess / total**: `os_signpost` intervals.
  Report p50 and p95 over 5 warm runs.
- **Download time**: Wi-Fi and cellular, including SHA-256 verification and
  unpack. Record network type and file size.
- **Peak memory**: `os_proc_available_memory()` before and after, plus
  Instruments VM Tracker/Allocations. Report the delta, not just the absolute.
- **Model footprint**: archive bytes, uncompressed bytes, compiled
  `.mlmodelc` bytes.
- **Thermal**: `ProcessInfo.thermalState` before/after each run; run 10
  consecutive Maximum passes and record when it reaches `.fair`, `.serious`,
  `.critical`.
- **Battery**: `UIDevice.batteryLevel` before/after 30 consecutive passes;
  Instruments Energy Log for the same run. Report %/30 runs and the energy
  impact. Battery is a report, not a hard gate until a baseline exists.
- **Stability**: 20 consecutive runs per tier; no crash, no jetsam, no
  unbounded memory growth.

### 4.3 Parity

- **Maximum vs web ISNet**: run the same DIS-TE1 samples through web ISNet and
  native Maximum; compare IoU (target within 0.05), Boundary F (within 0.10),
  and MAE (within 0.01). If ISNet is licensed and becomes the Maximum engine,
  tighten to IoU within 0.01 and Boundary F within 0.03.
- **Quality vs web BiRefNet**: the native Quality engine should be the same
  model family and preprocessing; target IoU within 0.01 after conversion.
- **Hair A/B**: web ISNet vs native Maximum on the five hair/fur crops; two
  blind raters; no worse than −0.5 on the 5-point strand scale.
- **No-subject**: native must not produce a cut-out where web ISNet returns
  empty.

## 5. Harness

Add `App/Features/Editor/AI/EditorAIBenchmark.swift`, compiled under `DEBUG`
(or a `BENCHMARK` flag). A hidden entry in Settings → AI models opens it; a
long-press on the AI tab title is an alternative. It must not appear in
production builds.

The harness:

1. Loads a folder of images from the app bundle or a `UIDocumentPicker`
   directory (Files app). Test images stay on the device.
2. Runs the matrix `tier × engine × image`, skipping engines that are not
   installed or do not fit the device.
3. Writes to `Documents/AIBenchmark/<run-id>/`:
   - `masks/<image>__<engine>.png` — 8-bit grayscale alpha, top-down.
   - `composites/<image>__<engine>.jpg` — checkerboard composite for visual
     review.
   - `results.csv` — one row per run.
   - `device.json` — device model, RAM, iOS version, app build, thermal/battery
     start state, model hashes.
   - `log.txt` — progress, errors, fallback reasons.
4. Exports the folder with `UIActivityViewController` or the Files app. No
   network upload and no analytics.
5. Uses `os_signpost` subsystem `com.mngcloud.ai`, categories `load`,
   `preprocess`, `inference`, `postprocess`; the Instruments trace is saved
   alongside the run.

CSV columns:

```
run_id,timestamp,device,os,build,image,image_w,image_h,tier,engine,
engine_version,model_sha,input_w,input_h,cold,run_index,
preprocess_ms,inference_ms,postprocess_ms,total_ms,
available_before_mb,available_after_mb,peak_delta_mb,
thermal_before,thermal_after,battery_before,battery_after,
coverage,halo,soft_share,edge_gradient,
iou,dice,boundary_f,mae,boundary_chamfer_px,
no_subject,used_fallback,fallback_reason,notes
```

Quality metrics are computed offline from the exported masks, not in the app,
so the scoring code can be reviewed and rerun. The app only writes masks,
timings and device state.

## 6. Acceptance thresholds

Initial targets; replace with measured baselines after the first device run.
Do not ship a tier that misses both its quality and its performance target.

| Tier | Warm total | Peak delta | Quality gate |
|---|---|---|---|
| Fast (Vision) | < 300 ms | < 300 MB | current native baseline; no regression |
| Balanced (MODNet) | < 700 ms | < 500 MB | hair/fur visual ≥ Vision; no-subject gate passes |
| Quality (BiRefNet) | < 2.5 s | < 1.2 GB | halo ≤ Vision; hair visual ≥ Vision; DIS MAE ≤ Vision |
| Maximum (BEN2) | < 5.0 s | < 2.2 GB | hair/strand ≥ BiRefNet; halo ≤ Vision; no-subject gate passes |

Additional gates:

- No jetsam or crash in 20 consecutive runs per tier.
- Thermal: 10 Maximum runs must not reach `.critical`; if they reach
  `.serious`, the app must downgrade the next run and show why.
- Battery: report the measured delta; set the budget after the first run (a
  reasonable starting point is < 2 % per 30 Quality passes).
- Download: SHA mismatch is rejected; cancel/resume works; low disk fails
  before writing; airplane mode after install runs every installed tier.
- Parity: Maximum vs web ISNet within the tolerances in §4.3, or the report
  states the measured gap and why.

## 7. Run order

1. **Smoke** (1 image per category): download, compile, run each tier, export.
2. **Quality matrix**: all test images × installed tiers; two raters for
   hair/fur/veil; DIS metrics offline.
3. **Performance matrix**: 1 cold + 5 warm per tier on the portrait, pug and
   river images; Instruments trace.
4. **Thermal/battery**: 10 consecutive Maximum, then 30 consecutive Quality;
   record thermal and battery; allow 10 minutes between blocks.
5. **Fallback matrix**: no model installed, model corrupt (truncate a file),
   low disk, Low Power Mode, thermal `.serious` (use a stress app or repeated
   runs), no-subject image, no-face retouch, airplane mode.
6. **Parity**: web ISNet/BiRefNet vs native Maximum/Quality on DIS-TE1 and the
   hair crops; export both mask sets for the offline comparison.

## 8. Reporting

- Append a dated section to `docs/AI_BENCHMARK_RESULTS.md` (create it with the
  first run) or store a JSON report under `docs/benchmarks/`. Include the
  device, OS, build hash, model hashes, test-set version and the raw CSV.
- Update `docs/PARITY.md` with the actual engine per tier and the measured gap.
- Update `docs/DEVICE_CHECKS.md` with any new manual checks that came out of
  the fallback matrix.
- Keep personal photos and their masks out of the repository; publish only
  synthetic or license-cleared assets.

## 9. Device checklist additions

Add these to `DEVICE_CHECKS.md` once the Core ML phase lands:

- [ ] The model picker shows Fast / Balanced / Quality / Maximum, and the
      detail line names the engine that will run.
- [ ] Choosing Quality or Maximum on a fresh install opens a download sheet
      with size, license and Wi-Fi policy; cancelling leaves the photo
      untouched.
- [ ] A download interrupted by backgrounding resumes or restarts cleanly; a
      corrupt archive is rejected and the previous version still runs.
- [ ] Airplane mode after install runs every installed tier.
- [ ] A no-subject landscape reports "Không tìm thấy chủ thể" instead of
      cutting out the scenery.
- [ ] Maximum on a long-hair portrait keeps the ponytail and flyaways; compare
      with the web ISNet output.
- [ ] Low Power Mode and a hot device downgrade the engine and say so; the
      photo still bakes.
- [ ] Hair retouch follows a ponytail and does not tint the face; the no-face
      fallback still reports the existing message.
- [ ] The brush, invert, transparent background, live blur and retouch sliders
      behave exactly as before on every tier.
- [ ] After a pass the image is upright and the mask matches the finger; no
      top/bottom flip on any tier.
- [ ] "Hoàn tác AI" restores the source after a model-backed pass.
