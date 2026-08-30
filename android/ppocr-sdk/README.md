# PaddleOCR Android SDK

This directory vendors the official PaddleOCR Android SDK pipeline used by
航迹的图片导入功能. It runs PP-OCRv6 small locally through ONNX Runtime and
OpenCV, so screenshots are not uploaded to a server.

The model files under `src/main/assets/models/` are downloaded from the official
PaddlePaddle BOS artifacts:

- `PP-OCRv6_small_det_onnx_infer`
- `PP-OCRv6_small_rec_onnx_infer`

The SDK source is Apache-2.0 licensed; see `PADDLEOCR-LICENSE`. Model licenses
and notices are provided by PaddlePaddle alongside the corresponding release.
