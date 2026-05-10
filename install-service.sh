#!/usr/bin/env bash
# install-service.sh — Install llama-server as a systemd service on the GX10
#
# Installs:
#   /etc/llama-server/llama-server.env   — configuration (edit to change model/port)
#   /etc/systemd/system/llama-server.service — systemd unit
#
# Usage:
#   chmod +x install-service.sh && ./install-service.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="llama-server"
ENV_DIR="/etc/llama-server"
ENV_FILE="${ENV_DIR}/${SERVICE_NAME}.env"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LLAMA_BIN="${HOME}/llama.cpp/build-gpu/bin/llama-server"

echo "============================================================"
echo " llama-server systemd service installer"
echo " Port    : 8080"
echo " Binary  : ${LLAMA_BIN}"
echo "============================================================"
echo ""

# ── Verify llama.cpp build exists ─────────────────────────────────────────────
echo "==> Checking llama-server binary..."
if [[ ! -f "${LLAMA_BIN}" ]]; then
  echo "    ERROR: ${LLAMA_BIN} not found."
  echo "    Run ./build-llama.sh first."
  exit 1
fi
echo "    OK — ${LLAMA_BIN}"

# ── Verify model path in env file ─────────────────────────────────────────────
echo ""
echo "==> Checking model path..."
MODEL=$(grep "^MODEL=" "${SCRIPT_DIR}/llama-server.env" | cut -d= -f2-)
if [[ ! -f "${MODEL}" ]]; then
  echo "    ERROR: Model not found at:"
  echo "    ${MODEL}"
  echo ""
  echo "    Edit llama-server.env and set MODEL= to a valid .gguf path."
  echo "    Available GGUFs:"
  find "${HOME}/models" -name "*.gguf" 2>/dev/null | grep -v mmproj | head -10
  exit 1
fi
echo "    OK — $(basename ${MODEL})"

# ── Install env file ───────────────────────────────────────────────────────────
echo ""
echo "==> Installing config to ${ENV_FILE}..."
sudo mkdir -p "${ENV_DIR}"
sudo cp "${SCRIPT_DIR}/llama-server.env" "${ENV_FILE}"
sudo chmod 644 "${ENV_FILE}"
echo "    Done"

# ── Install systemd unit ───────────────────────────────────────────────────────
echo ""
echo "==> Installing systemd unit to ${SERVICE_FILE}..."
# Expand $HOME in service file to the actual path
sed "s|/home/itenev|${HOME}|g" \
  "${SCRIPT_DIR}/llama-server.service" | sudo tee "${SERVICE_FILE}" > /dev/null
sudo chmod 644 "${SERVICE_FILE}"
echo "    Done"

# ── Enable and start ───────────────────────────────────────────────────────────
echo ""
echo "==> Enabling and starting llama-server..."
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}"
sudo systemctl restart "${SERVICE_NAME}"

# ── Wait for server to come up ─────────────────────────────────────────────────
echo ""
echo "==> Waiting for llama-server to become ready..."
for i in $(seq 1 30); do
  if curl -sf "http://localhost:8080/health" &>/dev/null; then
    echo "    OK — llama-server is up"
    break
  fi
  sleep 2
  if [[ $i -eq 30 ]]; then
    echo "    WARNING: Health check timed out. Check logs:"
    echo "    journalctl -u llama-server -f"
  fi
done

echo ""
echo "============================================================"
echo " llama-server is running!"
echo ""
echo " Inference endpoint : http://$(hostname -I | awk '{print $1}'):8080"
echo " OpenAI-compatible  : http://$(hostname -I | awk '{print $1}'):8080/v1"
echo " Health             : http://$(hostname -I | awk '{print $1}'):8080/health"
echo ""
echo " Logs    : journalctl -u llama-server -f"
echo " Stop    : sudo systemctl stop llama-server"
echo " Start   : sudo systemctl start llama-server"
echo " Restart : sudo systemctl restart llama-server"
echo " Config  : sudo nano ${ENV_FILE}"
echo "============================================================"
