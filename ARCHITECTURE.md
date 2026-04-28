# FinPulse — Platform Engineering Architecture

> **Local Kubernetes Platform** built with GitOps, CI/CD, Secrets Management, and full Observability  
> **Stack:** Parallels · Terraform · Ansible · Kubernetes (HA) · ArgoCD · GitHub Actions · Vault · Prometheus · Grafana · Loki

---

## High-Level Architecture

```mermaid
graph TB
    subgraph DEV["👨‍💻 Developer Machine — Mac M3 (64GB)"]
        VSCODE["VS Code / Git"]
        TF["Terraform\nnull_resource + prlctl"]
        ANS["Ansible\n11 Playbooks"]
    end

    subgraph GITHUB["☁️ GitHub"]
        REPO_INFRA["krasteki/platform_eng\nTerraform · Ansible · ArgoCD config"]
        REPO_APP["krasteki/finpulse-app\nFastAPI · React · K8s manifests"]
        CI["GitHub Actions CI\nMulti-arch Docker build\nlinux/amd64 + linux/arm64"]
        GHCR["GHCR\nghcr.io/krasteki/finpulse-*"]
    end

    subgraph PARALLELS["🖥️ Parallels Desktop Pro"]
        LB["k8s-lb\n10.211.55.10\nHAProxy :6443"]

        subgraph CP["Control Plane (HA etcd quorum)"]
            CP1["k8s-control-01\n10.211.55.11"]
            CP2["k8s-control-02\n10.211.55.12"]
            CP3["k8s-control-03\n10.211.55.13"]
        end

        subgraph WN["Worker Nodes"]
            W1["k8s-worker-01\n10.211.55.21"]
            W2["k8s-worker-02\n10.211.55.22"]
            W3["k8s-worker-03\n10.211.55.23"]
        end
    end

    TF -->|"prlctl clone × 7"| PARALLELS
    ANS -->|"SSH → kubeadm init\nHAProxy · MetalLB · ArgoCD\nVault · Loki"| PARALLELS
    VSCODE -->|"git push"| REPO_INFRA
    VSCODE -->|"git push"| REPO_APP
    REPO_APP -->|"trigger"| CI
    CI -->|"docker push"| GHCR
    CI -->|"update image tag\ngit commit+push"| REPO_APP
    REPO_INFRA -->|"ArgoCD watches"| CP1
    REPO_APP -->|"ArgoCD watches\nk8s/ path"| CP1
    LB -->|":6443 round-robin"| CP1
    LB -->|":6443 round-robin"| CP2
    LB -->|":6443 round-robin"| CP3
```

---

## Kubernetes Cluster — Internal Architecture

```mermaid
graph TB
    INET["🌐 Browser\nfinpulse.k8s.local\ngrafana.k8s.local\nargocd.k8s.local\nvault.k8s.local"] 

    subgraph NET["Networking Layer"]
        MLB["MetalLB L2\npool: 10.211.55.200-250"]
        ING["ingress-nginx\nLoadBalancer IP: 10.211.55.200"]
        CM["cert-manager\nlocal-ca-issuer\n(TLS for all *.k8s.local)"]
    end

    subgraph GITOPS["namespace: argocd"]
        ARGO["ArgoCD\nApp-of-Apps pattern\nhttps://argocd.k8s.local"]
        ROOT["root-app\nwatches argocd/apps/"]
    end

    subgraph SECRETS["Secrets Management"]
        VAULT["HashiCorp Vault\nnamespace: vault\nKV v2 · K8s Auth\nhttps://vault.k8s.local"]
        ESO["External Secrets Operator\nnamespace: external-secrets\nClusterSecretStore: vault-backend"]
    end

    subgraph APP["namespace: finpulse"]
        FE["frontend\nnginx + React/Vite\nport: 80"]
        BE["backend\nFastAPI / Python 3.14\nport: 8000\n/health probe"]
        PG["postgres\nPostgreSQL 16\nPVC: 5Gi local-path"]
        ES1["ExternalSecret\nfinpulse-db-secret"]
        ES2["ExternalSecret\nfinpulse-backend-secret"]
    end

    subgraph OBS["namespace: monitoring"]
        PROM["Prometheus\nretention: 7d\nscrapes all pods+nodes"]
        GRAF["Grafana\nhttps://grafana.k8s.local\nadmin / admin123"]
        LOKI["Loki\nlog aggregation\nPVC: 5Gi"]
        PTAIL["Promtail DaemonSet\n1 pod per node × 6"]
    end

    INET --> ING
    ING --> FE
    ING --> BE
    ING --> ARGO
    ING --> GRAF
    ING --> VAULT
    FE -->|"/api/* proxy"| BE
    BE --> PG
    MLB --> ING
    CM -->|"TLS certs"| ING
    ROOT -->|"discovers apps/"| ARGO
    ARGO -->|"kubectl apply"| APP
    ARGO -->|"kubectl apply"| VAULT
    ARGO -->|"kubectl apply"| ESO
    ARGO -->|"kubectl apply"| OBS
    VAULT -->|"K8s auth\nKV secrets"| ESO
    ESO -->|"creates K8s Secret"| ES1
    ESO -->|"creates K8s Secret"| ES2
    ES1 -->|"env vars"| PG
    ES2 -->|"env vars"| BE
    PTAIL -->|"ship logs"| LOKI
    LOKI -->|"datasource"| GRAF
    PROM -->|"datasource"| GRAF
```

---

## CI/CD GitOps Flow

```mermaid
sequenceDiagram
    participant Dev as 👨‍💻 Developer
    participant GH as GitHub
    participant CI as GitHub Actions
    participant GHCR as GHCR
    participant ArgoCD as ArgoCD
    participant K8s as Kubernetes

    Dev->>GH: git push (code change)
    GH->>CI: trigger workflow
    CI->>CI: QEMU + Docker Buildx
    CI->>CI: Build backend (linux/amd64+arm64)
    CI->>CI: Build frontend (linux/amd64+arm64)
    CI->>GHCR: push images :<git-sha>
    CI->>GH: update k8s/*.yaml image tags
    CI->>GH: git commit + push
    GH-->>ArgoCD: poll / webhook (3min)
    ArgoCD->>ArgoCD: detect diff in k8s/
    ArgoCD->>K8s: kubectl apply
    K8s->>K8s: rolling update
    K8s-->>ArgoCD: readinessProbe /health ✓
    ArgoCD-->>Dev: Synced + Healthy ✓
```

---

## Secrets Flow (Vault + ESO)

```mermaid
graph LR
    subgraph VAULT["HashiCorp Vault"]
        KV["KV v2\nsecret/finpulse/postgres\nsecret/finpulse/backend"]
        AUTH["Kubernetes Auth\nrole: external-secrets\npolicy: read-only"]
    end

    subgraph ESO["External Secrets Operator"]
        CSS["ClusterSecretStore\nvault-backend"]
        EXT["ExternalSecret\n(per namespace)"]
    end

    subgraph K8S["Kubernetes"]
        SA["ServiceAccount\nexternal-secrets"]
        SEC["K8s Secret\n(auto-created + refreshed 1h)"]
        POD["finpulse pods\nenv vars injected"]
    end

    SA -->|"JWT token"| AUTH
    AUTH -->|"Vault token"| CSS
    CSS --> EXT
    EXT -->|"pull secrets"| KV
    EXT -->|"create/update"| SEC
    SEC -->|"secretKeyRef"| POD
```

---

## Infrastructure Stack — Component Summary

| Layer | Component | Version | Role |
|---|---|---|---|
| **Virtualization** | Parallels Desktop Pro | ARM64 | 7 VMs on Mac M3 |
| **IaC** | Terraform + null_resource | ≥1.5 | VM provisioning via prlctl |
| **Config Mgmt** | Ansible | 11 playbooks | K8s setup + platform config |
| **Container Runtime** | containerd | 1.7 | CRI on all nodes |
| **Kubernetes** | kubeadm | v1.29 | HA cluster (3 control + 3 workers) |
| **Load Balancer** | HAProxy | — | API server HA endpoint :6443 |
| **CNI** | Flannel | — | Pod network 10.244.0.0/16 |
| **LB for Services** | MetalLB | v0.14 | L2 mode, IP pool .200-.250 |
| **Ingress** | ingress-nginx | — | Single entry point, TLS termination |
| **TLS** | cert-manager | v1.14 | local-ca-issuer for *.k8s.local |
| **GitOps** | ArgoCD | v2.x | App-of-Apps, automated sync |
| **CI/CD** | GitHub Actions | — | Multi-arch Docker build + push |
| **Registry** | GHCR | — | ghcr.io/krasteki/finpulse-* |
| **Secrets** | HashiCorp Vault | 0.28 | KV v2, Kubernetes auth method |
| **Secrets Sync** | External Secrets Operator | 0.9 | Vault → K8s Secrets (1h refresh) |
| **Storage** | local-path-provisioner | v0.0.28 | Default StorageClass (PVCs) |
| **Metrics** | Prometheus | — | 7d retention, K8s + app metrics |
| **Dashboards** | Grafana | — | Metrics + Logs in one UI |
| **Logs** | Loki + Promtail | 2.6 | Log aggregation, 7d retention |
| **App — Backend** | FastAPI + Python 3.14 | — | REST API, yfinance, asyncpg |
| **App — Frontend** | React + Vite + TypeScript | — | SPA served by nginx |
| **App — Database** | PostgreSQL | 16 | Persistent storage |

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| **HA Control Plane (3 nodes)** | etcd quorum, no single point of failure |
| **HAProxy before API server** | Single `k8s-lb:6443` endpoint, hides control plane topology |
| **Two-repo strategy** | `platform_eng` (infra) vs `finpulse-app` (app) — separate concerns, separate access rights |
| **App-of-Apps (ArgoCD)** | Scalable GitOps: new app = one yaml file in `argocd/apps/` |
| **Multi-arch Docker build** | Parallels VMs are ARM64, GitHub runners are AMD64 — both needed |
| **Image tag = git SHA** | Full traceability: know exactly which commit is deployed |
| **Vault + ESO over plain K8s Secrets** | Secrets never in Git, centralized rotation, audit log |
| **Loki over ELK** | 10× lower resource usage, integrates natively into Grafana |
| **MetalLB L2** | Real LoadBalancer IPs on bare-metal without cloud provider |
| **cert-manager + local CA** | HTTPS everywhere, realistic prod-like setup locally |
| **local-path-provisioner** | PVCs work on bare-metal without NFS or cloud storage |
| **Terraform null_resource** | No Parallels provider available; prlctl CLI is idempotent and works immediately |

---

## Endpoints

| URL | Service | Credentials |
|---|---|---|
| https://finpulse.k8s.local | FinPulse Application | — |
| https://argocd.k8s.local | ArgoCD UI | admin / *(see initial secret)* |
| https://grafana.k8s.local | Grafana (Metrics + Logs) | admin / admin123 |
| https://vault.k8s.local | HashiCorp Vault UI | Token: see `vault-init-keys` secret |
| https://dashboard.k8s.local | Kubernetes Dashboard | Bearer token |

---

## Ansible Bootstrap Order

Full cluster bootstrap from zero — run in sequence:

```bash
cd ansible/
ansible-playbook -i inventory.ini 01-prereqs.yml        # OS prep: swap off, modules, sysctl, containerd, kubeadm/kubelet
ansible-playbook -i inventory.ini 02-haproxy.yml        # HAProxy LB on k8s-lb → API server :6443
ansible-playbook -i inventory.ini 03-control-init.yml   # kubeadm init on control-01, copy kubeconfig, install Flannel CNI
ansible-playbook -i inventory.ini 04-join-nodes.yml     # Join control-02/03 + workers to cluster
ansible-playbook -i inventory.ini 05-static-ips.yml     # Persist static IPs across VM reboots (netplan)
ansible-playbook -i inventory.ini 06-metallb.yml        # MetalLB L2 + IP pool 10.211.55.200-250
ansible-playbook -i inventory.ini 07-ingress-nginx.yml  # ingress-nginx (LoadBalancer → MetalLB IP)
ansible-playbook -i inventory.ini 08-cert-manager.yml   # cert-manager + local CA + ClusterIssuer
ansible-playbook -i inventory.ini 09-argocd.yml         # ArgoCD + root App-of-Apps → deploys everything else
ansible-playbook -i inventory.ini 10-prometheus-stack.yml # kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
ansible-playbook -i inventory.ini 11-vault-init.yml     # Vault init + unseal + KV v2 + K8s auth + finpulse secrets
```

> After playbook 09, ArgoCD automatically deploys: MetalLB config, ingress-nginx, cert-manager, Vault, ESO, Loki, finpulse app.  
> Playbook 11 must run **after** ArgoCD has synced the Vault application (pod Running).

---

## Repositories

| Repo | Purpose |
|---|---|
| `github.com/krasteki/platform_eng` | Terraform · Ansible · ArgoCD config · Architecture docs |
| `github.com/krasteki/finpulse-app` | Application code · K8s manifests · CI pipeline |
| `ghcr.io/krasteki/finpulse-backend` | Backend Docker image (multi-arch) |
| `ghcr.io/krasteki/finpulse-frontend` | Frontend Docker image (multi-arch) |
