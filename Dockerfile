# Unsloth Studio — GX10 / DGX Spark (ARM64 aarch64, SM_121)
#
# Pinned versions are defined in .env.versions and passed in as build args.
#
# Key build-time constraints:
#   - Docker build has NO GPU access — install.sh must run with --no-torch
#     since the NVIDIA base image already provides the correct PyTorch build
#   - torchcodec==0.10.0 is hardcoded in studio's extras-no-deps.txt but has
#     no aarch64 wheel — patched to 0.11.1 before setup runs

ARG NVIDIA_BASE_IMAGE=nvcr.io/nvidia/pytorch:25.11-py3
FROM ${NVIDIA_BASE_IMAGE}

ARG UNSLOTH_VERSION=2026.4.8
ARG TORCHCODEC_VERSION=0.11.1
ARG CUDA_INDEX=cu130
ARG UV_PYTHON_VERSION=cpython-3.13.9-linux-aarch64-gnu

ENV DEBIAN_FRONTEND=noninteractive
ENV UV_PYTHON_VERSION=${UV_PYTHON_VERSION}

# ── System deps ───────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    git cmake build-essential curl wget \
    libgl1 libglib2.0-0 libsm6 libxrender1 libxext6 libxcb1 \
    && rm -rf /var/lib/apt/lists/*

# ── Install pinned unsloth + diceware into system Python 3.12 ─────────────────
RUN pip install --no-cache-dir \
    unsloth==${UNSLOTH_VERSION} \
    diceware

# ── Patch torchcodec in system Python (no aarch64 wheel on PyPI) ─────────────
RUN pip install --no-cache-dir \
    torchcodec==${TORCHCODEC_VERSION} \
    --index-url https://download.pytorch.org/whl/${CUDA_INDEX} || \
    echo "torchcodec system install skipped (non-fatal)"

# ── Run install.sh with --no-torch ───────────────────────────────────────────
# --no-torch: skip PyTorch install — the NVIDIA base image already has the
#   correct CUDA-enabled PyTorch for aarch64. install.sh would otherwise
#   install a CPU-only build (no GPU visible during docker build).
# The script still creates the studio venv and installs all other deps.
RUN curl -fsSL https://unsloth.ai/install.sh | sh -s -- --no-torch

# ── Patch torchcodec in studio venv BEFORE setup runs ────────────────────────
# install.sh pins torchcodec==0.10.0 in extras-no-deps.txt but no aarch64
# wheel exists for that version. Patch to 0.11.1 which has aarch64 support.
RUN EXTRAS=/root/.unsloth/studio/unsloth_studio/lib/python3.13/site-packages/studio/backend/requirements/extras-no-deps.txt && \
    if [ -f "${EXTRAS}" ]; then \
        sed -i "s|torchcodec==0.10.0|torchcodec==${TORCHCODEC_VERSION}|g" "${EXTRAS}"; \
        echo "Patched torchcodec in ${EXTRAS}"; \
    fi && \
    /root/.unsloth/studio/unsloth_studio/bin/pip install --no-cache-dir \
        torchcodec==${TORCHCODEC_VERSION} \
        --index-url https://download.pytorch.org/whl/${CUDA_INDEX} || \
    echo "torchcodec venv install skipped (non-fatal)"

# ── Install missing auth/server deps into studio venv ────────────────────────
RUN /root/.unsloth/studio/unsloth_studio/bin/pip install --no-cache-dir \
    diceware fastapi aiofiles python-jose passlib bcrypt

# ── Run studio setup (builds frontend + llama.cpp targeting sm_121) ──────────
RUN unsloth studio setup

WORKDIR /workspace

EXPOSE 8000 8888

# ── Runtime entrypoint ────────────────────────────────────────────────────────
# Use uv Python 3.13 directly — NVIDIA's entrypoint corrupts the exec environment.
# UV_PYTHON_VERSION is set as ENV above so the shell can expand it at runtime.
ENTRYPOINT ["/bin/sh", "-c", \
    "exec /root/.local/share/uv/python/${UV_PYTHON_VERSION}/bin/python3.13 \"$@\"", "--"]
CMD ["/root/.unsloth/studio/unsloth_studio/bin/unsloth", \
     "studio", "-H", "0.0.0.0", "-p", "8000"]
