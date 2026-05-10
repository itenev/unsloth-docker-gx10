#!/usr/bin/env bash
# build-llama.sh — Build llama.cpp for ASUS GX10 (ARM64, SM_121 Blackwell)
#
# Must be run on the host (not inside Docker) — requires GPU access for CUDA.
#
# Usage:
#   chmod +x build-llama.sh && ./build-llama.sh

set -euo pipefail

LLAMA_SRC="${HOME}/llama.cpp"
LLAMA_BUILD="${LLAMA_SRC}/build-gpu"
LLAMA_BIN="${LLAMA_BUILD}/bin/llama-server"

echo "============================================================"
echo " llama.cpp SM_121 Build — ASUS GX10"
echo " Target : NVIDIA GB10, compute capability 12.1"
echo " Output : ${LLAMA_BUILD}/bin/"
echo "============================================================"
echo ""

# ── Step 1: Clone if needed ───────────────────────────────────────────────────
if [[ ! -d "${LLAMA_SRC}" ]]; then
  echo "==> Cloning llama.cpp..."
  git clone --depth=1 https://github.com/ggerganov/llama.cpp.git "${LLAMA_SRC}"
else
  echo "==> llama.cpp already cloned at ${LLAMA_SRC}"
  echo "    To pull latest: cd ${LLAMA_SRC} && git pull"
fi

# ── Step 2: Configure ─────────────────────────────────────────────────────────
echo ""
echo "==> Configuring for SM_121 (Blackwell)..."
mkdir -p "${LLAMA_BUILD}"
cd "${LLAMA_BUILD}"

cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_CUDA=ON \
  -DGGML_CUDA_F16=ON \
  -DCMAKE_CUDA_ARCHITECTURES=121 \
  -DCMAKE_C_COMPILER=gcc \
  -DCMAKE_CXX_COMPILER=g++ \
  -DCMAKE_CUDA_COMPILER=nvcc

# ── Step 3: Compile ───────────────────────────────────────────────────────────
echo ""
echo "==> Compiling with $(nproc) cores (2-4 minutes)..."
make -j"$(nproc)"

# ── Step 4: Verify ────────────────────────────────────────────────────────────
echo ""
echo "==> Verifying build..."
VERSION_OUT=$(${LLAMA_BIN} --version 2>&1)
echo "${VERSION_OUT}"

if echo "${VERSION_OUT}" | grep -q "compute capability 12.1"; then
  echo ""
  echo "============================================================"
  echo " Build successful — SM_121 confirmed"
  echo " Binary : ${LLAMA_BIN}"
  echo " Libs   : $(ls ${LLAMA_BUILD}/*.so* 2>/dev/null | wc -l) shared libraries found"
  echo "============================================================"
else
  echo ""
  echo "WARNING: compute capability 12.1 not found in output."
  echo "Check cmake flags and CUDA toolkit version."
  exit 1
fi
