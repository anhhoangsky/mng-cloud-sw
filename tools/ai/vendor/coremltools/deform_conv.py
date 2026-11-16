"""torchvision::deform_conv2d lowering for coremltools 9.0.

coremltools 9.0 has no lowering for ``torchvision.ops.deform_conv2d``, which
BiRefNet's ASPP-deformable decoder needs. Apple merged a lowering in
https://github.com/apple/coremltools/pull/2752 (commit ``d5d4267a``, July 2026)
but has not shipped a release that contains it, so the op body below is a
verbatim copy of that pull request's ``ops.py`` hunk.

The only changes are the import block and the registration wrapper at the
bottom: upstream inserts the function into ``ops.py``, where ``Var``,
``is_symbolic``, ``_get_inputs`` and ``register_torch_op`` are already in
scope. Everything else, including comments, is unchanged.

Upstream license: BSD-3-Clause, see ``LICENSE`` and ``NOTICE.md``.
"""

from typing import List, Tuple

import numpy as np

from coremltools.converters.mil.frontend import _utils
from coremltools.converters.mil.frontend.torch.ops import _get_inputs
from coremltools.converters.mil.frontend.torch.torch_op_registry import (
    _TORCH_OPS_REGISTRY,
    register_torch_op,
)
from coremltools.converters.mil.mil import Builder as mb
from coremltools.converters.mil.mil import types
from coremltools.converters.mil.mil.ops.defs._utils import promote_input_dtypes
from coremltools.converters.mil.mil.types.symbolic import is_symbolic
from coremltools.converters.mil.mil.var import Var

# --------------------------------------------------------------------------
# Verbatim from https://github.com/apple/coremltools/pull/2752.
# --------------------------------------------------------------------------


def _torchvision_deform_conv2d_const_int(x: Var, name: str) -> int:
    if x is None or x.val is None:
        raise ValueError(f"torchvision::deform_conv2d requires constant {name}.")
    return int(np.array(x.val).item())


def _torchvision_deform_conv2d_const_bool(x: Var, name: str) -> bool:
    if x is None or x.val is None:
        raise ValueError(f"torchvision::deform_conv2d requires constant {name}.")
    return bool(np.array(x.val).item())


def _torchvision_deform_conv2d_require_static_dim(dim, name: str) -> int:
    if is_symbolic(dim):
        raise ValueError(f"torchvision::deform_conv2d requires static {name}.")
    return int(dim)


def _torchvision_deform_conv2d_slice_channel(x: Var, channel: int) -> Var:
    return mb.slice_by_index(
        x=x,
        begin=[0, channel, 0, 0],
        end=[0, channel + 1, 0, 0],
        begin_mask=[True, False, True, True],
        end_mask=[True, False, True, True],
        squeeze_mask=[False, True, False, False],
    )


def _torchvision_deform_conv2d_slice_channel_range(x: Var, start: int, end: int) -> Var:
    return mb.slice_by_index(
        x=x,
        begin=[0, start, 0, 0],
        end=[0, end, 0, 0],
        begin_mask=[True, False, True, True],
        end_mask=[True, False, True, True],
    )


def _torchvision_deform_conv2d_concat(values: List[Var], axis: int) -> Var:
    if len(values) == 1:
        return values[0]
    return mb.concat(values=values, axis=axis)


def _torchvision_deform_conv2d_base_grids(
    height: int,
    width: int,
    stride_h: int,
    stride_w: int,
    pad_h: int,
    pad_w: int,
    kh_index: int,
    kw_index: int,
    dilation_h: int,
    dilation_w: int,
) -> Tuple[np.ndarray, np.ndarray]:
    base_y = np.arange(height, dtype=np.float32) * stride_h - pad_h + kh_index * dilation_h
    base_x = np.arange(width, dtype=np.float32) * stride_w - pad_w + kw_index * dilation_w
    base_y = np.broadcast_to(base_y.reshape(1, height, 1), (1, height, width)).astype(
        np.float32
    )
    base_x = np.broadcast_to(base_x.reshape(1, 1, width), (1, height, width)).astype(
        np.float32
    )
    return base_y, base_x


def torchvision_deform_conv2d(context, node):
    inputs = _get_inputs(context, node, expected=14)
    x, weight, offset, mask, bias = inputs[:5]
    stride_h = _torchvision_deform_conv2d_const_int(inputs[5], "stride_h")
    stride_w = _torchvision_deform_conv2d_const_int(inputs[6], "stride_w")
    pad_h = _torchvision_deform_conv2d_const_int(inputs[7], "pad_h")
    pad_w = _torchvision_deform_conv2d_const_int(inputs[8], "pad_w")
    dilation_h = _torchvision_deform_conv2d_const_int(inputs[9], "dilation_h")
    dilation_w = _torchvision_deform_conv2d_const_int(inputs[10], "dilation_w")
    groups = _torchvision_deform_conv2d_const_int(inputs[11], "groups")
    offset_groups = _torchvision_deform_conv2d_const_int(inputs[12], "offset_groups")
    use_mask = _torchvision_deform_conv2d_const_bool(inputs[13], "use_mask")

    if x.rank != 4 or weight.rank != 4 or offset.rank != 4:
        raise ValueError(
            "torchvision::deform_conv2d expects rank-4 input, weight, and offset tensors."
        )
    if use_mask and (mask is None or mask.rank != 4):
        raise ValueError("torchvision::deform_conv2d expects a rank-4 mask when use_mask=True.")
    if bias is not None and bias.rank != 1:
        raise ValueError("torchvision::deform_conv2d expects rank-1 bias.")

    cin = _torchvision_deform_conv2d_require_static_dim(x.shape[1], "input channels")
    hin = x.shape[2]
    win = x.shape[3]
    cout = _torchvision_deform_conv2d_require_static_dim(weight.shape[0], "output channels")
    cin_per_group = _torchvision_deform_conv2d_require_static_dim(
        weight.shape[1], "weight input channels per group"
    )
    kh = _torchvision_deform_conv2d_require_static_dim(weight.shape[2], "kernel height")
    kw = _torchvision_deform_conv2d_require_static_dim(weight.shape[3], "kernel width")
    offset_channels = _torchvision_deform_conv2d_require_static_dim(
        offset.shape[1], "offset channels"
    )
    hout = _torchvision_deform_conv2d_require_static_dim(offset.shape[2], "output height")
    wout = _torchvision_deform_conv2d_require_static_dim(offset.shape[3], "output width")

    if stride_h <= 0 or stride_w <= 0:
        raise ValueError("torchvision::deform_conv2d expects positive stride.")
    if dilation_h <= 0 or dilation_w <= 0:
        raise ValueError("torchvision::deform_conv2d expects positive dilation.")
    if pad_h < 0 or pad_w < 0:
        raise ValueError("torchvision::deform_conv2d expects non-negative padding.")
    if groups <= 0 or offset_groups <= 0:
        raise ValueError("torchvision::deform_conv2d expects positive groups and offset_groups.")
    if cin % groups != 0:
        raise ValueError("torchvision::deform_conv2d input channels must be divisible by groups.")
    if cout % groups != 0:
        raise ValueError("torchvision::deform_conv2d output channels must be divisible by groups.")
    if cin % offset_groups != 0:
        raise ValueError(
            "torchvision::deform_conv2d input channels must be divisible by offset_groups."
        )
    if cin_per_group != cin // groups:
        raise ValueError(
            "torchvision::deform_conv2d weight shape does not match input channels/groups."
        )

    kernel_size = kh * kw
    expected_offset_channels = 2 * offset_groups * kernel_size
    if offset_channels != expected_offset_channels:
        raise ValueError(
            "torchvision::deform_conv2d offset channels must equal "
            f"2 * offset_groups * kernel_height * kernel_width ({expected_offset_channels})."
        )
    if use_mask:
        mask_channels = _torchvision_deform_conv2d_require_static_dim(
            mask.shape[1], "mask channels"
        )
        expected_mask_channels = offset_groups * kernel_size
        if mask_channels != expected_mask_channels:
            raise ValueError(
                "torchvision::deform_conv2d mask channels must equal "
                f"offset_groups * kernel_height * kernel_width ({expected_mask_channels})."
            )

    if not is_symbolic(hin) and not is_symbolic(win):
        expected_hout = (hin + 2 * pad_h - dilation_h * (kh - 1) - 1) // stride_h + 1
        expected_wout = (win + 2 * pad_w - dilation_w * (kw - 1) - 1) // stride_w + 1
        if hout != expected_hout or wout != expected_wout:
            raise ValueError(
                "torchvision::deform_conv2d offset spatial dimensions do not match "
                "the input/weight/stride/padding/dilation configuration."
            )

    channels_per_offset_group = cin // offset_groups
    sampled_by_kernel = []

    for kh_index in range(kh):
        for kw_index in range(kw):
            kernel_index = kh_index * kw + kw_index
            base_y, base_x = _torchvision_deform_conv2d_base_grids(
                hout,
                wout,
                stride_h,
                stride_w,
                pad_h,
                pad_w,
                kh_index,
                kw_index,
                dilation_h,
                dilation_w,
            )
            base_y = mb.const(val=base_y)
            base_x = mb.const(val=base_x)

            sampled_offset_groups = []
            for offset_group in range(offset_groups):
                channel_start = offset_group * channels_per_offset_group
                channel_end = channel_start + channels_per_offset_group
                x_group = _torchvision_deform_conv2d_slice_channel_range(
                    x, channel_start, channel_end
                )
                # Core ML resample's constant padding is applied to the whole sample when
                # coordinates are out of range. Deformable convolution needs per-neighbor
                # zero padding for bilinear interpolation, so make the one-pixel border
                # explicit and shift the sample coordinates into the padded image.
                pad_value = np.float16(0.0) if x_group.dtype == types.fp16 else 0.0
                x_group = mb.pad(
                    x=x_group,
                    pad=[0, 0, 0, 0, 1, 1, 1, 1],
                    mode="constant",
                    constant_val=pad_value,
                )

                offset_base = offset_group * 2 * kernel_size
                offset_y = _torchvision_deform_conv2d_slice_channel(
                    offset, offset_base + 2 * kernel_index
                )
                offset_x = _torchvision_deform_conv2d_slice_channel(
                    offset, offset_base + 2 * kernel_index + 1
                )
                if offset_y.dtype != types.fp32:
                    offset_y = mb.cast(x=offset_y, dtype="fp32")
                if offset_x.dtype != types.fp32:
                    offset_x = mb.cast(x=offset_x, dtype="fp32")

                coord_y = mb.add(x=base_y, y=offset_y)
                coord_x = mb.add(x=base_x, y=offset_x)
                coord_y = mb.add(x=coord_y, y=1.0)
                coord_x = mb.add(x=coord_x, y=1.0)

                x_group_shape = mb.shape(x=x_group)
                hpad = mb.cast(x=_utils.pymil_value_at(x_group_shape, 2), dtype="fp32")
                wpad = mb.cast(x=_utils.pymil_value_at(x_group_shape, 3), dtype="fp32")
                coord_y = mb.real_div(x=coord_y, y=mb.sub(x=hpad, y=1.0))
                coord_x = mb.real_div(x=coord_x, y=mb.sub(x=wpad, y=1.0))
                coord_y = mb.sub(x=mb.mul(x=coord_y, y=2.0), y=1.0)
                coord_x = mb.sub(x=mb.mul(x=coord_x, y=2.0), y=1.0)
                coordinates = mb.stack(values=[coord_x, coord_y], axis=-1)
                sampled = mb.resample(
                    x=x_group,
                    coordinates=coordinates,
                    sampling_mode="bilinear",
                    padding_mode="constant",
                    padding_value=pad_value,
                    coordinates_mode="normalized_minus_one_to_one",
                    align_corners=True,
                )

                if use_mask:
                    mask_channel = offset_group * kernel_size + kernel_index
                    mask_slice = _torchvision_deform_conv2d_slice_channel_range(
                        mask, mask_channel, mask_channel + 1
                    )
                    sampled = mb.mul(x=sampled, y=mask_slice)

                sampled_offset_groups.append(sampled)

            sampled_by_kernel.append(
                _torchvision_deform_conv2d_concat(sampled_offset_groups, axis=1)
            )

    patch_groups = []
    channels_per_weight_group = cin // groups
    for weight_group in range(groups):
        channel_start = weight_group * channels_per_weight_group
        channel_end = channel_start + channels_per_weight_group
        for sampled in sampled_by_kernel:
            patch_groups.append(
                _torchvision_deform_conv2d_slice_channel_range(
                    sampled, channel_start, channel_end
                )
            )
    patches = _torchvision_deform_conv2d_concat(patch_groups, axis=1)

    weight_1x1 = mb.transpose(x=weight, perm=[0, 2, 3, 1])
    weight_1x1 = mb.reshape(x=weight_1x1, shape=[cout, kernel_size * cin_per_group, 1, 1])
    patches, weight_1x1 = promote_input_dtypes([patches, weight_1x1])

    conv_name = node.name if bias is None else node.name + "_conv"
    out = mb.conv(
        x=patches,
        weight=weight_1x1,
        groups=groups,
        pad_type="valid",
        name=conv_name,
    )

    if bias is not None:
        bias = mb.reshape(x=bias, shape=[1, cout, 1, 1])
        out, bias = promote_input_dtypes([out, bias])
        out = mb.add(x=out, y=bias, name=node.name)

    context.add(out)


def register() -> None:
    """Register the lowering once, before ``ct.convert`` runs."""
    if "torchvision::deform_conv2d" in _TORCH_OPS_REGISTRY.name_to_func_mapping:
        return
    register_torch_op(torch_alias=["torchvision::deform_conv2d"])(torchvision_deform_conv2d)


register()
