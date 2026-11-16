from .wrapper import MobileNetV2Backbone

SUPPORTED_BACKBONES = {"mobilenetv2": MobileNetV2Backbone}

__all__ = ["SUPPORTED_BACKBONES", "MobileNetV2Backbone"]
