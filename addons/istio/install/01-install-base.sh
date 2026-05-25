#!/bin/bash
# Install Istio Base on both clusters
# Run AFTER: terraform apply (clusters must exist and kubeconfig configured)
set -e

ISTIO_VERSION="${ISTIO_VERSION:-1.24.3}"
CONTEXT="${1:-cluster1-eks}"  # or cluster2-gke

echo "================================================"
echo "Instalando Istio Base — contexto: ${CONTEXT}"
echo "================================================"

echo "1. Agregando repositorio de Istio..."
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

echo "2. Creando namespace istio-system..."
kubectl create namespace istio-system --context "${CONTEXT}" 2>/dev/null || \
  echo "Namespace istio-system ya existe en ${CONTEXT}"

echo "3. Instalando Gateway API CRDs (requerido antes de istiod)..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml \
  --context "${CONTEXT}"

echo "4. Instalando istio-base ${ISTIO_VERSION}..."
helm upgrade --install istio-base istio/base \
  --kube-context "${CONTEXT}" \
  -n istio-system \
  --version "${ISTIO_VERSION}" \
  --set defaultRevision=default

echo ""
echo "✅ Istio Base instalado en ${CONTEXT}"
echo "Siguiente paso: 02-install-istiod.sh ${CONTEXT}"
