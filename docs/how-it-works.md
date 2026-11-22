# How the Ornith 1.5 122B recipe works

## How the model works

The target is the [Mia AI Lab Ornith 1.5 122B EXL3 EAQv1 checkpoint](https://huggingface.co/Mia-AiLab/Ornith-1.5-122B-EXL3-EAQv1-4-bpw/tree/9c5c913b3de1eef901520d6fedaf450044ea0423), packed for TensorFold at 4 bpw. The original [Ornith model card](https://huggingface.co/ornith-ai/Ornith-1.5-122B) and its [config](https://huggingface.co/ornith-ai/Ornith-1.5-122B/blob/main/config.json) describe a 48-layer Qwen3.5-MoE VLM with 3,072 hidden width, 32 attention heads, 2 KV heads, 256 experts per MoE layer, and 8 routed plus 1 shared expert active per token. The layer pattern is 36 linear Gated DeltaNet layers and 12 full-attention layers, grouped as three linear layers before each full-attention layer. The model has one MTP layer and a 27-layer vision tower. The public recipe pairs it with the [IncoAI DFlash2 draft](https://huggingface.co/incoai/Ornith-1.5-122B-DFlash2/tree/a5ed7396f5f9e5b1abf7ff50b7899a3186961432). The pinned upstream deployment is [MiaAI-Lab/Ornith-1.5-122B-TensorFold](https://github.com/MiaAI-Lab/Ornith-1.5-122B-TensorFold/tree/0c8fd6a0d1e2ece7557978a7d8c3d96d137eb075).

The verified inference topology is a large EXL3 target plus a separate DFlash2 proposal model, with TensorFold's native Zig scheduler managing the two. EXL3's effective bits-per-weight is a storage average over per-module quantization groups and calibration metadata, so `4 bpw` estimates the storage scale of the packed weights. The verified cache path is FP8 shared KV with a 262,144-token request window and five serving slots.

For a request, TensorFold tokenizes and applies the model template, prefills the target and stores KV state, then decodes. DFlash2 proposes continuations and the target verifies them. The public benchmark's `thinking: true` workload streams reasoning tokens, so TTFT is the first reasoning or answer token. The synthetic retrieval probe checks that long prefill preserved the inserted key.

## How this recipe runs it on one DGX Spark

```text
OpenAI client → 127.0.0.1:18893/v1 → TensorFold Zig HTTP server
             → EXL3 Ornith target + DFlash2 draft → streamed tokens
```

`./serve.sh download` checks out the upstream recipe at `0c8fd6a...`, pulls the pinned ARM64 image `zig-d1018b3-f5683f4c5651`, and downloads both revisions. `./serve.sh start` runs the upstream `start.sh` offline with `PARALLEL=5`, `PORT=18893`, and `max_model_len=262144` as recorded by the benchmark. The launch script reserves 10 GiB of host memory and uses a kernel cache plus state directory. Use `docker logs -f spark-catalog-ornith` until `/v1/models` responds.

TensorFold's relevant optimizations are EXL3 weight packing, native Zig kernels, FP8 KV storage, continuous scheduling across five slots, and DFlash2 speculative execution. Together these choices reduce weight traffic and amortize target work. Measuring each contribution requires a matched one-variable trial or profiler trace. The image is pinned by digest in [`serve.sh`](../serve.sh), which is the runtime source of truth.

### Capacity and measured limits

The 122B target's packed weights need about 63 GiB before runtime state. The measured GPU-process peak was **90.4 GiB** and Docker had no fixed memory cap. One stream reached **61.3 tok/s**, while five streams reached **100.2 aggregate tok/s**. Fresh prompts measured **1,968 input tok/s and 16.64 s TTFT at 32,740 tokens**, then **986 input tok/s and 202.70 s TTFT at 199,952 tokens**. Both retrieval checks returned the exact key. These values are from [`results/benchmark-2026-11-21.json`](../results/benchmark-2026-11-21.json).

Five requests at the API limit would span 1,310,720 token positions before scheduler overhead. The benchmark exercises short concurrent requests and a separate long prefill test. Weight residency, KV growth, and target verification dominate memory and latency. DFlash 2 predicts a block in parallel, then scores adjacent candidates to select a coherent draft before target verification. Acceptance remains an open measurement for this recipe. [DFlash paper](https://arxiv.org/abs/2602.06036) · [DFlash 2 design](https://inco.ai/blog/dflash2/)
