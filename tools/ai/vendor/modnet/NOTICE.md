# MODNet (vendored)

- Upstream: https://github.com/ZHKKKe/MODNet
- Commit: `28165a451e4610c9d77cfdf925a94610bb2810fb`
- License: Apache-2.0 (see `LICENSE`)
- Files:
  - `modnet.py` — unchanged
  - `backbones/mobilenetv2.py` — unchanged
  - `backbones/wrapper.py` — unchanged
  - `__init__.py`, `backbones/__init__.py` — package wiring added by MNG Cloud
- Checkpoint used by the converter:
  `modnet_photographic_portrait_matting.ckpt`, mirrored by
  https://huggingface.co/frkesk/modnet (SHA-256
  `7c22235f0925deba15d4d63e53afcb654c47055bbcd98f56e393ab2584007ed8`).

The vendored code is only used to rebuild the web model in PyTorch so it can be
converted to Core ML. The app downloads the converted Core ML package, not this
source or the checkpoint.
