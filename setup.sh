#!/usr/bin/env bash
# setup.sh — Build and start Unsloth Studio for the ASUS GX10 (ARM64/aarch64)
#
# All pinned versions are read from .env.versions in the same directory.
#
# Usage:
#   chmod +x setup.sh && ./setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Load pinned versions ───────────────────────────────────────────────────────
VERSIONS_FILE="${SCRIPT_DIR}/.env.versions"
if [[ ! -f "${VERSIONS_FILE}" ]]; then
  echo "ERROR: ${VERSIONS_FILE} not found."
  exit 1
fi
set -a
# shellcheck disable=SC1090
source "${VERSIONS_FILE}"
set +a

IMAGE_NAME="unsloth-gx10:${UNSLOTH_VERSION}"
LLAMA_SRC="${HOME}/llama.cpp"
LLAMA_BUILD="${LLAMA_SRC}/build-gpu"
LLAMA_BIN="${LLAMA_BUILD}/bin/llama-server"

echo "============================================================"
echo " Unsloth Studio GX10 Setup"
echo " Unsloth version  : ${UNSLOTH_VERSION}"
echo " Base image        : ${NVIDIA_BASE_IMAGE}"
echo " UV Python         : ${UV_PYTHON_VERSION}"
echo " torchcodec        : ${TORCHCODEC_VERSION}"
echo " Architecture      : $(uname -m)"
echo " Image             : ${IMAGE_NAME}"
echo "============================================================"
echo ""

# ── Step 1: Verify prerequisites ──────────────────────────────────────────────
echo "==> Step 1: Checking prerequisites..."

if ! command -v docker &>/dev/null; then
  echo "    ERROR: Docker not found."
  exit 1
fi

if ! docker info --format '{{.Runtimes}}' 2>/dev/null | grep -q nvidia; then
  echo "    ERROR: NVIDIA Container Toolkit not found."
  echo "    Install with: sudo apt install nvidia-container-toolkit"
  exit 1
fi

if ! command -v cmake &>/dev/null || ! command -v nvcc &>/dev/null; then
  echo "    Installing build dependencies..."
  sudo apt-get update -q
  sudo apt-get install -y --no-install-recommends git cmake build-essential
fi

echo "    OK — all prerequisites found"

# ── Step 2: Create host directories ───────────────────────────────────────────
echo ""
echo "==> Step 2: Creating host directories..."
mkdir -p "${HOME}/models"
mkdir -p "${SCRIPT_DIR}/work"
echo "    ~/models and ./work ready"

# ── Step 3: Build llama.cpp on host with SM_121 CUDA support ──────────────────
# Docker build has no GPU access so the image contains a CPU-only llama.cpp.
# We build a GPU version on the host and mount it over the CPU binary at runtime.
echo ""
echo "==> Step 3: Building llama.cpp for SM_121 on host..."

if [[ -f "${LLAMA_BIN}" ]]; then
  EXISTING_VER=$(${LLAMA_BIN} --version 2>&1 | grep "compute capability" || true)
  if [[ "${EXISTING_VER}" == *"12.1"* ]]; then
    echo "    SM_121 build already exists — skipping"
    echo "    ${EXISTING_VER}"
  else
    echo "    Existing build found but SM_121 not confirmed — rebuilding"
    rm -rf "${LLAMA_BUILD}"
  fi
fi

if [[ ! -f "${LLAMA_BIN}" ]]; then
  if [[ ! -d "${LLAMA_SRC}" ]]; then
    echo "    Cloning llama.cpp..."
    git clone --depth=1 https://github.com/ggerganov/llama.cpp.git "${LLAMA_SRC}"
  fi

  echo "    Configuring for SM_121..."
  mkdir -p "${LLAMA_BUILD}"
  cd "${LLAMA_BUILD}"
  cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_CUDA=ON \
    -DGGML_CUDA_F16=ON \
    -DCMAKE_CUDA_ARCHITECTURES=121

  echo "    Compiling (this takes 2-4 minutes)..."
  make -j"$(nproc)"
  cd "${SCRIPT_DIR}"

  BUILT_VER=$(${LLAMA_BIN} --version 2>&1 | grep "compute capability" || true)
  if [[ "${BUILT_VER}" == *"12.1"* ]]; then
    echo "    OK — ${BUILT_VER}"
  else
    echo "    WARNING: SM_121 not confirmed in build output"
    echo "    ${BUILT_VER}"
  fi
fi

# ── Step 4: Build the Docker image ────────────────────────────────────────────
echo ""
echo "==> Step 4: Building ${IMAGE_NAME} (20-40 min on first run)..."

docker build \
  --build-arg NVIDIA_BASE_IMAGE="${NVIDIA_BASE_IMAGE}" \
  --build-arg UNSLOTH_VERSION="${UNSLOTH_VERSION}" \
  --build-arg TORCHCODEC_VERSION="${TORCHCODEC_VERSION}" \
  --build-arg CUDA_INDEX="${CUDA_INDEX}" \
  --build-arg UV_PYTHON_VERSION="${UV_PYTHON_VERSION}" \
  -t "${IMAGE_NAME}" \
  -t "unsloth-gx10:latest" \
  -f "${SCRIPT_DIR}/Dockerfile" \
  "${SCRIPT_DIR}"

echo "    Image built successfully"

# ── Step 5: Start via docker compose ──────────────────────────────────────────
echo ""
echo "==> Step 5: Starting Unsloth Studio..."
docker compose -f "${SCRIPT_DIR}/docker-compose.yml" up -d

echo ""
echo "==> Waiting for studio to become healthy..."
for i in $(seq 1 30); do
  if curl -sf "http://localhost:8000/api/health" &>/dev/null; then
    echo "    OK — Studio is up"
    break
  fi
  sleep 2
  if [[ $i -eq 30 ]]; then
    echo "    WARNING: Health check timed out. Check logs:"
    echo "    docker logs -f unsloth-studio"
  fi
done

# ── Step 6: Verify GPU inference ──────────────────────────────────────────────
echo ""
echo "==> Step 6: Verifying GPU backend..."
GPU_CHECK=$(docker logs unsloth-studio 2>&1 | grep "Hardware detected" | tail -1)
if [[ "${GPU_CHECK}" == *"CPU"* ]]; then
  echo "    WARNING: ${GPU_CHECK}"
  echo "    llama.cpp mount may not be working — check the bind mount in docker-compose.yml"
elif [[ "${GPU_CHECK}" == *"CUDA"* ]]; then
  echo "    OK — ${GPU_CHECK}"
else
  echo "    ${GPU_CHECK}"
fi

# ── Step 7: Print access details ──────────────────────────────────────────────
BOOTSTRAP_PW=$(docker exec unsloth-studio \
  cat /root/.unsloth/studio/auth/.bootstrap_password 2>/dev/null || echo "(already changed)")

echo ""
echo "============================================================"
echo " Unsloth Studio is running!"
echo ""
echo " URL:      http://$(hostname -I | awk '{print $1}'):8000"
echo " Username: unsloth"
echo " Password: ${BOOTSTRAP_PW}"
echo ""
echo " Logs:     docker logs -f unsloth-studio"
echo " Stop:     docker compose down"
echo " Restart:  docker compose up -d"
echo "============================================================"
