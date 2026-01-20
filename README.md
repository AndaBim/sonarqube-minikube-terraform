# SonarQube on Minikube using Terraform

## Overview

- This repository contains a fully automated solution to deploy **SonarQube** on a **local Kubernetes cluster (Minikube)** using **Terraform** and **Helm**. 
- A single script performs all installation, cluster initialization, application deployment, and verification steps.
- From the project root, run:

./scripts/setup.sh

## The script will:

- Perform pre-flight checks
- Install system dependencies
- Install Docker
- Install Minikube, kubectl, Helm, and Terraform
- Start the Minikube cluster
- Enable the ingress controller
- Deploy PostgreSQL and SonarQube via Terraform
- Verify that all components are running

---

## Prerequisites

- Ubuntu Server (any recent LTS)
- Bash
- curl
- git

No other tools are required upfront.

---

## Scope and Intent

This implementation is intentionally scoped to:
- environment setup automation,
- Kubernetes resource provisioning,
- Helm-based application deployment.

---

## Architecture Overview

High-level flow:

- A Bash script installs all required tools and dependencies.
- Minikube provides a local Kubernetes cluster.
- Terraform manages:
  - Kubernetes namespace creation
  - Helm releases for PostgreSQL and SonarQube
- Helm deploys:
  - PostgreSQL (as a separate Helm chart)
  - SonarQube with persistent storage
- NGINX Ingress exposes SonarQube via HTTP.

---

## Repository Structure
.
├── README.md
├── scripts/
│   └── setup.sh
├── terraform/
│   ├── main.tf
│   ├── providers.tf
│   ├── versions.tf
│   └── values/
│       ├── sonarqube.yaml
│       └── postgresql.yaml
├── helm/
│   └── postgresql/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── service.yaml
│           └── statefulset.yaml

---

## Tooling and Versions

The following tools are installed and used by the setup script:

| Tool       | Version (Pinned) | Reason                      |
| ---------- | ---------------- | --------------------------- |
| Terraform  | ~> 1.6.x         | Stable, widely adopted      |
| Helm       | ~> 3.x           | Tillerless, modern Helm     |
| Minikube   | Latest stable    | Local Kubernetes cluster    |
| Kubernetes | v1.28.x          | Compatible with Helm charts |
| Docker     | Latest stable    | Container runtime           |

Version pinning is applied where possible to ensure reproducibility.

---

## PostgreSQL Helm Chart Choice

The task requirement explicitly states that PostgreSQL must be installed using a separate Helm chart.

However, during testing in a local Minikube environment (using the Docker driver under WSL2), the Bitnami PostgreSQL Helm chart (referenced with a link in the assignment) consistently failed to deploy due to persistent `ImagePullBackOff` errors.

The failures were caused by the chart referencing very specific container image tags (e.g. `bitnami/postgresql:<version>-debian-<revision>`) that could not be successfully pulled in the tested environment. Despite correct Helm and Kubernetes configuration, image resolution repeatedly failed, preventing the database from becoming Ready.

To avoid coupling the success of the assignment to environment-specific container image resolution issues, a lightweight custom Helm chart based on the official PostgreSQL image was implemented instead.
This approach:

- still satisfies the requirement of using a separate Helm chart,
- ensures reliable image availability,
- keeps the database fully decoupled from SonarQube.

---

## SonarQube Configuration

- SonarQube is deployed using the official Helm chart.
- Persistent storage is enabled for SonarQube data.
- SonarQube is configured to connect to the external PostgreSQL database.
- An NGINX ingress resource exposes SonarQube via HTTP.
- SonarQube data is stored on a PersistentVolumeClaim to survive pod restarts.

---

## Ingress and Access

The NGINX ingress controller is enabled using the Minikube ingress addon.

### Setup and Execution:

- Host: sonarqube.local
- Protocol: HTTP
- Port: 80 (via ingress)

---

## Verification

- After the script completes successfully:

kubectl get pods -n sonarqube

- All pods should be in Running state.

## Accessing SonarQube
###  Native Linux (Ubuntu Server)

On native Linux, SonarQube is accessible directly via Ingress:

http://sonarqube.local

### Windows with WSL2 (where the script was implemented originally)

- When running Minikube inside WSL2 using the Docker driver, the Minikube internal network (e.g. 192.168.49.0/24) was not routable from the Windows host. As a result, the Ingress host (sonarqube.local) may be reachable from inside WSL but it was not from a Windows browser.
- In this case, Minikube’s service URL output was used as the browser endpoint:

minikube service sonarqube-sonarqube -n sonarqube --url

- Example output:
http://127.0.0.1:33921

- Open the printed localhost URL in a Windows browser while the command is running.

NB! Ingress resources are still created and validated inside the cluster; the difference is due to WSL networking constraints.

## Security Considerations (Out of Scope)

- Security hardening was considered during the design of this solution but intentionally kept out of scope to align with the assignment focus.
- Examples of security aspects not implemented include:
-- HTTPS / TLS termination at ingress
-- External secrets management
-- Network policies

## Assumptions and Limitations

- This setup targets local or evaluation environments.
- The solution assumes unrestricted outbound internet access for pulling container images.
- Resource sizing is tuned for local execution, not production workloads.
- HTTP access is intentional and aligns with assignment requirements.