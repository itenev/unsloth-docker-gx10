#!/usr/bin/env bash
# setup.sh — Build and start Unsloth Studio for the ASUS GX10 (ARM64/aarch64)
#
# Prerequisites:
#   - Docker with NVIDIA Container Toolkit installed
#   - llama.cpp built with SM_121: see README for build steps
#
# Usage:
#   chmod +x setup.sh && ./setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNSLOTH_VERSION="2026.4.8"
IMAGE_NAME="unsloth-gx10:${UNSLOTH_VERSION}"

echo "============================================================"
echo " Unsloth Studio GX10 Setup"
echo " Unsloth version : ${UNSLOTH_VERSION} (pinned)"
echo " Architecture    : $(uname -m)"
echo " Image           : ${IMAGE_NAME}"
echo "============================================================"
echo ""

# ── Step 1: Verify prerequisites ──────────────────────────────────────────────
echo "==> Step 1: Checking prerequisites..."

if ! command -v docker &>/dev/null; then
  echo "    ERROR: Docker not found. Install Docker first."
  exit 1
fi

if ! docker info --format '{{.Runtimes}}' 2>/dev/null | grep -q nvidia; then
  echo "    ERROR: NVIDIA Container Toolkit not found."
  echo "    Install with: sudo apt install nvidia-container-toolkit"
  exit 1
fi

echo "    OK — Docker + NVIDIA runtime found"

# ── Step 2: Create host directories ───────────────────────────────────────────
echo ""
echo "==> Step 2: Creating host directories..."
mkdir -p "${HOME}/models"
mkdir -p "${SCRIPT_DIR}/work"
echo "    ~/models and ./work ready"

# ── Step 3: Build the image ───────────────────────────────────────────────────
echo ""
echo "==> Step 3: Building ${IMAGE_NAME} (20-40 min on first run)..."
echo "    This compiles llama.cpp from source targeting SM_121 (Blackwell)."
echo ""

docker build \
  --build-arg UNSLOTH_VERSION="${UNSLOTH_VERSION}" \
  -t "${IMAGE_NAME}" \
  -t "unsloth-gx10:latest" \
  -f "${SCRIPT_DIR}/Dockerfile" \
  "${SCRIPT_DIR}"

echo ""
echo "==> Step 3 complete — image built successfully"

# ── Step 4: Verify SM_121 llama.cpp inside image ──────────────────────────────
echo ""
echo "==> Step 4: Verifying SM_121 llama.cpp inside image..."
LLAMA_VER=$(docker run --rm --gpus all \
  --entrypoint /root/.local/share/uv/python/cpython-3.13.9-linux-aarch64-gnu/bin/python3.13 \
  "${IMAGE_NAME}" \
  -c "import subprocess, sys; r = subprocess.run(['/root/.unsloth/llama.cpp/build/bin/llama-server','--version'], capture_output=True, text=True); print(r.stderr)" \
  2>/dev/null | grep "compute capability" || echo "    WARNING: could not verify — check manually")
echo "    ${LLAMA_VER}"

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
    echo "    WARNING: Health check timed out — check logs with:"
    echo "    docker logs -f unsloth-studio"
  fi
done

# ── Step 6: Print bootstrap password ──────────────────────────────────────────
echo ""
BOOTSTRAP_PW=$(docker exec unsloth-studio \
  cat /root/.unsloth/studio/auth/.bootstrap_password 2>/dev/null || echo "(already changed)")

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
