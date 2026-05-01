# Technology Stack

Complete reference of all technologies used in this platform — what each tool is, why we chose it, and how it fits into the architecture.

---

## Infrastructure & Virtualization

### Parallels Desktop Pro
- **What:** Type-2 hypervisor for macOS (ARM64)
- **Why:** Native ARM64 support on Mac M3 — runs Ubuntu 22.04 VMs at near-native speed. VMware Fusion lacks ARM64 nested virt support at the same level.
- **How:** 7 VMs total — 1 load balancer, 3 control-plane nodes, 3 worker nodes. Managed via `prlctl` CLI.

### Terraform (null_resource + prlctl)
- **What:** Infrastructure as Code tool — declarative provisioning
- **Why:** No official Parallels provider exists, but `null_resource` + `local-exec` + `prlctl` CLI is idempotent and scriptable.
- **How:** `terraform/` — clones a base Ubuntu 22.04 ARM64 VM 7 times, sets hostnames, network config, injects SSH keys via `cloud-init`. `terraform apply` provisions the full VM fleet.

### Ansible
- **What:** Agentless configuration management (SSH-based)
- **Why:** Idempotent playbooks — safe to re-run. No agent to install on nodes. YAML-native.
- **How:** 11 sequential playbooks in `ansible/` — each one handles a distinct layer (OS prep → K8s → networking → platform components → secrets). Run once after Terraform provisions the VMs.

---

## Kubernetes

### kubeadm
- **What:** Official Kubernetes cluster bootstrapping tool
- **Why:** Production-grade, full control over configuration (vs. k3s/kind which abstract away too much). Used in real enterprise clusters.
- **How:** Playbook `03-control-init.yml` runs `kubeadm init` on the first control-plane node. Playbook `04-join-nodes.yml` joins the remaining control-plane and worker nodes.

### containerd
- **What:** CNCF-graduated container runtime (CRI)
- **Why:** Default and recommended runtime for Kubernetes. Lighter than Docker daemon. OCI-compliant.
- **How:** Installed on all 6 K8s nodes in `01-prereqs.yml`. Configured with `SystemdCgroup = true` for kubeadm compatibility.

### HAProxy
- **What:** High-performance TCP/HTTP load balancer
- **Why:** Provides a single stable API server endpoint (`k8s-lb:6443`) for the HA control-plane. Clients (kubectl, kubelets, ArgoCD) never need to know which control-plane node is active.
- **How:** Runs on the dedicated `k8s-lb` VM. Configured in `02-haproxy.yml` — TCP mode, round-robin across all 3 control-plane nodes on port 6443.

### Flannel (CNI)
- **What:** Simple overlay network plugin for Kubernetes pod networking
- **Why:** Minimal resource usage, works on ARM64, no complex configuration. Sufficient for a lab cluster — production would use Cilium for NetworkPolicy enforcement.
- **How:** Deployed via `kubectl apply` in `03-control-init.yml`. Pod CIDR: `10.244.0.0/16`. NetworkPolicy objects are accepted by the API server but **not enforced** with Flannel (enforcement requires Calico/Cilium).

---

## Networking

### MetalLB
- **What:** LoadBalancer implementation for bare-metal Kubernetes
- **Why:** Cloud Kubernetes clusters get LoadBalancer IPs from the cloud provider. On bare-metal there is nothing — MetalLB fills this gap using L2 (ARP) or BGP.
- **How:** L2 mode, IP pool `10.211.55.200-10.211.55.250`. `ingress-nginx` gets IP `.200` as its LoadBalancer. Deployed via ArgoCD Helm chart.

### ingress-nginx
- **What:** Kubernetes Ingress controller based on NGINX
- **Why:** Single entry point for all HTTP/HTTPS traffic. Handles TLS termination, routing by hostname and path prefix.
- **How:** Deployed as a `LoadBalancer` Service — gets IP `10.211.55.200` from MetalLB. All `*.k8s.local` hostnames are routed through it. TLS terminated here using certs from cert-manager.

### cert-manager
- **What:** Kubernetes-native X.509 certificate management
- **Why:** Automates TLS certificate issuance and renewal. Integrates with ACME (Let's Encrypt) for production or with custom CAs for local environments.
- **How:** Running with a self-signed `local-ca-issuer` (ClusterIssuer). The local CA cert is imported into the macOS System Keychain so browsers trust all `*.k8s.local` certificates. Certs auto-renew before expiry.

---

## GitOps & CI/CD

### ArgoCD
- **What:** GitOps continuous delivery tool for Kubernetes
- **Why:** Declarative, Git-driven deployments. Automatically detects drift between Git state and cluster state and self-heals. Single pane of glass for all deployed applications.
- **How:** App-of-Apps pattern — `root-app` watches `argocd/apps/`. Every platform component (Vault, Loki, Kyverno, etc.) is one YAML file in that folder. ArgoCD polls GitHub every 3 minutes and syncs automatically.

### GitHub Actions
- **What:** CI/CD platform integrated into GitHub
- **Why:** Zero infrastructure to manage, native integration with GHCR, free for public repos.
- **How:** On every push to `main` in `finpulse-app`, the workflow: (1) builds multi-arch Docker images (linux/amd64 + linux/arm64) using QEMU + Buildx, (2) pushes to GHCR tagged with the git SHA, (3) updates `k8s/*.yaml` image tags and commits back to `main`. ArgoCD then picks up the commit and deploys.

### GHCR (GitHub Container Registry)
- **What:** OCI-compliant container registry integrated with GitHub
- **Why:** Free for public repos, automatic auth via `GITHUB_TOKEN`, no separate infrastructure.
- **How:** Images: `ghcr.io/krasteki/finpulse-backend:<sha>` and `ghcr.io/krasteki/finpulse-frontend:<sha>`. Multi-arch manifest — K8s pulls the correct arch automatically.

---

## Secrets Management

### HashiCorp Vault
- **What:** Enterprise-grade secrets management platform
- **Why:** Secrets never live in Git or K8s etcd unencrypted. Vault provides: KV storage, dynamic secrets, audit logging, fine-grained access policies.
- **How:** Standalone mode (1 pod), KV v2 secrets engine at `secret/`. Kubernetes Auth Method allows pods to authenticate using their ServiceAccount JWT tokens. Initialized and configured by Ansible playbook `11-vault-init.yml`. Exposed at `https://vault.k8s.local`.

### External Secrets Operator (ESO)
- **What:** Kubernetes operator that syncs external secrets into K8s Secrets
- **Why:** Bridges Vault → Kubernetes. Pods use standard `secretKeyRef` env vars — no Vault SDK needed in app code.
- **How:** `ClusterSecretStore` named `vault-backend` connects to Vault via K8s Auth. `ExternalSecret` resources in `finpulse` namespace define which Vault paths to pull from. K8s Secrets are created and refreshed every hour automatically.

---

## Observability

### kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
- **What:** Full metrics observability stack — collection, storage, visualization, alerting
- **Why:** De-facto standard for K8s monitoring. Ships with pre-built dashboards for nodes, pods, deployments.
- **How:** Deployed via ArgoCD Helm chart. Prometheus scrapes all pods + nodes. 7-day retention. Grafana exposed at `https://grafana.k8s.local`. Custom `PrometheusRule` for finpulse alerts (CrashLoop, OOMKill, HighCPU, NodeNotReady, etc).

### Loki
- **What:** Log aggregation system — "Prometheus for logs"
- **Why:** 10× lower resource usage than ELK. Integrates natively into Grafana — metrics and logs in one UI. Label-based indexing (no full-text index like Elasticsearch).
- **How:** Deployed as part of `loki-stack` Helm chart. 5Gi PVC for log storage, 7-day retention. Exposed as datasource in Grafana automatically via ConfigMap with label `grafana_datasource: "1"`.

### Promtail
- **What:** Log shipping agent for Loki
- **Why:** Native Loki integration, auto-discovers pods via Kubernetes labels, zero config needed per pod.
- **How:** Deployed as a DaemonSet — 1 pod per node (6 total). Tails `/var/log/pods/` and ships to Loki. All pod logs are immediately available in Grafana Explore.

---

## Policy as Code

### Kyverno
- **What:** Kubernetes-native policy engine — validates, mutates, and generates K8s resources
- **Why:** OPA/Gatekeeper requires learning Rego. Kyverno uses native YAML/K8s patterns — lower learning curve, same power.
- **How:** 3 `ClusterPolicy` resources in `argocd/manifests/kyverno/`:
  - `require-pod-labels` — Audit: all pods must have `app` label
  - `disallow-privilege-escalation` — Audit: no root/privileged containers in finpulse
  - `restrict-image-registries` — **Enforce**: finpulse images only from `ghcr.io/krasteki/` or `postgres:*`

---

## Backup & Recovery

### Velero
- **What:** Kubernetes backup and disaster recovery tool
- **Why:** Backs up both K8s resource manifests AND PVC data. Can restore a full namespace in minutes.
- **How:** Uses AWS plugin configured against MinIO (S3-compatible). Daily scheduled backup of `finpulse` namespace at 02:00, 7-day retention. PVC data backed up via restic (node agent DaemonSet).

### MinIO
- **What:** S3-compatible object storage — runs inside the cluster
- **Why:** Velero requires an S3 endpoint for backup storage. In a local lab without AWS, MinIO provides an identical S3 API.
- **How:** Standalone mode, 10Gi PVC. Credentials managed by ESO pulling from Vault (`secret/velero/minio`). Velero bucket `velero` created on startup.

---

## Workload Reliability

### HorizontalPodAutoscaler (HPA)
- **What:** Kubernetes controller that scales Deployments based on metrics
- **Why:** Auto-handles traffic spikes without manual intervention.
- **How:** `finpulse-backend` scales 1→3 replicas when CPU >70% or memory >80%. Scale-up is aggressive (1 pod per minute), scale-down is conservative (wait 5 minutes) to avoid flapping.

### PodDisruptionBudget (PDB)
- **What:** Kubernetes policy that limits voluntary disruption to pods
- **Why:** Prevents node drains (cluster upgrades, maintenance) from taking down all replicas simultaneously.
- **How:** `minAvailable: 1` for both `finpulse-backend` and `finpulse-frontend` — at least 1 pod is always running during node drain operations.

### ResourceQuota + LimitRange
- **What:** Namespace-level resource governance
- **Why:** Prevents a single namespace from consuming all cluster resources. LimitRange provides safe defaults for pods that don't specify requests/limits.
- **How:** `finpulse` namespace: 2CPU/2Gi requests, 4CPU/4Gi limits, max 20 pods. LimitRange defaults: 100m/128Mi request, 500m/512Mi limit per container.

---

## Code Quality

### SonarQube
- **What:** Static application security testing (SAST) and code quality platform
- **Why:** Catches security vulnerabilities (SQL injection, hardcoded secrets, insecure dependencies) in Python and TypeScript _before_ deploy. Quality Gates in GitHub Actions block PRs that fail coverage, bug count, or security thresholds — ArgoCD never sees a bad image tag.
- **How:** Deployed as a Helm chart on control-plane nodes (4GB RAM — workers have only 2GB). Embedded PostgreSQL for persistence. Exposed at `https://sonarqube.k8s.local`. GitHub Actions workflow runs `sonar-scanner` on every push; if the Quality Gate fails, the pipeline stops before building the Docker image. ServiceMonitor exposes metrics to Prometheus.

---

## Application Stack

### FastAPI (Python 3.14)
- **What:** Modern, async Python web framework
- **Why:** High performance (ASGI), automatic OpenAPI docs, native async support for DB and external APIs.
- **How:** Backend service in `finpulse` namespace. Reads `DATABASE_URL`, `FMP_API_KEY`, `OPENAI_API_KEY` from K8s Secrets (injected by ESO). Exposes `/health` for readiness probe.

### React + Vite + TypeScript
- **What:** Modern frontend SPA framework + build tool + typed JavaScript
- **Why:** Fast development with HMR, type safety, small production bundle.
- **How:** Built as static files, served by nginx in the frontend container. All `/api/*` requests proxied to the backend service.

### PostgreSQL 16
- **What:** Production-grade relational database
- **Why:** ACID compliant, excellent Python ecosystem (asyncpg), widely used in production.
- **How:** Single-pod deployment with 5Gi PVC (local-path). Credentials (`POSTGRES_USER`, `POSTGRES_PASSWORD`) injected from K8s Secret via ESO/Vault. Readiness probe uses `pg_isready`.

---

## Storage

### local-path-provisioner
- **What:** Simple dynamic PVC provisioner using local node storage
- **Why:** Bare-metal clusters have no cloud storage provider. local-path-provisioner creates PVs automatically on the node where the pod is scheduled.
- **How:** Default StorageClass on the cluster. Used for: PostgreSQL (5Gi), Loki (5Gi), MinIO/Velero (10Gi), Vault (1Gi). Not suitable for production (no replication) — would be replaced with Longhorn or Rook/Ceph in a real environment.
