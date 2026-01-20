#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# SonarQube on Minikube - Automated Setup Script 
#
# Goal:
#   - Install prerequisites (Docker, kubectl, Helm, Terraform, Minikube)
#   - Start Minikube and enable NGINX ingress
#   - Deploy PostgreSQL (separate Helm chart) + SonarQube via Terraform
#   - Wait until workloads are ready
#   - Print access instructions (Linux ingress host + local service URL)
#
# Assumptions:
#   - Ubuntu Server / Ubuntu under WSL2
#   - User has sudo privileges
#   - Outbound internet access available
# -----------------------------------------------------------------------------

# -----------------------------
# Version pins 
# -----------------------------
MINIKUBE_VERSION="${MINIKUBE_VERSION:-v1.32.0}"
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.28.3}"
HELM_VERSION="${HELM_VERSION:-v3.13.3}"
TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.6.6}"

# -----------------------------
# Minikube sizing 
# -----------------------------
MINIKUBE_CPUS="${MINIKUBE_CPUS:-2}"
MINIKUBE_MEMORY_MB="${MINIKUBE_MEMORY_MB:-4096}"

# -----------------------------
# Paths
# -----------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform"

# -----------------------------
# Logging helpers
# -----------------------------
log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERROR] $*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

sudo_keepalive() {
  # Cache sudo credentials early; fail fast if user cannot sudo
  if ! sudo -n true 2>/dev/null; then
    log "Sudo permission required. You may be prompted for your password."
  fi
  sudo true
}

detect_ubuntu() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
      warn "Detected OS ID=${ID:-unknown}. This script is intended for Ubuntu."
    fi
    log "Detected OS: ${PRETTY_NAME:-unknown}"
  else
    warn "Unable to detect OS (/etc/os-release missing). Proceeding anyway."
  fi
}

install_base_dependencies() {
  log "Installing base system dependencies"
  sudo apt-get update -y
  sudo apt-get install -y \
    ca-certificates \
    curl \
    git \
    gnupg \
    lsb-release \
    apt-transport-https \
    unzip \
    jq
}

install_docker() {
  if need_cmd docker; then
    log "Docker already installed, skipping"
    return 0
  fi

  log "Installing Docker"
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  local codename
  codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Enable + start service
  sudo systemctl enable docker >/dev/null 2>&1 || true
  sudo systemctl start docker >/dev/null 2>&1 || true

  # Ensure docker group exists and add current user
  sudo groupadd docker >/dev/null 2>&1 || true
  sudo usermod -aG docker "$USER" >/dev/null 2>&1 || true

  log "Docker installed. Ensuring the script continues with docker group permissions."
}

ensure_docker_access_or_reexec() {
  # If docker requires sudo, Minikube (docker driver) can fail for non-root.
  # We re-exec the script under the docker group using 'sg', avoiding logout/login.
  if docker info >/dev/null 2>&1; then
    log "Docker is usable without sudo"
    return 0
  fi

  if groups | tr ' ' '\n' | grep -qx docker; then
    # User is in docker group but session may not have picked it up yet.
    # Re-exec under docker group to apply group membership in this run.
    if [[ "${REEXEC_UNDER_DOCKER_GROUP:-}" != "1" ]]; then
      log "Re-executing script under 'docker' group (no logout required)"
      export REEXEC_UNDER_DOCKER_GROUP="1"
      exec sg docker -c "$0 ${*:-}"
    fi
  fi

  # Last attempt: if still failing, stop with a clear error.
  err "Docker is not usable without sudo, and group escalation did not succeed."
  err "Please run: newgrp docker  (or log out/in), then rerun: ./scripts/setup.sh"
  exit 1
}

install_minikube() {
  if need_cmd minikube; then
    log "Minikube already installed, skipping"
    return 0
  fi

  log "Installing Minikube (${MINIKUBE_VERSION})"
  curl -fsSL -o /tmp/minikube.deb "https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/minikube_${MINIKUBE_VERSION#v}-0_amd64.deb"
  sudo dpkg -i /tmp/minikube.deb
  rm -f /tmp/minikube.deb
}

install_kubectl() {
  if need_cmd kubectl; then
    log "kubectl already installed, skipping"
    return 0
  fi

  log "Installing kubectl (${KUBECTL_VERSION})"
  curl -fsSL -o /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm -f /tmp/kubectl
}

install_helm() {
  if need_cmd helm; then
    log "Helm already installed, skipping"
    return 0
  fi

  log "Installing Helm (${HELM_VERSION})"
  curl -fsSL -o /tmp/helm.tar.gz "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
  tar -xzf /tmp/helm.tar.gz -C /tmp
  sudo install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
  rm -rf /tmp/helm.tar.gz /tmp/linux-amd64
}

install_terraform() {
  if need_cmd terraform; then
    log "Terraform already installed, skipping"
    return 0
  fi

  log "Installing Terraform (${TERRAFORM_VERSION})"
  curl -fsSL -o /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
  unzip -o /tmp/terraform.zip -d /tmp >/dev/null
  sudo install -m 0755 /tmp/terraform /usr/local/bin/terraform
  rm -f /tmp/terraform.zip /tmp/terraform
}

start_minikube() {
  log "Starting Minikube cluster (driver=docker, cpus=${MINIKUBE_CPUS}, memory=${MINIKUBE_MEMORY_MB}MB)"
  # If cluster already exists, start is idempotent.
  minikube start \
    --driver=docker \
    --cpus="${MINIKUBE_CPUS}" \
    --memory="${MINIKUBE_MEMORY_MB}mb" \
    --kubernetes-version="${KUBECTL_VERSION#v}" >/dev/null

  log "Waiting for Kubernetes node to become Ready"
  kubectl wait --for=condition=Ready nodes --all --timeout=300s >/dev/null
}

enable_ingress() {
  log "Enabling NGINX ingress controller (Minikube addon)"
  minikube addons enable ingress >/dev/null || true

  log "Waiting for ingress controller to be Ready"
  kubectl wait \
    --namespace ingress-nginx \
    --for=condition=Ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=300s >/dev/null
}

ensure_hosts_entry_linux() {
  # On native Linux, map sonarqube.local -> minikube ip for convenience.
  # On WSL2, this only affects WSL itself (Windows host uses its own hosts file).
  local ip
  ip="$(minikube ip)"
  if grep -qE "^[[:space:]]*${ip}[[:space:]]+sonarqube\.local([[:space:]]+|$)" /etc/hosts 2>/dev/null; then
    log "/etc/hosts already contains sonarqube.local mapping (${ip})"
    return 0
  fi

  # Remove any stale sonarqube.local lines (best effort), then add current mapping.
  log "Ensuring /etc/hosts contains sonarqube.local -> ${ip} (Linux/WSL convenience)"
  sudo sed -i.bak '/[[:space:]]sonarqube\.local$/d' /etc/hosts 2>/dev/null || true
  echo "${ip} sonarqube.local" | sudo tee -a /etc/hosts >/dev/null
}

tf_apply() {
  if [[ ! -d "${TERRAFORM_DIR}" ]]; then
    err "Terraform directory not found: ${TERRAFORM_DIR}"
    exit 1
  fi

  log "Deploying Kubernetes resources via Terraform"
  pushd "${TERRAFORM_DIR}" >/dev/null
  terraform init -input=false >/dev/null
  terraform apply -auto-approve
  popd >/dev/null
}

wait_for_namespace() {
  local ns="$1"
  log "Waiting for namespace '${ns}' to exist"
  for _ in $(seq 1 60); do
    if kubectl get ns "${ns}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  err "Namespace '${ns}' did not appear in time"
  exit 1
}

wait_for_pods_ready() {
  local ns="$1"
  local selector="$2"
  local timeout="$3"

  # kubectl wait expects timeout like 600s
  log "Waiting for pods in namespace '${ns}' with selector '${selector}' to become Ready (timeout ${timeout})"
  if kubectl wait --namespace "${ns}" --for=condition=Ready pod --selector="${selector}" --timeout="${timeout}" >/dev/null 2>&1; then
    return 0
  fi

  warn "Pod readiness wait failed for selector '${selector}'. Showing diagnostics:"
  kubectl get pods -n "${ns}" -o wide || true
  kubectl get events -n "${ns}" --sort-by=.lastTimestamp | tail -n 50 || true
  return 1
}

verify_http_via_port_forward() {
  # To avoid environment-specific ingress routing issues (notably Windows+WSL).
  # It gives a "service responds" check.
  log "Verifying SonarQube HTTP readiness via port-forward (localhost:9000)"
  kubectl -n sonarqube port-forward svc/sonarqube-sonarqube 9000:9000 >/dev/null 2>&1 &
  local pf_pid=$!

  # Ensure cleanup if script exits early
  trap 'kill "${pf_pid}" >/dev/null 2>&1 || true' EXIT

  # Wait a moment for port-forward to bind
  sleep 3

  # Poll API status until UP or timeout
  for _ in $(seq 1 90); do
    if curl -fsS "http://127.0.0.1:9000/api/system/status" | jq -e '.status' >/dev/null 2>&1; then
      log "SonarQube is responding on localhost:9000"
      kill "${pf_pid}" >/dev/null 2>&1 || true
      trap - EXIT
      return 0
    fi
    sleep 2
  done

  warn "SonarQube did not respond in time via port-forward. Showing pod status:"
  kubectl get pods -n sonarqube -o wide || true
  return 1
}

print_access_instructions() {
  local mk_ip
  mk_ip="$(minikube ip)"

  echo
  echo "---------------------------------------------------------------------"
  echo "Setup completed."
  echo
  echo "Access instructions:"
  echo
  echo "1) Native Linux (Ubuntu Server):"
  echo "   - Ensure DNS/hosts resolves sonarqube.local -> ${mk_ip}"
  echo "   - Open:"
  echo "       http://sonarqube.local"
  echo
  echo "2) Windows + WSL2 (recommended access method from Windows browser):"
  echo "   - Run the following in WSL (keep the terminal open while you browse):"
  echo "       minikube service sonarqube-sonarqube -n sonarqube --url"
  echo "   - Open the printed http://127.0.0.1:<port> URL in your Windows browser."
  echo
  echo "Verification (optional):"
  echo "  kubectl get pods -n sonarqube"
  echo "  kubectl get ingress -n sonarqube"
  echo "---------------------------------------------------------------------"
  echo
}

preflight() {
  log "Running pre-flight checks"
  detect_ubuntu
  sudo_keepalive

  if [[ ! -d "${TERRAFORM_DIR}" ]]; then
    err "Expected Terraform directory not found: ${TERRAFORM_DIR}"
    err "Run this script from the repository (or keep repo layout intact)."
    exit 1
  fi

  log "Pre-flight checks passed"
}

main() {
  preflight

  install_base_dependencies
  install_docker

  # Ensure docker permissions are effective in this run (no manual logout)
  ensure_docker_access_or_reexec "$@"

  install_minikube
  install_kubectl
  install_helm
  install_terraform

  start_minikube
  enable_ingress

  # Convenience mapping for Linux/WSL; Windows uses its own hosts file.
  ensure_hosts_entry_linux

  tf_apply

  wait_for_namespace "sonarqube"

  # Wait for PostgreSQL and SonarQube pods.
  # These selectors assume the chart labels used in this repo:
  # - PostgreSQL custom chart: app=postgresql
  # - SonarQube chart: app=sonarqube
  wait_for_pods_ready "sonarqube" "app=postgresql" "600s" || true
  wait_for_pods_ready "sonarqube" "app=sonarqube" "900s" || true

  # HTTP readiness check (not depending on ingress routing)
  verify_http_via_port_forward || warn "HTTP readiness check did not confirm within timeout."

  print_access_instructions
}

main "$@"
