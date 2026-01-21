#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[INFO] Bootstrap starting"

# Ensure sudo is available
if ! sudo -n true 2>/dev/null; then
  echo "[INFO] Sudo permission required"
  sudo true
fi

# Check docker availability
if ! command -v docker >/dev/null 2>&1; then
  echo "[ERROR] Docker not installed. This should not happen."
  exit 1
fi

# Check if user can run docker
if docker info >/dev/null 2>&1; then
  echo "[INFO] Docker usable without group change"
  exec "${SCRIPT_DIR}/setup.sh"
fi

# Docker exists but not usable → fix group
echo "[INFO] Docker installed but not usable by current user"
echo "[INFO] Adding user '$USER' to docker group"

sudo usermod -aG docker "$USER"

echo "[INFO] Restarting script in a new docker group shell"

exec newgrp docker -c "${SCRIPT_DIR}/setup.sh"
