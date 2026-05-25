#!/usr/bin/env bash
# =============================================================================
# paso8-screenshot.sh — Solo PASO 8: curl desde EC2 al FQDN interno
#
# Pre-requisitos: clusters ya corriendo, Istio instalado, receiver desplegado
# Uso: bash scripts/paso8-screenshot.sh
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AWS_DIR="${REPO_ROOT}/terraform/envs/dev/aws"
ADDONS="${REPO_ROOT}/addons/istio"
SSH_KEY="${HOME}/.ssh/id_rsa"
AWS_REGION="us-east-1"

log()  { echo -e "\n\033[1;34m[$(date +%H:%M:%S)] $*\033[0m"; }
ok()   { echo -e "\033[1;32m  ✓ $*\033[0m"; }

# =============================================================================
log "1 — Obtener outputs de Terraform"
# =============================================================================
cd "${AWS_DIR}"
VM_PRIVATE_IP=$(terraform output -raw vm_private_ip)
VM_PUBLIC_IP=$(terraform output -raw vm_public_ip)
ok "EC2 priv: ${VM_PRIVATE_IP}  pub: ${VM_PUBLIC_IP}"

# =============================================================================
log "2 — Obtener LB del Gateway en EKS"
# =============================================================================
EKS_LB=$(kubectl get gateway receiver-gateway -n default \
  --context cluster1-eks \
  -o jsonpath='{.status.addresses[0].value}')
ok "EKS LB: ${EKS_LB}"

# Resolver el hostname del ELB a IP
EKS_LB_IP=$(dig +short "${EKS_LB}" | grep -E '^[0-9]+\.' | head -1)
ok "EKS LB IP: ${EKS_LB_IP}"

# =============================================================================
log "3 — PASO 7: WorkloadEntry + SA + WorkloadGroup en EKS"
# =============================================================================
kubectl apply -f "${ADDONS}/cluster1-eks/service-account.yaml" --context cluster1-eks
kubectl apply -f "${ADDONS}/cluster1-eks/workload-group.yaml" --context cluster1-eks

sed "s|REPLACE_WITH_EC2_PRIVATE_IP|${VM_PRIVATE_IP}|g" \
  "${ADDONS}/cluster1-eks/workload-entry.yaml" | kubectl apply -f - --context cluster1-eks

ok "WorkloadEntry registrado: ${VM_PRIVATE_IP}"
kubectl get workloadentry -n default --context cluster1-eks

# =============================================================================
log "4 — PASO 9: AuthPolicy con sender-vm"
# =============================================================================
kubectl apply -f "${ADDONS}/cluster1-eks/authorization-policy-with-vm.yaml" --context cluster1-eks
ok "AuthPolicy: receiver-gateway-istio + sender-vm permitidos"

# =============================================================================
log "5 — PASO 8: SSH a EC2 → curl receiver.default.svc.cluster.local"
# =============================================================================
echo ""
echo "  Agregando /etc/hosts en EC2: ${EKS_LB_IP} → receiver.default.svc.cluster.local"

ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "${SSH_KEY}" \
  "ec2-user@${VM_PUBLIC_IP}" bash <<REMOTE
set -e
# Agregar entrada al /etc/hosts para que el FQDN resuelva al LB de EKS
grep -q "receiver.default.svc.cluster.local" /etc/hosts || \
  sudo bash -c 'echo "${EKS_LB_IP} receiver.default.svc.cluster.local" >> /etc/hosts'

echo "=== /etc/hosts ==="
grep "receiver" /etc/hosts

echo ""
echo "================================================================"
echo "  PASO 8 — curl http://receiver.default.svc.cluster.local/"
echo "  TOMAR SCREENSHOT DE ESTE OUTPUT"
echo "================================================================"
echo ""

curl -sv http://receiver.default.svc.cluster.local/ 2>&1

echo ""
echo "================================================================"
REMOTE

echo ""
ok "Screenshot listo — PASO 8 completado"
echo ""
echo "  WorkloadEntry: kubectl get workloadentry --context cluster1-eks"
echo "  AuthPolicy:    kubectl describe authorizationpolicy receiver-allow-ingress-only -n default --context cluster1-eks"
