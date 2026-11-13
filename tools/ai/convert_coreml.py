"""Convert the pinned ONNX background/face models to Core ML for the native app.

Runs on macOS only (coremltools requirement). The GitHub workflow
`.github/workflows/ai-models.yml` calls this script on a macOS runner and
uploads the resulting `.mlpackage.zip` artifacts.

The script does four things:
1. downloads the exact pinned ONNX bytes and verifies SHA-256;
2. converts them to an iOS 17 `mlprogram` with Float16 weights;
3. runs the ONNX and Core ML models on the same deterministic tensor and
   checks that the outputs agree;
4. writes a metadata JSON (versions, hashes, validation metrics) and a zip
   containing the `.mlpackage`, the metadata and the license notice.

Usage:
    python tools/ai/convert_coreml.py --check-manifest
    python tools/ai/convert_coreml.py --model all
    python tools/ai/convert_coreml.py --model bisenet-face-parsing

The ONNX cache is `tools/ai/.cache`; artifacts go to `tools/ai/artifacts`.
Neither directory is committed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import sys
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "models.json"
DEFAULT_CACHE = ROOT / ".cache"
DEFAULT_OUT = ROOT / "artifacts"

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
    if data.get("schema") != 1:
        raise SystemExit(f"unsupported manifest schema: {data.get('schema')!r}")
    models = data.get("models")
    if not isinstance(models, list) or not models:
        raise SystemExit("manifest has no models")
    ids: set[str] = set()
    for model in models:
        for key in (
            "id",
            "enabled",
            "source",
            "sourceSha256",
            "inputName",
            "outputName",
            "inputShape",
            "preprocess",
            "outputSemantics",
            "license",
        ):
            if key not in model:
                raise SystemExit(f"{model.get('id', '<unknown>')}: missing {key}")
        if model["id"] in ids:
            raise SystemExit(f"duplicate model id: {model['id']}")
        ids.add(model["id"])
        if len(model["sourceSha256"]) != 64:
            raise SystemExit(f"{model['id']}: sourceSha256 must be 64 hex chars")
        shape = model["inputShape"]
        if len(shape) != 4 or shape[0] != 1 or shape[1] != 3:
            raise SystemExit(f"{model['id']}: inputShape must be [1,3,H,W]")
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
        print(f"  cache hit: {destination} ({destination.stat().st_size:,} B)")
        return destination

    partial = destination.with_suffix(destination.suffix + ".part")
    if partial.exists():
        partial.unlink()
    print(f"  downloading {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "mngcloud-ai-convert/1.0"})
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

def synthetic_image(shape: list[int], preprocess: str) -> "Any":
    """A deterministic smooth image, so ONNX and Core ML get identical bytes.

    The input is already normalised, because the ONNX graphs in this manifest
    take the normalised tensor (the app does the same preprocessing).
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

    if preprocess == "modnet":
        value = (base - 0.5) / 0.5
    elif preprocess == "imagenet":
        value = (base - np.array(MEAN, dtype=np.float32)) / np.array(STD, dtype=np.float32)
    elif preprocess == "isnet":
        value = (base * 255.0 - 128.0) / 256.0
    else:
        raise SystemExit(f"unknown preprocess: {preprocess}")

    return np.transpose(value, (2, 0, 1))[None].astype(np.float32)


# ------------------------------------------------------------------ conversion

def output_metric(spec: dict[str, Any], expected: "Any", actual: "Any") -> dict[str, Any]:
    import numpy as np

    semantics = spec["outputSemantics"]
    expected = np.asarray(expected, dtype=np.float32)
    actual = np.asarray(actual, dtype=np.float32)
    if expected.shape != actual.shape:
        if expected.size == actual.size:
            actual = actual.reshape(expected.shape)
        else:
            raise SystemExit(
                f"{spec['id']}: output shape {actual.shape} != ONNX {expected.shape}"
            )

    if semantics == "alpha01":
        a = np.clip(expected, 0.0, 1.0)
        b = np.clip(actual, 0.0, 1.0)
        return {
            "kind": semantics,
            "max_abs_diff": float(np.max(np.abs(a - b))),
            "mean_abs_diff": float(np.mean(np.abs(a - b))),
        }
    if semantics == "logitsSigmoid":
        a = 1.0 / (1.0 + np.exp(-expected))
        b = 1.0 / (1.0 + np.exp(-actual))
        return {
            "kind": semantics,
            "max_abs_diff": float(np.max(np.abs(a - b))),
            "mean_abs_diff": float(np.mean(np.abs(a - b))),
        }
    if semantics == "bisenet19":
        def softmax(value: "Any") -> "Any":
            shifted = value - np.max(value, axis=1, keepdims=True)
            exp = np.exp(shifted)
            return exp / np.sum(exp, axis=1, keepdims=True)

        a = softmax(expected)
        b = softmax(actual)
        agreement = float(np.mean(np.argmax(a, axis=1) == np.argmax(b, axis=1)))
        return {
            "kind": semantics,
            "max_abs_diff": float(np.max(np.abs(a - b))),
            "mean_abs_diff": float(np.mean(np.abs(a - b))),
            "argmax_agreement": agreement,
        }
    raise SystemExit(f"unknown outputSemantics: {semantics}")


def validate(spec: dict[str, Any], metrics: dict[str, Any]) -> None:
    max_diff = metrics["max_abs_diff"]
    mean_diff = metrics["mean_abs_diff"]
    if metrics["kind"] == "bisenet19":
        if metrics.get("argmax_agreement", 0.0) < 0.999:
            raise SystemExit(f"{spec['id']}: argmax agreement below 0.999")
        max_limit, mean_limit = 0.05, 0.01
    else:
        max_limit, mean_limit = 0.02, 0.005
    if max_diff > max_limit or mean_diff > mean_limit:
        raise SystemExit(
            f"{spec['id']}: conversion drift max={max_diff:.5f} "
            f"mean={mean_diff:.5f} (limits {max_limit}/{mean_limit})"
        )


def convert_one(
    spec: dict[str, Any], onnx_path: Path, out_dir: Path, cache_dir: Path
) -> dict[str, Any]:
    import coremltools as ct
    import numpy as np
    import onnxruntime as ort

    model_id = spec["id"]
    work = out_dir / model_id
    work.mkdir(parents=True, exist_ok=True)
    package = work / f"{model_id}.mlpackage"
    if package.exists():
        shutil.rmtree(package)

    input_shape = spec["inputShape"]
    x = synthetic_image(input_shape, spec["preprocess"])

    print(f"  ONNX runtime reference")
    session = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    input_names = [item.name for item in session.get_inputs()]
    output_names = [item.name for item in session.get_outputs()]
    if spec["inputName"] not in input_names:
        raise SystemExit(f"{model_id}: input {spec['inputName']} not in {input_names}")
    if spec["outputName"] not in output_names:
        raise SystemExit(f"{model_id}: output {spec['outputName']} not in {output_names}")
    expected = session.run([spec["outputName"]], {spec["inputName"]: x})[0]

    print(f"  converting to mlprogram (iOS 17, Float16)")
    converted = ct.convert(
        str(onnx_path),
        inputs=[ct.TensorType(name=spec["inputName"], shape=input_shape)],
        outputs=[ct.TensorType(name=spec["outputName"])],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
        skip_model_load=False,
    )
    converted.save(str(package))
    if not package.exists():
        raise SystemExit(f"{model_id}: Core ML package was not written")

    print(f"  Core ML runtime reference")
    model = ct.models.MLModel(str(package), compute_units=ct.ComputeUnit.CPU_ONLY)
    try:
        prediction = model.predict({spec["inputName"]: x})
    except (TypeError, ValueError) as error:
        # A Float16 model may reject a float32 multi-array at the boundary on
        # some coremltools/macOS combinations. Retry with the matching dtype.
        if "float16" not in str(error).lower() and "dtype" not in str(error).lower():
            raise
        prediction = model.predict({spec["inputName"]: x.astype(np.float16)})
    if spec["outputName"] in prediction:
        actual = prediction[spec["outputName"]]
    else:
        arrays = [v for v in prediction.values() if hasattr(v, "shape")]
        if not arrays:
            raise SystemExit(f"{model_id}: no array output in {list(prediction)}")
        actual = arrays[0]
    actual = np.asarray(actual, dtype=np.float32)
    metrics = output_metric(spec, expected, actual)
    validate(spec, metrics)
    print(
        f"  validation ok: max={metrics['max_abs_diff']:.5f} "
        f"mean={metrics['mean_abs_diff']:.5f}"
    )

    metadata = {
        "schema": 1,
        "id": model_id,
        "displayName": spec.get("displayName"),
        "version": spec.get("version"),
        "tier": spec.get("tier"),
        "kind": spec.get("kind"),
        "source": spec["source"],
        "sourceSha256": spec["sourceSha256"],
        "sourceBytes": spec.get("sourceBytes"),
        "inputName": spec["inputName"],
        "outputName": spec["outputName"],
        "inputShape": input_shape,
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
        },
        "validation": metrics,
        "environment": {
            "python": platform.python_version(),
            "platform": platform.platform(),
            "coremltools": ct.__version__,
            "onnxruntime": ort.__version__,
            "numpy": np.__version__,
            "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        },
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
    if archive.exists():
        archive.unlink()
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
    args = parser.parse_args()

    data = load_manifest()
    chosen = selected_models(data, args.model, args.include_disabled)
    print(f"models: {', '.join(m['id'] for m in chosen)}")
    if args.check_manifest:
        for model in chosen:
            print(
                f"  {model['id']}: {model['inputShape']} {model['preprocess']} "
                f"-> {model['outputSemantics']} ({model['license']})"
            )
        return

    try:
        import coremltools  # noqa: F401
        import onnxruntime  # noqa: F401
        import numpy  # noqa: F401
    except ImportError as error:
        raise SystemExit(
            "coremltools, onnxruntime and numpy are required; run this on macOS "
            f"with `pip install coremltools onnxruntime numpy` ({error})"
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
        summaries.append(convert_one(spec, source, args.out, args.cache))

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
