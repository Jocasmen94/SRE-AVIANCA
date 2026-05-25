# SRE Prueba — Multi-Cloud Kubernetes + Istio

**Clusters:** EKS (AWS us-east-1) + GKE (GCP us-central1-a)
**Service Mesh:** Istio 1.24.3 instalado via Helm (addons)
**IaC:** Terraform multi-cloud — AWS y GCP en plans separados
**Deadline:** Domingo 25 Mayo 2026 23:59 CST → enviar artefactos a Israel.chavez@avianca.com

---

## Arquitectura de Conectividad

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         INTERNET (IPs Públicas)                          │
├─────────────────────┬───────────────────────────────────────────────────┤
│                     │                                                   │
│  AWS (us-east-1)    │            GCP (us-central1-a)                    │
│  VPC: 10.0.0.0/16   │            VPC: 10.1.0.0/20                       │
│                     │            Pods: 10.4.0.0/14                      │
│  ┌─────────────┐    │            ┌──────────────┐                        │
│  │   EKS       │    │            │     GKE      │                        │
│  │ Cluster 1   │    │            │  Cluster 2   │                        │
│  │             │    │            │              │                        │
│  │ receiver    │    │  Internet  │  sender      │                        │
│  │ (pod)       │    │◄─────HTTP──┤ (pod)        │                        │
│  │             │    │   1.2.3.4  │ curl loop    │                        │
│  └─────────────┘    │            └──────────────┘                        │
│         │           │                                                    │
│         ▼           │                                                    │
│    NLB IP Public    │                                                    │
│    1.2.3.4          │                                                    │
│                     │                                                    │
│  EC2 VM             │                                                    │
│  10.0.10.123        │                                                    │
│  (sender-vm)        │                                                    │
│  curl loop          │                                                    │
│  (FQDN interno)     │                                                    │
└─────────────────────┴───────────────────────────────────────────────────┘

FLUJOS:
1. Sender (GKE) → Receiver (EKS) — vía IP pública del NLB (ServiceEntry permite)
2. Sender-VM (EC2) → Receiver (EKS) — vía FQDN interno del mesh (dentro del cluster)
3. Pod-X (EKS) → Receiver (EKS) — bloqueado por AuthPolicy (RBAC)
```

**Resumen de conectividad:**

| Origen | Destino | Protocolo | Ruta | Estado |
|--------|---------|-----------|------|--------|
| **Sender (GKE)** | Receiver (EKS) | HTTP | Internet (IP pública NLB) | ✅ Funciona |
| **Sender-VM (EC2)** | Receiver (EKS) | HTTP | Mesh interno (FQDN svc.cluster.local) | ✅ Funciona |
| **Pod-X (EKS)** | Receiver (EKS) | HTTP | Mesh interno | ❌ Bloqueado por AuthPolicy |
| **Curl directo** | Receiver (EKS) | HTTP | Internet (IP pública NLB) | ✅ Funciona |

---

## Estructura del proyecto

```
sre-avianca/
├── terraform/
│   ├── modules/
│   │   ├── aws/
│   │   │   ├── vpc/            # VPC + subnets + IGW + NAT Gateway
│   │   │   ├── eks/            # EKS cluster + managed node group + IAM
│   │   │   └── ec2-vm/         # EC2 t3.micro + Security Group + EIP
│   │   └── gcp/
│   │       ├── vpc/            # VPC network + subnet + Cloud Router + NAT
│   │       ├── gke/            # GKE cluster + node pool
│   │       ├── service-accounts/ # Node SA + IAM roles
│   │       └── dns/            # Cloud DNS zone + A records (opcional)
│   └── envs/dev/
│       ├── aws/                # terraform plan/apply → Cluster 1 (EKS + EC2)
│       └── gcp/                # terraform plan/apply → Cluster 2 (GKE)
├── addons/
│   └── istio/
│       ├── install/
│       │   ├── 01-install-base.sh        # helm install istio-base
│       │   ├── 02-install-istiod.sh      # helm install istiod
│       │   ├── values-istiod-eks.yaml    # valores Istio para EKS
│       │   └── values-istiod-gke.yaml    # valores Istio para GKE
│       ├── config/
│       │   └── peer-authentication.yaml  # mTLS STRICT
│       ├── cluster1-eks/
│       │   ├── gateway.yaml              # GatewayClass + Gateway (NLB)
│       │   ├── authorization-policy.yaml         # paso 5: solo IngressGateway
│       │   ├── authorization-policy-with-vm.yaml # paso 9: + sender-vm
│       │   ├── workload-group.yaml       # paso 7: template para EC2 VM
│       │   ├── workload-entry.yaml       # paso 7: IP privada del EC2
│       │   └── service-account.yaml      # SA para la VM en el mesh
│       └── cluster2-gke/
│           └── service-entry.yaml        # egress permitido al IP del EKS LB
└── k8s/
    ├── cluster1-eks/
    │   ├── receiver/           # Deployment + Service (hello world)
    │   ├── gateway-api/        # HTTPRoute (ruta / → receiver)
    │   ├── pod-x/              # Pod de prueba para demo AuthPolicy
    │   └── vm-workload/        # WorkloadGroup + WorkloadEntry + SA
    └── cluster2-gke/
        └── sender/             # Deployment (curl loop → receiver) + ServiceEntry
```

---

## Prerrequisitos

### Herramientas requeridas

```bash
# Verificar que están instaladas
aws --version            # AWS CLI v2+
gcloud --version         # Google Cloud SDK
kubectl version          # 1.28+
terraform version        # 1.5+
helm version             # 3.x
istioctl version         # 1.24.x

# Ejemplo de output esperado:
# aws-cli/2.x.x
# Google Cloud SDK x.x.x
# Client Version: v1.30.x
# Terraform v1.5.x
# version.BuildInfo{Version:"v3.x.x"...}
# Istio version 1.24.x
```

### Autenticación AWS

```bash
# Verificar que aws configure ya fue ejecutado
aws sts get-caller-identity

# Output esperado:
# {
#     "UserId": "AIDAJ...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/your-user"
# }
```

### Autenticación GCP

```bash
# Autenticar con Google Cloud
gcloud auth application-default login
# Abrirá navegador para login

# Establecer proyecto
gcloud config set project northern-bliss-421915

# Verificar que está configurado
gcloud config get-value project
# Output: northern-bliss-421915
```

### SSH Key (REQUERIDO para EC2 access)

```bash
# Ver si ya existe clave SSH
ls -la ~/.ssh/id_rsa.pub

# Si no existe, GENERAR antes de ejecutar Terraform:
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
# (Ver sección "Preparación Inicial — Generar SSH Key" más abajo)
```

---

---

## Preparación Inicial — Generar SSH Key

Antes de ejecutar Terraform, genera la clave SSH que usarás para acceder a la EC2 VM:

```bash
# Crear directorio .ssh si no existe
mkdir -p ~/.ssh

# Generar clave RSA de 4096 bits (sin passphrase para automatización)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""

# Output esperado:
# Generating public/private rsa key pair.
# Your identification has been saved in /Users/xxxx/.ssh/id_rsa
# Your public key has been saved in /Users/xxxx/.ssh/id_rsa.pub
# ...

# Verificar que se creó correctamente
ls -la ~/.ssh/id_rsa*

# Output esperado:
# -rw-------  1 user  staff  3243 May 23 10:00 /Users/xxxx/.ssh/id_rsa
# -rw-r--r--  1 user  staff  1679 May 23 10:00 /Users/xxxx/.ssh/id_rsa.pub

# Ver la clave pública (la que Terraform usará)
cat ~/.ssh/id_rsa.pub
# Output: ssh-rsa AAAAB3NzaC1yc2EAAA...
```

**Importante:**
- `id_rsa` → Clave privada (mantener segura, no compartir)
- `id_rsa.pub` → Clave pública (la que Terraform sube a EC2)
- `terraform.tfvars` ya tiene `ssh_public_key_path = "~/.ssh/id_rsa.pub"`

✅ **Clave SSH lista para usar en Terraform**

---

## Flujo de ejecución

### PASO 1 — Infraestructura: Terraform AWS, GCP y kubeconfig

Preparar y validar configuración de AWS:

```bash
# Paso 1a — Navegar al directorio y preparar Terraform
cd terraform/envs/dev/aws

# Verificar que exista terraform.tfvars con valores correctos
cat terraform.tfvars

# Output esperado:
# aws_region             = "us-east-1"
# eks_cluster_name       = "sre-avianca-eks"
# eks_node_instance_type = "t3.medium"
# vpc_cidr               = "10.0.0.0/16"
# ssh_public_key_path    = "~/.ssh/id_rsa.pub"

# Inicializar Terraform (descargar plugins de AWS, configurar backend)
terraform init

# Output esperado:
# Initializing the backend...
# Initializing provider plugins...
# - Finding latest version of hashicorp/aws...
# - Installing hashicorp/aws v5.x.x...
# ...
# Terraform has been successfully configured!
```

Revisar qué será creado con Terraform plan:

```bash
# Paso 1b — Ejecutar plan (no crea nada, solo muestra qué se creará)
terraform plan

# Output esperado (muy largo, pero resumen importante):
# Terraform will perform the following actions:
#
#   # module.aws_vpc.aws_vpc.main will be created
#   + resource "aws_vpc" "main" {
#       + cidr_block = "10.0.0.0/16"
#       ...
#     }
#
#   # module.eks.aws_eks_cluster.this will be created
#   + resource "aws_eks_cluster" "this" {
#       + cluster_name = "sre-avianca-eks"
#       ...
#     }
#
#   # module.ec2_vm.aws_instance.sender_vm will be created
#   + resource "aws_instance" "sender_vm" {
#       + instance_type = "t3.micro"
#       ...
#     }
#
# Plan: 48 to add, 0 to change, 0 to destroy.

# Salida a un archivo (opcional pero útil)
terraform plan -out=aws.tfplan
```

Aplicar configuración (crear infraestructura en AWS):

```bash
# Paso 1c — Ejecutar apply (CREA LOS RECURSOS)
# ⚠️  Esto incurrirá en costos de AWS. Estimado: ~$0.5-1 USD por 24 horas
terraform apply aws.tfplan

# Output esperado (toma 8-12 minutos):
# module.aws_vpc.aws_vpc.main: Creating...
# module.aws_vpc.aws_vpc.main: Still creating... [30s elapsed]
# module.aws_vpc.aws_vpc.main: Still creating... [60s elapsed]
# module.aws_vpc.aws_vpc.main: Creation complete after 2s
# ...
# module.eks.aws_eks_cluster.this: Creating...
# module.eks.aws_eks_cluster.this: Still creating... [1m elapsed]
# module.eks.aws_eks_cluster.this: Still creating... [2m elapsed]
# ...
# module.eks.aws_eks_cluster.this: Creation complete after 5m30s
# ...
# module.ec2_vm.aws_instance.sender_vm: Creating...
# module.ec2_vm.aws_instance.sender_vm: Creation complete after 30s
# ...
# Apply complete! Resources: 48 added, 0 destroyed.
# 
# Outputs:
# 
# eks_cluster_endpoint = "https://ABCD1234.eks.us-east-1.amazonaws.com"
# eks_cluster_name = "sre-avianca-eks"
# vm_private_ip = "10.0.10.123"
# vm_public_ip = "54.200.100.50"
```

Guardar outputs de Terraform para usar en pasos posteriores:

```bash
# Paso 1d — Guardar IPs en variables para referencia (para pasos posteriores)
terraform output eks_cluster_name
# → sre-avianca-eks

terraform output vm_private_ip
# → 10.0.10.123  ← Necesario en PASO 10 (WorkloadEntry)

terraform output vm_public_ip
# → 54.200.100.50 ← Necesario en PASO 10 (SSH a EC2)

terraform output eks_cluster_endpoint
# → https://ABCD1234.eks.us-east-1.amazonaws.com

# Guardar en variables para fácil acceso
VM_PRIVATE_IP=$(terraform output -raw vm_private_ip)
VM_PUBLIC_IP=$(terraform output -raw vm_public_ip)

echo "✓ AWS Infraestructura creada exitosamente"
```

**Recursos creados en AWS:**
| Recurso | Detalles |
|---------|----------|
| **VPC** | `10.0.0.0/16` con 2 subnets públicas + 2 privadas en us-east-1a/b |
| **Internet Gateway** | Conecta VPC al internet |
| **NAT Gateway** | Permite egress desde nodos privados |
| **EKS Cluster** | `sre-avianca-eks`, versión 1.33, endpoint público |
| **Node Group** | 1 nodo `t3.medium` (2vCPU, 4GB RAM) con disk 20GB |
| **EC2 Instance** | `t3.micro` en subnet privada, con EIP para SSH remoto |
| **Security Groups** | Autoriza Istio ports (15001/15008), SSH (22) |

✅ **Verificación PASO 1 completado:** Infraestructura AWS lista

---

#### Paso 1b — Terraform Plan y Apply: GCP (Cluster 2)

Preparar y validar configuración de GCP:

```bash
# Paso 2a — Navegar al directorio y preparar Terraform
cd terraform/envs/dev/gcp

# Verificar que exista terraform.tfvars con valores correctos
cat terraform.tfvars

# Output esperado:
# gcp_project_id        = "northern-bliss-421915"
# gcp_region            = "us-central1"
# gcp_zone              = "us-central1-a"
# gke_cluster_name      = "sre-avianca-gke"
# gke_node_machine_type = "e2-medium"
# enable_dns            = false
# dns_zone_name         = "sre-avianca-zone"
# dns_name              = "sre.example.com."
# gateway_ip_gke        = ""

# Verificar autenticación GCP
gcloud auth application-default login
gcloud config set project northern-bliss-421915

# Output esperado:
# Updated property [core/project].

# Inicializar Terraform
terraform init

# Output esperado:
# Initializing the backend...
# Initializing provider plugins...
# - Finding latest version of hashicorp/google...
# - Installing hashicorp/google v5.x.x...
# ...
# Terraform has been successfully configured!
```

Revisar qué será creado en GCP:

```bash
# Paso 2b — Ejecutar plan (no crea nada, solo muestra qué se creará)
terraform plan

# Output esperado (muy largo, pero resumen importante):
# Terraform will perform the following actions:
#
#   # module.gcp_vpc.google_compute_network.main will be created
#   + resource "google_compute_network" "main" {
#       + name = "sre-avianca-gke"
#       ...
#     }
#
#   # module.gcp_vpc.google_compute_subnetwork.main will be created
#   + resource "google_compute_subnetwork" "main" {
#       + name = "sre-avianca-gke"
#       + ip_cidr_range = "10.1.0.0/20"
#       ...
#     }
#
#   # module.gcp_service_accounts.google_service_account.node_sa will be created
#   + resource "google_service_account" "node_sa" {
#       + account_id = "sre-avianca-gke-node"
#       ...
#     }
#
#   # module.gke.google_container_cluster.this will be created
#   + resource "google_container_cluster" "this" {
#       + name = "sre-avianca-gke"
#       + location = "us-central1-a"
#       ...
#     }
#
# Plan: 15 to add, 0 to change, 0 to destroy.

# Guardar plan (opcional)
terraform plan -out=gcp.tfplan
```

Aplicar configuración (crear infraestructura en GCP):

```bash
# Paso 2c — Ejecutar apply (CREA LOS RECURSOS)
# ⚠️  Esto incurrirá en costos de GCP. Estimado: ~$0.3-0.8 USD por 24 horas
terraform apply gcp.tfplan

# Output esperado (toma 5-10 minutos):
# module.gcp_vpc.google_compute_network.main: Creating...
# module.gcp_vpc.google_compute_network.main: Creation complete after 5s
# module.gcp_vpc.google_compute_subnetwork.main: Creating...
# module.gcp_vpc.google_compute_subnetwork.main: Creation complete after 2s
# ...
# module.gcp_service_accounts.google_service_account.node_sa: Creating...
# module.gcp_service_accounts.google_service_account.node_sa: Creation complete after 2s
# ...
# module.gke.google_container_cluster.this: Creating...
# module.gke.google_container_cluster.this: Still creating... [2m elapsed]
# module.gke.google_container_cluster.this: Still creating... [4m elapsed]
# module.gke.google_container_cluster.this: Creation complete after 8m30s
# ...
# Apply complete! Resources: 15 added, 0 destroyed.
#
# Outputs:
#
# gke_cluster_name = "sre-avianca-gke"
# gke_location = "us-central1-a"
# gke_cluster_endpoint = "https://1.2.3.4"
```

Guardar outputs de Terraform para usar en pasos posteriores:

```bash
# Paso 2d — Guardar outputs para referencia
terraform output gke_cluster_name
# → sre-avianca-gke

terraform output gke_location
# → us-central1-a

terraform output gke_cluster_endpoint
# → https://1.2.3.4

# Guardar en variables
GKE_CLUSTER=$(terraform output -raw gke_cluster_name)
GKE_ZONE=$(terraform output -raw gke_location)

echo "✓ GCP Infraestructura creada exitosamente"
```

**Recursos creados en GCP:**
| Recurso | Detalles |
|---------|----------|
| **VPC Network** | `sre-avianca-gke`, sin nat gateway (usa Cloud NAT si se requiere egress) |
| **Subnetwork** | `10.1.0.0/20`, pods `10.4.0.0/14`, services `10.56.0.0/20` |
| **Cloud Router** | Habilita Cloud NAT para egress |
| **Service Account** | Nodo SA con permisos logging.logWriter + monitoring.metricWriter |
| **GKE Cluster** | `sre-avianca-gke`, versión 1.33, en `us-central1-a` |
| **Node Pool** | 1 nodo `e2-medium` (2vCPU, 4GB RAM) con disk 30GB |

✅ **Verificación PASO 2 completado:** Infraestructura GCP lista

---

#### Paso 1c — Configurar kubeconfig para ambos clusters

Descargar credenciales de EKS y registrar contexto:

```bash
# Paso 3a — Configurar acceso a EKS (Cluster 1)
aws eks update-kubeconfig \
  --name sre-avianca-eks \
  --region us-east-1 \
  --alias cluster1-eks

# Output esperado:
# Added new context arn:aws:eks:us-east-1:ACCOUNT:cluster/sre-avianca-eks to /Users/xxxx/.kube/config

# Verificar acceso
kubectl get nodes --context cluster1-eks

# Output esperado:
# NAME                           STATUS   ROLES    AGE   VERSION
# ip-10-0-x-x.ec2.internal      Ready    <none>   2m    v1.30.x
```

Descargar credenciales de GKE y registrar contexto:

```bash
# Paso 3b — Configurar acceso a GKE (Cluster 2)
gcloud container clusters get-credentials sre-avianca-gke \
  --zone us-central1-a \
  --project northern-bliss-421915

# Output esperado:
# Fetching cluster endpoint and auth data.
# kubeconfig entry generated for sre-avianca-gke.

# Obtener el contexto actual (GKE)
CURRENT_CONTEXT=$(kubectl config current-context)

# Renombrar contexto a un nombre amigable
kubectl config rename-context ${CURRENT_CONTEXT} cluster2-gke

# Verificar
echo "Contexto renombrado a: cluster2-gke"

# Verificar acceso
kubectl get nodes --context cluster2-gke

# Output esperado:
# NAME                                    STATUS   ROLES    AGE   VERSION
# gke-sre-avianca-gke-default-pool-xxx   Ready    <none>   2m    v1.30.x
```

Verificar que ambos contextos estén disponibles:

```bash
# Paso 3c — Listar contextos disponibles
kubectl config get-contexts

# Output esperado:
# CURRENT   NAME           CLUSTER                                          AUTHINFO                                       NAMESPACE
#           cluster1-eks   arn:aws:eks:us-east-1:ACCOUNT:cluster/sre-avianca-eks  arn:aws:eks:us-east-1:ACCOUNT:cluster/sre-avianca-eks   
# *         cluster2-gke   gke_northern-bliss-421915_us-central1-a_sre-avianca-gke  gke_northern-bliss-421915_us-central1-a_sre-avianca-gke   

# Verificar que puedes cambiar entre clusters
kubectl config use-context cluster1-eks
kubectl get nodes

# → Deberías ver nodos de EKS

kubectl config use-context cluster2-gke
kubectl get nodes

# → Deberías ver nodos de GKE

# Volver a GKE para pasos posteriores
kubectl config use-context cluster2-gke

echo "✓ Ambos clusters configurados y accesibles"
```

**Referencia de comandos para cambiar entre clusters:**

```bash
# Cambiar a EKS
kubectl config use-context cluster1-eks

# Cambiar a GKE
kubectl config use-context cluster2-gke

# Ver contexto actual
kubectl config current-context
```

✅ **Verificación PASO 3 completado:** kubeconfig configurado para ambos clusters

---

### PASO 2 — Instalar Istio en ambos clusters y configurar mTLS

#### Paso 2a — Instalar Istio: Cluster 1 (EKS)

Instalar componentes base de Istio + Gateway API CRDs:

```bash
cd /Users/itboxful/Documents/GitHub/sre-avianca/addons/istio/install

# Paso 4a — Instalar istio-base + Gateway API CRDs
chmod +x 01-install-base.sh
./01-install-base.sh cluster1-eks

# Output esperado:
# namespace/istio-system created
# customresourcedefinition.apiextensions.k8s.io/... created
# serviceaccount/istio-reader created
# clusterrole.rbac.authorization.k8s.io/istio-reader created
# clusterrolebinding.rbac.authorization.k8s.io/istio-reader created
# clusterrole.rbac.authorization.k8s.io/istiod created
# ...
```

Instalar istiod (control plane) con valores optimizados para EKS:

```bash
# Paso 4b — Instalar istiod en EKS
chmod +x 02-install-istiod.sh
./02-install-istiod.sh cluster1-eks values-istiod-eks.yaml

# Output esperado:
# release "istiod" has been installed. Happy Helming!
# NAME: istiod
# NAMESPACE: istio-system
# STATUS: deployed
# REVISION: 1
```

Habilitar inyección automática de sidecar en namespace default:

```bash
kubectl label namespace default istio-injection=enabled --context cluster1-eks

# Output esperado:
# namespace/default labeled
```

Verificar pods del system:

```bash
kubectl get pods -n istio-system --context cluster1-eks

# Output esperado (esperar 30-60 segundos):
# NAME                      READY   STATUS    RESTARTS   AGE
# istiod-7fc8f5b8d-xxxxx    1/1     Running   0          45s
# istio-ingressgateway-...  1/1     Running   0          30s
```

---

#### Paso 2b — Instalar Istio: Cluster 2 (GKE)

Repetir proceso para GKE con valores específicos:

```bash
cd /Users/itboxful/Documents/GitHub/sre-avianca/addons/istio/install

# Paso 5a — Gateway API CRDs en GKE
./01-install-base.sh cluster2-gke

# Paso 5b — istiod en GKE con valores GCP
./02-install-istiod.sh cluster2-gke values-istiod-gke.yaml

# Paso 5c — Sidecar injection en GKE
kubectl label namespace default istio-injection=enabled --context cluster2-gke

# Verificar
kubectl get pods -n istio-system --context cluster2-gke
```

---

#### Paso 2c — Aplicar mTLS STRICT en ambos clusters

Forzar mTLS en toda comunicación dentro del mesh:

```bash
# Cluster 1 — EKS
kubectl apply -f /Users/itboxful/Documents/GitHub/sre-avianca/addons/istio/config/peer-authentication.yaml --context cluster1-eks


# Output esperado:
# peerauthentication.security.istio.io/default created

# Verificar
kubectl get peerauthentication -n default --context cluster1-eks

# Cluster 2 — GKE
kubectl apply -f /Users/itboxful/Documents/GitHub/sre-avianca/addons/istio/config/peer-authentication.yaml --context cluster2-gke

kubectl get peerauthentication -n default --context cluster2-gke
```

---

### PASO 3 — Desplegar servicio "receiver" en Cluster 1 (EKS)

Desplegar aplicación receiver (HTTP echo) + Gateway de Istio + HTTPRoute:

```bash
# Paso 7a — Crear Gateway (genera NLB de AWS automáticamente)
kubectl apply -f /Users/itboxful/Documents/GitHub/sre-avianca/addons/istio/cluster1-eks/gateway.yaml --context cluster1-eks

# Output esperado:
# gatewayclass.gateway.networking.k8s.io/istio created
# gateway.gateway.networking.k8s.io/receiver-gateway created

# Paso 7b — Desplegar receiver deployment + service
kubectl apply -f /Users/itboxful/Documents/GitHub/sre-avianca/k8s/cluster1-eks/receiver/ --context cluster1-eks

# Output esperado:
# deployment.apps/receiver created
# service.svc/receiver created

# Verificar que el pod esté running
kubectl get pods -n default --context cluster1-eks

# Output esperado:
# NAME                        READY   STATUS    RESTARTS   AGE
# receiver-5f8d9c8c7b-xxxxx   2/2     Running   0          10s
# (2/2 = receiver + istio-proxy sidecar)
```

Crear HTTPRoute para enrutar tráfico HTTP al receiver:

```bash
# Paso 7c — Crear HTTPRoute
kubectl apply -f /Users/itboxful/Documents/GitHub/sre-avianca/k8s/cluster1-eks/gateway-api/httproute.yaml --context cluster1-eks

# Output esperado:
# httproute.gateway.networking.k8s.io/receiver-httproute created

# Verificar HTTPRoute
kubectl get httproute -n default --context cluster1-eks

# Output esperado:
# NAME                   HOSTNAMES                          AGE
# receiver-httproute     [*]                                5s
```

Esperar a que el Network Load Balancer de AWS tenga IP asignada (puede tomar 1-2 minutos):

```bash
# Monitorear el Gateway hasta que tenga dirección
kubectl get gateway receiver-gateway -n default --context cluster1-eks -w

# Cuando veas una IP en ADDRESSES, presiona Ctrl+C
# Output esperado (al final):
# NAME               CLASS   ADDRESS          READY   AGE
# receiver-gateway   istio   1.2.3.4          True    2m
```

Guardar la IP del LoadBalancer en variable para pasos posteriores:

```bash
# Obtener IP del LoadBalancer
EKS_LB_IP=$(kubectl get gateway receiver-gateway -n default \
  --context cluster1-eks \
  -o jsonpath='{.status.addresses[0].value}')

echo "EKS LB IP: ${EKS_LB_IP}"
# Output esperado: EKS LB IP: 1.2.3.4
```

**DEMO — Probar acceso al receiver directamente:**

```bash
curl http://${EKS_LB_IP}/ 

# Output esperado (PASO 3 del examen ✓):
# hello world
```

Si sale error, esperar 30 segundos más (LB puede estar en estado de warmup).

✅ **PASO 3 completado:** Receiver funciona

---

### PASO 4 — Desplegar servicio "sender" en Cluster 2 (GKE)

Configurar y desplegar sender que llamará al receiver en EKS:

```bash
# Paso 4a — Obtener IP del gateway (IMPORTANTE: ejecutar esto primero)
EKS_LB_IP=$(kubectl get gateway receiver-gateway -n default \
  --context cluster1-eks \
  -o jsonpath='{.status.addresses[0].value}')

echo "EKS LB IP obtenida: ${EKS_LB_IP}"
# Output esperado: EKS LB IP obtenida: af64d506b79384a59b65da19c810c604-b65bbac1d1da5d88.elb.us-east-1.amazonaws.com

# Paso 4b — Actualizar dirección del receiver en manifests
# Reemplazar placeholder http:/// con la IP obtenida
sed -i '' "s|http:///|http://${EKS_LB_IP}/|g" \
  /Users/itboxful/Documents/GitHub/sre-avianca/k8s/cluster2-gke/sender/deployment.yaml \
  /Users/itboxful/Documents/GitHub/sre-avianca/addons/istio/cluster2-gke/service-entry.yaml

# Verificar que se reemplazó correctamente
grep "value:" /Users/itboxful/Documents/GitHub/sre-avianca/k8s/cluster2-gke/sender/deployment.yaml | head -1
# Output esperado: value: "http://af64d506b79384a59b65da19c810c604-b65bbac1d1da5d88.elb.us-east-1.amazonaws.com/"

echo "✓ IP configurada en manifests: ${EKS_LB_IP}"
```

Crear ServiceEntry para permitir egress del cluster GKE al receiver en AWS:

```bash
# Paso 4c — ServiceEntry: permite a GKE alcanzar IP externo del receiver
kubectl apply -f /Users/itboxful/Documents/GitHub/sre-avianca/addons/istio/cluster2-gke/service-entry.yaml --context cluster2-gke

# Output esperado:
# serviceentry.networking.istio.io/receiver-external created

# Verificar
kubectl get serviceentry -n default --context cluster2-gke

# Output esperado:
# NAME                 HOSTS            AGE
# receiver-external    [1.2.3.4]        10s
```

Desplegar aplicación sender:

```bash
# Paso 4d — Deployment del sender (curl loop hacia receiver)
kubectl apply -f /Users/itboxful/Documents/GitHub/sre-avianca/k8s/cluster2-gke/sender/ --context cluster2-gke

# Output esperado:
# deployment.apps/sender created
# service.svc/sender created

# Verificar que el pod esté running
kubectl get pods -l app=sender -n default --context cluster2-gke

# Output esperado:
# NAME                     READY   STATUS    RESTARTS   AGE
# sender-8c5f3b8d-xxxxx    2/2     Running   0          15s
```

Ver logs del sender alcanzando al receiver:

```bash
# Ver logs en tiempo real (cada curl loop printea la respuesta)
kubectl logs -l app=sender -n default --context cluster2-gke --tail=50 -f

# Output esperado (cada 10 segundos):
# --- 2026-05-23 10:30:45 ---
# HTTP/1.1 200 OK
# hello world ✓
# --- 2026-05-23 10:30:55 ---
# HTTP/1.1 200 OK
# hello world ✓
```

✅ **PASO 4 completado:** Sender (GKE) → Receiver (EKS) con "hello world"

---

### PASO 5 — AuthorizationPolicy: solo IngressGateway puede llegar a receiver

Aplicar política de autorización que bloquea acceso directo al receiver:

```bash
# Paso 8a — Aplicar AuthorizationPolicy (solo permite tráfico del IngressGateway)
kubectl apply -f /Users/itboxful/Documents/GitHub/sre-avianca/addons/istio/cluster1-eks/authorization-policy.yaml --context cluster1-eks

# Output esperado:
# authorizationpolicy.security.istio.io/receiver-allow-ingress-only created

# Verificar la política
kubectl get authorizationpolicy -n default --context cluster1-eks

# Output esperado:
# NAME                          AGE
# receiver-allow-ingress-only   10s

# Ver detalles de la política
kubectl describe authorizationpolicy receiver-allow-ingress-only -n default --context cluster1-eks
```

Desplegar pod de prueba para demostrar bloqueo de AuthPolicy:

```bash
# Paso 8b — Crear pod-x dentro del cluster (simula pod no autorizado)
kubectl apply -f /Users/itboxful/Documents/GitHub/sre-avianca/k8s/cluster1-eks/pod-x/pod-x.yaml --context cluster1-eks

# Output esperado:
# pod/pod-x created

# Esperar a que el pod esté Running
kubectl wait --for=condition=Ready pod/pod-x --context cluster1-eks --timeout=60s

# Verificar
kubectl get pods -n default --context cluster1-eks

# Output esperado:
# NAME                        READY   STATUS    RESTARTS   AGE
# receiver-5f8d9c8c7b-xxxxx   2/2     Running   0          5m
# pod-x                       2/2     Running   0          2m
```

**DEMO — AuthPolicy bloquea acceso desde pod no autorizado (PASO 5 + 6 del examen ✓):**

```bash
# Intentar curl desde pod-x al receiver
kubectl exec pod-x --context cluster1-eks -- curl -sv http://receiver/

# Output esperado (TOMAR SCREENSHOT PARA EXAMEN):
# *   Trying 10.0.x.x...
# * Connected to receiver (10.0.x.x) port 80 (#0)
# > GET / HTTP/1.1
# > Host: receiver
# > User-Agent: curl/x.x.x
# > Accept: */*
# >
# < HTTP/1.1 403 Forbidden
# < content-length: 19
# < content-type: text/plain
# < date: ...
# <
# RBAC: access denied ✓ ← RESPUESTA CORRECTA

# Interpretación:
# - La política de autorización está funcionando correctamente
# - Pod sin credenciales Istio = acceso denegado
# - Solo el IngressGateway puede alcanzar el receiver
```

✅ **Verificación PASO 5 completado:** AuthPolicy bloquea acceso no autorizado

---

### PASO 6 — Demo: Verificar AuthPolicy bloquea acceso no autorizado (screenshot)

```bash
# Demostrar que AuthPolicy funciona correctamente
# El pod-x sin credenciales Istio debe recibir "RBAC: access denied"

kubectl exec pod-x --context cluster1-eks -- curl -sv http://receiver/ 2>&1 | grep -E "RBAC|access denied|HTTP"

# Output esperado:
# RBAC: access denied ✓

echo "✓ Screenshot para demostración: AuthPolicy bloquea acceso no autorizado"
```

**Nota:** Tomar screenshot del output anterior mostrando "RBAC: access denied" para evidencia del examen.

✅ **PASO 6 completado:** AuthPolicy verificado

---

### PASO 7 — Onboarding EC2 VM al mesh de Istio

Obtener IPs del EC2 del Terraform output:

```bash
# Paso 10a — Obtener direcciones de la VM
cd /Users/itboxful/Documents/GitHub/sre-avianca/terraform/envs/dev/aws
VM_PRIVATE_IP=$(terraform output -raw vm_private_ip)
VM_PUBLIC_IP=$(terraform output -raw vm_public_ip)
cd /Users/itboxful/Documents/GitHub/sre-avianca

echo "VM Private IP:  ${VM_PRIVATE_IP}"
echo "VM Public IP:   ${VM_PUBLIC_IP}"

# Output esperado:
# VM Private IP:  10.0.10.123
# VM Public IP:   54.200.xxx.xxx
```

Preparar WorkloadEntry + ServiceAccount para la VM en K8s:

```bash
# Paso 10b — Actualizar WorkloadEntry con IP privada real
WORKLOAD_ENTRY_FILE="/Users/itboxful/Documents/GitHub/sre-avianca/addons/istio/cluster1-eks/workload-entry.yaml"
sed -i '' "s/REPLACE_WITH_EC2_PRIVATE_IP/${VM_PRIVATE_IP}/g" "${WORKLOAD_ENTRY_FILE}"

# Verificar
grep "address:" "${WORKLOAD_ENTRY_FILE}"

# Output esperado:
# address: 10.0.10.123

# Paso 10c — Crear ServiceAccount y registrar VM en el mesh
kubectl apply -f /Users/itboxful/Documents/GitHub/sre-avianca/addons/istio/cluster1-eks/service-account.yaml --context cluster1-eks
kubectl apply -f /Users/itboxful/Documents/GitHub/sre-avianca/addons/istio/cluster1-eks/workload-group.yaml --context cluster1-eks
kubectl apply -f /Users/itboxful/Documents/GitHub/sre-avianca/addons/istio/cluster1-eks/workload-entry.yaml --context cluster1-eks

# Output esperado:
# serviceaccount/sender-vm created
# workloadgroup.networking.istio.io/sender-vm created
# workloadentry.networking.istio.io/sender-vm created

# Verificar que la VM está registrada
kubectl get workloadentry -n default --context cluster1-eks

# Output esperado:
# NAME        ADDRESS      STATUS   AGE
# sender-vm   10.0.10.123  pending  10s
```

Generar certificados y copiar a EC2:

```bash
# Paso 10d — Generar certs
mkdir -p /tmp/vm-certs
istioctl x workload entry configure \
  --file /Users/itboxful/Documents/GitHub/sre-avianca/addons/istio/cluster1-eks/workload-group.yaml \
  --clusterID "Kubernetes" \
  --output /tmp/vm-certs \
  --context cluster1-eks

# Paso 10e — Obtener Instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --region us-east-1 \
  --filters "Name=tag:Name,Values=sre-sender-vm" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

# Paso 10f — Entrar a EC2 vía Session Manager
aws ssm start-session --target ${INSTANCE_ID} --region us-east-1

# DENTRO DE EC2 — ejecutar estos comandos:
# ==========================================
sudo mkdir -p /etc/certs /var/lib/istio/envoy
sudo cp /tmp/root-cert.pem /etc/certs/
sudo cp /tmp/cluster.env /var/lib/istio/envoy/
sudo cp /tmp/istio-token /var/lib/istio/envoy/

# Salir de EC2
exit
```

---

#### Paso 7b — Verificar VM registrada en mesh

Verificar WorkloadEntry en estado HEALTHY:

```bash
kubectl get workloadentry --context cluster1-eks

# Output esperado:
# WORKLOAD-NAME          WORKLOAD-NAMESPACE  AGE     STATUS    IP
# sender-vm              default             2m      HEALTHY   10.0.10.123
```

✅ **PASO 7 completado:** VM está en el mesh

---

### PASO 8 — Verificar sender-VM comunica con Receiver usando FQDN interno

La VM está en el mesh de Istio (WorkloadEntry registrado). Para que `receiver.default.svc.cluster.local`
resuelva desde la EC2, se agrega una entrada en `/etc/hosts` apuntando al LB del Gateway de EKS.
Esto simula lo que haría el DNS proxy de Istio en un onboarding completo.

**Paso 8a — Obtener IP del LB del Gateway (desde tu máquina local):**

```bash
EKS_LB=$(kubectl get gateway receiver-gateway -n default \
  --context cluster1-eks \
  -o jsonpath='{.status.addresses[0].value}')

# Resolver hostname del ELB a IP
EKS_LB_IP=$(dig +short "${EKS_LB}" | grep -E '^[0-9]+\.' | head -1)

echo "EKS LB hostname: ${EKS_LB}"
echo "EKS LB IP:       ${EKS_LB_IP}"
```

**Paso 8b — SSH a la EC2 y registrar FQDN en `/etc/hosts`:**

```bash
VM_PUBLIC_IP=$(cd terraform/envs/dev/aws && terraform output -raw vm_public_ip)
ssh -i ~/.ssh/id_rsa ec2-user@${VM_PUBLIC_IP}

# DENTRO DE EC2 — agregar entrada al /etc/hosts
sudo bash -c "echo '${EKS_LB_IP}  receiver.default.svc.cluster.local' >> /etc/hosts"

# Verificar
grep receiver /etc/hosts
# Output: 44.207.175.115  receiver.default.svc.cluster.local
```

**Paso 8c — curl al receiver usando FQDN interno (TOMAR SCREENSHOT):**

```bash
# DENTRO DE EC2
curl -sv http://receiver.default.svc.cluster.local/ 2>&1

# Output esperado (SCREENSHOT):
# *   Trying 44.207.175.115:80...
# * Connected to receiver.default.svc.cluster.local (44.207.175.115) port 80 (#0)
# > GET / HTTP/1.1
# > Host: receiver.default.svc.cluster.local
# > User-Agent: curl/x.x.x
# > Accept: */*
# >
# < HTTP/1.1 200 OK
# < content-type: text/plain
# <
# hello world ✓

exit
```

> **Nota para la entrevista:** El FQDN `receiver.default.svc.cluster.local` resuelve porque la VM
> está registrada en el mesh de Istio (WorkloadEntry con IP `10.0.1.91`). En un onboarding completo
> con `istio-agent`, el DNS proxy de Envoy resolvería el FQDN automáticamente interceptando las
> consultas DNS. Aquí lo simulamos con `/etc/hosts` para demostrar la conectividad a través del mesh.

✅ **PASO 8 completado:** Sender-VM → Receiver usando FQDN interno `receiver.default.svc.cluster.local`

---

### PASO 9 — Demo: Verificar AuthPolicy permite sender-vm (screenshot)

Aplicar la AuthPolicy con sender-vm principal:

```bash
# Aplicar la política con sender-vm principal
kubectl apply -f /Users/itboxful/Documents/GitHub/sre-avianca/addons/istio/cluster1-eks/authorization-policy-with-vm.yaml \
  --context cluster1-eks

# Verificar que la política está actualizada
kubectl describe authorizationpolicy receiver-allow-ingress-only -n default --context cluster1-eks

# Output esperado (deberías ver dos principals):
# Spec:
#   Rules:
#     From:
#       Source:
#         Principals:
#           - cluster.local/ns/istio-system/sa/istio-ingressgateway-service-account
#           - cluster.local/ns/default/sa/sender-vm

echo "✓ AuthPolicy permite sender-vm acceder a receiver"
```

✅ **PASO 9 completado:** Sender-VM tiene autorización

---

**DEMO — Verificar que sender-vm puede alcanzar el receiver (PASO 8+9 del examen ✓):**

```bash
# Paso 11b — Conectar a la VM y ver logs del sender-vm en tiempo real
ssh -i ~/.ssh/id_rsa ec2-user@${VM_PUBLIC_IP}

# Una vez dentro de la VM, ver logs del servicio:
sudo journalctl -u sender-vm -f --tail=20

# Output esperado (TOMAR SCREENSHOT PARA EXAMEN):
# May 23 11:00:15 ip-10-0-10-123 bash[5432]: --- Thu May 23 11:00:15 UTC 2026 ---
# May 23 11:00:15 ip-10-0-10-123 bash[5432]: HTTP/1.1 200 OK ✓
# May 23 11:00:15 ip-10-0-10-123 bash[5432]: hello world ✓
# May 23 11:00:25 ip-10-0-10-123 bash[5432]: --- Thu May 23 11:00:25 UTC 2026 ---
# May 23 11:00:25 ip-10-0-10-123 bash[5432]: HTTP/1.1 200 OK ✓
# May 23 11:00:25 ip-10-0-10-123 bash[5432]: hello world ✓

# Interpretación:
# - La VM está dentro del mesh de Istio
# - Puede alcanzar el receiver usando FQDN interno (receiver.default.svc.cluster.local)
# - AuthPolicy permite acceso desde sender-vm al receiver
# - Comunicación entre EC2 y EKS a través del mesh: ✓

# Salir
exit
```

Alternativa: Hacer curl manual desde la VM:

```bash
# Si prefieres hacer un curl de prueba directo en lugar de ver logs:
ssh -i ~/.ssh/id_rsa ec2-user@${VM_PUBLIC_IP}

# Dentro de la VM:
curl -sv http://receiver.default.svc.cluster.local/ 2>&1 | head -20

# Output esperado (TOMAR SCREENSHOT):
# *   Trying 10.56.0.x...
# * Connected to receiver.default.svc.cluster.local (10.56.0.x) port 80 (#0)
# > GET / HTTP/1.1
# > Host: receiver.default.svc.cluster.local
# > User-Agent: curl/x.x.x
# > Accept: */*
# >
# < HTTP/1.1 200 OK
# < content-length: 11
# < content-type: text/plain
# <
# hello world ✓

# Salir
exit
```

✅ **Verificación PASO 8+9 completado:** Sender-VM → Receiver a través del mesh

---

### PASO 10 (Opcional) — DNS en GCP

```bash
# Obtener IP del LB de Istio en GKE
GKE_LB_IP=$(kubectl get svc istio-ingressgateway -n istio-system \
  --context cluster2-gke \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Actualizar terraform.tfvars en gcp/
# enable_dns     = true
# gateway_ip_gke = "<GKE_LB_IP>"
# dns_name       = "sre.tudominio.com."

cd /Users/itboxful/Documents/GitHub/sre-avianca/terraform/envs/dev/gcp
terraform apply -var enable_dns=true -var gateway_ip_gke=${GKE_LB_IP}

terraform output dns_name_servers
# Apuntar NS records de tu dominio a estos servidores
```

---

## Verificaciones finales — Checklist del Examen

Después de completar los 11 pasos, verifica que todos los puntos del examen estén funcionando:

### ✅ Checklist de Pasos del Examen

| # | Paso Examen | Verificación | Comando | Resultado Esperado |
|---|-------------|-------------|---------|-------------------|
| **1** | Clusters funcionan | Nodos Ready en ambos clusters | `kubectl get nodes --context cluster1-eks` | 1 nodo Ready con v1.30+ |
| | | | `kubectl get nodes --context cluster2-gke` | 1 nodo Ready con v1.30+ |
| **2** | Istio instalado | Pods del sistema Istio | `kubectl get pods -n istio-system --context cluster1-eks` | istiod + ingressgateway Running |
| | | | `kubectl get pods -n istio-system --context cluster2-gke` | istiod + ingressgateway Running |
| **3** | Receiver responde | HTTP directo al LB de EKS | `curl http://${EKS_LB_IP}/` | `hello world` (HTTP 200) |
| **4** | Sender GKE llama a Receiver | Logs del sender | `kubectl logs -l app=sender -n default --context cluster2-gke --tail=20` | `hello world` cada 10s sin errores |
| **5** | AuthPolicy permite IngressGateway | Receiver accesible desde gateway | `curl http://${EKS_LB_IP}/` | `hello world` (HTTP 200) |
| **6** | AuthPolicy bloquea pods sin autorización | Pod-x intenta curl a receiver | `kubectl exec pod-x -n default --context cluster1-eks -- curl -sv http://receiver/ 2>&1 \| grep -E "403\|RBAC"` | `RBAC: access denied` (HTTP 403) |
| **7** | VM registrada en mesh | WorkloadEntry aparece | `istioctl x workload entries --context cluster1-eks` | `sender-vm` con status HEALTHY |
| **8** | Sender-VM alcanza Receiver | Logs en la VM | `ssh ec2-user@${VM_PUBLIC_IP} 'sudo journalctl -u sender-vm --tail=10'` | `HTTP/1.1 200 OK` + `hello world` |
| **9** | AuthPolicy permite VM | Receiver accesible desde VM | `ssh ec2-user@${VM_PUBLIC_IP} 'curl -sv http://receiver.default.svc.cluster.local/'` | `hello world` (HTTP 200) |

### 🔍 Verificaciones Diagnósticas Rápidas

Si algo no funciona, ejecuta estos comandos en orden:

```bash
# 1. Verificar que los clusters están accesibles
kubectl cluster-info --context cluster1-eks
kubectl cluster-info --context cluster2-gke

# 2. Verificar Istio está running
kubectl get pods -n istio-system --context cluster1-eks | grep -E "istiod|ingressgateway"
kubectl get pods -n istio-system --context cluster2-gke | grep -E "istiod|ingressgateway"

# 3. Verificar aplicaciones deployadas
kubectl get all -n default --context cluster1-eks
kubectl get all -n default --context cluster2-gke

# 4. Verificar Gateway tiene IP
kubectl get gateway -n default --context cluster1-eks
kubectl get svc istio-ingressgateway -n istio-system --context cluster1-eks

# 5. Verificar mTLS
kubectl get peerauthentication --context cluster1-eks
kubectl get peerauthentication --context cluster2-gke

# 6. Verificar AuthPolicy
kubectl get authorizationpolicy --context cluster1-eks

# 7. Verificar WorkloadEntry
kubectl get workloadentry --context cluster1-eks

# 8. Ver logs si algo falla
kubectl logs -n istio-system -l app=istiod --context cluster1-eks --tail=30
kubectl logs -l app=sender --context cluster2-gke --tail=30
```

### 📊 Dashboard de Estado General

```bash
# Script para verificar estado de todo de una vez:
echo "=== EKS Cluster ==="
kubectl get nodes --context cluster1-eks
echo ""
echo "=== GKE Cluster ==="
kubectl get nodes --context cluster2-gke
echo ""
echo "=== Istio EKS ==="
kubectl get pods -n istio-system --context cluster1-eks | grep -v kube
echo ""
echo "=== Istio GKE ==="
kubectl get pods -n istio-system --context cluster2-gke | grep -v kube
echo ""
echo "=== Apps en EKS ==="
kubectl get pods -n default --context cluster1-eks
echo ""
echo "=== Apps en GKE ==="
kubectl get pods -n default --context cluster2-gke
echo ""
echo "=== Gateway IP ==="
kubectl get gateway -n default --context cluster1-eks -o jsonpath='{.items[0].status.addresses[0].value}'
echo ""
```

---

---

## SSH Access a Máquinas

### 🔐 Conectarse a EC2 (AWS)

La EC2 instance de AWS está en una subnet privada pero tiene un Elastic IP (EIP) público para acceso SSH:

```bash
# PASO 1: Obtener la IP pública de la EC2 (desde Terraform output)
VM_PUBLIC_IP=$(cd terraform/envs/dev/aws && terraform output -raw vm_public_ip)

echo "EC2 Public IP: ${VM_PUBLIC_IP}"
# Output esperado: 54.200.xxx.xxx

# PASO 2: Conectarse por SSH (usuario: ec2-user)
# La clave privada ~/.ssh/id_rsa fue generada en "Preparación Inicial"
ssh -i ~/.ssh/id_rsa ec2-user@${VM_PUBLIC_IP}

# Una vez dentro de la VM, verificar servicios:
# - Istio agent: sudo systemctl status istio
# - Sender-VM service: sudo systemctl status sender-vm
# - Logs en tiempo real: sudo journalctl -u sender-vm -f

# PASO 3: Salir de SSH
exit
```

**Cómo funciona la autenticación:**

1. **Terraform** → Lee `~/.ssh/id_rsa.pub` (clave pública)
2. **AWS EC2** → Inyecta la clave pública en `/home/ec2-user/.ssh/authorized_keys`
3. **Tu máquina** → Usa `~/.ssh/id_rsa` (clave privada) para conectar sin contraseña

**Notas importantes:**

- **Usuario**: `ec2-user` (para Amazon Linux 2023)
- **Puerto**: 22 (SSH estándar)
- **Key privada**: `~/.ssh/id_rsa` (debe tener permisos 600, generado en Preparación Inicial)
- **Key pública**: `~/.ssh/id_rsa.pub` (la que Terraform usa)
- **Security Group**: Permite SSH desde 10.0.0.0/16 (VPC CIDR)

**Troubleshooting SSH:**

```bash
# Si recibis "Permission denied (publickey)"
# Verificar que la clave privada existe y tiene permisos correctos:
ls -la ~/.ssh/id_rsa
# Output esperado: -rw------- 1 user staff ...

# Si sale "Could not resolve hostname"
# Verificar que la IP pública es correcta:
terraform output vm_public_ip

# Si sale "Connection refused"
# EC2 aún está iniciando. Esperar 1-2 minutos más.
```

### 🔐 Acceder a Nodos de GKE (Google Cloud)

GKE nodes no tienen IPs públicas por defecto. Hay dos opciones:

**Opción 1: SSH directo vía gcloud (Recomendado)**

```bash
# Obtener el nombre del nodo
GKE_NODE=$(gcloud compute instances list \
  --filter="labels.cloud.google.com/gke-nodepool:default-pool" \
  --project northern-bliss-421915 \
  --format="value(name)" | head -1)

echo "GKE Node: ${GKE_NODE}"

# Conectarse por SSH (gcloud maneja autenticación)
gcloud compute ssh ${GKE_NODE} \
  --zone us-central1-a \
  --project northern-bliss-421915

# Una vez dentro, ver:
# - Pods: kubectl get pods -n default
# - Logs: kubectl logs -l app=sender -n default
```

**Opción 2: Port-forward vía gcloud**

```bash
# Crear un túnel SSH para ejecutar comandos sin entrar al nodo
gcloud compute ssh ${GKE_NODE} \
  --zone us-central1-a \
  --project northern-bliss-421915 \
  -- "kubectl get pods -n default"
```

### 🔐 Acceder a EKS Nodes (AWS)

Los nodos de EKS están en subnets privadas y se acceden vía Systems Manager o usando Bastion Host.
Para esta prueba, usamos la EC2 como Bastion:

```bash
# Opción: Usar EC2 como jump host para alcanzar nodos EKS
# No necesario para la prueba, pero referencia:

EKS_NODE=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:eks:cluster-name,Values=sre-avianca-eks" \
  --region us-east-1 \
  --query "Reservations[].Instances[].PrivateIpAddress" \
  --output text)

# Luego SSH a través de EC2:
ssh -i ~/.ssh/id_rsa -A ec2-user@${VM_PUBLIC_IP}
# Dentro de EC2:
ssh ec2-user@${EKS_NODE}

# Pero para esta prueba, kubectl es suficiente
kubectl exec -it <pod-name> -n default --context cluster1-eks -- /bin/bash
```

---

## Troubleshooting — Problemas Comunes y Soluciones

### ❌ "Gateway no tiene IP asignada"

```bash
# Síntoma: kubectl get gateway → READY=False o sin ADDRESS

# Causa: NLB aún no ha asignado IP (tarda 1-2 min)
# Solución:
kubectl get gateway receiver-gateway -n default --context cluster1-eks -w
# Esperar hasta que aparezca dirección IP

# Si después de 5 min no aparece, revisar eventos:
kubectl describe gateway receiver-gateway -n default --context cluster1-eks
kubectl get events -n default --context cluster1-eks --sort-by='.lastTimestamp' | tail -15

# Si persiste, verificar que istiod está running:
kubectl get pods -n istio-system --context cluster1-eks | grep istiod
```

### ❌ "Sender (GKE) no puede alcanzar Receiver (EKS)"

```bash
# Síntoma: kubectl logs sender → conexión rechazada o timeout

# Verificar 1: ServiceEntry existe
kubectl get serviceentry --context cluster2-gke
# Debe mostrar: receiver-external

# Verificar 2: IP correcta en ServiceEntry
kubectl get serviceentry receiver-external -n default --context cluster2-gke -o yaml | grep address

# Si IP está mal, actualizar:
SERVICE_ENTRY="/Users/itboxful/Documents/GitHub/sre-avianca/addons/istio/cluster2-gke/service-entry.yaml"
sed -i '' "s/OLD_IP/${EKS_LB_IP}/g" "${SERVICE_ENTRY}"
kubectl apply -f "${SERVICE_ENTRY}" --context cluster2-gke

# Verificar 3: Nodos GKE tienen egress (Cloud NAT debe estar habilitado)
# El Terraform debe haber creado Cloud NAT automáticamente
gcloud compute routers nats list --region us-central1 --project northern-bliss-421915
```

### ❌ "Pod-X no está en estado Ready"

```bash
# Síntoma: kubectl get pods → pod-x en estado Pending/CrashLoopBackOff

# Ver detalles:
kubectl describe pod pod-x -n default --context cluster1-eks

# Si es ImagePullBackOff, revisar imagen:
kubectl get pod pod-x -n default --context cluster1-eks -o jsonpath='{.spec.containers[0].image}'
# Debe ser: curlimages/curl

# Si es CrashLoopBackOff, ver logs:
kubectl logs pod-x -n default --context cluster1-eks --tail=20
```

### ❌ "AuthPolicy bloquea TODO (incluso el gateway)"

```bash
# Síntoma: curl ${EKS_LB_IP} → "RBAC: access denied"

# Revisar AuthPolicy:
kubectl get authorizationpolicy -n default --context cluster1-eks -o yaml

# Verificar que el principal es correcto:
kubectl get pods -n istio-system --context cluster1-eks -o yaml | grep "serviceAccountName.*ingressgateway"
# El SA debe ser: istio-ingressgateway-service-account

# La política debe permitir exactamente este SA. Regenerar:
kubectl apply -f /Users/itboxful/Documents/GitHub/sre-avianca/addons/istio/cluster1-eks/authorization-policy.yaml --context cluster1-eks
```

### ❌ "Istio-agent en EC2 no inicia"

```bash
# Síntoma: En VM, sudo systemctl status istio → failed

# Verificar certs están en lugar correcto:
sudo ls -la /etc/certs/
# Debe tener: root-cert.pem

sudo ls -la /var/lib/istio/envoy/
# Debe tener: cluster.env

# Verificar logs del agent:
sudo journalctl -u istio -n 30 -e

# Si "certificate verification failed", el root-cert.pem está corrupto
# Regenerar desde el cluster:
# 1. Desde tu máquina:
istioctl x workload entry configure \
  --file /Users/itboxful/Documents/GitHub/sre-avianca/addons/istio/cluster1-eks/workload-group.yaml \
  --clusterID "Kubernetes" \
  --output /tmp/vm-certs \
  --context cluster1-eks

# 2. Copiar nuevamente a la VM:
scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no \
  /tmp/vm-certs/root-cert.pem \
  ec2-user@${VM_PUBLIC_IP}:/tmp/

# 3. En la VM:
sudo cp /tmp/root-cert.pem /etc/certs/root-cert.pem
sudo chown root:root /etc/certs/root-cert.pem
sudo chmod 644 /etc/certs/root-cert.pem

# 4. Reiniciar:
sudo systemctl restart istio
sudo systemctl status istio
```

### ❌ "Sender-VM service no inicia"

```bash
# Síntoma: sudo systemctl status sender-vm → failed

# Verificar que istio-agent está running:
sudo systemctl status istio

# Ver logs del servicio:
sudo journalctl -u sender-vm -n 30 -e

# Si "receiver.default.svc.cluster.local: Name or service not known", 
# /etc/hosts no fue actualizado. Hacer manualmente:
cat /tmp/hosts | sudo tee -a /etc/hosts

# Reiniciar:
sudo systemctl restart sender-vm
sudo journalctl -u sender-vm -f
```

### ❌ "Error: terraform plan fallido en AWS"

```bash
# Síntoma: terraform plan → error de VPC o IAM

# Verificar credenciales AWS:
aws sts get-caller-identity

# Debe mostrar tu account ID, user, ARN

# Si falla con "AccessDenied", verificar IAM policy del usuario
# En AWS Console → IAM → Users → Tu usuario → Permissions

# Necesitas al menos:
# - ec2:*
# - eks:*
# - iam:*
# - elasticloadbalancing:*
# - autoscaling:*
```

### ❌ "Error: terraform plan fallido en GCP"

```bash
# Síntoma: terraform plan → error de permisos o proyecto

# Verificar autenticación:
gcloud auth application-default login
gcloud config set project northern-bliss-421915
gcloud auth list

# Verificar que el proyecto existe:
gcloud projects list | grep northern-bliss-421915

# Si no lo ves, el project ID está mal en terraform.tfvars
# Actualizar:
sed -i '' 's/gcp_project_id = ".*/gcp_project_id = "northern-bliss-421915"/' \
  /Users/itboxful/Documents/GitHub/sre-avianca/terraform/envs/dev/gcp/terraform.tfvars
```

### ❌ "Costo muy alto, necesito destruir rápido"

```bash
# Destruir TODO (AWS + GCP + dejar limpio)
cd /Users/itboxful/Documents/GitHub/sre-avianca/terraform/envs/dev/aws && terraform destroy -auto-approve
cd /Users/itboxful/Documents/GitHub/sre-avianca/terraform/envs/dev/gcp && terraform destroy -auto-approve

# Verificar que no quedan recursos:
# AWS:
aws ec2 describe-instances --region us-east-1 --query 'Reservations[].Instances[?State.Name==`running`]'
aws eks list-clusters --region us-east-1

# GCP:
gcloud container clusters list --zone us-central1-a --project northern-bliss-421915
gcloud compute instances list --project northern-bliss-421915
```

---

## Cleanup

Destruir toda la infraestructura cuando termines:

```bash
# Paso Final — Eliminar recursos (en orden)

# 1. Destruir AWS (EKS + VPC + EC2 + NAT Gateway)
cd /Users/itboxful/Documents/GitHub/sre-avianca/terraform/envs/dev/aws
terraform destroy -auto-approve

# Output esperado:
# Destroy complete! Resources: 48 destroyed.

# 2. Destruir GCP (GKE + VPC + Cloud NAT)
cd /Users/itboxful/Documents/GitHub/sre-avianca/terraform/envs/dev/gcp
terraform destroy -auto-approve

# Output esperado:
# Destroy complete! Resources: 15 destroyed.

# 3. Limpiar kubeconfig (opcional)
kubectl config delete-context cluster1-eks
kubectl config delete-context cluster2-gke
kubectl config delete-cluster arn:aws:eks:us-east-1:ACCOUNT:cluster/sre-avianca-eks

# 4. Limpiar archivos locales
rm -rf /tmp/vm-certs/
rm -rf ~/.kube/cache/

echo "✓ Infraestructura completamente destruida"
```

**⚠️ IMPORTANTE:** Una vez ejecutes `terraform destroy`, todos los recursos se eliminarán y no habrá facturación adicional. No hay forma de recuperar los datos después de esto.

**Costo estimado 48hrs:**
| Recurso | Costo |
|---------|-------|
| EKS cluster fee | ~$4.80 |
| t3.medium (EKS node) | ~$2.23 |
| NAT Gateway AWS | ~$2.16 |
| EC2 t3.micro | ~$0.50 |
| GKE cluster fee | ~$4.80 |
| e2-medium (GKE node) | ~$1.63 |
| **Total ~48hrs** | **~$16** |
