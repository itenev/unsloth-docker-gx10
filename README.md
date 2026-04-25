# Unsloth Studio — ASUS Ascent GX10 (ARM64 / SM_121)

A reproducible Docker deployment of [Unsloth Studio](https://unsloth.ai) for the ASUS Ascent GX10 (NVIDIA GB10 Grace-Blackwell Superchip).

This repo fixes all known aarch64 incompatibilities in the upstream Unsloth Docker image and produces a working, self-contained build in a single command.

---

## Hardware

| | |
|---|---|
| Device | ASUS Ascent GX10 |
| SoC | NVIDIA GB10 Grace-Blackwell |
| Architecture | ARM64 (aarch64) |
| GPU compute | SM_121 (Blackwell) |
| Unified memory | 128 GB (124 GB visible to CUDA) |
| OS | DGX OS (Ubuntu 24.04) |

---

## What this repo contains

| File | Purpose |
|---|---|
| `.env.versions` | Single source of truth for all pinned versions |
| `Dockerfile` | ARM64-compatible image with all aarch64 fixes baked in |
| `docker-compose.yml` | Hardened runtime config (GPU, IPC, ports, volumes) |
| `setup.sh` | One-command build + start script |

---

## Known aarch64 fixes applied

| Fix | Reason |
|---|---|
| `torchcodec` installed from PyTorch index | No aarch64 wheel on PyPI |
| `diceware` installed into studio venv | Required for bootstrap password generation — missing from upstream |
| `fastapi`, `passlib`, `bcrypt`, `python-jose`, `aiofiles` installed into studio venv | Missing from upstream studio venv |
| NVIDIA entrypoint overridden | NVIDIA's `nvidia_entrypoint.sh` corrupts the exec environment, preventing Python from starting |
| `PYTHONPATH` + `VIRTUAL_ENV` set explicitly | Required for Python 3.13 venv to resolve studio packages without full activation |
| llama.cpp compiled from source targeting `sm_121` | No prebuilt aarch64 asset exists in unslothai/llama.cpp releases |

---

## Prerequisites

- Docker 20+ with NVIDIA Container Toolkit
- User in `docker` group
- GX10 connected to local network

Install NVIDIA Container Toolkit if not present:

```bash
sudo apt install nvidia-container-toolkit
sudo systemctl restart docker
```

---

## Quick start

```bash
git clone <this-repo> unsloth-docker-gx10
cd unsloth-docker-gx10
chmod +x setup.sh
```

Build takes **20–40 minutes** on first run — llama.cpp is compiled from source targeting SM_121.

When complete, the script prints:

```
============================================================
 Unsloth Studio is running!

 URL:      http://192.168.x.x:8000
 Username: unsloth
 Password: <bootstrap password>
============================================================
```

Open the URL, log in, and change the password when prompted.

---

## Day-to-day operations

```bash
# Start
docker compose up -d

# Stop
docker compose down

# Restart
docker compose restart

# Follow logs
docker logs -f unsloth-studio

# Shell into container
docker exec -it unsloth-studio bash
```

---

## Volumes

| Volume | Host path | Container path | Purpose |
|---|---|---|---|
| `unsloth-hf-cache` | Docker named volume | `/workspace/.cache/huggingface` | Model cache — survives rebuilds |
| `unsloth-studio-auth` | Docker named volume | `/root/.unsloth/studio/auth` | Login credentials — survives restarts |
| `./work` | `./work/` | `/workspace/work` | Notebooks, training runs, exports |
| models | `~/models/` | `/workspace/models` | GGUF model files (read-only) |

> **Important:** do not bind-mount all of `~/.unsloth/studio` into the container.
> It would overwrite the studio venv baked into the image and break startup.
> Only the `auth` subdirectory is mounted, via a named volume.

---

## Pinned versions

| Component | Version |
|---|---|
| Unsloth | `2026.4.8` |
| NVIDIA base image | `nvcr.io/nvidia/pytorch:25.11-py3` |
| Python (system) | 3.12 (from base image) |
| Python (studio venv) | 3.13.9 (via uv) |
| llama.cpp | Built from source at setup time (sm_121) |

To update any version, edit `.env.versions` and rebuild:

```bash
docker compose down
docker rmi unsloth-gx10:latest
```

---

## Ports

| Port | Service |
|---|---|
| `8000` | Unsloth Studio web UI |
| `8888` | JupyterLab |

---

## Resetting the admin password

```bash
docker exec -it unsloth-studio \
  /root/.local/share/uv/python/cpython-3.13.9-linux-aarch64-gnu/bin/python3.13 \
  /root/.unsloth/studio/unsloth_studio/bin/unsloth studio reset-password

docker compose restart
docker exec unsloth-studio cat /root/.unsloth/studio/auth/.bootstrap_password
```

---

## Troubleshooting

**Container keeps restarting**

```bash
docker logs unsloth-studio 2>&1 | tail -30
```

**`cannot execute binary file`**
The NVIDIA entrypoint is interfering. Verify `entrypoint` in `docker-compose.yml` points to the full uv Python path:

```
/root/.local/share/uv/python/cpython-3.13.9-linux-aarch64-gnu/bin/python3.13
```

**`No module named 'unsloth_cli'`**
`PYTHONPATH` is not set. Verify the `environment` section in `docker-compose.yml` includes:

```yaml
PYTHONPATH: "/root/.unsloth/studio/unsloth_studio/lib/python3.13/site-packages"
```

**GPU not detected / sm_121 not shown**

```bash
docker exec unsloth-studio nvidia-smi
```

If GPU is missing, verify `--gpus all` is active via the `deploy.resources` block in compose.

---

## Related resources

- [Unsloth Studio docs](https://unsloth.ai/docs/new/studio)
- [ASUS Ascent GX10 product page](https://www.asus.com/ai-products/ascent-gx10/)
- [NVIDIA GB10 Grace-Blackwell](https://www.nvidia.com/en-us/products/workstations/dgx-spark/)
- [llama.cpp](https://github.com/ggerganov/llama.cpp)
