#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[INFO] Bootstrap starting"

# Ensure sudo works early
if ! sudo -n true 2>/dev/null; then
  echo "[INFO] Sudo permission required"
  sudo true
fi

# If Docker exists and is usable, run setup directly
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  exec "${SCRIPT_DIR}/setup.sh"
fi

# Otherwise, run setup once to install Docker and prerequisites
"${SCRIPT_DIR}/setup.sh"

# After setup.sh, Docker should exist; check usability
if docker info >/dev/null 2>&1; then
  exit 0
fi

# Docker installed but group membership not yet applied
echo "[INFO] Docker group change required, restarting in new group shell"
exec newgrp docker -c "${SCRIPT_DIR}/bootstrap.sh"