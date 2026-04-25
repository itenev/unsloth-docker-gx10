# Unsloth Studio — GX10 / DGX Spark (ARM64 aarch64, SM_121)
#
# Pinned versions are defined in .env.versions
# Build args are passed in by setup.sh via --build-arg

ARG NVIDIA_BASE_IMAGE=nvcr.io/nvidia/pytorch:25.11-py3
FROM ${NVIDIA_BASE_IMAGE}

ARG UNSLOTH_VERSION=2026.4.8
ARG TORCHCODEC_VERSION=0.11.1
ARG CUDA_INDEX=cu130

ENV DEBIAN_FRONTEND=noninteractive

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

# ── Run install.sh to create studio venv (Python 3.13 via uv) ────────────────
RUN curl -fsSL https://unsloth.ai/install.sh | sh

# ── Patch torchcodec in studio venv (Python 3.13) ────────────────────────────
RUN /root/.unsloth/studio/unsloth_studio/bin/pip install --no-cache-dir \
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
# UV_PYTHON_VERSION must match what install.sh downloads at build time.
# Check /root/.local/share/uv/python/ if this needs updating after a rebuild.
ARG UV_PYTHON_VERSION=cpython-3.13.9-linux-aarch64-gnu
ENV UV_PYTHON_VERSION=${UV_PYTHON_VERSION}

ENTRYPOINT ["/bin/sh", "-c", \
    "exec /root/.local/share/uv/python/${UV_PYTHON_VERSION}/bin/python3.13 \"$@\"", "--"]
CMD ["/root/.unsloth/studio/unsloth_studio/bin/unsloth", \
     "studio", "-H", "0.0.0.0", "-p", "8000"]
