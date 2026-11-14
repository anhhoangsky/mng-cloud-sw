"""Convert the pinned native AI models to Core ML for the iOS app.

Runs on macOS for the actual conversion (coremltools requirement). The GitHub
workflow `.github/workflows/ai-models.yml` calls this script on a macOS runner
and uploads the resulting `.mlpackage.zip` artifacts.

Why PyTorch sources?

coremltools 9 removed the ONNX importer. The two shipping models have official
PyTorch checkpoints, and the app must match the web ONNX models. The pipeline
therefore:

1. downloads the pinned PyTorch checkpoint and the pinned fp32 ONNX reference;
2. builds the vendored official architecture, loads the checkpoint and compares
   the PyTorch output against ONNX Runtime on deterministic inputs;
3. traces the PyTorch graph and converts it to an iOS 17 `mlprogram` with
   Float16 weights;
4. runs the Core ML model on the same inputs and checks the alpha against the
   ONNX reference, with fp16-aware gates;
5. writes a metadata JSON (versions, hashes, validation metrics) and a zip
   containing the `.mlpackage`, the metadata and the license notice.

Usage:
    python tools/ai/convert_coreml.py --check-manifest
    python tools/ai/convert_coreml.py --validate-only --model all
    python tools/ai/convert_coreml.py --model all

`--validate-only` needs torch, onnxruntime, numpy and Pillow, but not
coremltools, so it also runs on Windows/Linux. The ONNX cache is
`tools/ai/.cache`; artifacts go to `tools/ai/artifacts`. Neither directory is
committed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import shutil
import sys
import time
import urllib.request
import zipfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "models.json"
VENDOR = ROOT / "vendor"
TEST_PORTRAIT = ROOT / "test-assets" / "portrait.jpg"
DEFAULT_CACHE = ROOT / ".cache"
DEFAULT_OUT = ROOT / "artifacts"

if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

MEAN = (0.485, 0.456, 0.406)
STD = (0.229, 0.224, 0.225)


# --------------------------------------------------------------------------- io
def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_manifest(path: Path = MANIFEST) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if data.get("schema") != 2:
        raise SystemExit(f"unsupported manifest schema: {data.get('schema')!r}")
    models = data.get("models")
    if not isinstance(models, list) or not models:
        raise SystemExit("manifest has no models")

    ids: set[str] = set()
    for model in models:
        model_id = model.get("id", "<unknown>")
        for key in (
            "id",
            "enabled",
            "tier",
            "kind",
            "sourceFormat",
            "source",
            "sourceSha256",
            "sourceBytes",
            "inputName",
            "outputName",
            "inputShape",
            "preprocess",
            "outputSemantics",
            "outputClasses",
            "license",
        ):
            if key not in model:
                raise SystemExit(f"{model_id}: missing {key}")
        if model_id in ids:
            raise SystemExit(f"duplicate model id: {model_id}")
        ids.add(model_id)
        if len(model["sourceSha256"]) != 64:
            raise SystemExit(f"{model_id}: sourceSha256 must be 64 hex chars")
        shape = model["inputShape"]
        if len(shape) != 4 or shape[0] != 1 or shape[1] != 3:
            raise SystemExit(f"{model_id}: inputShape must be [1,3,H,W]")
        if model["sourceFormat"] not in ("pytorch", "onnx"):
            raise SystemExit(f"{model_id}: unknown sourceFormat {model['sourceFormat']!r}")

        if model["sourceFormat"] == "pytorch":
            if model.get("architecture") not in ("modnet", "bisenet"):
                raise SystemExit(f"{model_id}: unsupported architecture {model.get('architecture')!r}")
            if model["architecture"] == "bisenet":
                if int(model.get("numClasses", 0)) != 19:
                    raise SystemExit(f"{model_id}: BiSeNet numClasses must be 19")
                hair_class = int(model.get("hairClass", -1))
                if not 0 <= hair_class < 19:
                    raise SystemExit(f"{model_id}: hairClass must be in 0..18")
            reference = model.get("reference")
            if not isinstance(reference, dict):
                raise SystemExit(f"{model_id}: PyTorch sources need an ONNX reference")
            for key in ("url", "sha256", "bytes", "inputName", "outputName"):
                if key not in reference:
                    raise SystemExit(f"{model_id}: reference missing {key}")
            if len(reference["sha256"]) != 64:
                raise SystemExit(f"{model_id}: reference sha256 must be 64 hex chars")
    return data


def selected_models(
    data: dict[str, Any], requested: str, include_disabled: bool
) -> list[dict[str, Any]]:
    models = data["models"]
    if requested == "all":
        chosen = [m for m in models if m["enabled"] or include_disabled]
    else:
        chosen = [m for m in models if m["id"] == requested]
        if not chosen:
            raise SystemExit(f"unknown model: {requested}")
        if not chosen[0]["enabled"] and not include_disabled:
            raise SystemExit(
                f"{requested} is disabled in models.json; pass --include-disabled"
            )
    if not chosen:
        raise SystemExit("no models selected")
    return chosen


def download(url: str, destination: Path, expected_sha: str, expected_bytes: int | None) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and sha256_file(destination) == expected_sha:
        print(f"  cache hit: {destination.name} ({destination.stat().st_size:,} B)")
        return destination

    partial = destination.with_suffix(destination.suffix + ".part")
    partial.unlink(missing_ok=True)
    print(f"  downloading {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "mngcloud-ai-convert/2.0"})
    downloaded = 0
    last_report = 0
    with urllib.request.urlopen(request, timeout=120) as response, partial.open("wb") as out:
        total = int(response.headers.get("Content-Length") or 0)
        while True:
            chunk = response.read(4 * 1024 * 1024)
            if not chunk:
                break
            out.write(chunk)
            downloaded += len(chunk)
            if downloaded - last_report >= 20 * 1024 * 1024:
                last_report = downloaded
                suffix = f" / {total:,}" if total else ""
                print(f"    {downloaded:,}{suffix} B")
    if expected_bytes is not None and downloaded != expected_bytes:
        partial.unlink(missing_ok=True)
        raise SystemExit(
            f"size mismatch for {destination.name}: {downloaded:,} != {expected_bytes:,}"
        )
    actual = sha256_file(partial)
    if actual != expected_sha:
        partial.unlink(missing_ok=True)
        raise SystemExit(
            f"sha256 mismatch for {destination.name}: {actual} != {expected_sha}"
        )
    partial.replace(destination)
    print(f"  verified {destination.name} ({downloaded:,} B)")
    return destination


# ------------------------------------------------------------------- test input
def normalise(rgb: "Any", preprocess: str) -> "Any":
    import numpy as np

    base = np.asarray(rgb, dtype=np.float32)
    if preprocess == "modnet":
        value = (base - 0.5) / 0.5
    elif preprocess == "imagenet":
        value = (base - np.array(MEAN, dtype=np.float32)) / np.array(STD, dtype=np.float32)
    elif preprocess == "isnet":
        value = (base * 255.0 - 128.0) / 256.0
    else:
        raise SystemExit(f"unknown preprocess: {preprocess}")
    return np.transpose(value, (2, 0, 1))[None].astype(np.float32)


def synthetic_image(shape: list[int], preprocess: str) -> "Any":
    """A deterministic smooth image, so PyTorch and ONNX get identical bytes.

    The input is already normalised, because the graphs in this manifest take
    the normalised tensor (the app does the same preprocessing).
    """
    import numpy as np

    _, channels, height, width = shape
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    u = xx / max(width - 1, 1)
    v = yy / max(height - 1, 1)
    base = np.stack(
        [
            0.15 + 0.70 * u,
            0.20 + 0.60 * v,
            0.25 + 0.50 * (1.0 - u) * (1.0 - v),
        ],
        axis=-1,
    )
    # A soft disc and a diagonal band make the tensor non-symmetric, so a
    # row/column flip in the converted graph is visible in the comparison.
    disc = ((u - 0.36) ** 2 + (v - 0.42) ** 2) < 0.018
    band = np.abs(u - v) < 0.035
    base[disc] = base[disc] * 0.25 + np.array([0.95, 0.55, 0.20]) * 0.75
    base[band] = base[band] * 0.35 + np.array([0.10, 0.85, 0.65]) * 0.65
    base = np.clip(base, 0.0, 1.0)
    return normalise(base, preprocess)


def portrait_image(shape: list[int], preprocess: str) -> "Any":
    """A real portrait, so hair and matting outputs are not trivially empty."""
    from PIL import Image

    _, _, height, width = shape
    image = Image.open(TEST_PORTRAIT).convert("RGB").resize(
        (width, height), Image.BILINEAR
    )
    import numpy as np

    return normalise(np.asarray(image, dtype=np.float32) / 255.0, preprocess)


def validation_inputs(spec: dict[str, Any]) -> list[tuple[str, "Any"]]:
    inputs = [("synthetic", synthetic_image(spec["inputShape"], spec["preprocess"]))]
    if TEST_PORTRAIT.exists():
        inputs.append(("portrait", portrait_image(spec["inputShape"], spec["preprocess"])))
    return inputs


# ---------------------------------------------------------------------- models
def load_state_dict(path: Path, prefix: str) -> dict[str, "Any"]:
    import torch

    state = torch.load(path, map_location="cpu", weights_only=True)
    if isinstance(state, dict) and "state_dict" in state:
        state = state["state_dict"]
    if not isinstance(state, dict):
        raise SystemExit(f"{path.name}: expected a state dict")
    if prefix:
        state = {
            key[len(prefix):] if key.startswith(prefix) else key: value
            for key, value in state.items()
        }
    return state


def build_model(spec: dict[str, Any], checkpoint: Path) -> "Any":
    import torch
    import torch.nn as nn

    architecture = spec["architecture"]
    if architecture == "modnet":
        from vendor.modnet import MODNet

        inner = MODNet(backbone_pretrained=False)
    elif architecture == "bisenet":
        from vendor.face_parsing import BiSeNet

        inner = BiSeNet(int(spec["numClasses"]), backbone_name="resnet18")
    else:
        raise SystemExit(f"{spec['id']}: unsupported architecture {architecture}")

    state = load_state_dict(checkpoint, spec.get("stateDictPrefix", ""))
    missing, unexpected = inner.load_state_dict(state, strict=False)
    if missing or unexpected:
        raise SystemExit(
            f"{spec['id']}: checkpoint mismatch, missing={len(missing)} "
            f"unexpected={len(unexpected)}: {missing[:3]} {unexpected[:3]}"
        )
    inner.eval()

    if architecture == "modnet":

        class Matting(nn.Module):
            def __init__(self, inner: nn.Module) -> None:
                super().__init__()
                self.inner = inner

            def forward(self, image):
                _, _, matte = self.inner(image, True)
                return matte

        return Matting(inner).eval()

    hair_class = int(spec.get("hairClass", 17))

    class HairAlpha(nn.Module):
        """Exactly the web hair math: sigmoid(hair - max(other logits))."""

        def __init__(self, inner: nn.Module) -> None:
            super().__init__()
            self.inner = inner

        def forward(self, image):
            logits = self.inner(image)[0]
            hair = logits[:, hair_class:hair_class + 1]
            others = torch.cat(
                (logits[:, :hair_class], logits[:, hair_class + 1:]), dim=1
            )
            return torch.sigmoid(hair - others.max(dim=1, keepdim=True).values)

    return HairAlpha(inner).eval()


def reference_postprocess(spec: dict[str, Any], raw: "Any") -> "Any":
    """Turn the ONNX reference output into the tensor the native model emits."""
    import numpy as np

    raw = np.asarray(raw, dtype=np.float32)
    semantics = spec["outputSemantics"]
    if spec["kind"] == "faceParsing" and semantics == "alpha01":
        hair_class = int(spec.get("hairClass", 17))
        hair = raw[:, hair_class:hair_class + 1]
        others = np.concatenate(
            (raw[:, :hair_class], raw[:, hair_class + 1:]), axis=1
        )
        return 1.0 / (1.0 + np.exp(-(hair - others.max(axis=1, keepdims=True))))
    if semantics == "logitsSigmoid":
        return 1.0 / (1.0 + np.exp(-raw))
    return raw


# --------------------------------------------------------------------- metrics
def compare(spec: dict[str, Any], expected: "Any", actual: "Any") -> dict[str, Any]:
    import numpy as np

    expected = np.asarray(expected, dtype=np.float32)
    actual = np.asarray(actual, dtype=np.float32)
    if expected.shape != actual.shape:
        if expected.size == actual.size:
            actual = actual.reshape(expected.shape)
        else:
            raise SystemExit(
                f"{spec['id']}: output shape {actual.shape} != reference {expected.shape}"
            )

    semantics = spec["outputSemantics"]
    if semantics == "bisenet19":
        def softmax(value: "Any") -> "Any":
            shifted = value - np.max(value, axis=1, keepdims=True)
            exp = np.exp(shifted)
            return exp / np.sum(exp, axis=1, keepdims=True)

        a = softmax(expected)
        b = softmax(actual)
        return {
            "kind": semantics,
            "max_abs_diff": float(np.max(np.abs(a - b))),
            "mean_abs_diff": float(np.mean(np.abs(a - b))),
            "p99_abs_diff": float(np.percentile(np.abs(a - b), 99)),
            "argmax_agreement": float(np.mean(np.argmax(a, axis=1) == np.argmax(b, axis=1))),
        }

    a = np.clip(expected, 0.0, 1.0)
    b = np.clip(actual, 0.0, 1.0)
    diff = np.abs(a - b)
    positive = a >= 0.5
    union = np.logical_or(positive, b >= 0.5).sum()
    intersection = np.logical_and(positive, b >= 0.5).sum()
    iou = float(intersection / union) if union else 1.0
    return {
        "kind": semantics,
        "max_abs_diff": float(diff.max()),
        "mean_abs_diff": float(diff.mean()),
        "p99_abs_diff": float(np.percentile(diff, 99)),
        "p99_9_abs_diff": float(np.percentile(diff, 99.9)),
        "fraction_gt_0_02": float(np.mean(diff > 0.02)),
        "fraction_gt_0_05": float(np.mean(diff > 0.05)),
        "uint8_mean_abs_diff": float(np.mean(np.abs(np.round(a * 255) - np.round(b * 255)))),
        "iou_at_0_5": iou,
        "reference_positive_fraction": float(np.mean(positive)),
    }


def validate_pytorch_vs_reference(spec: dict[str, Any], metrics: dict[str, Any], label: str) -> None:
    if metrics["kind"] == "bisenet19":
        if metrics["argmax_agreement"] < 1.0:
            raise SystemExit(f"{spec['id']}/{label}: PyTorch argmax differs from ONNX")
        if metrics["max_abs_diff"] > 1e-4 or metrics["mean_abs_diff"] > 1e-6:
            raise SystemExit(
                f"{spec['id']}/{label}: PyTorch prob drift max={metrics['max_abs_diff']:.3e} "
                f"mean={metrics['mean_abs_diff']:.3e}"
            )
        return
    if metrics["max_abs_diff"] > 2e-3 or metrics["mean_abs_diff"] > 5e-5:
        raise SystemExit(
            f"{spec['id']}/{label}: PyTorch drift max={metrics['max_abs_diff']:.6f} "
            f"mean={metrics['mean_abs_diff']:.8f} (limits 2e-3/5e-5)"
        )


def validate_coreml(spec: dict[str, Any], metrics: dict[str, Any], label: str) -> None:
    """fp16 weights and activations are allowed to drift, structure is not."""
    if metrics["kind"] == "bisenet19":
        if metrics["argmax_agreement"] < 0.995:
            raise SystemExit(
                f"{spec['id']}/{label}: Core ML argmax agreement "
                f"{metrics['argmax_agreement']:.5f} < 0.995"
            )
        if metrics["mean_abs_diff"] > 0.01 or metrics["p99_abs_diff"] > 0.05:
            raise SystemExit(
                f"{spec['id']}/{label}: Core ML prob drift mean={metrics['mean_abs_diff']:.5f} "
                f"p99={metrics['p99_abs_diff']:.5f}"
            )
        return

    if (
        metrics["mean_abs_diff"] > 0.008
        or metrics["p99_abs_diff"] > 0.10
        or metrics["p99_9_abs_diff"] > 0.15
    ):
        raise SystemExit(
            f"{spec['id']}/{label}: Core ML alpha drift mean={metrics['mean_abs_diff']:.5f} "
            f"p99={metrics['p99_abs_diff']:.5f} p99.9={metrics['p99_9_abs_diff']:.5f} "
            "(limits 0.008/0.10/0.15)"
        )
    if metrics["uint8_mean_abs_diff"] > 2.0:
        raise SystemExit(
            f"{spec['id']}/{label}: Core ML 8-bit drift "
            f"{metrics['uint8_mean_abs_diff']:.3f} levels > 2.0"
        )
    # IoU is meaningless when the reference has almost no positive pixels.
    if metrics["reference_positive_fraction"] >= 0.005 and metrics["iou_at_0_5"] < 0.98:
        raise SystemExit(
            f"{spec['id']}/{label}: Core ML IoU {metrics['iou_at_0_5']:.5f} < 0.98"
        )
    if metrics["max_abs_diff"] > 0.6:
        raise SystemExit(
            f"{spec['id']}/{label}: Core ML max drift {metrics['max_abs_diff']:.4f} > 0.6"
        )


# ------------------------------------------------------------------ conversion
def load_reference(spec: dict[str, Any], cache_dir: Path) -> tuple["Any", str, str]:
    import numpy as np
    import onnxruntime as ort

    reference = spec["reference"]
    path = cache_dir / Path(reference["url"]).name
    download(reference["url"], path, reference["sha256"], reference["bytes"])
    session = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])
    input_names = [item.name for item in session.get_inputs()]
    output_names = [item.name for item in session.get_outputs()]
    if reference["inputName"] not in input_names:
        raise SystemExit(
            f"{spec['id']}: reference input {reference['inputName']} not in {input_names}"
        )
    if reference["outputName"] not in output_names:
        raise SystemExit(
            f"{spec['id']}: reference output {reference['outputName']} not in {output_names}"
        )

    def run(image: "Any") -> "Any":
        raw = session.run(
            [reference["outputName"]], {reference["inputName"]: image}
        )[0]
        return reference_postprocess(spec, np.asarray(raw, dtype=np.float32))

    return run, ort.__version__, path.name


def convert_one(
    spec: dict[str, Any], checkpoint: Path, out_dir: Path, cache_dir: Path
) -> dict[str, Any]:
    import coremltools as ct
    import numpy as np
    import torch

    torch.set_num_threads(4)
    model_id = spec["id"]
    work = out_dir / model_id
    work.mkdir(parents=True, exist_ok=True)
    package = work / f"{model_id}.mlpackage"
    if package.exists():
        shutil.rmtree(package)

    print("  building PyTorch model")
    model = build_model(spec, checkpoint)

    reference_run, ort_version, reference_name = load_reference(spec, cache_dir)
    inputs = validation_inputs(spec)

    pytorch_metrics: dict[str, Any] = {}
    expected_by_input: dict[str, "Any"] = {}
    for label, image in inputs:
        print(f"  PyTorch vs ONNX reference [{label}]")
        with torch.no_grad():
            actual = model(torch.from_numpy(image)).numpy()
        expected = reference_run(image)
        metrics = compare(spec, expected, actual)
        validate_pytorch_vs_reference(spec, metrics, label)
        pytorch_metrics[label] = metrics
        expected_by_input[label] = expected
        print(
            f"    ok: max={metrics['max_abs_diff']:.6f} "
            f"mean={metrics['mean_abs_diff']:.8f}"
        )

    print("  tracing PyTorch graph")
    example = torch.from_numpy(inputs[0][1])
    with torch.no_grad():
        traced = torch.jit.trace(model, example, strict=False)

    print("  converting to mlprogram (iOS 17, Float16)")
    converted = ct.convert(
        traced,
        inputs=[ct.TensorType(name=spec["inputName"], shape=spec["inputShape"], dtype=np.float32)],
        # Naming the output here renames the graph output inside the MIL
        # program. Renaming afterwards would require the weights directory, and
        # an mlprogram cannot be rebuilt from its spec alone.
        outputs=[ct.TensorType(name=spec["outputName"], dtype=np.float32)],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
        skip_model_load=False,
    )
    converted.save(str(package))
    if not package.exists():
        raise SystemExit(f"{model_id}: Core ML package was not written")

    print("  Core ML vs ONNX reference")
    runtime = ct.models.MLModel(str(package), compute_units=ct.ComputeUnit.CPU_ONLY)
    coreml_metrics: dict[str, Any] = {}
    for label, image in inputs:
        prediction = runtime.predict({spec["inputName"]: image})
        if spec["outputName"] not in prediction:
            raise SystemExit(
                f"{model_id}: output {spec['outputName']} not in {list(prediction)}"
            )
        actual = np.asarray(prediction[spec["outputName"]], dtype=np.float32)
        metrics = compare(spec, expected_by_input[label], actual)
        coreml_metrics[label] = metrics
        print(
            f"    {label}: max={metrics['max_abs_diff']:.5f} "
            f"mean={metrics['mean_abs_diff']:.5f} "
            f"p99={metrics['p99_abs_diff']:.5f} "
            f"p99.9={metrics['p99_9_abs_diff']:.5f} "
            f"u8={metrics['uint8_mean_abs_diff']:.3f} "
            f"iou={metrics['iou_at_0_5']:.5f} "
            f"gt.02={metrics['fraction_gt_0_02']:.5f} "
            f"pos={metrics['reference_positive_fraction']:.5f}"
        )
    for label, metrics in coreml_metrics.items():
        validate_coreml(spec, metrics, label)

    environment = {
        "python": platform.python_version(),
        "platform": platform.platform(),
        "coremltools": ct.__version__,
        "onnxruntime": ort_version,
        "torch": torch.__version__,
        "numpy": np.__version__,
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    metadata = {
        "schema": 2,
        "id": model_id,
        "displayName": spec.get("displayName"),
        "version": spec.get("version"),
        "tier": spec.get("tier"),
        "kind": spec.get("kind"),
        "sourceFormat": spec["sourceFormat"],
        "architecture": spec.get("architecture"),
        "source": spec["source"],
        "sourceSha256": spec["sourceSha256"],
        "sourceBytes": spec.get("sourceBytes"),
        "reference": {
            **spec["reference"],
            "artifactId": reference_name,
        },
        "inputName": spec["inputName"],
        "outputName": spec["outputName"],
        "inputShape": spec["inputShape"],
        "preprocess": spec["preprocess"],
        "outputSemantics": spec["outputSemantics"],
        "outputClasses": spec.get("outputClasses", 1),
        "hairClass": spec.get("hairClass"),
        "license": spec["license"],
        "licenseURL": spec.get("licenseURL"),
        "attribution": spec.get("attribution"),
        "conversion": {
            "format": "mlprogram",
            "precision": "Float16",
            "minimumDeploymentTarget": "iOS17",
            "computeUnits": "CPU_ONLY (validation)",
            "output": "sigmoid(hair - max(other))" if spec.get("hairClass") else "matte",
        },
        "validation": {
            "pytorchVsReference": pytorch_metrics,
            "coremlVsReference": coreml_metrics,
        },
        "environment": environment,
        "packageBytes": directory_size(package),
    }

    license_text = (
        f"{spec.get('displayName')}\n"
        f"License: {spec['license']}\n"
        f"License URL: {spec.get('licenseURL', '')}\n"
        f"Attribution: {spec.get('attribution', '')}\n\n"
        "This package contains converted model weights. The full license text is "
        "available at the URL above. The conversion tooling is part of the MNG "
        "Cloud repository.\n"
    )
    (work / "LICENSE.txt").write_text(license_text, encoding="utf-8")
    (work / "metadata.json").write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    archive = work / f"{model_id}.mlpackage.zip"
    archive.unlink(missing_ok=True)
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for path in sorted(package.rglob("*")):
            if path.is_file():
                zf.write(path, arcname=f"{model_id}.mlpackage/{path.relative_to(package)}")
        zf.write(work / "metadata.json", arcname="metadata.json")
        zf.write(work / "LICENSE.txt", arcname="LICENSE.txt")
    # The archive hash cannot live inside the archive (changing the hash changes
    # the archive). It is recorded in the sibling metadata.json, which is what
    # the app catalog pins.
    metadata["archiveSha256"] = sha256_file(archive)
    metadata["archiveBytes"] = archive.stat().st_size
    (work / "metadata.json").write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(
        f"  wrote {archive.name} ({metadata['archiveBytes']:,} B, "
        f"sha256 {metadata['archiveSha256'][:16]}…)"
    )
    return metadata


def directory_size(path: Path) -> int:
    return sum(item.stat().st_size for item in path.rglob("*") if item.is_file())


def validate_only(spec: dict[str, Any], checkpoint: Path, cache_dir: Path) -> dict[str, Any]:
    """Run the PyTorch-vs-ONNX proof without coremltools (works on Windows)."""
    import torch

    torch.set_num_threads(4)
    model = build_model(spec, checkpoint)
    reference_run, _, _ = load_reference(spec, cache_dir)
    results: dict[str, Any] = {}
    for label, image in validation_inputs(spec):
        with torch.no_grad():
            actual = model(torch.from_numpy(image)).numpy()
        expected = reference_run(image)
        metrics = compare(spec, expected, actual)
        validate_pytorch_vs_reference(spec, metrics, label)
        results[label] = metrics
        print(
            f"    {label}: max={metrics['max_abs_diff']:.8f} "
            f"mean={metrics['mean_abs_diff']:.10f} iou={metrics['iou_at_0_5']:.6f}"
        )
    return results


# ------------------------------------------------------------------------ main
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default="all", help="model id or all")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--cache", type=Path, default=DEFAULT_CACHE)
    parser.add_argument("--include-disabled", action="store_true")
    parser.add_argument(
        "--check-manifest",
        action="store_true",
        help="validate models.json and list the selected models without converting",
    )
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="prove the PyTorch model matches ONNX; does not need coremltools",
    )
    args = parser.parse_args()

    data = load_manifest()
    chosen = selected_models(data, args.model, args.include_disabled)
    print(f"models: {', '.join(m['id'] for m in chosen)}")
    if args.check_manifest:
        for model in chosen:
            reference = model.get("reference", {}).get("url", "")
            print(
                f"  {model['id']}: {model['sourceFormat']} "
                f"{model['inputShape']} {model['preprocess']} "
                f"-> {model['outputSemantics']} ({model['license']})"
                + (f" ref={reference}" if reference else "")
            )
        return

    unsupported = [m["id"] for m in chosen if m["sourceFormat"] != "pytorch"]
    if unsupported:
        raise SystemExit(
            "ONNX-only models still need a PyTorch checkpoint: " + ", ".join(unsupported)
        )

    if args.validate_only:
        try:
            import numpy  # noqa: F401
            import onnxruntime  # noqa: F401
            import PIL  # noqa: F401
            import torch  # noqa: F401
        except ImportError as error:
            raise SystemExit(
                "torch, onnxruntime, numpy and Pillow are required for "
                f"--validate-only ({error})"
            )
    else:
        try:
            import coremltools  # noqa: F401
            import numpy  # noqa: F401
            import onnxruntime  # noqa: F401
            import PIL  # noqa: F401
            import torch  # noqa: F401
        except ImportError as error:
            raise SystemExit(
                "coremltools, torch, onnxruntime, numpy and Pillow are required; "
                f"run this on macOS ({error})"
            )

    args.out.mkdir(parents=True, exist_ok=True)
    args.cache.mkdir(parents=True, exist_ok=True)
    summaries = []
    for spec in chosen:
        print(f"\n[{spec['id']}]")
        source = args.cache / Path(spec["source"]).name
        download(
            spec["source"],
            source,
            spec["sourceSha256"],
            spec.get("sourceBytes"),
        )
        if args.validate_only:
            summaries.append(
                {
                    "id": spec["id"],
                    "sourceFormat": spec["sourceFormat"],
                    "validation": validate_only(spec, source, args.cache),
                }
            )
        else:
            summaries.append(convert_one(spec, source, args.out, args.cache))

    if args.validate_only:
        print("\nvalidate-only: every PyTorch model matches its ONNX reference")
        return

    summary_path = args.out / "summary.json"
    summary_path.write_text(
        json.dumps(
            {
                "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "models": summaries,
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"\nsummary: {summary_path}")


if __name__ == "__main__":
    main()
