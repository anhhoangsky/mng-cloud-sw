# coremltools patches (vendored)

- Upstream: https://github.com/apple/coremltools
- License: BSD-3-Clause (see `LICENSE`)
- Only `tools/ai/` (the conversion toolchain) imports these modules. They are
  not part of the iOS app and do not ship in the model archives.

## `deform_conv.py`: torchvision deform_conv2d lowering

- Pull request: https://github.com/apple/coremltools/pull/2752
- Merge commit: `d5d4267a` (merged 2026-07-15, unreleased as of coremltools 9.0)
- File is the `ops.py` hunk of that PR, copied verbatim except for the import
  block and the `register()` wrapper at the bottom. Upstream inserts the
  function next to `torchvision_nms`, where `Var`, `is_symbolic`,
  `_get_inputs` and `register_torch_op` are already imported.

BiRefNet Lite's decoder uses `torchvision.ops.deform_conv2d` inside its
`ASPPDeformable` attention blocks. coremltools 9.0 does not lower that op, so
`ct.convert` fails before emitting an mlprogram. Registering this lowering
before conversion teaches the TorchScript frontend to express the op with
Core ML `resample`/`conv` layers instead of a missing custom op.

## `torch_cast.py`: constant `aten::Int` / `aten::Bool` casting

- Pull request: https://github.com/apple/coremltools/pull/2632
- Commit: `7e9e671274` ("Fix type casting error with numpy 2.4"), unreleased
  as of coremltools 9.0
- File copies the 9.0 `_cast` handler and makes the same change as upstream:
  squeeze a compile-time constant before converting it to `int` or `bool`.
  It uses `np.asarray(x.val).squeeze()` so Python scalars and array-likes are
  handled too.

BiRefNet's Swin backbone converts the spatial dimensions to tensors
(`torch.tensor(H)`), and `torch.jit.trace` records those as
`prim::NumToTensor`. coremltools 9.0 materialises that op as a length-one
constant (`mb.const(val=[x.val])`); `aten::Int` then calls `int(x.val)`, which
NumPy 2.4+ rejects with "only 0-dimensional arrays can be converted to Python
scalars". Squeezing the constant gives the 0-dimensional value PyTorch's
`NumToTensor` means, and conversion proceeds.
