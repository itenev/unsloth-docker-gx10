# Unsloth Studio — ASUS Ascent GX10 (ARM64 / SM_121)

A reproducible Docker deployment of [Unsloth Studio](https://unsloth.ai) for the ASUS Ascent GX10 (NVIDIA GB10 Grace-Blackwell Superchip), with a persistent `llama-server` systemd service for always-on OpenAI-compatible inference.

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
| `docker-compose.yml` | Unsloth Studio runtime config (GPU, ports, volumes) |
| `setup.sh` | One-command build + start script for Unsloth Studio |
| `build-llama.sh` | Builds llama.cpp on host with SM_121 CUDA support |
| `llama-server.env` | llama-server configuration (model, port, GPU settings) |
| `llama-server.service` | systemd unit for persistent inference service |
| `install-service.sh` | Installs and enables llama-server as a system service |

---

## Architecture

Two services run independently and never conflict:

| Service | Port | Managed by | Purpose |
|---|---|---|---|
| Unsloth Studio | `8000` | Docker Compose | Web UI, model download, fine-tuning |
| llama-server | `8080` | systemd | Always-on OpenAI-compatible inference API |

Both share `~/models` as a unified model directory — models downloaded via Studio are immediately available to llama-server and vice versa.

---

## Known aarch64 fixes applied

| Fix | Reason |
|---|---|
| `torchcodec` installed from PyTorch index | No aarch64 wheel on PyPI |
| `torchcodec` pre-patched before `install.sh` | `install.sh` pins `0.10.0` internally; patched to `0.11.1` before it runs |
| `diceware`, `fastapi`, `passlib`, `bcrypt`, `python-jose`, `aiofiles` installed into studio venv | Missing from upstream studio venv |
| NVIDIA entrypoint overridden | `nvidia_entrypoint.sh` corrupts the exec environment |
| `PYTHONPATH` + `VIRTUAL_ENV` set explicitly | Required for Python 3.13 venv resolution without full activation |
| `install.sh` run with `--no-torch` | No GPU during `docker build`; would install CPU-only PyTorch otherwise |
| CUDA PyTorch installed into studio venv post-`install.sh` | Required for `Hardware detected: CUDA` GPU detection at runtime |
| llama.cpp compiled on host with `-DCMAKE_CUDA_ARCHITECTURES=121` | Docker build has no GPU; host build mounted over CPU-only image binary |
| llama.cpp `bin/` mounted (not parent dir) | All `.so` shared libraries are in `build-gpu/bin/` |
| `unsloth studio setup` not re-run after `install.sh` | `install.sh` already calls it; re-running triggers upstream TypeScript frontend bug |

---

## Prerequisites

- Docker 20+ with NVIDIA Container Toolkit
- User in `docker` group
- `cmake`, `gcc`, `nvcc` available on host (for llama.cpp build)

```bash
# Install NVIDIA Container Toolkit if not present
sudo apt install nvidia-container-toolkit
sudo systemctl restart docker

# Install build tools if not present
sudo apt install cmake build-essential
```

---

## Quick start

```bash
git clone <this-repo> ~/unsloth-docker-gx10
cd ~/unsloth-docker-gx10
chmod +x setup.sh build-llama.sh install-service.sh

# 1. Build SM_121 llama.cpp on host (2-4 min)
./build-llama.sh

# 2. Build and start Unsloth Studio (20-40 min first run)
./setup.sh

# 3. Install llama-server as a persistent systemd service
#    Edit llama-server.env first to set your MODEL path
./install-service.sh
```

---

## Unsloth Studio

### Accessing the UI

```
http://<gx10-ip>:8000
```

Default credentials printed by `setup.sh`. Change password on first login.

### Model storage

Models downloaded via the Studio UI are stored at:
```
~/models/.cache/huggingface/hub/
```

This directory is shared with the host and with llama-server — no duplication needed.

### Day-to-day operations

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

### Resetting the admin password

```bash
docker exec -it unsloth-studio \
  /root/.local/share/uv/python/cpython-3.13.9-linux-aarch64-gnu/bin/python3.13 \
  /root/.unsloth/studio/unsloth_studio/bin/unsloth studio reset-password

docker compose restart
docker exec unsloth-studio cat /root/.unsloth/studio/auth/.bootstrap_password
```

---

## llama-server (persistent inference API)

A systemd service that loads a model at boot and exposes an OpenAI-compatible API on port `8080`.

### Configuration

Edit `/etc/llama-server/llama-server.env`:

```bash
sudo nano /etc/llama-server/llama-server.env
```

Key settings:

| Variable | Default | Description |
|---|---|---|
| `MODEL` | Qwen3.6 27B Q4_K_XL | Full path to GGUF file |
| `HOST` | `0.0.0.0` | Listen address |
| `PORT` | `8080` | Listen port |
| `N_GPU_LAYERS` | `-1` | GPU layers (-1 = all) |
| `CONTEXT_SIZE` | `8192` | Context window tokens |
| `PARALLEL` | `4` | Concurrent request slots |

### Service management

```bash
# Status
sudo systemctl status llama-server

# Start / stop / restart
sudo systemctl start llama-server
sudo systemctl stop llama-server
sudo systemctl restart llama-server

# Follow logs
journalctl -u llama-server -f

# Enable / disable on boot
sudo systemctl enable llama-server
sudo systemctl disable llama-server
```

### API endpoints

```
http://<gx10-ip>:8080/health          # Health check
http://<gx10-ip>:8080/v1              # OpenAI-compatible base URL
http://<gx10-ip>:8080/v1/chat/completions
```

### Test with curl

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "local",
    "messages": [{"role": "user", "content": "Hello!"}],
    "stream": false
  }'
```

### Switch models

```bash
sudo nano /etc/llama-server/llama-server.env   # update MODEL=
sudo systemctl restart llama-server
```

---

## Volumes and paths

| Path | Purpose |
|---|---|
| `~/models/` | Unified model directory (shared by Studio + llama-server) |
| `~/models/.cache/huggingface/hub/` | HF cache — Studio downloads land here |
| `~/llama.cpp/build-gpu/bin/` | Host-compiled SM_121 llama.cpp binaries + shared libs |
| `/etc/llama-server/llama-server.env` | llama-server runtime config |
| Docker volume `unsloth-studio-auth` | Studio login credentials |
| `./work/` | Notebooks, training runs, exports |

---

## Pinned versions

Defined in `.env.versions`. Edit and rebuild to update.

| Component | Default |
|---|---|
| Unsloth | `latest` (pin to e.g. `2026.5.2` for reproducibility) |
| NVIDIA base image | `nvcr.io/nvidia/pytorch:25.11-py3` |
| Python (system) | 3.12 (from base image) |
| Python (studio venv) | 3.13.9 (via uv) |
| torchcodec | `0.11.1` |
| llama.cpp | Built from source at `./build-llama.sh` run time |

### Updating Unsloth

```bash
cd ~/unsloth-docker-gx10
docker compose down
docker rmi unsloth-gx10:latest 2>/dev/null || true
./setup.sh
```

### Updating llama.cpp

```bash
cd ~/llama.cpp && git pull
cd ~/unsloth-docker-gx10 && ./build-llama.sh
sudo systemctl restart llama-server
docker compose restart   # picks up new binary via bind mount
```

---

## Troubleshooting

**`Hardware detected: CPU` in Studio logs**
The llama.cpp bind mount may not be active or the binary can't find its shared libraries. Verify:
```bash
docker exec unsloth-studio ls ~/llama.cpp/build-gpu/bin/*.so | head -3
docker logs unsloth-studio 2>&1 | grep "Hardware detected"
```

**Container keeps restarting**
```bash
docker logs unsloth-studio 2>&1 | tail -30
```

**llama-server fails to start**
```bash
journalctl -u llama-server -f
# Most common cause: MODEL path in /etc/llama-server/llama-server.env is wrong
```

**`No module named 'unsloth_cli'`**
`PYTHONPATH` is not set. Verify `docker-compose.yml` contains:
```yaml
PYTHONPATH: "/root/.unsloth/studio/unsloth_studio/lib/python3.13/site-packages"
```

**GPU not detected**
```bash
docker exec unsloth-studio nvidia-smi
# Note: Memory-Usage shows "Not Supported" on GB10 — this is normal.
# Confirm GPU is active by checking temperature rise during inference
# and "Hardware detected: CUDA" in docker logs.
```

---

## Related resources

- [Unsloth Studio docs](https://unsloth.ai/docs/new/studio)
- [ASUS Ascent GX10](https://www.asus.com/ai-products/ascent-gx10/)
- [NVIDIA GB10 Grace-Blackwell](https://www.nvidia.com/en-us/products/workstations/dgx-spark/)
- [llama.cpp](https://github.com/ggerganov/llama.cpp)
