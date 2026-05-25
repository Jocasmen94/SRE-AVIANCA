#!/usr/bin/env bash
# =============================================================================
# destroy-full.sh — Elimina toda la infraestructura de la prueba SRE Avianca
#
# Orden:
#   1. Release EIP del EC2 (evita DependencyViolation en destroy AWS)
#   2. Terraform destroy AWS (EKS + EC2)
#   3. Terraform destroy GCP (GKE)
#   4. Limpia kubeconfig (contextos cluster1-eks y cluster2-gke)
#
# Uso: bash scripts/destroy-full.sh
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AWS_DIR="${REPO_ROOT}/terraform/envs/dev/aws"
GCP_DIR="${REPO_ROOT}/terraform/envs/dev/gcp"
AWS_REGION="us-east-1"

log()  { echo -e "\n\033[1;34m[$(date +%H:%M:%S)] $*\033[0m"; }
ok()   { echo -e "\033[1;32m  ✓ $*\033[0m"; }
warn() { echo -e "\033[1;33m  ⚠ $*\033[0m"; }

# =============================================================================
log "1 — Liberar EIP del EC2 (evita DependencyViolation)"
# =============================================================================
cd "${AWS_DIR}"

# Obtener allocation IDs de EIPs asociadas a instancias EC2 con tag sre-*
EIPS=$(aws ec2 describe-addresses \
  --region "${AWS_REGION}" \
  --filters "Name=domain,Values=vpc" \
  --query 'Addresses[?InstanceId!=null && contains(Tags[?Key==`Name`].Value | [0], `sre`)].AllocationId' \
  --output text 2>/dev/null || echo "")

if [[ -n "${EIPS}" ]]; then
  for ALLOC_ID in ${EIPS}; do
    warn "Desasociando y liberando EIP: ${ALLOC_ID}"
    # Desasociar primero
    ASSOC_ID=$(aws ec2 describe-addresses \
      --allocation-ids "${ALLOC_ID}" \
      --region "${AWS_REGION}" \
      --query 'Addresses[0].AssociationId' \
      --output text 2>/dev/null || echo "")
    if [[ -n "${ASSOC_ID}" && "${ASSOC_ID}" != "None" ]]; then
      aws ec2 disassociate-address --association-id "${ASSOC_ID}" --region "${AWS_REGION}" 2>/dev/null || true
      ok "EIP desasociada: ${ASSOC_ID}"
    fi
    aws ec2 release-address --allocation-id "${ALLOC_ID}" --region "${AWS_REGION}" 2>/dev/null || true
    ok "EIP liberada: ${ALLOC_ID}"
  done
else
  warn "No se encontraron EIPs asociadas con tag sre-* (puede que ya estén liberadas)"
fi

# =============================================================================
log "2 — Terraform destroy AWS (EKS + EC2 + VPC)"
# =============================================================================
cd "${AWS_DIR}"
terraform init -input=false -reconfigure 2>/dev/null || true
terraform destroy -auto-approve -input=false || {
  warn "Primer destroy falló, reintentando (DependencyViolation puede necesitar 2 intentos)..."
  sleep 10
  terraform destroy -auto-approve -input=false
}
ok "AWS destruido"

# =============================================================================
log "3 — Terraform destroy GCP (GKE)"
# =============================================================================
cd "${GCP_DIR}"
terraform init -input=false -reconfigure 2>/dev/null || true
terraform destroy -auto-approve -input=false
ok "GCP destruido"

# =============================================================================
log "4 — Limpiar kubeconfig"
# =============================================================================
kubectl config delete-context cluster1-eks 2>/dev/null && ok "Contexto cluster1-eks eliminado" || warn "cluster1-eks ya no existe"
kubectl config delete-context cluster2-gke 2>/dev/null && ok "Contexto cluster2-gke eliminado" || warn "cluster2-gke ya no existe"

# =============================================================================
log "5 — Limpiar archivos temporales"
# =============================================================================
rm -rf /tmp/vm-certs 2>/dev/null && ok "Certs temp eliminados" || true

# =============================================================================
log "DESTROY COMPLETO"
# =============================================================================
echo ""
ok "Toda la infraestructura ha sido eliminada."
echo ""
echo "  Costo acumulado fue ~\$6-8 por 48hrs de uso."
echo "  Para recrear: bash scripts/setup-full.sh"
echo ""
