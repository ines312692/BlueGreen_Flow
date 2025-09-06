# scripts/deploy.sh
#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"
IMAGE="${2:-}"
NS="${NS:-blue-green-demo}"

if [[ "$TARGET" != "blue" && "$TARGET" != "green" ]]; then
  echo "Usage: $0 [blue|green] <image>"
  echo "Ex: $0 green inestmimi123/blue-green-app:1.2.0"
  exit 1
fi
if [[ -z "${IMAGE}" ]]; then
  echo "Image requise."
  exit 1
fi

DEPLOY="app-${TARGET}"

echo "Déploiement ${DEPLOY} avec l'image ${IMAGE}..."
kubectl -n "${NS}" set image "deployment/${DEPLOY}" app="${IMAGE}"

echo "Attente du rollout..."
kubectl -n "${NS}" rollout status "deployment/${DEPLOY}"

echo "Bascule du trafic..."
"$(dirname "$0")/switch_traffic.sh" "${TARGET}"

OTHER="blue"
[[ "$TARGET" == "blue" ]] && OTHER="green"

echo "Optionnel: scale down de ${OTHER} (conserver pour rollback rapide)"
# kubectl -n "${NS}" scale deployment "app-${OTHER}" --replicas=0

echo "OK. Trafic actif: ${TARGET}"