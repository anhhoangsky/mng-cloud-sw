# IS-Net / DIS (vendored)

- Upstream code: https://github.com/xuebinqin/DIS
- Code revision: `b6764e20381f6f42a70f83fa3324181529ed1403`
- License: Apache-2.0 (see `LICENSE`)
- Files:
  - `isnet.py` — unchanged copy of `IS-Net/models/isnet.py`.
  - `__init__.py` — package wiring added by MNG Cloud.
- Checkpoint used by the converter:
  https://huggingface.co/NimaBoscarino/IS-Net_DIS-general-use/resolve/608a843548f1f32716542d57dc59dcbb773294d4/isnet-general-use.pth
  (SHA-256 `9e1aafea58f0b55d0c35077e0ceade6ba1ba2bce372fd4f8f77215391f3fac13`),
  a mirror of the official DIS general-use checkpoint.
- Parity reference:
  https://huggingface.co/onnx-community/ISNet-ONNX/resolve/3fe6e3db3e32c69aadde61fe388ddb1a0574440c/onnx/model_fp16.onnx
  (SHA-256 `dffe20331551dcc5d7601563e472448424821f2df41f5bad395848826c5b5be5`),
  the exact `isnet-fp16` bytes the web app installs. Its model card declares
  AGPL-3.0; it is used only to validate the Apache-2.0 checkpoint and is never
  shipped to the app.
- Conversion dependencies: `torch` and `torchvision` (the unchanged file keeps
  its unused `from torchvision import models` import).

The vendored code is only used to rebuild the upstream model in PyTorch so it
can be converted to Core ML. The app downloads the converted Core ML package,
not this source or the checkpoint.
