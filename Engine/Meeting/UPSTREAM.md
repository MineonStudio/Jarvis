# Meeting engine provenance

Adapted from [Tingo](https://github.com/tancheng33/tingo), commit `e5a5bbaff1a0f2351be7414b0352acb2442ee27e` (MIT). See `vendor/Tingo-LICENSE`.

Reused pipeline: FunASR Paraformer-large int8 through sherpa-onnx, Silero VAD, CT-Transformer punctuation, CAM++ embeddings, sampled spectral clustering, pause-based chunking and duck mixing.

Jarvis exposes only Paraformer-large. Its native SwiftUI interface, ScreenCaptureKit capture and existing AI provider client communicate with this local subprocess using newline-delimited JSON. There is no HTTP server, push integration or external document synchronization. All data and models live under Jarvis Application Support.
