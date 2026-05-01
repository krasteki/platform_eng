# Platform Engineering — Local Kubernetes Lab

> Production-grade Kubernetes platform running locally on **Parallels VMs (Mac M3)** — IaC, GitOps, CI/CD, Secrets Management, and full Observability.

## What's Running

| Component | Technology | Status |
|---|---|---|
| K8s Cluster (HA) | kubeadm v1.29 — 3 control-plane + 3 workers | ✅ Running |
| Infrastructure | Terraform + Ansible (11 playbooks) | ✅ Automated |
| GitOps | ArgoCD — App-of-Apps pattern | ✅ Synced |
| CI/CD | GitHub Actions — multi-arch Docker (amd64+arm64) | ✅ Active |
| Code Quality | SonarQube + Quality Gate in CI pipeline | ✅ Running |
| CI Runner | Self-hosted GitHub Actions runner in K8s | ✅ Running |
| Secrets | HashiCorp Vault + External Secrets Operator | ✅ Synced |
| Observability | Prometheus + Grafana + Loki + Promtail | ✅ Running |
| Policy | Kyverno — image registry + pod security | ✅ Enforced |
| Backup | Velero + MinIO (S3-compatible) | ✅ Scheduled |
| IDP | Backstage — Service Catalog + Software Templates | ✅ Running |
| App | FinPulse — FastAPI + React + PostgreSQL | ✅ Deployed |

## Repository Structure

```
platform_eng/
├── terraform/          # VM provisioning via prlctl (7 Parallels VMs)
├── ansible/            # 11 playbooks — full cluster bootstrap from zero
│   ├── 01-prereqs.yml
│   ├── 02-haproxy.yml
│   ├── 03-control-init.yml
│   ├── 04-join-nodes.yml
│   ├── 05-static-ips.yml
│   ├── 06-metallb.yml
│   ├── 07-ingress-nginx.yml
│   ├── 08-cert-manager.yml
│   ├── 09-argocd.yml
│   ├── 10-prometheus-stack.yml
│   └── 11-vault-init.yml
├── argocd/
│   ├── apps/           # ArgoCD Application manifests (one file per component)
│   └── manifests/      # Helm values + extra K8s resources (Vault config, Loki datasource)
└── ARCHITECTURE.md     # Full architecture documentation with diagrams
```

## Quick Start — Full Bootstrap

```bash
# 1. Provision VMs
cd terraform && terraform apply -auto-approve

# 2. Configure cluster (run in order)
cd ../ansible
ansible-playbook -i inventory.ini 01-prereqs.yml
ansible-playbook -i inventory.ini 02-haproxy.yml
ansible-playbook -i inventory.ini 03-control-init.yml
ansible-playbook -i inventory.ini 04-join-nodes.yml
ansible-playbook -i inventory.ini 05-static-ips.yml
ansible-playbook -i inventory.ini 06-metallb.yml
ansible-playbook -i inventory.ini 07-ingress-nginx.yml
ansible-playbook -i inventory.ini 08-cert-manager.yml
ansible-playbook -i inventory.ini 09-argocd.yml
# ArgoCD now auto-deploys: Vault, ESO, Loki, FinPulse app
ansible-playbook -i inventory.ini 10-prometheus-stack.yml
ansible-playbook -i inventory.ini 11-vault-init.yml  # after Vault pod is Running

# 3. Add /etc/hosts entries
echo "10.211.55.200  finpulse.k8s.local argocd.k8s.local grafana.k8s.local vault.k8s.local dashboard.k8s.local sonarqube.k8s.local backstage.k8s.local" | sudo tee -a /etc/hosts

# 4. Trust local CA (macOS)
kubectl get secret local-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/k8s-local-ca.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/k8s-local-ca.crt
```

## Endpoints

| URL | Service |
|---|---|
| https://finpulse.k8s.local | FinPulse Application |
| https://argocd.k8s.local | ArgoCD GitOps UI |
| https://grafana.k8s.local | Grafana — Metrics + Logs |
| https://vault.k8s.local | HashiCorp Vault |
| https://sonarqube.k8s.local | SonarQube — Code Quality |
| https://backstage.k8s.local | Backstage — Internal Developer Portal |
| https://dashboard.k8s.local | Kubernetes Dashboard |

## Key Design Decisions

- **HA Control Plane** — 3 nodes with etcd quorum, HAProxy as single API endpoint
- **Two-repo GitOps** — `platform_eng` (infra) + `finpulse-app` (app) — separate concerns
- **App-of-Apps** — new platform component = one YAML file in `argocd/apps/`
- **Vault + ESO** — secrets never in Git, centralized rotation, full audit trail
- **Loki over ELK** — 10× lower resource usage, native Grafana integration
- **Image tag = git SHA** — full traceability from Grafana → ArgoCD → GitHub commit
- **SonarQube Quality Gate** — blocks Docker build if code quality/security fails; runs on self-hosted K8s runner with direct access to internal SonarQube
- **Backstage IDP** — single developer portal: service catalog, docs, CI status, ArgoCD sync state per service

## Related Repos

| Repo | Purpose |
|---|---|
| [krasteki/finpulse-app](https://github.com/krasteki/finpulse-app) | Application code + K8s manifests + CI pipeline |

---

📖 See [ARCHITECTURE.md](ARCHITECTURE.md) for full architecture diagrams and detailed documentation.
