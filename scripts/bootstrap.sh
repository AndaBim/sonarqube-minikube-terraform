#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERROR] $*" >&2; }

log "Bootstrap starting"

# Ensure sudo works
if ! sudo -n true 2>/dev/null; then
  log "Sudo permission required"
  sudo true
fi

# If Docker is missing, run setup to install it
if ! command -v docker >/dev/null 2>&1; then
  log "Docker not installed; running setup"
  exec "${SCRIPT_DIR}/setup.sh"
fi

# If Docker works, run setup normally
if docker info >/dev/null 2>&1; then
  log "Docker usable; running setup"
  exec "${SCRIPT_DIR}/setup.sh"
fi

# Docker exists but not usable → group issue
if ! groups | grep -q '\bdocker\b'; then
  log "Docker group missing; re-running bootstrap under docker group"
  exec sg docker -c "${SCRIPT_DIR}/bootstrap.sh"
fi

# If we reach here, something is genuinely wrong
err "Docker installed and docker group present, but docker still unusable"
err "Check /var/run/docker.sock permissions or Docker daemon"
exit 1