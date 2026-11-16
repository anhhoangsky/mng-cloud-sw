# Conversion test assets

- `portrait.jpg` — the MediaPipe sample portrait
  (`storage.googleapis.com/mediapipe-assets/portrait.jpg`, 176,561 bytes,
  SHA-256 `a6f11efaa834706db23f275b6115058fa87fc7f14362681e6abe14e82749de3e`).
  MediaPipe sample assets are published under the Apache-2.0 license.

The conversion pipeline runs every model on two deterministic inputs: a
synthetic geometric tensor and this portrait. The synthetic tensor catches
row/column flips; the portrait gives the hair parser and the matting model
non-empty outputs, so IoU and 8-bit drift mean something.

The asset is used only by `tools/ai/convert_coreml.py`. It is not bundled into
the iOS app.
