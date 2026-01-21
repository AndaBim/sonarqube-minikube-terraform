# SonarQube on Minikube using Terraform

## Overview

This repository provides a **fully automated** deployment of **SonarQube** on a local **Kubernetes (Minikube)** cluster using **Terraform** and **Helm**.

The solution is designed to meet the assignment requirement that **no manual intervention** is needed after execution: a reviewer runs **one script**, waits for completion, and then opens SonarQube in a browser.

The automation covers:
- system prerequisites
- Docker and Kubernetes tooling
- Minikube cluster creation
- NGINX ingress controller
- PostgreSQL (external, separate Helm chart)
- SonarQube with persistent storage 
- readiness and verification checks

---

## System Requirements

Tested on:
- Ubuntu Server 22.04 
- Ubuntu Desktop 24.04
- Ubuntu on WSL2 (Windows)

### Minimum recommended resources

| Resource | Minimum | Recommended | Notes |
|--------|--------|------------|------|
| CPU | 2 vCPUs | 4 vCPUs | Affects startup time |
| Memory | 6 GB RAM | 8 GB RAM | SonarQube is memory-intensive |
| Disk | 16 GB total | 20+ GB total | Docker + Minikube consume significant space |
| Internet | Required | Required | Images, Helm charts, packages |


> Disk space is critical: Docker images, Minikube, PostgreSQL, and SonarQube together consume several gigabytes.
> During testing, a server with only ~12 GB total disk space was prone to failures due to Docker image and Minikube storage requirements, even when free space initially appeared sufficient.
> Note: SonarQube startup time can vary significantly depending on available CPU, memory, and disk performance. On slower virtual machines, the initial deployment may take up to 20–30 minutes.

### Prerequisites
    Ubuntu Server (any recent LTS)
    Bash
    curl
    git

---
## Tool Versions and Pinning

To ensure reproducible and predictable behavior, key tooling versions are **explicitly pinned** in this project.

The goal is not to always use the latest versions, but to use **known-working combinations** that are compatible with each other and with Minikube.

### Pinned components

| Tool | Version | Rationale |
|-----|--------|-----------|
| Minikube | v1.32.0 | Stable release with Docker driver support |
| Kubernetes | v1.28.x | Default Minikube version, widely supported |
| Terraform | v1.6.x | Stable, non-experimental provider behavior |
| Helm | v3.13.x | Helm 3 (no Tiller), mature chart handling |
| PostgreSQL | 15 | Supported by SonarQube and stable |
| SonarQube | 10.5 Community | Current LTS-compatible community release |

### Why versions are pinned

- Prevents breaking changes during evaluation
- Avoids incompatibilities between Kubernetes, Helm, and Terraform providers
- Ensures the reviewer can reproduce the same result consistently

Upgrading versions was considered out of scope for this assignment and intentionally left as a manual decision.

---

## Execution Model (Important)

- The script **must be run by a non-root user**
- That user **must have sudo privileges**
- `sudo` is used **only when required** (package installation, system configuration)
- **Do NOT run the script as `root`**

This is intentional:
- Minikube (Docker driver) **refuses to run as root**
- Running everything as root breaks cluster creation

---
## Repository Structure
.
├── README.md
├── scripts/
│   ├── bootstrap.sh        # Entry point (handles docker group logic)
│   └── setup.sh            # Main automation script
├── terraform/
│   ├── main.tf             # Namespace + Helm releases
│   ├── providers.tf        # Kubernetes & Helm providers
│   ├── versions.tf         # Provider constraints
│   └── values/
│       ├── postgresql.yaml # PostgreSQL values
│       └── sonarqube.yaml  # SonarQube values
├── helm/
│   └── postgresql/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── service.yaml
│           └── statefulset.yaml

---

## How to Run

### 1. Clone the repository

    git clone <REPOSITORY_URL>
    cd sonarqube-minikube-terraform

### 2. Make scripts executable

    chmod +x scripts/bootstrap.sh scripts/setup.sh

### 3. Run the bootstrap script from the project root directory

    ./scripts/bootstrap.sh


The bootstrap script:

- ensures Docker is usable
- handles Docker group membership if needed
- runs the full setup automatically

Note! setup.sh may run more than once to apply Docker group membership; all steps are idempotent.

---

## What Happens During Setup

The automation performs the following steps in order:

1. Pre-flight checks (OS, sudo access, disk space)
2. Installation of base dependencies
3. Docker verification
4. Minikube cluster creation (Docker driver)
5. Kubernetes readiness checks
6. NGINX ingress controller enablement
7. Terraform apply:
   - Kubernetes namespace creation
   - PostgreSQL Helm release
   - SonarQube Helm release
8. Pod readiness verification
9. HTTP availability check

---

## Accessing SonarQube

### Native Linux (Ubuntu Server)

1. Ensure DNS/hosts resolution exists:

    sonarqube.local -> <minikube IP>

2. Then open:

    http://sonarqube.local

### Windows + WSL2

1. When running Minikube inside WSL2 using the Docker driver, the Minikube internal network (e.g. 192.168.49.0/24) was not routable from the Windows host. As a result, the Ingress host (sonarqube.local) may be reachable from inside WSL but it was not from a Windows browser.
In this case, Minikube’s service URL output was used as the browser endpoint:

    minikube service sonarqube-sonarqube -n sonarqube --url

2. Open the printed http://127.0.0.1:<port> in a Windows browser while the command is running.

---

## Subsequent Access (Next Day)

1. If the machine was rebooted:

    minikube start

2. Then access SonarQube using the same method as before (Ingress on Linux or minikube service --url on WSL2).

No re-deployment is required unless the cluster was deleted.

---

## PostgreSQL Choice (Important Note)

The assignment explicitly required **PostgreSQL to be installed using a separate Helm chart**.

However, during testing in a local Minikube environment (using the Docker driver under WSL2), the Bitnami PostgreSQL Helm chart (referenced with a link in the assignment) consistently failed to deploy due to persistent ImagePullBackOff errors.

The failures were caused by the chart referencing very specific container image tags (e.g. bitnami/postgresql:<version>-debian-<revision>) that could not be successfully pulled in the tested environment. Despite correct Helm and Kubernetes configuration, image resolution repeatedly failed, preventing the database from becoming Ready.

To keep the deployment repeatable and avoid environment-specific failures, this solution uses:
- a small custom PostgreSQL Helm chart
- the official `postgres` Docker image

---
## Known Limitations / Out of Scope

The following topics were considered but intentionally left out of scope for this assignment:

- TLS / HTTPS 
- secrets encryption and external secret managers
- network policies

The goal here was correctness, automation, and clarity — not production hardening.

---
## Verification Commands

    kubectl get pods -n sonarqube
    kubectl get ingress -n sonarqube
    kubectl get svc -n ingress-nginx

---

## Assumptions and Limitations
- This setup targets local or evaluation environments.
- The solution assumes unrestricted outbound internet access for pulling container images.
- Resource sizing is tuned for local execution, not production workloads.
- HTTP access is intentional and aligns with assignment requirements.
