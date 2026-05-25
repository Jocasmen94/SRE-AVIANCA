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
log "5 — PASO 8: configurar EC2 via SSM y abrir sesión interactiva"
# =============================================================================
INSTANCE_ID=$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --filters "Name=network-interface.association.public-ip,Values=${VM_PUBLIC_IP}" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)
ok "Instance ID: ${INSTANCE_ID}"

# Esperar a que SSM esté disponible
warn "Esperando SSM agent en EC2..."
for i in $(seq 1 18); do
  STATUS=$(aws ssm describe-instance-information \
    --region "${AWS_REGION}" \
    --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
    --query 'InstanceInformationList[0].PingStatus' \
    --output text 2>/dev/null || echo "None")
  [[ "${STATUS}" == "Online" ]] && break
  echo -n "."
  sleep 10
done
echo ""
ok "SSM Online"

# Agregar /etc/hosts en EC2 via SSM send-command
CMD_ID=$(aws ssm send-command \
  --instance-ids "${INSTANCE_ID}" \
  --document-name "AWS-RunShellScript" \
  --region "${AWS_REGION}" \
  --parameters "commands=[\"grep -q receiver.default.svc.cluster.local /etc/hosts || echo '${EKS_LB_IP}  receiver.default.svc.cluster.local' | sudo tee -a /etc/hosts\"]" \
  --query 'Command.CommandId' \
  --output text)

aws ssm wait command-executed \
  --command-id "${CMD_ID}" \
  --instance-id "${INSTANCE_ID}" \
  --region "${AWS_REGION}" 2>/dev/null || true
ok "/etc/hosts configurado en EC2"

# =============================================================================
echo ""
echo "================================================================="
echo "  PASO 8 — SCREENSHOT"
echo "  Abre una nueva terminal y ejecuta:"
echo ""
echo "  aws ssm start-session --target ${INSTANCE_ID} --region ${AWS_REGION}"
echo ""
echo "  Dentro de la EC2 ejecuta:"
echo "  curl -sv http://receiver.default.svc.cluster.local/"
echo ""
echo "  Toma el screenshot mostrando 'hello world'"
echo "================================================================="
echo ""
ok "Setup listo — abre la sesión SSM en otra terminal para el screenshot"
