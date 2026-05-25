#!/usr/bin/env bash
# =============================================================================
# paso8-screenshot.sh — PASO 8: curl desde EC2 a receiver.default.svc.cluster.local
#
# Pre-requisitos: clusters corriendo, Istio instalado, receiver desplegado
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
warn() { echo -e "\033[1;33m  ⚠ $*\033[0m"; }

cleanup_sg() {
  if [[ -n "${SG_ID:-}" && -n "${MY_IP:-}" ]]; then
    aws ec2 revoke-security-group-ingress \
      --group-id "${SG_ID}" --protocol tcp --port 22 --cidr "${MY_IP}/32" \
      --region "${AWS_REGION}" 2>/dev/null && warn "Puerto 22 cerrado en SG" || true
  fi
}
trap cleanup_sg EXIT

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

EKS_LB_IP=$(dig +short "${EKS_LB}" | grep -E '^[0-9]+\.' | head -1)
ok "EKS LB IP: ${EKS_LB_IP}"

# =============================================================================
log "3 — PASO 7: WorkloadEntry con IP correcta + SA + WorkloadGroup"
# =============================================================================
kubectl apply -f "${ADDONS}/cluster1-eks/service-account.yaml" --context cluster1-eks

kubectl apply -f "${ADDONS}/cluster1-eks/workload-group.yaml" --context cluster1-eks

# Aplicar WorkloadEntry inline con la IP real (no depender de sed sobre archivo)
kubectl apply -f - --context cluster1-eks <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: WorkloadEntry
metadata:
  name: sender-vm-entry
  namespace: default
spec:
  address: "${VM_PRIVATE_IP}"
  labels:
    app: sender-vm
    version: v1
  serviceAccount: sender-vm
EOF

ok "WorkloadEntry registrado: ${VM_PRIVATE_IP}"
kubectl get workloadentry -n default --context cluster1-eks

# =============================================================================
log "4 — PASO 9: AuthPolicy con sender-vm"
# =============================================================================
kubectl apply -f "${ADDONS}/cluster1-eks/authorization-policy-with-vm.yaml" --context cluster1-eks
ok "AuthPolicy: receiver-gateway-istio + sender-vm"

# =============================================================================
log "5 — Abrir puerto 22 temporalmente para SSH"
# =============================================================================
MY_IP=$(curl -s https://checkip.amazonaws.com)
ok "Tu IP pública: ${MY_IP}"

SG_ID=$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --filters "Name=network-interface.association.public-ip,Values=${VM_PUBLIC_IP}" \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
  --output text)
ok "Security Group: ${SG_ID}"

aws ec2 authorize-security-group-ingress \
  --group-id "${SG_ID}" \
  --protocol tcp --port 22 --cidr "${MY_IP}/32" \
  --region "${AWS_REGION}" 2>/dev/null && ok "Puerto 22 abierto para ${MY_IP}" || warn "Regla ya existe"

# Esperar a que SSH esté disponible
warn "Esperando SSH..."
for i in $(seq 1 12); do
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "${SSH_KEY}" \
    "ec2-user@${VM_PUBLIC_IP}" 'exit' 2>/dev/null && break
  echo -n "."
  sleep 5
done
echo ""
ok "SSH disponible"

# =============================================================================
log "6 — PASO 8: curl desde EC2 a receiver.default.svc.cluster.local"
# =============================================================================
ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}" "ec2-user@${VM_PUBLIC_IP}" bash <<REMOTE
set -e
# Agregar FQDN interno al /etc/hosts apuntando al LB de EKS
grep -q "receiver.default.svc.cluster.local" /etc/hosts || \
  sudo bash -c 'echo "${EKS_LB_IP}  receiver.default.svc.cluster.local" >> /etc/hosts'

echo "=== /etc/hosts ==="
grep "receiver" /etc/hosts || true

echo ""
echo "================================================================="
echo "  PASO 8 — curl http://receiver.default.svc.cluster.local/"
echo "================================================================="
echo ""
curl -sv http://receiver.default.svc.cluster.local/ 2>&1
echo ""
echo "================================================================="
REMOTE

echo ""
ok "PASO 8 completado — toma el screenshot de la salida de arriba"
echo ""
echo "  Para abrir una sesión interactiva en la EC2:"
echo "  ssh -i ~/.ssh/id_rsa ec2-user@${VM_PUBLIC_IP}"
