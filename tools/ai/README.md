# AI model conversion (Core ML)

The native app downloads Core ML models; it never bundles ONNX weights. This
directory is the reproducible conversion pipeline that turns the pinned web
ONNX artifacts into iOS 17 `mlprogram` packages.

## Files

- `models.json` — the pinned source URLs, SHA-256 values, input geometry,
  preprocessing, output semantics, license and tier for each model. Only
  models with `enabled: true` are converted by default.
- `convert_coreml.py` — downloads and verifies the ONNX source, converts it,
  compares the Core ML output against ONNX Runtime on the same deterministic
  tensor, and writes a `.mlpackage.zip` plus metadata.
- `.github/workflows/ai-models.yml` — runs the conversion on a macOS runner
  and uploads the artifacts.

## Run

On macOS:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install coremltools onnx onnxruntime numpy
python tools/ai/convert_coreml.py --check-manifest
python tools/ai/convert_coreml.py --model all
```

The first run downloads the pinned ONNX files into `tools/ai/.cache` and
verifies their SHA-256. Artifacts land in `tools/ai/artifacts/<id>/`:

```
<id>.mlpackage.zip   # model.mlpackage + metadata.json + LICENSE.txt
metadata.json        # archive SHA-256, sizes, versions, validation metrics
```

Do not commit `.cache/` or `artifacts/`; the GitHub workflow uploads the zip
as a build artifact. Publish the exact zip on the model CDN and pin its
`archiveSha256` in the app catalog.

## Rules

- Never edit a model's `sourceSha256` to make a download pass. That means the
  upstream bytes changed; investigate before pinning.
- A conversion fails if the Core ML output drifts from ONNX: max abs diff
  0.02 / mean 0.005 for alpha and sigmoid outputs, plus 0.999 argmax agreement
  for the 19-class face parser.
- Keep `enabled: false` for models that are blocked (ISNet license) or not yet
  proven (BiRefNet deform-conv, BEN2 transformer). Flip the flag only when the
  conversion and the device benchmark both pass.
- The app catalog and this manifest must agree on id, version, input geometry,
  preprocessing, output semantics and license.
