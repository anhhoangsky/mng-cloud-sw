# BiRefNet Lite (vendored)

- Upstream model card: https://huggingface.co/ZhengPeng7/BiRefNet_lite
- Revision: `aa62cd87eafb9cc43056d08ef3615a14628b831d`
- Upstream code: https://github.com/ZhengPeng7/BiRefNet
- License: MIT (see `LICENSE`)
- Files:
  - `birefnet.py` — unchanged copy of the model card's `birefnet.py`.
  - `BiRefNet_config.py` — unchanged copy of the model card's
    `BiRefNet_config.py`; it is the sibling module `birefnet.py` imports.
  - `__init__.py` — package wiring added by MNG Cloud.
- Checkpoint used by the converter:
  https://huggingface.co/ZhengPeng7/BiRefNet_lite/resolve/aa62cd87eafb9cc43056d08ef3615a14628b831d/model.safetensors
  (SHA-256 `4417d89795250e698c3cb0ae8df15743810065f646f48a694fdfa7ca052d0815`).
- Conversion dependencies: `torch`, `torchvision` (for
  `deform_conv2d`), `timm` (Swin layers), `transformers` (the
  `PreTrainedModel`/`PretrainedConfig` base classes) and `safetensors`.

The vendored code is only used to rebuild the upstream model in PyTorch so it
can be converted to Core ML. The app downloads the converted Core ML package,
not this source or the checkpoint.

The decoder uses `torchvision.ops.deform_conv2d`, which coremltools 9.0 does
not lower by itself. The converter registers Apple's upstream lowering from
PR https://github.com/apple/coremltools/pull/2752; see
`../coremltools/NOTICE.md`.
