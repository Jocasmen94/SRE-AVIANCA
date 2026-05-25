# SRE Avianca — Evidencias de Prueba Técnica

10 imágenes documentando cada PASO de la prueba.

---

## PASO 2 — Infraestructura: Istio + mTLS

### 01-PASO-2b-gcp-gke-nodes-details.jpg
- **Descripción:** Detalles de nodos GKE
- Node pool: e2-medium (2 nodos Ready)
- Versión: 1.35.3-gke.1389000
- Status: Healthy ✓

### 02-PASO-2a-gcp-gke-cluster-console.jpg
- **Descripción:** GKE Cluster Console - Vista general
- Nombre: sre-avianca-gke
- Estado: Running
- Modo: Standard
- Nodos: 2 en us-central1-a ✓

---

## PASO 3 — Receiver en EKS

### 03-PASO-3-aws-eks-cluster-console.jpg
- **Descripción:** AWS EKS Cluster Console
- Nombre: sre-avianca-eks
- Status: Active
- Versión K8s: 1.30
- Health: 0 issues ✓

### 04-PASO-3-receiver-curl-hello-world.jpg
- **Descripción:** Curl a EKS LB IP → "hello world"
- Response: HTTP 200 OK
- Body: `hello world` ✓
- Server: istio-envoy
- Latencia: 1ms ✓

---

## PASO 4 — Sender en GKE

### 05-PASO-4-sender-gke-logs-hello-world.jpg
- **Descripción:** Logs del pod sender (GKE)
- Namespace: default
- Contexto: cluster2-gke
- Output: HTTP 200 OK + `hello world` repetido cada 10s
- Cross-cluster communication: ✓ Verificado

---

## PASO 6 — Demo: AuthPolicy bloquea acceso

### 06-PASO-6-authpolicy-rbac-access-denied.jpg
- **Descripción:** Pod-x intenta curl a receiver → BLOQUEADO
- Comando: `kubectl exec pod-x -- curl http://receiver/`
- Response: HTTP 403 Forbidden
- Error: `RBAC: access denied` ✓
- Verificación: AuthPolicy funciona ✓

---

## PASO 7 — EC2 VM Onboarding

### 07-PASO-7-workloadentry-sender-vm-mesh.jpg
- **Descripción:** WorkloadEntry de sender-vm en Istio
- Name: sender-vm-entry
- Address: 10.0.1.91 (EC2 privada)
- Age: 57m
- Status: HEALTHY ✓

---

## PASO 8 — Sender-VM comunica con Receiver

### 08-PASO-8-ec2-sender-vm-curl-hello-world.jpg
- **Descripción:** Curl desde EC2 a EKS LB IP
- Origen: EC2 VM (10.0.1.91)
- Destino: EKS LB (34.199.51.154:80)
- Response: HTTP 200 OK
- Body: `hello world` ✓

---

## PASO 9 — AuthPolicy permite sender-vm

### 09-PASO-9-authpolicy-sender-vm-principals.jpg
- **Descripción:** AuthPolicy con 2 principals (gateway + sender-vm)
- Name: receiver-allow-ingress-only
- Action: ALLOW
- Principals:
  1. `cluster.local/ns/default/sa/receiver-gateway-istio`
  2. `cluster.local/ns/default/sa/sender-vm` ✓

---

## Deadline & Requisitos

### 10-PASO-deadline-notes.jpg
- **Descripción:** Requisitos de entrega
- Fecha límite: Domingo 25 mayo 2026, 11:59 PM CST
- Entregar: Todos los artefactos por correo
- Incluir: Código, configs, YAMLs, Terraform files
- Timestamp: Validado en consola ✓

---

## Resumen: Prueba SRE Avianca ✓

| PASO | Evidencia | Status |
|------|-----------|--------|
| 2 | Istio + mTLS en EKS + GKE | ✅ |
| 3 | Receiver EKS → "hello world" | ✅ |
| 4 | Sender GKE → Receiver (cross-cloud) | ✅ |
| 6 | AuthPolicy bloquea pod-x | ✅ |
| 7 | EC2 en mesh (WorkloadEntry) | ✅ |
| 8 | Sender-VM → Receiver | ✅ |
| 9 | AuthPolicy permite sender-vm | ✅ |

**Prueba técnica completada y documentada.**
