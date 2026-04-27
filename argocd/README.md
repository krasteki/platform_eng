# App-of-Apps ArgoCD Pattern

## Структура

```
argocd/
├── projects/
│   └── platform.yaml         # AppProject — RBAC граница за всички platform apps
├── apps/
│   ├── metallb.yaml          # MetalLB — LoadBalancer за bare metal
│   ├── ingress-nginx.yaml    # Ingress controller
│   ├── cert-manager.yaml     # TLS certificates
│   └── kube-prometheus-stack.yaml  # Monitoring stack
└── root-app.yaml             # Root Application — управлява argocd/apps/
```

## Концепцията App-of-Apps

```
                ┌──────────────┐
                │   root-app   │  (следи argocd/apps/ в Git)
                └──────┬───────┘
                       │ управлява
        ┌──────────────┼──────────────┬──────────────┐
        ▼              ▼              ▼              ▼
   [metallb]   [ingress-nginx]  [cert-manager]  [prometheus]
```

- **root-app** следи `argocd/apps/` директорията в Git
- Всеки `*.yaml` файл там е ArgoCD `Application`
- Нова app = нов файл в Git → ArgoCD я открива и деплойва автоматично

## Deployment (след push в GitHub)

### 1. Обнови `root-app.yaml` с твоето GitHub repo:
```bash
# Замени в root-app.yaml:
repoURL: https://github.com/ТВОЕТО_USERNAME/platform_eng.git
```

### 2. Push в GitHub:
```bash
cd /Users/krasteki/krasteki/platform_eng
git init
git add .
git commit -m "feat: add App-of-Apps ArgoCD structure"
git remote add origin https://github.com/ТВОЕТО_USERNAME/platform_eng.git
git push -u origin main
```

### 3. Приложи root-app в ArgoCD:
```bash
KUBECONFIG=~/.kube/k8s-local-config kubectl apply -f argocd/root-app.yaml
```

### 4. ArgoCD ще открие и синхронизира всички apps автоматично

## Проверка
```bash
# Виж всички apps
KUBECONFIG=~/.kube/k8s-local-config kubectl get applications -n argocd

# ArgoCD UI
open https://argocd.k8s.local
# admin / SiHiyMcdVNOfF8Iq
```

## Добавяне на нова app
```bash
# Просто добави нов файл в argocd/apps/:
cat > argocd/apps/my-new-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
...
EOF
git add . && git commit -m "feat: add my-new-app" && git push
# ArgoCD автоматично я открива и деплойва
```
