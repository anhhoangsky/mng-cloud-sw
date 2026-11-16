# BiSeNet face parsing (vendored)

- Upstream: https://github.com/yakhyo/face-parsing
- Commit: `4f0632b17a3e729a7871683aab7c89b6a595da9f`
- License: MIT (see `LICENSE`)
- Files:
  - `bisenet.py` — one modification: `from models.resnet` became
    `from .resnet` so the package works without the upstream repository root.
  - `resnet.py` — two modifications: the `torchvision` dependency was removed,
    and `resnet18`/`resnet34` default to `weights=None`. Upstream downloads
    ImageNet weights on construction; the face parsing checkpoint replaces all
    of them, so the download is wasted in a conversion job.
- Checkpoint used by the converter:
  https://github.com/yakhyo/face-parsing/releases/download/weights/resnet18.pt
  (SHA-256 `18c44e06b77e47da86fe2b48fac78e0ccbd0b5241c829f9487ebf7fd4a6389e6`).

The vendored code is only used to rebuild the web model in PyTorch so it can be
converted to Core ML. The app downloads the converted Core ML package, not this
source or the checkpoint.
