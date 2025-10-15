# GitOps Home Infrastructure

Kompletne rozwiązanie GitOps do zarządzania home infrastructure z wykorzystaniem ArgoCD, k3d i Kubernetes.

## 🏗️ Architektura

```
┌─────────────────────────────────────────────────────────┐
│                   Git Repository                         │
│              (Single Source of Truth)                    │
└───────────────────┬─────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────┐
│                      ArgoCD                              │
│            (Continuous Deployment)                       │
└───┬─────────────────────┬──────────────────────────────┘
    │                     │
    ▼                     ▼
┌──────────┐      ┌──────────────┐
│ Platform │      │ Applications │
│  Stack   │      │    Stack     │
└──────────┘      └──────────────┘
    │                     │
    ├─ Ingress-NGINX     ├─ Home Assistant
    ├─ Monitoring        ├─ Dashy (Dashboard)
    └─ Logging           ├─ InfluxDB
                         ├─ OpenWebUI
                         ├─ Grocy
                         └─ AdGuard
```

## 📁 Struktura Katalogów

```
gitops/
├── apps/                      # Definicje aplikacji
│   ├── home-assistant/       # Home automation
│   ├── dashy/                # Service dashboard (MAIN ENTRY POINT)
│   ├── influxdb/             # Time-series database
│   ├── openwebui/            # AI interface
│   ├── grocy/                # Inventory management
│   ├── adguard/              # DNS ad blocker
│   └── argocd-ingress/       # ArgoCD UI ingress
│
├── platform/                  # Platform services
│   ├── ingress-nginx/        # Ingress controller
│   ├── monitoring/           # kube-prometheus-stack (Prometheus + Grafana)
│   └── logging/              # Loki stack
│
├── clusters/                  # Cluster-specific configs
│   ├── prod/                 # Production environment
│   │   ├── cluster-config.yaml      # k3d cluster config
│   │   └── argocd-apps/
│   │       ├── root-app.yaml        # App of Apps pattern
│   │       ├── platform.yaml        # Platform stack
│   │       └── apps.yaml            # Application stack
│   │
│   └── develop/              # Development environment
│       └── (similar structure)
│
└── scripts/                   # Automation scripts
    ├── bootstrap.sh          # Setup entire infrastructure
    └── destroy.sh            # Tear down clusters
```

## 🚀 Szybki Start

### Wymagania

- Docker
- kubectl
- k3d
- helm

### 1. Zainstaluj wszystko automatycznie

```bash
# Stwórz oba środowiska (prod + develop)
./gitops/scripts/bootstrap.sh

# Lub tylko production
./gitops/scripts/bootstrap.sh prod

# Lub tylko develop
./gitops/scripts/bootstrap.sh develop
```

### 2. Skonfiguruj /etc/hosts

Dodaj następujące wpisy do `/etc/hosts`:

```bash
# Production
127.0.0.1 dashy.local
127.0.0.1 argocd.local
127.0.0.1 grafana.local

# Development (opcjonalnie)
127.0.0.1 dashy-dev.local
127.0.0.1 argocd-dev.local
127.0.0.1 grafana-dev.local
```

**Linux/Mac:**
```bash
sudo vim /etc/hosts
```

**Windows (jako Administrator):**
```cmd
notepad C:\Windows\System32\drivers\etc\hosts
```

### 3. Dostęp do Aplikacji

Po uruchomieniu wszystkie aplikacje są dostępne przez przeglądarkę **BEZ port-forwarding**:

#### Production:
- 🏠 **Dashy Dashboard**: http://dashy.local (główny punkt wejścia)
- 🔄 **ArgoCD UI**: http://argocd.local
- 📊 **Grafana**: http://grafana.local

#### Development:
- 🏠 **Dashy Dashboard**: http://dashy-dev.local:8080
- 🔄 **ArgoCD UI**: http://argocd-dev.local:8080
- 📊 **Grafana**: http://grafana-dev.local:8080

### 4. Credentials

**ArgoCD:**
- Username: `admin`
- Password: Pobierz komendą:
  ```bash
  # Production
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" --context k3d-home-prod | base64 -d

  # Development
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" --context k3d-home-develop | base64 -d
  ```

**Grafana (z kube-prometheus-stack):**
- Username: `admin`
- Password: `admin123` (zmień po pierwszym logowaniu!)

## 🔧 Zarządzanie

### Zobacz status aplikacji

```bash
# Lista aplikacji w ArgoCD
kubectl get applications -n argocd --context k3d-home-prod

# Status konkretnej aplikacji
kubectl get application dashy-prod -n argocd --context k3d-home-prod -o yaml
```

### Synchronizacja ręczna

```bash
# Jeśli coś nie zadziałało automatycznie
kubectl patch application <app-name> -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"normal"}}}' \
  --context k3d-home-prod
```

### Zobacz logi

```bash
# Logi ArgoCD
kubectl logs -n argocd deployment/argocd-server --context k3d-home-prod

# Logi konkretnej aplikacji
kubectl logs -n <namespace> deployment/<app-name> --context k3d-home-prod
```

## 🛠️ Rozwój

### Dodanie nowej aplikacji

1. Stwórz strukturę w `gitops/apps/`:
   ```
   gitops/apps/my-app/
   ├── base/
   │   ├── kustomization.yaml
   │   ├── deployment.yaml
   │   └── service.yaml
   └── overlays/
       ├── prod/
       │   └── kustomization.yaml
       └── develop/
           └── kustomization.yaml
   ```

2. Dodaj Application do `clusters/prod/argocd-apps/apps.yaml`:
   ```yaml
   ---
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: my-app-prod
     namespace: argocd
   spec:
     project: default
     source:
       repoURL: https://github.com/Kobeep/Home_infra.git
       targetRevision: main
       path: gitops/apps/my-app/overlays/prod
     destination:
       server: https://kubernetes.default.svc
       namespace: my-app
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
       syncOptions:
         - CreateNamespace=true
   ```

3. Commit i push - ArgoCD automatycznie zdeployuje!

### Testowanie zmian

```bash
# Zbuduj lokalnie Kustomize
kustomize build gitops/apps/my-app/overlays/prod

# Zastosuj bez commitu (dla testów)
kustomize build gitops/apps/my-app/overlays/prod | kubectl apply -f -
```

## 🔒 Bezpieczeństwo

### Domyślna Architektura Bezpieczeństwa

- ✅ **Tylko Dashy ma publiczny ingress** - wszystkie inne usługi są dostępne tylko wewnętrznie
- ✅ **ArgoCD ma dedykowany ingress** - do zarządzania, nie publicznie dostępny
- ✅ **Grafana ma ingress** - monitoring dla administratora
- ❌ **Inne serwisy (Home Assistant, InfluxDB, etc.)** - tylko ClusterIP, dostęp przez Dashy

### Zalecane Ulepszenia

1. **Użyj Sealed Secrets** zamiast plain text passwords
2. **Skonfiguruj TLS/SSL** z cert-manager
3. **Dodaj Network Policies** dla izolacji
4. **Użyj AppProjects w ArgoCD** dla RBAC

## 📊 Monitoring

### kube-prometheus-stack

System używa **kube-prometheus-stack** który zapewnia:
- **Prometheus** - zbieranie metryk (http://grafana.local → Explore)
- **Grafana** - wizualizacja (http://grafana.local)
- **Alertmanager** - alerty (tylko prod)

### Dostęp do metryk

Wszystkie metryki Kubernetes są automatycznie zbierane. Grafana ma pre-configured datasource dla Prometheusa.

## 🧹 Czyszczenie

```bash
# Usuń wszystko
./gitops/scripts/destroy.sh

# Usuń tylko prod
./gitops/scripts/destroy.sh prod

# Usuń tylko develop
./gitops/scripts/destroy.sh develop
```

## 🐛 Troubleshooting

### Aplikacja nie startuje

```bash
# Sprawdź status w ArgoCD
kubectl get application <app-name> -n argocd

# Sprawdź logi ArgoCD dla aplikacji
kubectl logs -n argocd deployment/argocd-application-controller | grep <app-name>

# Sprawdź pod
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

### Ingress nie działa

```bash
# Sprawdź czy ingress-nginx działa
kubectl get pods -n ingress-nginx

# Sprawdź ingress
kubectl get ingress -A

# Sprawdź czy porty są zmapowane w k3d
docker ps | grep k3d
```

### Monitoring się nie uruchamia

```bash
# Sprawdź czy PVC są utworzone
kubectl get pvc -n monitoring

# Sprawdź logi operatora
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator

# Sprawdź zasoby
kubectl top nodes
kubectl top pods -n monitoring
```

### ArgoCD nie synchronizuje

```bash
# Wymuś refresh
kubectl patch application <app-name> -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Usuń i stwórz na nowo
kubectl delete application <app-name> -n argocd
kubectl apply -f clusters/prod/argocd-apps/apps.yaml
```

## 📚 Dodatkowe Zasoby

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kustomize Documentation](https://kustomize.io/)
- [k3d Documentation](https://k3d.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## 🤝 Contributing

1. Fork repository
2. Stwórz feature branch (`git checkout -b feature/amazing-feature`)
3. Commit zmiany (`git commit -m 'Add amazing feature'`)
4. Push do brancha (`git push origin feature/amazing-feature`)
5. Otwórz Pull Request

## 📝 License

MIT License - zobacz [LICENSE](../LICENSE)

---

**Przygotowane przez:** Jakub Pospieszyński
**Data aktualizacji:** 2025-01-16
