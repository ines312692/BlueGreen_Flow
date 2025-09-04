# scripts/switch_traffic.sh
#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"
NS="${NS:-blue-green-demo}"

if [[ "$TARGET" != "blue" && "$TARGET" != "green" ]]; then
  echo "Usage: $0 [blue|green]"
  exit 1
fi

echo "Bascule du Service vers: ${TARGET}"
kubectl -n "${NS}" patch service web -p \
  "{\"spec\":{\"selector\":{\"app\":\"web\",\"color\":\"${TARGET}\"}}}"

echo "Attente de la mise à jour des Endpoints..."
for i in {1..30}; do
  READY=$(kubectl -n "${NS}" get endpoints web -o jsonpath='{range .subsets[*].addresses[*]}1{end}')
  if [[ -n "${READY}" ]]; then
    echo "Endpoints prêts."
    break
  fi
  echo "En attente (${i}/30)..."
  sleep 1
done