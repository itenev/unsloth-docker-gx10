# Unsloth Studio — GX10 / DGX Spark (ARM64 aarch64, SM_121)
#
# Pinned versions defined in .env.versions, passed as build args by setup.sh.
#
# Build-time constraints:
#   - Docker build has NO GPU access — install.sh runs with --no-torch
#   - CUDA PyTorch is installed manually into the studio venv after install.sh
#   - torchcodec==0.10.0 has no aarch64 wheel — patched to 0.11.1
#   - install.sh already calls unsloth studio setup internally — not re-run

ARG NVIDIA_BASE_IMAGE=nvcr.io/nvidia/pytorch:25.11-py3
FROM ${NVIDIA_BASE_IMAGE}

# UNSLOTH_VERSION=latest installs the newest PyPI release.
# Pin to a specific version (e.g. 2026.5.2) for reproducible builds.
ARG UNSLOTH_VERSION=latest
ARG TORCHCODEC_VERSION=0.11.1
ARG CUDA_INDEX=cu130
ARG UV_PYTHON_VERSION=cpython-3.13.9-linux-aarch64-gnu

ENV DEBIAN_FRONTEND=noninteractive

# ── System deps ───────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    git cmake build-essential curl wget \
    libgl1 libglib2.0-0 libsm6 libxrender1 libxext6 libxcb1 \
    && rm -rf /var/lib/apt/lists/*

# ── Install unsloth + diceware into system Python 3.12 ───────────────────────
# Installs latest if UNSLOTH_VERSION=latest, otherwise pins to given version
RUN if [ "${UNSLOTH_VERSION}" = "latest" ]; then \
        pip install --no-cache-dir unsloth diceware; \
    else \
        pip install --no-cache-dir unsloth==${UNSLOTH_VERSION} diceware; \
    fi

# ── Patch torchcodec in system Python (no aarch64 wheel on PyPI) ─────────────
RUN pip install --no-cache-dir \
    torchcodec==${TORCHCODEC_VERSION} \
    --index-url https://download.pytorch.org/whl/${CUDA_INDEX} || \
    echo "torchcodec system install skipped (non-fatal)"

# ── Patch torchcodec requirements before install.sh runs ─────────────────────
# install.sh calls unsloth studio setup which pins torchcodec==0.10.0 (no aarch64 wheel).
# Use find to locate the extras file without importing unsloth (requires GPU).
RUN find /usr/local/lib/python3.12/dist-packages/studio \
         -name "extras-no-deps.txt" 2>/dev/null | while read f; do \
        sed -i "s|torchcodec==0.10.0|torchcodec==${TORCHCODEC_VERSION}|g" "$f"; \
        echo "Pre-patched torchcodec in $f"; \
    done || echo "extras-no-deps.txt not found yet (will be patched after install.sh)"  

# ── Run install.sh with --no-torch ───────────────────────────────────────────
# Creates studio venv, builds frontend, and runs studio setup.
# --no-torch: skip PyTorch — GPU not available during docker build.
# CUDA PyTorch is installed into the venv in the next step.
RUN curl -fsSL https://unsloth.ai/install.sh | sh -s -- --no-torch

# ── Install CUDA PyTorch into studio venv ─────────────────────────────────────
# Required for GPU detection ("Hardware detected: CUDA") at runtime.
# Must run after install.sh creates the venv.
RUN /root/.unsloth/studio/unsloth_studio/bin/pip install --no-cache-dir \
    torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/${CUDA_INDEX}

# ── Patch torchcodec in studio venv ──────────────────────────────────────────
RUN EXTRAS=/root/.unsloth/studio/unsloth_studio/lib/python3.13/site-packages/studio/backend/requirements/extras-no-deps.txt && \
    if [ -f "${EXTRAS}" ]; then \
        sed -i "s|torchcodec==0.10.0|torchcodec==${TORCHCODEC_VERSION}|g" "${EXTRAS}"; \
    fi && \
    /root/.unsloth/studio/unsloth_studio/bin/pip install --no-cache-dir \
        torchcodec==${TORCHCODEC_VERSION} \
        --index-url https://download.pytorch.org/whl/${CUDA_INDEX} || \
    echo "torchcodec venv install skipped (non-fatal)"

# ── Install missing auth/server deps into studio venv ────────────────────────
RUN /root/.unsloth/studio/unsloth_studio/bin/pip install --no-cache-dir \
    diceware fastapi aiofiles python-jose passlib bcrypt

WORKDIR /workspace

EXPOSE 8000 8888

# Entrypoint is set in docker-compose.yml using the hardcoded uv Python path
# from UV_PYTHON_VERSION in .env.versions
CMD ["/root/.unsloth/studio/unsloth_studio/bin/unsloth", \
     "studio", "-H", "0.0.0.0", "-p", "8000"]
