#!/usr/bin/env bash
set -euo pipefail

source_url=https://github.com/MiaAI-Lab/Ornith-1.5-122B-TensorFold.git
revision=0c8fd6a0d1e2ece7557978a7d8c3d96d137eb075
image=ghcr.io/miaai-lab/ornith-1.5-122b-tensorfold
image_tag=zig-d1018b3-f5683f4c5651
image_digest=sha256:56c064d22327a6d0ce09d0de3930084b11841918072e9467a2dd9039b3d92b82
project="$HOME/.cache/spark-ornith-122b"
source_dir="$project/upstream"
name=spark-catalog-ornith
export HF_CACHE="$project/huggingface" HF_HOME="$project/huggingface"
export HF_HUB_DISABLE_IMPLICIT_TOKEN=1
export MODEL_REVISION=9c5c913b3de1eef901520d6fedaf450044ea0423
export DRAFT_REVISION=a5ed7396f5f9e5b1abf7ff50b7899a3186961432
export KERNEL_CACHE="$project/kernel-cache" STATE_DIR="$project/state"
export IMAGE_TAG="$image_tag" IMAGE_DIGEST="$image_digest"

case "${1:-}" in
  download)
    if [[ ! -d "$source_dir/.git" ]]; then
      mkdir -p "$source_dir"
      git -C "$source_dir" init -q
    fi
    if ! git -C "$source_dir" cat-file -e "$revision^{commit}" 2>/dev/null; then
      git -C "$source_dir" fetch --depth=1 "$source_url" "$revision"
    fi
    git -C "$source_dir" checkout --detach "$revision"
    if ! docker pull --platform linux/arm64 "$image@$image_digest"; then
      docker pull --platform linux/arm64 "$image:$image_tag"
    fi
    docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$image@$image_digest" \
      | grep -Fx "$image@$image_digest"
    docker image tag "$image@$image_digest" tensorfold-ornith:zig-d1018b3
    HF_HUB_DISABLE_IMPLICIT_TOKEN=1 hf download Mia-AiLab/Ornith-1.5-122B-EXL3-EAQv1-4-bpw \
      --revision "$MODEL_REVISION" --cache-dir "$HF_CACHE/hub"
    HF_HUB_DISABLE_IMPLICIT_TOKEN=1 hf download incoai/Ornith-1.5-122B-DFlash2 \
      --revision "$DRAFT_REVISION" --cache-dir "$HF_CACHE/hub"
    ;;
  start)
    test "$(git -C "$source_dir" rev-parse HEAD)" = "$revision"
    cd "$source_dir"
    env -u HF_TOKEN -u HUGGING_FACE_HUB_TOKEN HF_HUB_OFFLINE=1 \
      TMPDIR=/tmp HOST=127.0.0.1 PORT=18893 CONTAINER_NAME="$name" \
      SERVED_NAME=Ornith-1.5-122B PARALLEL=5 PULL=0 PREPARE=0 WAIT_TIMEOUT=900 bash start.sh
    ;;
  stop)
    docker stop "$name"
    docker rm "$name"
    ;;
  *)
    echo "Usage: $0 {download|start|stop}" >&2
    exit 2
    ;;
esac
