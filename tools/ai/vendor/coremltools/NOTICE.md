# coremltools deform_conv2d lowering (vendored)

- Upstream: https://github.com/apple/coremltools
- Pull request: https://github.com/apple/coremltools/pull/2752
- Merge commit: `d5d4267a` (merged 2026-07-15, unreleased as of coremltools 9.0)
- License: BSD-3-Clause (see `LICENSE`)
- File: `deform_conv.py` is the `ops.py` hunk of that PR, copied verbatim
  except for the import block and the `register()` wrapper at the bottom.
  Upstream inserts the function next to `torchvision_nms`, where `Var`,
  `is_symbolic`, `_get_inputs` and `register_torch_op` are already imported.

## Why it is needed

BiRefNet Lite's decoder uses `torchvision.ops.deform_conv2d` inside its
`ASPPDeformable` attention blocks. coremltools 9.0 does not lower that op, so
`ct.convert` fails before emitting an mlprogram. Registering this lowering
before conversion teaches the TorchScript frontend to express the op with
Core ML `resample`/`conv` layers instead of a missing custom op.

Only `tools/ai/` (the conversion toolchain) imports this module. It is not
part of the iOS app and does not ship in the model archives.
