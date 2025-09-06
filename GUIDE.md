# Complete Guide: Blue-Green Deployment + Monitoring + CI/CD (EN)

This guide provides an end-to-end walkthrough for installing, operating, and observing the Blue-Green Flow project.

Contents:
- Blue/Green deployment on Kubernetes (manually and via scripts)
- GitOps/Jenkins integration (pipeline included)
- Prometheus/Grafana monitoring via Argo CD
- Troubleshooting and best practices

Prerequisites
- A working kubectl pointing to your cluster
- Access to a Docker registry
- (Optional) Ingress Controller to expose the app and/or Grafana
- (Optional) Argo CD installed for the GitOps/monitoring parts

Part A — Blue/Green (quick recap)
- Namespace: blue-green-demo
- Service web selects app=web, color=<blue|green>
- Switch traffic:
  kubectl -n blue-green-demo patch service web -p '{"spec":{"selector":{"app":"web","color":"green"}}}'
- Roll back:
  kubectl -n blue-green-demo patch service web -p '{"spec":{"selector":{"app":"web","color":"blue"}}}'

Part B — Jenkins Pipeline (GitOps CI/CD)
1) Jenkins secrets/credentials
- docker-registry: Docker login credentials
- gitops-bot: SSH/https credentials to push to the GitOps repo
2) Pipeline variables (see Jenkinsfile)
- REGISTRY, GITOPS_REPO_SSH, GITOPS_BRANCH, HEALTH_URL, NAMESPACE
3) Pipeline flow
- Build Node app, build & push Docker image
- GitOps commit: update deployment-green.yaml (image + APP_VERSION)
- Wait for GREEN health (curl on HEALTH_URL)
- Switch Service to green
- Auto-rollback to blue on failure

Part C — Monitoring (Prometheus + Grafana) via Argo CD

Variables to customize
- <GRAFANA_ADMIN_PASSWORD>: Grafana admin password
- <GRAFANA_HOST>: Grafana FQDN (e.g., grafana.example.com)
- <KPS_CHART_VERSION>: kube-prometheus-stack chart version (e.g., 62.7.0)

Step 1 — Create the “monitoring” namespace
```bash
kubectl create namespace monitoring || true
```

Step 2 — Deploy kube-prometheus-stack via Argo CD
Create a file named app-monitoring.yaml (locally), then apply it in the argocd namespace.
Example Argo CD Application:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-monitoring
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/prometheus-community/helm-charts
    targetRevision: <KPS_CHART_VERSION>
    chart: kube-prometheus-stack
    helm:
      values: |
        grafana:
          adminPassword: <GRAFANA_ADMIN_PASSWORD>
          service:
            type: ClusterIP
          ingress:
            enabled: false
        prometheus:
          service:
            type: ClusterIP
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Apply the Application:
```bash
kubectl -n argocd apply -f app-monitoring.yaml
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=2m || true
```

Step 3 — Temporarily access Grafana (port-forward)
```bash
kubectl -n monitoring port-forward svc/platform-monitoring-grafana 3000:80
# then open http://localhost:3000 (admin / <GRAFANA_ADMIN_PASSWORD>)
```

Step 4 — Wire the application with a ServiceMonitor
Create a ServiceMonitor that targets your app’s Kubernetes Service (Service "web" in namespace "blue-green-demo", a port named "http", endpoint /metrics).
Example:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: web-servicemonitor
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: web
  namespaceSelector:
    matchNames: ["blue-green-demo"]
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```
Apply:
```bash
kubectl -n monitoring apply -f servicemonitor.yaml
```

Step 5 — Add metrics in the app (Node.js)
Add prom-client to the app if missing:
```bash
npm i prom-client
```
Minimal example in app/src/server.js:
```js
const client = require('prom-client');
client.collectDefaultMetrics();
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});
```
Redeploy and then check the target in Prometheus Targets.

Step 6 — (Optional) Expose Grafana via Ingress
Edit app-monitoring.yaml to enable Grafana ingress, then re-apply.
Example configuration (grafana.values section):
```yaml
        grafana:
          ingress:
            enabled: true
            ingressClassName: nginx
            hosts: ["<GRAFANA_HOST>"]
            path: /
            pathType: Prefix
```

Step 7 — Import Grafana dashboards
- Log into Grafana → Dashboards → Import.
- Import a Node.js/Express (prom-client) dashboard. Configure the Prometheus data source.

Best practices
- Security: use Secrets for the Grafana admin password and restrict network access.
- GitOps: version-control app-monitoring.yaml and the ServiceMonitor in your GitOps repo.
- Label consistency: the ServiceMonitor uses selector.matchLabels.app=web. Ensure your Service has app: web and a port named http.
- Troubleshooting:
  - kubectl -n monitoring get servicemonitor, pod
  - Inspect Prometheus Targets for scrape statuses.

Updates and removal
- Update: change targetRevision (<KPS_CHART_VERSION>) and re-apply the Argo CD Application.
- Uninstall: kubectl -n argocd delete app platform-monitoring; then delete the monitoring namespace if needed.