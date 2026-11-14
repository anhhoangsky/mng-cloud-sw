# AI model conversion (Core ML)

The native app downloads Core ML models; it never bundles ONNX or PyTorch
weights. This directory is the reproducible conversion pipeline that turns the
pinned model sources into iOS 17 `mlprogram` packages.

## Why PyTorch, not ONNX

`coremltools 9` removed the ONNX importer. Both shipping models have official
PyTorch checkpoints, so the pipeline:

1. downloads the pinned PyTorch checkpoint and the pinned fp32 ONNX reference;
2. rebuilds the exact web architecture from the vendored upstream code, loads
   the checkpoint and compares its output to ONNX Runtime;
3. traces the PyTorch graph and converts it to Core ML with Float16 weights;
4. compares the Core ML output to the ONNX reference with fp16-aware gates;
5. writes the `.mlpackage.zip`, metadata and license notice.

The PyTorch-vs-ONNX gate is strict (max 2e-3, mean 5e-5). The Core ML gate
allows fp16 drift but catches structural errors (mean alpha 0.008, p99 0.05,
8-bit mean 1.5 levels, IoU 0.98).

## Files

- `models.json` — pinned checkpoint URLs, SHA-256 values, the fp32 ONNX
  reference for each model, input geometry, preprocessing, output semantics,
  license and tier. Only models with `enabled: true` are converted by default.
- `convert_coreml.py` — the pipeline described above.
- `vendor/modnet` — the official MODNet code at commit `28165a4`
  (Apache-2.0), used to rebuild the checkpoint.
- `vendor/face_parsing` — the BiSeNet face parsing code at commit `4f0632b`
  (MIT), with the torchvision download removed and relative imports.
- `test-assets/portrait.jpg` — the MediaPipe sample portrait used as a
  non-empty validation input.
- `.github/workflows/ai-models.yml` — macOS conversion job.

## Run

Prove the PyTorch rebuild matches ONNX (works on Windows/Linux, no
coremltools):

```bash
pip install torch onnxruntime numpy pillow
python tools/ai/convert_coreml.py --validate-only --model all
```

Convert on macOS:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install "torch==2.7.0" "coremltools==9.0" onnxruntime numpy pillow
python tools/ai/convert_coreml.py --check-manifest
python tools/ai/convert_coreml.py --validate-only --model all
python tools/ai/convert_coreml.py --model all
```

Sources are cached in `tools/ai/.cache` and verified against the manifest on
every run. Artifacts land in `tools/ai/artifacts/<id>/`:

```
<id>.mlpackage.zip   # model.mlpackage + metadata.json + LICENSE.txt
metadata.json        # archive SHA-256, sizes, versions, validation metrics
```

Do not commit `.cache/` or `artifacts/`; the GitHub workflow uploads the zip as
a build artifact. Publish the exact zip on the model CDN and pin its
`archiveSha256` in the app catalog.

## Rules

- Never edit a model's `sourceSha256` to make a download pass. That means the
  upstream bytes changed; investigate before pinning.
- Never relax the PyTorch-vs-ONNX gate. If it fails, the checkpoint or the
  architecture does not match the web model.
- Do not edit the vendored code beyond the changes listed in each `NOTICE.md`.
- Keep `enabled: false` for models that are blocked (ISNet license) or do not
  have a PyTorch checkpoint yet (BiRefNet, BEN2). Flip the flag only when the
  conversion and the device benchmark both pass.
- The app catalog and this manifest must agree on id, version, input geometry,
  preprocessing, output semantics, output name and license.
