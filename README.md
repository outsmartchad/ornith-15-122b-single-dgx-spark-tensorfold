# Ornith 1.5 122B on one DGX Spark

TensorFold’s native Zig runtime serves the Ornith 1.5 122B EXL3 EAQv1 4 bpw checkpoint with an IncoAI DFlash2 draft. The model API binds to `127.0.0.1:18893`.

[Benchmarks](#benchmarks) · [Runtime](#runtime) · [Quick start](#quick-start) · [Raw results](results/benchmark-2026-11-21.json)

[How the model and recipe work](docs/how-it-works.md)

## Benchmarks

Measured November 21, 2026 on one NVIDIA GB10 DGX Spark. The benchmark sent direct streaming requests to the localhost model API. Other model servers were paused.

### Decode, prose

SparkDash hash-map prompt with thinking on, temperature 0.7, top-p 1, top-k 20 and 400 generated tokens per request. Each row shows the fastest aggregate decode wave across three repetitions. Per-request decode and TTFT are medians from the same wave. TTFT counts the first streamed reasoning or answer token.

| Streams | Best aggregate tok/s | Per request tok/s | TTFT |
| ---: | ---: | ---: | ---: |
| 1 | 61.3 | 61.3 | 158 ms |
| 2 | 72.6 | 38.7 | 254 ms |
| 3 | 91.5 | 31.3 | 341 ms |
| 4 | 99.2 | 25.9 | 427 ms |
| 5 | 100.2 | 20.4 | 512 ms |

### Fresh prompt prefill

The input rate divides uncached input tokens by client TTFT. The benchmark uses an independent synthetic key for each context size and compares the response with that key.

| Prompt tokens | Input tok/s to first token | TTFT | Retrieval |
| ---: | ---: | ---: | --- |
| 32,740 | 1,968 | 16.64 s | Exact key |
| 199,952 | 986 | 202.70 s | Exact key |

## Runtime

- Pinned arm64 TensorFold image `zig-d1018b3-f5683f4c5651` and exact image digest in [serve.sh](serve.sh).
- EXL3 EAQv1 4 bpw target at `9c5c913b3de1eef901520d6fedaf450044ea0423` and DFlash2 draft at `a5ed7396f5f9e5b1abf7ff50b7899a3186961432`.
- FP8 shared KV cache, configured 262,144-token window and five simultaneous slots. The launcher reserves 10 GiB of system memory.
- Peak GPU memory was 90.4 GiB across sampled inference-container processes. Docker reported no fixed container memory limit.

## Quick start

Use a single DGX Spark with Docker, NVIDIA Container Toolkit, the Hugging Face CLI, Python 3 and curl. Allow around 63 GiB for model files plus room for the runtime image. Stop any existing model server before running this recipe.

```bash
./serve.sh download
./serve.sh start
docker logs -f spark-catalog-ornith
```

When the localhost API is ready, run the direct benchmark on the Spark.

```bash
curl -fsS http://127.0.0.1:18893/v1/models
export SPARK_BENCHMARK_URL=http://127.0.0.1:18893
export SPARK_BENCHMARK_MODEL=Ornith-1.5-122B
python3 benchmark.py > decode-local.json
python3 benchmark.py 32768 2026144868 > prefill-32768-local.json
python3 benchmark.py 200000 2026312100 > prefill-200000-local.json
./serve.sh stop
```

This recipe builds on [Mia AI Lab's pinned deployment](https://github.com/MiaAI-Lab/Ornith-1.5-122B-TensorFold/tree/0c8fd6a0d1e2ece7557978a7d8c3d96d137eb075). Our scripts, documentation and synthetic fixtures use the [MIT license](LICENSE). Upstream models and runtime components retain their own terms.
