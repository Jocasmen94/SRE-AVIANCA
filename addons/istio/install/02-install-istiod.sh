#!/bin/bash
# Install istiod on a cluster
# Usage: ./02-install-istiod.sh <context> <values-file>
# Example: ./02-install-istiod.sh cluster1-eks values-istiod-eks.yaml
set -e

ISTIO_VERSION="${ISTIO_VERSION:-1.24.3}"
CONTEXT="${1:-cluster1-eks}"
VALUES_FILE="${2:-values-istiod-eks.yaml}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================"
echo "Instalando Istiod — contexto: ${CONTEXT}"
echo "================================================"

echo "1. Instalando istiod ${ISTIO_VERSION}..."
helm upgrade --install istiod istio/istiod \
  --kube-context "${CONTEXT}" \
  -n istio-system \
  --version "${ISTIO_VERSION}" \
  -f "${SCRIPT_DIR}/${VALUES_FILE}" \
  --wait \
  --timeout 5m

echo "2. Habilitando sidecar injection en namespace default..."
kubectl label namespace default istio-injection=enabled \
  --context "${CONTEXT}" \
  --overwrite

echo ""
echo "3. Verificando instalación..."
kubectl get pods -n istio-system --context "${CONTEXT}"

echo ""
echo "✅ Istiod instalado en ${CONTEXT}"
