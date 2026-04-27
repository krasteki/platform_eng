# Kubernetes HA Cluster — Локален Setup с Parallels + Terraform

## Архитектура

```
                    ┌─────────────────┐
                    │  Load Balancer  │
                    │  HAProxy 1GB    │
                    │  192.168.64.10  │
                    └────────┬────────┘
                             │ :6443
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
     ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
     │ control-01   │ │ control-02   │ │ control-03   │
     │ 4GB RAM      │ │ 4GB RAM      │ │ 4GB RAM      │
     │ 192.168.64.11│ │ 192.168.64.12│ │ 192.168.64.13│
     └──────────────┘ └──────────────┘ └──────────────┘
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
     ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
     │  worker-01   │ │  worker-02   │ │  worker-03   │
     │  2GB RAM     │ │  2GB RAM     │ │  2GB RAM     │
     │ 192.168.64.21│ │ 192.168.64.22│ │ 192.168.64.23│
     └──────────────┘ └──────────────┘ └──────────────┘
```

**Общо RAM: 19GB** (3×4GB control + 3×2GB worker + 1×1GB LB) — при 64GB Mac съвсем удобно

---

## VM Спецификации

| Роля | Брой | RAM | CPU | Disk | IP |
|---|---|---|---|---|---|
| Load Balancer | 1 | 1GB | 1 vCPU | 20GB | 192.168.64.10 |
| Control Plane | 3 | 4GB | 2 vCPU | 40GB | .11 / .12 / .13 |
| Worker | 3 | 2GB | 2 vCPU | 60GB | .21 / .22 / .23 |

---

## Stack

| Компонент | Избор | Бележка |
|---|---|---|
| VM Provider | Parallels Desktop | Terraform provider: `parallelsvirtualization/parallels-desktop` |
| OS | Ubuntu 22.04 | **ARM64** (M3 чип) |
| Load Balancer | HAProxy | TCP mode port 6443 |
| K8s bootstrap | kubeadm | Стандартен HA setup |
| Config mgmt | **Ansible** | OS setup + kubeadm bootstrap + node join |
| etcd topology | Stacked | etcd вграден в control plane nodes |
| CNI | Flannel | Лек, подходящ за локален cluster |
| LB за Services | MetalLB | `LoadBalancer` type Services в cluster-а |
| Ingress | ingress-nginx | HTTP/HTTPS routing към pods |
| Storage | local-path-provisioner | Dynamic PVC provisioning от local disk |
| GitOps | **ArgoCD** | CD pipeline, deploy на всичко в cluster-а |
| CI | **TeamCity** | Build server (deploy като pod на worker) |
| Мониторинг | kube-prometheus-stack | Prometheus + Grafana |
| Cert mgmt | cert-manager | TLS certificates (Let's Encrypt / self-signed) |

---

## Фази

### Phase 1 — Terraform: VM Provisioning ✅ ФАЙЛОВЕТЕ СА ГОТОВИ

- [x] 1.1 `terraform/main.tf` — Parallels provider конфигурация
- [x] 1.2 `terraform/variables.tf` — всички параметри (RAM, CPU, IPs)
- [x] 1.3 `terraform/vms.tf` — 7 VM ресурса с for_each
- [x] 1.4 `terraform/outputs.tf` — IPs + автоматичен Ansible inventory
- [x] 1.5 `terraform/cloud-init/` — lb.yaml, control.yaml, worker.yaml
- [x] 1.6 `terraform/terraform.tfvars` — твоите реални стойности
- [x] `.gitignore` — state файл и tfvars извън git

#### Предварително: Активирай Parallels API

```
Parallels Desktop → Settings → Developer → Enable Parallels Desktop API
```

#### Команди за изпълнение

```bash
# 1. Влез в terraform директорията
cd platform_eng/terraform

# 2. Смени паролата в terraform.tfvars!
# parallels_password = "ТВОЯТА_MAC_ПАРОЛА"

# 3. Инициализирай — сваля Parallels provider plugin
terraform init

# 4. Виж какво ще се случи (dry run — нищо не се създава)
terraform plan

# 5. Създай VM-ите
terraform apply
# Terraform пита "Do you want to perform these actions? yes/no"
# Пиши: yes

# 6. Провери outputs (IP адреси)
terraform output
```

#### Какво се случва при `terraform apply`

```
Terraform чете vms.tf → вижда 7 resource блока
       ↓
Праща API заявки към Parallels Desktop (localhost:8080)
       ↓
Parallels създава 7 VM-а от Ubuntu ARM64 image
       ↓
Подава cloud-init YAML на всеки VM
       ↓
VM-ите стартират → cloud-init задава IP, инсталира пакети, рестартира
       ↓
Terraform записва резултата в terraform.tfstate
       ↓
outputs.tf генерира ansible/inventory.ini автоматично
```

#### Troubleshooting Phase 1

| Проблем | Причина | Решение |
|---|---|---|
| `Error: connection refused localhost:8080` | Parallels API не е активиран | Settings → Developer → Enable API |
| `Error: authentication failed` | Грешна парола в tfvars | Провери `parallels_password` в terraform.tfvars |
| `Error: image not found "ubuntu-22.04-arm64"` | Image-ът не съществува в Parallels | Свали Ubuntu 22.04 ARM64 image в Parallels |
| VM boot-ва но IP не се задава | cloud-init грешка | `ssh ubuntu@VM_IP` → `cat /var/log/cloud-init-output.log` |
| `swap` грешка при kubeadm после | swap не е изключен | Виж cloud-init runcmd — `swapoff -a` трябва да е минал |
| terraform.tfstate се счупи | apply прекъснат наполовина | `terraform refresh` → `terraform apply` отново |

#### Верификация след Phase 1

```bash
# Провери дали VM-ите са стартирали
prlctl list -a

# Трябва да видиш:
# UUID    STATUS    NAME
# ...     running   k8s-lb
# ...     running   k8s-control-01
# ...     running   k8s-control-02
# ...     running   k8s-control-03
# ...     running   k8s-worker-01
# ...     running   k8s-worker-02
# ...     running   k8s-worker-03

# Тествай SSH достъп до lb
ssh -i ~/.ssh/k8s-local ubuntu@192.168.64.10

# Провери дали IP е зададен правилно
ip addr show enp0s5

# Провери дали swap е изключен (трябва да е ПРАЗЕН)
free -h
```

### Phase 2 — Ansible: HAProxy + kubeadm Bootstrap

- [ ] 2.1 Ansible inventory от Terraform outputs
- [ ] 2.2 Playbook `haproxy.yml`: инсталация и конфигурация на HAProxy (TCP :6443)
- [ ] 2.3 Playbook `prereqs.yml`: containerd, kubeadm, kubelet, kubectl на всички nodes
- [ ] 2.4 Playbook `control-init.yml`: `kubeadm init` на `control-01` с `--control-plane-endpoint` и `--upload-certs`
- [ ] 2.5 Playbook `control-join.yml`: join `control-02` и `control-03`
- [ ] 2.6 Playbook `worker-join.yml`: join `worker-01/02/03`
- [ ] 2.7 Playbook `flannel.yml`: инсталация на Flannel CNI
- [ ] 2.8 Fetch kubeconfig локално → `~/.kube/config`

### Phase 3 — Helm: Core Add-ons

- [ ] 3.1 MetalLB — IP pool `192.168.64.100-192.168.64.120`
- [ ] 3.2 ingress-nginx като DaemonSet на workers
- [ ] 3.3 local-path-provisioner за dynamic PVCs
- [ ] 3.4 cert-manager

### Phase 4 — GitOps: ArgoCD Bootstrap

- [ ] 4.1 Инсталация на ArgoCD (Helm)
- [ ] 4.2 Git repo конфигурация (GitHub / Gitea self-hosted)
- [ ] 4.3 ArgoCD App-of-Apps pattern за всички следващи инструменти
- [ ] 4.4 TeamCity deploy като ArgoCD Application (Helm chart)
- [ ] 4.5 kube-prometheus-stack (Prometheus + Grafana) като ArgoCD Application

### Phase 5 — Верификация

- [ ] 5.1 `kubectl get nodes` — всички 6 nodes в Ready
- [ ] 5.2 HA тест: спри `control-01`, провери дали API-то отговаря през LB
- [ ] 5.3 Deploy тестово приложение с `LoadBalancer` Service и Ingress
- [ ] 5.4 Тест на PVC creation
- [ ] 5.5 ArgoCD UI достъпен, sync работи
- [ ] 5.6 TeamCity CI pipeline минава успешно

---

## Структура на Terraform файловете

```
platform_eng/                        ← тук сме сега
├── terraform/
│   ├── main.tf              # Parallels provider конфигурация
│   ├── variables.tf         # RAM, CPU, IPs, disk
│   ├── vms.tf               # 7 VM ресурса
│   ├── outputs.tf           # IPs → Ansible inventory
│   └── cloud-init/
│       ├── lb.yaml
│       ├── control.yaml
│       └── worker.yaml
├── ansible/
│   ├── inventory.ini        # Генериран от Terraform outputs
│   ├── group_vars/
│   │   └── all.yml          # K8s версия, pod CIDR и др.
│   └── playbooks/
│       ├── haproxy.yml
│       ├── prereqs.yml
│       ├── control-init.yml
│       ├── control-join.yml
│       ├── worker-join.yml
│       └── flannel.yml
├── argocd-apps/
│   ├── metallb/
│   ├── ingress-nginx/
│   ├── cert-manager/
│   ├── teamcity/
│   └── kube-prometheus-stack/
└── k8s-ha-cluster-plan.md   # този файл
```

---

## Известни рискове

| Риск | Детайл | Митигация |
|---|---|---|
| Worker RAM | 2GB е минимум — достатъчно за dev workloads | Вдигни на 4GB ако ще deploy-ваш FinPulse тук |
| Parallels provider | По-малко матур от VMware провайдъри | Имай готов bash fallback за VM creation |
| Apple Silicon | ~~Нужен ARM64 image~~ → **M3 потвърден, ARM64 Ubuntu** ✓ | TeamCity има ARM64 image, повечето popular charts са OK |
| Статични IP | Parallels Shared Network изисква netplan конфигурация в cloud-init | Тествай с един VM преди да вдигнеш всички |

---

## Предварителни изисквания

- [x] Parallels Desktop 26.3.1 инсталиран ✓
- [ ] **Parallels API активиран** ← следваща стъпка!
- [x] M3 чип → ARM64 Ubuntu 22.04 image ✓
- [x] Terraform v1.5.7 инсталиран ✓
- [x] Ansible 13.6.0 инсталиран ✓
- [ ] Ubuntu 22.04 ARM64 cloud image свален в Parallels
- [x] SSH key pair генериран (`~/.ssh/k8s-local`) ✓
- [x] Свободни ≥ 20GB RAM (64GB) ✓

---

## Отворени въпроси

1. ~~Колко RAM има Mac-ът?~~ → 64GB ✓
2. ~~Apple Silicon или Intel?~~ → M3, ARM64 ✓
3. ~~Parallels Desktop версия?~~ → 26.3.1 ✓
4. ~~Terraform само VM-и или всичко IaC?~~ → **Terraform + Ansible + ArgoCD** ✓
5. Workers на 2GB или 4GB? (4GB препоръчително ако ще deploy-ваш FinPulse тук)
6. Git платформа за ArgoCD: GitHub или self-hosted Gitea в cluster-а?
