# Blue-Green Flow on Kubernetes

This repository demonstrates a simple Blue-Green deployment strategy on Kubernetes for a small Node.js web app. It contains:

- A sample app (Express) exposing `/` and `/health` on port 3000.
- Two Deployments (blue and green), a Service, and optional Ingress.
- Helper scripts to deploy a new image, switch traffic, port-forward for local testing, and run health checks.

Note: Filenames for the deployments use `deployement-*.yaml` (with an extra ‘e’) to match the current repo.

## Architecture overview

- Namespace: `blue-green-demo`
- Deployments:
  - Blue: `k8s/deployement-blue.yaml` → `Deployment/app-blue` using image `inestmimi123/blue-green-app:1.0.0`
  - Green: `k8s/deployement-green.yaml` → `Deployment/app-green` using image `inestmimi123/blue-green-app:1.1.0`
- Service: `k8s/service.yaml` named `web` targets label selector `app=web,color=<blue|green>`
  - Default selector is `color: blue` so “blue” receives traffic initially.
- Ingress (optional): `k8s/ingress.yaml` for host `bg.localtest.me` routing to the `web` Service.

The app reports its `color` and `version` from environment variables and exposes a `GET /health` endpoint for probes and external checks.

## Prerequisites

- A working Kubernetes cluster with `kubectl` configured.
- Optional: an Ingress controller (e.g., NGINX Ingress) if you plan to use the provided Ingress.
- If running the helper scripts:
  - They are Bash scripts meant for macOS/Linux. On Windows, run them under WSL or Git Bash. Alternatively, adapt the shown `kubectl` commands manually in PowerShell.

## Quick start

1) Create the namespace

```bash
kubectl apply -f k8s/namespace.yaml
```

2) Deploy blue and green (both can exist; Service points to blue initially)

```bash
kubectl apply -f k8s/deployement-blue.yaml
kubectl apply -f k8s/deployement-green.yaml
kubectl apply -f k8s/service.yaml
```

3) (Optional) Apply Ingress

```bash
kubectl apply -f k8s/ingress.yaml
```

4) Access the app

- Port-forward the Service:

```bash
scripts/port_forward.sh
# or manually
kubectl -n blue-green-demo port-forward svc/web 8080:80
```

- Open:
  - http://localhost:8080/ → JSON info including color and version
  - http://localhost:8080/health → should return 200 OK

## Blue-Green deployment flow

Assume blue is serving traffic and a new version should be rolled out to green.

1) Update the green deployment to a new image and wait for rollout

Using the helper script (Bash):

```bash
# Deploy new image to green and switch the Service selector to green once ready
scripts/deploy.sh green <REGISTRY>/<REPO>/blue-green-app:<TAG>
```

What the script does:
- kubectl set image on `deployment/app-green` (namespace `blue-green-demo`)
- Waits for rollout to complete
- Switches Service `web` selector to `color: green`

Manual commands equivalent:

```bash
# Set image and wait for rollout
kubectl -n blue-green-demo set image deployment/app-green app=<REGISTRY>/<REPO>/blue-green-app:<TAG>
kubectl -n blue-green-demo rollout status deployment/app-green

# Switch traffic to green
kubectl -n blue-green-demo patch service web -p '{"spec":{"selector":{"app":"web","color":"green"}}}'
```

2) Verify

With port-forward still active:

```bash
curl -fsS http://localhost:8080/health && echo OK
curl -fsS http://localhost:8080/ | jq .
```

Or use the provided script:

```bash
scripts/health_check.sh http://localhost:8080/health 30 1
```

3) Roll back (if needed)

To route traffic back to blue quickly:

```bash
scripts/switch_traffic.sh blue
# or manually
kubectl -n blue-green-demo patch service web -p '{"spec":{"selector":{"app":"web","color":"blue"}}}'
```

4) Scale down the idle color (optional)

To save resources you can scale down the non-active color after confidence:

```bash
kubectl -n blue-green-demo scale deployment/app-blue --replicas=0
# or for green if blue is active
kubectl -n blue-green-demo scale deployment/app-green --replicas=0
```

## Building and publishing the app image

If you need to build your own image:

```bash
cd app
# Build image
docker build -t <REGISTRY>/<REPO>/blue-green-app:<TAG> .
# Push image
docker push <REGISTRY>/<REPO>/blue-green-app:<TAG>
```

Then use that image with the deployment flow above.

## File reference

- app/Dockerfile — Node 20-alpine base, installs deps, runs `npm start`.
- app/src/server.js — Express server exposing `/` and `/health`.
- k8s/namespace.yaml — Creates namespace `blue-green-demo`.
- k8s/deployement-blue.yaml — Deployment `app-blue`, default image `inestmimi123/blue-green-app:1.0.0`.
- k8s/deployement-green.yaml — Deployment `app-green`, default image `inestmimi123/blue-green-app:1.1.0`.
- k8s/service.yaml — Service `web`, selector defaults to `color: blue`, port 80 → targetPort 3000.
- k8s/ingress.yaml — Ingress for host `bg.localtest.me` to Service `web` (requires Ingress controller).
- scripts/deploy.sh — Update target deployment image, wait for rollout, switch Service.
- scripts/switch_traffic.sh — Patch Service selector to `blue` or `green` and wait for endpoints.
- scripts/port_forward.sh — Port-forward `web` Service to localhost:8080.
- scripts/health_check.sh — Simple curl-based health checker.

## Troubleshooting

- Probes failing: Ensure the container responds on `/health` and that `targetPort` matches `containerPort` (here 3000).
- Service not switching: Verify labels on Pods include both `app=web` and the correct `color`. Check with:

```bash
kubectl -n blue-green-demo get pods -l app=web -L color
kubectl -n blue-green-demo get svc web -o yaml
kubectl -n blue-green-demo get endpoints web -o wide
```

- Script usage on Windows: Run under WSL or Git Bash. Otherwise, copy the shown `kubectl` commands to PowerShell.

## Advanced usage

- Windows users: scripts are Bash. Use WSL/Git Bash or run the equivalent kubectl commands shown.
- GitOps flow: This repo pairs with a GitOps repository (see Jenkinsfile env GITOPS_REPO_SSH). The pipeline updates deployment-green.yaml and switches Service selector via PR/commit.
- Health gates: Before switching traffic, ensure /health returns 200 for the target color. Example curl probes are provided.
- Rollback strategy: Switch back selector and optionally scale down the bad color. Keep both colors for fast recovery.

## Jenkins pipeline overview

The included Jenkinsfile performs:
- Build Node app and Docker image, push to registry.
- Update GitOps repo with the new image in deployment-green and APP_VERSION env.
- Wait for GREEN health via HEALTH_URL.
- Switch Service selector to green. On failure, auto-rollback selector to blue.

Required Jenkins credentials:
- docker-registry: Docker username/password
- gitops-bot: credentials to push to the GitOps repo

Key env vars in Jenkinsfile:
- REGISTRY, APP_NAME, GITOPS_REPO_SSH, GITOPS_BRANCH, HEALTH_URL, NAMESPACE

## Observability quick start

To add Prometheus metrics to the app, install prom-client and expose /metrics:

```bash
npm i prom-client
```

Add to app/src/server.js:

```js
const client = require('prom-client');
client.collectDefaultMetrics();
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});
```

Then deploy kube-prometheus-stack and a ServiceMonitor as shown in GUIDE.md.

## License

MIT
