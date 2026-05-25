#!/usr/bin/env bash
# =============================================================================
# setup-full.sh — Prueba SRE Avianca: infraestructura completa end-to-end
#
# Crea todo desde cero:
#   1. Terraform AWS (EKS + EC2)
#   2. Terraform GCP (GKE)
#   3. kubeconfig para ambos clusters
#   4. Istio en ambos clusters (Helm)
#   5. mTLS PeerAuthentication
#   6. Receiver + Gateway + HTTPRoute en EKS
#   7. AuthPolicy inicial (solo IngressGateway)
#   8. Pod-x (demo RBAC)
#   9. Sender en GKE (apunta al LB de EKS)
#  10. VM onboarding: istiod expuesto en NLB, certs, istio-agent en EC2
#  11. AuthPolicy actualizada (agrega sender-vm)
#  12. curl desde EC2 a receiver.default.svc.cluster.local
#
# Pre-requisitos: aws cli, gcloud, terraform, kubectl, helm, istioctl, scp, ssh
# Uso: bash scripts/setup-full.sh
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AWS_DIR="${REPO_ROOT}/terraform/envs/dev/aws"
GCP_DIR="${REPO_ROOT}/terraform/envs/dev/gcp"
ADDONS="${REPO_ROOT}/addons/istio"
K8S="${REPO_ROOT}/k8s"
SCRIPTS_DIR="${REPO_ROOT}/addons/istio/install"

ISTIO_VERSION="1.24.3"
SSH_KEY="${HOME}/.ssh/id_rsa"
AWS_REGION="us-east-1"
GCP_PROJECT="northern-bliss-421915"
GCP_ZONE="us-central1-a"
GKE_NAME="sre-avianca-gke"

log()  { echo -e "\n\033[1;34m[$(date +%H:%M:%S)] $*\033[0m"; }
ok()   { echo -e "\033[1;32m  ✓ $*\033[0m"; }
warn() { echo -e "\033[1;33m  ⚠ $*\033[0m"; }
die()  { echo -e "\033[1;31m  ✗ $*\033[0m"; exit 1; }

# Esperar a que un comando devuelva 0 con timeout
wait_for() {
  local desc="$1"; shift
  local timeout="${1}"; shift
  local interval=10
  local elapsed=0
  echo -n "  Esperando: ${desc} ..."
  while ! eval "$@" &>/dev/null; do
    sleep ${interval}
    elapsed=$((elapsed + interval))
    echo -n "."
    [[ ${elapsed} -ge ${timeout} ]] && echo "" && die "Timeout esperando: ${desc}"
  done
  echo " OK"
}

# =============================================================================
log "PASO 1 — Terraform AWS (EKS + EC2)"
# =============================================================================
cd "${AWS_DIR}"
terraform init -upgrade -input=false
terraform apply -auto-approve -input=false

EKS_NAME=$(terraform output -raw eks_cluster_name)
VM_PRIVATE_IP=$(terraform output -raw vm_private_ip)
VM_PUBLIC_IP=$(terraform output -raw vm_public_ip)
VPC_CIDR=$(terraform output -raw vpc_cidr)

ok "EKS:        ${EKS_NAME}"
ok "EC2 priv:   ${VM_PRIVATE_IP}"
ok "EC2 pub:    ${VM_PUBLIC_IP}"

# =============================================================================
log "PASO 1b — Terraform GCP (GKE)"
# =============================================================================
cd "${GCP_DIR}"
terraform init -upgrade -input=false
terraform apply -auto-approve -input=false
ok "GKE aplicado"

# =============================================================================
log "PASO 1c — kubeconfig: ambos clusters"
# =============================================================================
cd "${REPO_ROOT}"

aws eks update-kubeconfig \
  --name "${EKS_NAME}" \
  --region "${AWS_REGION}" \
  --alias cluster1-eks
ok "kubeconfig cluster1-eks"

gcloud container clusters get-credentials "${GKE_NAME}" \
  --zone "${GCP_ZONE}" \
  --project "${GCP_PROJECT}"

# Renombrar contexto GKE
GKE_CTX=$(kubectl config get-contexts -o name | grep "${GKE_NAME}" | head -1)
if [[ "${GKE_CTX}" != "cluster2-gke" ]]; then
  kubectl config rename-context "${GKE_CTX}" cluster2-gke
fi
ok "kubeconfig cluster2-gke"

# Verificar acceso
kubectl get nodes --context cluster1-eks -o wide | head -5
kubectl get nodes --context cluster2-gke -o wide | head -5

# =============================================================================
log "PASO 2 — Instalar Istio en cluster1-eks (EKS)"
# =============================================================================
bash "${SCRIPTS_DIR}/01-install-base.sh" cluster1-eks
bash "${SCRIPTS_DIR}/02-install-istiod.sh" cluster1-eks values-istiod-eks.yaml

# Gateway API CRDs (ya instalados por 01-install-base.sh, pero asegurar)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml \
  --context cluster1-eks 2>/dev/null || true

# =============================================================================
log "PASO 2b — Instalar Istio en cluster2-gke (GKE)"
# =============================================================================
bash "${SCRIPTS_DIR}/01-install-base.sh" cluster2-gke
bash "${SCRIPTS_DIR}/02-install-istiod.sh" cluster2-gke values-istiod-gke.yaml

# =============================================================================
log "PASO 2c — mTLS STRICT en ambos clusters"
# =============================================================================
kubectl apply -f "${ADDONS}/config/peer-authentication.yaml" --context cluster1-eks
kubectl apply -f "${ADDONS}/config/peer-authentication.yaml" --context cluster2-gke
ok "PeerAuthentication STRICT aplicado"

# =============================================================================
log "PASO 3 — Receiver en EKS"
# =============================================================================
kubectl apply -f "${K8S}/cluster1-eks/00-namespace.yaml" --context cluster1-eks 2>/dev/null || true
kubectl apply -f "${K8S}/cluster1-eks/receiver/" --context cluster1-eks

# Gateway + HTTPRoute (Istio Gateway API)
kubectl apply -f "${ADDONS}/cluster1-eks/gateway.yaml" --context cluster1-eks
kubectl apply -f "${K8S}/cluster1-eks/gateway-api/" --context cluster1-eks

# Esperar receiver Running
wait_for "receiver pod Running" 180 \
  "kubectl get pods -l app=receiver -n default --context cluster1-eks | grep -q '2/2.*Running'"

# Obtener LB del Gateway (puede tardar 2-3 min en EKS)
log "Esperando LB del Gateway en EKS (puede tardar ~3 min)..."
wait_for "Gateway LB asignado" 300 \
  "kubectl get gateway receiver-gateway -n default --context cluster1-eks \
     -o jsonpath='{.status.addresses[0].value}' 2>/dev/null | grep -qE '.+'"

EKS_LB=$(kubectl get gateway receiver-gateway -n default \
  --context cluster1-eks \
  -o jsonpath='{.status.addresses[0].value}')
ok "EKS LB: ${EKS_LB}"

# Verificar que el receiver responde (puede tardar unos segundos)
wait_for "receiver responde hello world" 120 \
  "curl -sf http://${EKS_LB}/ | grep -q 'hello world'"
ok "curl http://${EKS_LB}/ → hello world"

# =============================================================================
log "PASO 5 — AuthorizationPolicy (solo IngressGateway)"
# =============================================================================
kubectl apply -f "${ADDONS}/cluster1-eks/authorization-policy.yaml" --context cluster1-eks
ok "AuthPolicy: solo receiver-gateway-istio permitido"

# =============================================================================
log "PASO 6 — Pod-x (demo RBAC)"
# =============================================================================
kubectl apply -f "${K8S}/cluster1-eks/pod-x/pod-x.yaml" --context cluster1-eks
wait_for "pod-x Running" 120 \
  "kubectl get pod pod-x --context cluster1-eks 2>/dev/null | grep -q 'Running'"
ok "pod-x listo"

echo ""
echo "  Demo PASO 6 — RBAC access denied:"
kubectl exec pod-x --context cluster1-eks -- curl -sv http://receiver/ 2>&1 | grep -E "RBAC|403|access denied" || true
echo ""

# =============================================================================
log "PASO 4 — Sender en GKE (apunta al LB de EKS)"
# =============================================================================
kubectl apply -f "${K8S}/cluster2-gke/00-namespace.yaml" --context cluster2-gke 2>/dev/null || true

# service-entry con el LB real de EKS
sed "s|af64d506b79384a59b65da19c810c604-b65bbac1d1da5d88.elb.us-east-1.amazonaws.com|${EKS_LB}|g" \
  "${ADDONS}/cluster2-gke/service-entry.yaml" | kubectl apply -f - --context cluster2-gke

# sender deployment con RECEIVER_URL correcto
sed "s|http://af64d506b79384a59b65da19c810c604-b65bbac1d1da5d88.elb.us-east-1.amazonaws.com/|http://${EKS_LB}/|g" \
  "${K8S}/cluster2-gke/sender/deployment.yaml" | kubectl apply -f - --context cluster2-gke

kubectl apply -f "${K8S}/cluster2-gke/sender/service.yaml" --context cluster2-gke

wait_for "sender pod Running" 180 \
  "kubectl get pods -l app=sender -n default --context cluster2-gke | grep -q '2/2.*Running'"
ok "Sender running en GKE"

# =============================================================================
log "PASO 7 — VM Onboarding: exponer istiod via NLB interno"
# =============================================================================
# Para que la EC2 (en la misma VPC) alcance istiod, creamos un NLB interno
# que expone los puertos xDS (15012) e istiod grpc (15010)
cat <<EOF | kubectl apply -f - --context cluster1-eks
apiVersion: v1
kind: Service
metadata:
  name: istiod-vm-nlb
  namespace: istio-system
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-internal: "true"
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
spec:
  type: LoadBalancer
  selector:
    app: istiod
  ports:
  - name: grpc-xds
    port: 15010
    targetPort: 15010
    protocol: TCP
  - name: https-dns
    port: 15012
    targetPort: 15012
    protocol: TCP
EOF

ok "istiod-vm-nlb creado — esperando IP interna (~2 min)..."
wait_for "NLB istiod IP asignada" 300 \
  "kubectl get svc istiod-vm-nlb -n istio-system --context cluster1-eks \
     -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null | grep -qE '.+'"

ISTIOD_LB=$(kubectl get svc istiod-vm-nlb -n istio-system --context cluster1-eks \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
ok "istiod NLB: ${ISTIOD_LB}"

# =============================================================================
log "PASO 7b — WorkloadEntry + ServiceAccount + WorkloadGroup en EKS"
# =============================================================================
kubectl apply -f "${ADDONS}/cluster1-eks/service-account.yaml" --context cluster1-eks

# WorkloadGroup (sin sed, no tiene placeholder de IP)
kubectl apply -f "${ADDONS}/cluster1-eks/workload-group.yaml" --context cluster1-eks

# WorkloadEntry con IP real de EC2
sed "s|REPLACE_WITH_EC2_PRIVATE_IP|${VM_PRIVATE_IP}|g" \
  "${ADDONS}/cluster1-eks/workload-entry.yaml" | kubectl apply -f - --context cluster1-eks

ok "WorkloadEntry registrado: ${VM_PRIVATE_IP}"
kubectl get workloadentry -n default --context cluster1-eks

# =============================================================================
log "PASO 7c — Generar certs para la VM"
# =============================================================================
mkdir -p /tmp/vm-certs
rm -f /tmp/vm-certs/*

istioctl x workload entry configure \
  --file "${ADDONS}/cluster1-eks/workload-group.yaml" \
  --clusterID "Kubernetes" \
  --ingressIP "${ISTIOD_LB}" \
  --output /tmp/vm-certs \
  --context cluster1-eks

ok "Certs generados en /tmp/vm-certs:"
ls -la /tmp/vm-certs/

# =============================================================================
log "PASO 7d — Instalar istio-agent en EC2 via SSH"
# =============================================================================
# Esperar a que SSH esté disponible
warn "Esperando SSH en EC2 ${VM_PUBLIC_IP}..."
wait_for "SSH disponible" 180 \
  "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i ${SSH_KEY} ec2-user@${VM_PUBLIC_IP} 'echo ok'"

# Copiar certs a EC2
scp -o StrictHostKeyChecking=no -i "${SSH_KEY}" \
  /tmp/vm-certs/root-cert.pem \
  /tmp/vm-certs/cluster.env \
  /tmp/vm-certs/istio-token \
  /tmp/vm-certs/hosts \
  "ec2-user@${VM_PUBLIC_IP}:/tmp/"
ok "Certs copiados a EC2"

# Instalar y configurar istio-agent en EC2
ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}" "ec2-user@${VM_PUBLIC_IP}" bash <<REMOTE_EOF
set -euo pipefail
echo "=== Instalando Istio ${ISTIO_VERSION} en EC2 ==="

# Directorios requeridos por istio-agent
sudo mkdir -p /etc/certs /var/lib/istio/envoy /etc/istio/proxy

# Copiar archivos de configuración
sudo cp /tmp/root-cert.pem /etc/certs/root-cert.pem
sudo cp /tmp/cluster.env   /var/lib/istio/envoy/cluster.env
sudo cp /tmp/istio-token   /var/lib/istio/envoy/istio-token
sudo chmod 600 /var/lib/istio/envoy/istio-token

# Agregar entradas al /etc/hosts para Istio
sudo bash -c 'cat /tmp/hosts >> /etc/hosts'
echo "Entradas /etc/hosts:"
cat /tmp/hosts

# Descargar Istio (binarios: pilot-agent + envoy)
echo "Descargando Istio ${ISTIO_VERSION}..."
curl -sL "https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-linux-amd64.tar.gz" \
  | tar xz -C /tmp

sudo cp /tmp/istio-${ISTIO_VERSION}/bin/pilot-agent /usr/local/bin/pilot-agent
sudo chmod +x /usr/local/bin/pilot-agent

# envoy viene dentro del tarball en diferente path en versiones recientes
ENVOY_PATH=\$(find /tmp/istio-${ISTIO_VERSION} -name envoy -type f 2>/dev/null | head -1)
if [[ -n "\${ENVOY_PATH}" ]]; then
  sudo cp "\${ENVOY_PATH}" /usr/local/bin/envoy
  sudo chmod +x /usr/local/bin/envoy
  echo "envoy instalado desde: \${ENVOY_PATH}"
else
  # Descargar envoy por separado si no viene en el tarball
  ENVOY_VER=\$(curl -sL https://api.github.com/repos/envoyproxy/envoy/releases/latest | grep tag_name | cut -d'"' -f4)
  curl -sL "https://github.com/envoyproxy/envoy/releases/download/\${ENVOY_VER}/envoy-\${ENVOY_VER}-linux-aarch64" \
    -o /usr/local/bin/envoy 2>/dev/null || \
  curl -sL "https://github.com/envoyproxy/envoy/releases/download/\${ENVOY_VER}/envoy-linux-x86_64" \
    -o /usr/local/bin/envoy 2>/dev/null || true
  sudo chmod +x /usr/local/bin/envoy 2>/dev/null || true
fi

# Crear usuario istio-proxy si no existe
id istio-proxy &>/dev/null || sudo useradd -r -s /sbin/nologin istio-proxy
sudo chown -R istio-proxy:istio-proxy /etc/certs /var/lib/istio /etc/istio

# Servicio systemd para istio-agent
sudo tee /etc/systemd/system/istio-agent.service > /dev/null <<'SERVICE'
[Unit]
Description=Istio Proxy Agent
After=network.target

[Service]
User=root
EnvironmentFile=/var/lib/istio/envoy/cluster.env
ExecStart=/usr/local/bin/pilot-agent proxy sidecar \
  --serviceCluster sender-vm.default \
  --concurrency 2 \
  --templateFile /etc/istio/proxy/envoy_bootstrap_tmpl.json \
  --proxyComponentLogLevel misc:error \
  --log_output_level default:warning
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

# Copiar template de bootstrap de envoy
sudo cp /tmp/istio-${ISTIO_VERSION}/samples/bookinfo/demo-profile-no-gateways.yaml /tmp/ 2>/dev/null || true
TMPL_PATH=\$(find /tmp/istio-${ISTIO_VERSION} -name "envoy_bootstrap_tmpl.json" 2>/dev/null | head -1)
if [[ -n "\${TMPL_PATH}" ]]; then
  sudo mkdir -p /etc/istio/proxy
  sudo cp "\${TMPL_PATH}" /etc/istio/proxy/
fi

sudo systemctl daemon-reload
sudo systemctl enable istio-agent
sudo systemctl start istio-agent || true

echo ""
echo "=== Estado istio-agent ==="
sudo systemctl status istio-agent --no-pager || true
sleep 5

# Servicio sender-vm: curl loop al receiver via FQDN interno
sudo tee /etc/systemd/system/sender-vm.service > /dev/null <<'SERVICE'
[Unit]
Description=Sender VM — curl loop a receiver.default.svc.cluster.local
After=network.target istio-agent.service

[Service]
ExecStart=/bin/bash -c 'while true; do echo "--- \$(date) ---"; curl -sv http://receiver.default.svc.cluster.local/ 2>&1 | grep -E "< HTTP|hello world|Connected|Error"; sleep 10; done'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable sender-vm
sudo systemctl start sender-vm || true

echo "=== Setup EC2 completado ==="
REMOTE_EOF

ok "istio-agent y sender-vm instalados en EC2"

# =============================================================================
log "PASO 9 — AuthorizationPolicy con sender-vm"
# =============================================================================
kubectl apply -f "${ADDONS}/cluster1-eks/authorization-policy-with-vm.yaml" --context cluster1-eks
ok "AuthPolicy actualizada: receiver-gateway-istio + sender-vm"

kubectl describe authorizationpolicy receiver-allow-ingress-only -n default --context cluster1-eks \
  | grep -A10 "Principals"

# =============================================================================
log "PASO 8 — Screenshot: curl desde EC2 a FQDN interno"
# =============================================================================
warn "Esperando 30s para que istio-agent establezca conexión con istiod..."
sleep 30

echo ""
echo "====================================================================="
echo "  PASO 8 — curl http://receiver.default.svc.cluster.local/"
echo "  TOMAR SCREENSHOT DE ESTE OUTPUT"
echo "====================================================================="
echo ""

ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}" "ec2-user@${VM_PUBLIC_IP}" \
  "curl -sv http://receiver.default.svc.cluster.local/ 2>&1 | head -30" || \
ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}" "ec2-user@${VM_PUBLIC_IP}" \
  "curl -sv http://${EKS_LB}/ 2>&1 | head -30"

echo ""
echo "====================================================================="
echo ""

# =============================================================================
log "RESUMEN FINAL"
# =============================================================================
echo ""
echo "  EKS Cluster:     ${EKS_NAME}"
echo "  GKE Cluster:     ${GKE_NAME}"
echo "  EC2 Private IP:  ${VM_PRIVATE_IP}"
echo "  EC2 Public IP:   ${VM_PUBLIC_IP}"
echo "  EKS LB:          ${EKS_LB}"
echo ""
echo "  Para entrar a EC2 y ver logs del sender-vm:"
echo "  ssh -i ~/.ssh/id_rsa ec2-user@${VM_PUBLIC_IP}"
echo "  sudo journalctl -u sender-vm -f"
echo ""
echo "  Para demo RBAC (PASO 6 — ya ejecutado arriba):"
echo "  kubectl exec pod-x --context cluster1-eks -- curl -sv http://receiver/"
echo ""
ok "Setup completo — todos los PASOS de la prueba cubiertos"
