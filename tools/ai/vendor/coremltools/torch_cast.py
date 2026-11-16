"""Backport of the coremltools ``_cast`` fix needed by BiRefNet.

coremltools 9.0's ``_cast`` handler (used by ``aten::Int`` and ``aten::Bool``)
assumes a constant input's ``.val`` is a Python scalar. Tracing BiRefNet's Swin
backbone turns the spatial dimensions into ``prim::NumToTensor`` values, whose
constant is a one-element array, so ``int(x.val)`` raises
``TypeError: only 0-dimensional arrays can be converted to Python scalars``.

coremltools ``main`` squashes that constant before converting; this module
applies the same one-line fix to the installed 9.0 frontend. The handler body
below is a copy of the 9.0 function with only that change, so the registration
table and all other ops continue to use coremltools' own implementation.

Upstream license: BSD-3-Clause, see ``LICENSE``.
"""

import numpy as np

from coremltools.converters.mil.frontend.torch import ops as _torch_ops
from coremltools.converters.mil.mil import Builder as mb


def _cast(context, node, dtype, dtype_name):
    """The 9.0 handler, with ``x.val.squeeze()`` from coremltools main."""
    inputs = _torch_ops._get_inputs(context, node, expected=1)
    x = inputs[0]
    # Input must either be a scalar or a (1 x 1 x ... x 1) tensor.
    if not (len(x.shape) == 0 or np.all([d == 1 for d in x.shape])):
        raise ValueError("input to cast must be either a scalar or a length 1 tensor")

    if x.can_be_folded_to_const():
        # If x is a compile-time constant, directly cast it to @dtype if it's
        # not one already. Squeeze so a traced NumToTensor's length-one array
        # becomes the 0-dimensional value that int()/bool() can consume.
        if not isinstance(x.val, dtype):
            value = np.asarray(x.val).squeeze()
            res = mb.const(val=dtype(value), name=node.name)
        else:
            res = x
    elif len(x.shape) > 0:
        x = mb.squeeze(x=x, name=node.name + "_item")
        res = mb.cast(x=x, dtype=dtype_name, name=node.name)
    else:
        res = mb.cast(x=x, dtype=dtype_name, name=node.name)
    context.add(res, node.name)


def register() -> None:
    """Apply the backport once, before ``ct.convert`` runs."""
    if getattr(_torch_ops, "_cast", None) is _cast:
        return
    _torch_ops._cast = _cast


register()
