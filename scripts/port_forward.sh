# scripts/port_forward.sh
#!/usr/bin/env bash
set -euo pipefail
NS="${1:-blue-green-demo}"
echo "Port-forward du Service web dans le namespace ${NS} sur http://localhost:8080 ..."
kubectl -n "${NS}" port-forward svc/web 8080:80