#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[INFO] Bootstrap starting"

# Ensure sudo works
if ! sudo -n true 2>/dev/null; then
  echo "[INFO] Sudo permission required"
  sudo true
fi

# If Docker exists AND is usable → normal execution
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  echo "[INFO] Docker usable; running setup"
  exec "${SCRIPT_DIR}/setup.sh"
fi

# First pass: Docker not installed or not usable
echo "[INFO] Running setup to install Docker and prerequisites"
"${SCRIPT_DIR}/setup.sh"

# If Docker usable after setup → done
if docker info >/dev/null 2>&1; then
  echo "[INFO] Docker now usable; re-running setup"
  exec "${SCRIPT_DIR}/setup.sh"
fi

# Docker installed but group not active → re-enter bootstrap
echo "[INFO] Docker group applied; re-running setup in docker group"
exec sg docker -c "${SCRIPT_DIR}/setup.sh"
