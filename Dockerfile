# Unsloth Studio — GX10 / DGX Spark (ARM64 aarch64, SM_121)
#
# Fixes baked in vs upstream Dockerfile_DGX_Spark:
#   1. torchcodec — no aarch64 wheel on PyPI; installed from pytorch index
#   2. diceware — missing from studio venv; required for bootstrap password gen
#   3. fastapi + auth deps — missing from studio venv
#   4. install.sh run to create studio venv (Python 3.13 via uv)
#   5. unsloth studio setup run to build frontend + llama.cpp (sm_121)

ARG UNSLOTH_VERSION=2026.4.8

# ── Base: official NVIDIA PyTorch image for sbsa (ARM64 server) ───────────────
FROM nvcr.io/nvidia/pytorch:25.11-py3

ENV DEBIAN_FRONTEND=noninteractive

# ── System deps ───────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    git cmake build-essential curl wget \
    libgl1 libglib2.0-0 libsm6 libxrender1 libxext6 libxcb1 \
    && rm -rf /var/lib/apt/lists/*

# ── Install pinned unsloth into system Python 3.12 ───────────────────────────
ARG UNSLOTH_VERSION
RUN pip install --no-cache-dir unsloth==${UNSLOTH_VERSION} diceware

# ── Patch torchcodec in system Python (no aarch64 wheel on PyPI) ─────────────
RUN pip install --no-cache-dir torchcodec \
    --index-url https://download.pytorch.org/whl/cu130 || \
    echo "torchcodec install skipped (non-fatal)"

# ── Run install.sh to create studio venv (Python 3.13 via uv) ────────────────
# This creates /root/.unsloth/studio/unsloth_studio/
RUN curl -fsSL https://unsloth.ai/install.sh | sh

# ── Patch torchcodec in studio venv (Python 3.13) ────────────────────────────
RUN /root/.unsloth/studio/unsloth_studio/bin/pip install --no-cache-dir \
    torchcodec --index-url https://download.pytorch.org/whl/cu130 || \
    echo "torchcodec venv install skipped (non-fatal)"

# ── Install missing auth/server deps into studio venv ────────────────────────
RUN /root/.unsloth/studio/unsloth_studio/bin/pip install --no-cache-dir \
    diceware fastapi aiofiles python-jose passlib bcrypt

# ── Run studio setup (builds frontend + llama.cpp targeting sm_121) ──────────
RUN unsloth studio setup

WORKDIR /workspace

# ── Expose ports ──────────────────────────────────────────────────────────────
# 8000 = Unsloth Studio UI
# 8888 = JupyterLab
EXPOSE 8000 8888

# ── Runtime entrypoint ────────────────────────────────────────────────────────
# Use uv Python 3.13 directly — NVIDIA's entrypoint corrupts exec environment
ENTRYPOINT ["/root/.local/share/uv/python/cpython-3.13.9-linux-aarch64-gnu/bin/python3.13"]
CMD ["/root/.unsloth/studio/unsloth_studio/bin/unsloth", "studio", "-H", "0.0.0.0", "-p", "8000"]
