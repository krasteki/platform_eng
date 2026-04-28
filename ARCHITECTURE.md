# FinPulse — Platform Engineering Architecture

> Local Kubernetes Platform с GitOps, CI/CD, Observability  
> Stack: Parallels · Terraform · Ansible · Kubernetes · ArgoCD · GitHub Actions · Prometheus/Grafana

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          DEVELOPER MACHINE (Mac M3)                         │
│                                                                             │
│  ┌──────────────┐    ┌──────────────────┐    ┌───────────────────────────┐ │
│  │  VS Code /   │    │   Terraform      │    │   Ansible                 │ │
│  │  Git         │    │   (null_resource │    │   (10 playbooks)          │ │
│  │              │    │    + prlctl)     │    │   01-prereqs              │ │
│  └──────┬───────┘    └────────┬─────────┘    │   02-haproxy              │ │
│         │ git push            │ prlctl clone │   03-control-init         │ │
│         │                     │              │   04-join-nodes           │ │
│         ▼                     ▼              │   06-metallb              │ │
│  ┌──────────────────────────────────────┐    │   07-ingress-nginx        │ │
│  │         Parallels Desktop Pro        │    │   08-cert-manager         │ │
│  │                                      │    │   09-argocd               │ │
│  │  k8s-lb         10.211.55.10         │    │   10-prometheus-stack     │ │
│  │  k8s-control-01 10.211.55.11  ┐      │    └───────────────────────────┘ │
│  │  k8s-control-02 10.211.55.12  ├─HA   │                                  │
│  │  k8s-control-03 10.211.55.13  ┘      │                                  │
│  │  k8s-worker-01  10.211.55.21  ┐      │                                  │
│  │  k8s-worker-02  10.211.55.22  ├─ Work│                                  │
│  │  k8s-worker-03  10.211.55.23  ┘      │                                  │
│  └──────────────────────────────────────┘                                  │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                              GITHUB                                         │
│                                                                             │
│  ┌─────────────────────────┐      ┌──────────────────────────────────────┐ │
│  │   krasteki/platform_eng │      │   krasteki/finpulse-app              │ │
│  │                         │      │                                      │ │
│  │  argocd/                │      │  backend/    (FastAPI Python)        │ │
│  │    root-app.yaml        │      │  frontend/   (React + Vite + TS)     │ │
│  │    apps/                │      │  k8s/        (K8s manifests)         │ │
│  │      finpulse.yaml      │      │  Dockerfile.backend                  │ │
│  │  ansible/  (playbooks)  │      │  Dockerfile.frontend                 │ │
│  │  terraform/ (infra)     │      │  .github/workflows/ci.yaml           │ │
│  └──────────────┬──────────┘      └──────────────┬───────────────────────┘ │
│                 │ ArgoCD watches               │                            │
│                 │                              │ push → triggers CI         │
│                 │                              ▼                            │
│                 │                    ┌─────────────────────┐               │
│                 │                    │  GitHub Actions CI  │               │
│                 │                    │                     │               │
│                 │                    │  1. QEMU (multi-arch│               │
│                 │                    │  2. Docker Buildx   │               │
│                 │                    │  3. Build backend   │               │
│                 │                    │  4. Build frontend  │               │
│                 │                    │  5. Push → GHCR     │               │
│                 │                    │  6. Update image tag│               │
│                 │                    │     in k8s/*.yaml   │               │
│                 │                    │  7. git commit+push │               │
│                 │                    └─────────┬───────────┘               │
│                 │                              │ image tag updated          │
└─────────────────┼──────────────────────────────┼───────────────────────────┘
                  │                              │
                  ▼                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                     KUBERNETES CLUSTER (HA, 3+3 nodes)                      │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  k8s-lb (HAProxy)                                                    │  │
│  │  10.211.55.10:6443  →  round-robin → control-01/02/03:6443          │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │  Networking & Ingress                                                 │ │
│  │                                                                       │ │
│  │  Flannel CNI  (pod CIDR: 10.244.0.0/16)                              │ │
│  │  MetalLB L2   (pool: 10.211.55.200-250)                              │ │
│  │  ingress-nginx  ──►  10.211.55.200  (LoadBalancer IP)                │ │
│  │  cert-manager   ──►  local-ca-issuer  (self-signed CA)               │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │  namespace: argocd                                                    │ │
│  │                                                                       │ │
│  │  ArgoCD  (App-of-Apps pattern)                                        │ │
│  │    root-app  ──watches──►  platform_eng/argocd/apps/                 │ │
│  │      └── finpulse Application  ──watches──►  finpulse-app/k8s/       │ │
│  │           syncPolicy: automated (prune + selfHeal)                   │ │
│  │                                                                       │ │
│  │  https://argocd.k8s.local                                            │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │  namespace: finpulse                                                  │ │
│  │                                                                       │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────────┐   │ │
│  │  │  postgres        │  │  backend         │  │  frontend          │   │ │
│  │  │  PostgreSQL 16   │  │  FastAPI / Python│  │  nginx / React     │   │ │
│  │  │  PVC: 5Gi        │  │  port: 8000      │  │  port: 80          │   │ │
│  │  │  (local-path)    │  │  /health probe   │  │  / probe           │   │ │
│  │  └────────┬─────────┘  └────────┬─────────┘  └─────────┬──────────┘   │ │
│  │           │                     │ asyncpg             │               │ │
│  │           └─────────────────────┘                     │               │ │
│  │                                                        │               │ │
│  │  Secrets:                                              │               │ │
│  │    finpulse-db-secret       (POSTGRES_USER/PASSWORD)   │               │ │
│  │    finpulse-backend-secret  (DATABASE_URL, API keys)   │               │ │
│  │    ghcr-pull-secret         (GHCR image pull)          │               │ │
│  │                                                                       │ │
│  │  Ingress:  finpulse.k8s.local  (HTTPS, TLS via cert-manager)         │ │
│  │    /api/*  ──►  finpulse-backend:8000                                │ │
│  │    /*      ──►  finpulse-frontend:80                                 │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │  namespace: monitoring                                                │ │
│  │                                                                       │ │
│  │  kube-prometheus-stack                                                │ │
│  │    Prometheus  ──scrapes──►  all pods, nodes, K8s metrics            │ │
│  │    Grafana     ──►  https://grafana.k8s.local                        │ │
│  │    Alertmanager                                                       │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## CI/CD Flow (GitOps)

```
Developer
   │
   │  git push (code change)
   ▼
GitHub (finpulse-app repo)
   │
   │  triggers
   ▼
GitHub Actions CI
   ├── QEMU + Buildx (linux/amd64 + linux/arm64)
   ├── Build Dockerfile.backend  →  ghcr.io/krasteki/finpulse-backend:<SHA>
   ├── Build Dockerfile.frontend →  ghcr.io/krasteki/finpulse-frontend:<SHA>
   ├── Push to GHCR
   └── Update k8s/backend.yaml + k8s/frontend.yaml (image tag)
          │  git commit + push
          ▼
       GitHub (k8s/ manifests updated)
          │
          │  ArgoCD polls every 3min (or manual refresh)
          ▼
       ArgoCD detects diff
          │
          │  kubectl apply
          ▼
       Kubernetes rolling update
          │
          │  readinessProbe passes
          ▼
       New pods Running ✓
```

---

## Deploy Process — стъпка по стъпка

### Фаза 1: Infrastructure Provisioning (Terraform)

**Цел:** Създаване на 7 VM-а в Parallels Desktop от един базов Ubuntu 22.04 ARM64 образ.

```bash
cd platform_eng/terraform
terraform init
terraform apply -auto-approve
```

**Какво прави Terraform:**
- Клонира базовия VM `Ubuntu 22.04 ARM64` → 7 пъти (последователно, за да не претовари disk I/O)
- Задава CPU/RAM за всеки VM:
  - `k8s-lb`: 1 CPU / 512MB — HAProxy load balancer
  - `k8s-control-01/02/03`: 2 CPU / 2GB — Kubernetes control plane (HA)
  - `k8s-worker-01/02/03`: 2 CPU / 4GB — worker nodes
- Стартира всички VM-ове
- Генерира `ansible/inventory.ini` с IP адресите

**Защо null_resource вместо Parallels provider:**  
Официалният Terraform Parallels provider изисква `prl-devops-service` daemon — отделен enterprise компонент. Решението с `null_resource` + `prlctl` CLI работи директно и е напълно idempotent.

---

### Фаза 2: Kubernetes Cluster Setup (Ansible)

**Цел:** Инсталиране и конфигуриране на HA Kubernetes cluster с kubeadm.

```bash
cd platform_eng/ansible
ansible-playbook -i inventory.ini 01-prereqs.yml      # containerd, kubeadm, kubelet, kubectl
ansible-playbook -i inventory.ini 02-haproxy.yml      # HAProxy на k8s-lb за 6443
ansible-playbook -i inventory.ini 03-control-init.yml  # kubeadm init + Flannel CNI
ansible-playbook -i inventory.ini 04-join-nodes.yml    # control-02/03 + workers join
```

**Playbook описание:**

| Playbook | Действие |
|---|---|
| `01-prereqs.yml` | static IP, hostname, containerd, kubeadm/kubelet/kubectl v1.29, kernel modules (br_netfilter, overlay) |
| `02-haproxy.yml` | HAProxy config — TCP frontend :6443 → backend control-01/02/03:6443 |
| `03-control-init.yml` | `kubeadm init --control-plane-endpoint k8s-lb:6443`, Flannel CNI, копиране на kubeconfig |
| `04-join-nodes.yml` | `kubeadm join` за control-02, control-03 (HA) и worker-01/02/03 |

**Резултат:** 6-node HA cluster, всички `Ready`:
```
k8s-control-01  Ready  control-plane
k8s-control-02  Ready  control-plane
k8s-control-03  Ready  control-plane
k8s-worker-01   Ready  <none>
k8s-worker-02   Ready  <none>
k8s-worker-03   Ready  <none>
```

---

### Фаза 3: Platform Components (Ansible)

**Цел:** Инсталиране на networking, ingress, TLS, GitOps и observability слоеве.

```bash
ansible-playbook -i inventory.ini 06-metallb.yml          # Layer 2 LoadBalancer
ansible-playbook -i inventory.ini 07-ingress-nginx.yml    # Ingress controller
ansible-playbook -i inventory.ini 08-cert-manager.yml     # TLS certificates
ansible-playbook -i inventory.ini 09-argocd.yml           # GitOps engine
ansible-playbook -i inventory.ini 10-prometheus-stack.yml # Monitoring
```

**Компоненти:**

| Component | Версия | Роля |
|---|---|---|
| **MetalLB** | v0.14 | L2 режим, IP pool `10.211.55.200-250` — дава реален IP на Services от тип LoadBalancer |
| **ingress-nginx** | latest | Единична точка на влизане, terminates TLS, маршрутизира по hostname/path |
| **cert-manager** | v1.14 | Автоматично издава TLS сертификати от local `ClusterIssuer` (self-signed CA) |
| **ArgoCD** | v2.x | GitOps — непрекъснато синхронизира K8s cluster-а с GitHub repo |
| **kube-prometheus-stack** | latest | Prometheus + Grafana + Alertmanager — metrics за nodes, pods, K8s |
| **local-path-provisioner** | v0.0.28 | Default StorageClass за PVC (локален disk на worker nodes) |

**ArgoCD App-of-Apps Pattern:**
```
root-app (platform_eng/argocd/apps/)
  └── finpulse Application  →  watches finpulse-app/k8s/
```
Всяка нова Application yaml в `argocd/apps/` се открива и деплойва автоматично.

---

### Фаза 4: Application Deployment (GitOps)

**Цел:** Deploy на FinPulse приложението чрез ArgoCD + GitHub Actions.

**Secrets (kubectl apply — еднократно):**
```bash
# PostgreSQL credentials
kubectl create secret generic finpulse-db-secret -n finpulse \
  --from-literal=POSTGRES_USER=finpulse_user \
  --from-literal=POSTGRES_PASSWORD=finpulse_secret

# Backend env
kubectl create secret generic finpulse-backend-secret -n finpulse \
  --from-literal=DATABASE_URL=postgresql+asyncpg://... \
  --from-literal=FMP_API_KEY="" \
  --from-literal=OPENAI_API_KEY=""

# GHCR image pull (ако images са private)
kubectl create secret docker-registry ghcr-pull-secret -n finpulse \
  --docker-server=ghcr.io --docker-username=krasteki --docker-password=<PAT>
```

**Application Stack:**

| Component | Technology | Image |
|---|---|---|
| **frontend** | React + Vite + TypeScript → nginx | `ghcr.io/krasteki/finpulse-frontend:<SHA>` |
| **backend** | FastAPI + Python 3.14 + uvicorn | `ghcr.io/krasteki/finpulse-backend:<SHA>` |
| **database** | PostgreSQL 16 | `postgres:16` |

**CI/CD Pipeline (GitHub Actions):**
1. Developer прави `git push` към `finpulse-app`
2. GitHub Actions стартира автоматично
3. Docker Buildx билдва multi-arch image (`linux/amd64` + `linux/arm64`) — QEMU за cross-compilation
4. Push към GHCR с тага `<github.sha>`
5. CI update-ва `k8s/backend.yaml` и `k8s/frontend.yaml` с новия SHA tag
6. `git commit --push` обратно към repo
7. ArgoCD засича промяната → `kubectl apply` → rolling update

---

## Key Design Decisions

| Decision | Why |
|---|---|
| **HA Control Plane (3 nodes)** | etcd quorum, без SPOF при control plane |
| **HAProxy пред API server** | Единствен endpoint `k8s-lb:6443`, скрива броя на control nodes |
| **Flannel CNI** | Лесна инсталация, стабилна, подходяща за on-prem |
| **MetalLB L2** | Дава реални IP адреси на LoadBalancer services без cloud provider |
| **App-of-Apps (ArgoCD)** | Scalable GitOps pattern — нова app = нов yaml файл в `argocd/apps/` |
| **Two-repo strategy** | `platform_eng` (infra) vs `finpulse-app` (app code) — separation of concerns, различни права за достъп |
| **Multi-arch Docker build** | Parallels ARM64 VMs + CI runners са AMD64 — двата image-а са необходими |
| **Image tag = git SHA** | Пълна traceability кой commit е деплойнат в prod |
| **Secrets извън Git** | Всички secrets са `kubectl create secret` — не влизат в repo |
| **local-path-provisioner** | PostgreSQL PVC работи без cloud storage |
| **cert-manager + local CA** | HTTPS навсякъде, дори локално — реалистичен setup |

---

## Достъпни Endpoints

| URL | Компонент |
|---|---|
| `https://finpulse.k8s.local` | FinPulse application |
| `https://argocd.k8s.local` | ArgoCD UI |
| `https://grafana.k8s.local` | Grafana dashboards |
| `https://dashboard.k8s.local` | Kubernetes Dashboard |

---

## Repositories

- **`github.com/krasteki/platform_eng`** — Terraform, Ansible, ArgoCD config
- **`github.com/krasteki/finpulse-app`** — Application code + K8s manifests + CI
- **`ghcr.io/krasteki/finpulse-backend`** — Backend Docker image (public)
- **`ghcr.io/krasteki/finpulse-frontend`** — Frontend Docker image (public)
