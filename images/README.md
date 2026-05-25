# SRE Avianca — Evidencias de Prueba Técnica

10 imágenes ordenadas por PASO de la prueba.

---

## PASO 2 — Infraestructura: Istio instalado en ambos clusters

### 01-PASO-2a-gke-cluster-overview.jpg
- **Contenido:** GKE Console — Descripción general del cluster
- Nombre: `sre-avianca-gke`
- Estado: Running
- Modo: Standard
- Nodos: 2
- Zona: us-central1-a
- Versión: 1.35.3-gke.1389000 ✓

### 02-PASO-2b-gke-nodes-e2-medium.jpg
- **Contenido:** GKE Console — Detalles de nodos
- Node pool: sre-avianca-gke-pool
- Tipo de máquina: e2-medium
- Cantidad: 2 nodos Ready
- Estado: Correcto ✓

---

## PASO 3 — Receiver en Cluster 1 (EKS) responde "hello world"

### 03-PASO-3a-eks-cluster-overview.jpg
- **Contenido:** AWS EKS Console — Overview del cluster
- Nombre: `sre-avianca-eks`
- Status: Active
- Kubernetes version: 1.30
- Health: 0 issues
- Platform: eks.68 ✓

### 03-PASO-3b-eks-console-pods.jpg
- **Contenido:** AWS EKS Console — Resources / Pods
- Pods Running: pod-x, receiver-8bf6b56c9-lktxc, receiver-gateway-istio-5c4665c5b6-fmqbg
- Todos en status: Running ✓

### 04-PASO-3c-receiver-curl-hello-world.jpg
- **Contenido:** Curl al EKS LB IP → hello world
- Comando: `curl http://${EKS_LB_IP}/`
- Response: `hello world` ✓

---

## PASO 4 — Sender en Cluster 2 (GKE) hace requests al receiver

### 05-PASO-4-sender-gke-logs-hello-world.jpg
- **Contenido:** Logs del pod sender en GKE
- Comando: `kubectl logs -l app=sender -n default --context cluster2-gke --tail=50 -f`
- Output: HTTP/1.1 200 OK + `hello world` cada 10 segundos
- Cross-cloud request: GKE → EKS ✓

---

## PASO 6 — AuthPolicy bloquea acceso no autorizado (screenshot)

### 06-PASO-6-pod-x-rbac-access-denied.jpg
- **Contenido:** Pod-x intenta acceder al receiver — bloqueado por AuthPolicy
- Comando: `kubectl exec pod-x --context cluster1-eks -- curl -sv http://receiver/`
- Response: HTTP/1.1 403 Forbidden
- Error: `RBAC: access denied` ✓

---

## PASO 7 — EC2 VM registrada en mesh de Istio

### 07-PASO-7-workloadentry-sender-vm.jpg
- **Contenido:** WorkloadEntry registrada en EKS
- Comando: `kubectl get workloadentry --context cluster1-eks`
- Name: `sender-vm-entry`
- Address: `10.0.1.91` (IP privada EC2)
- Age: 57m ✓

---

## PASO 8 — Sender-VM se comunica con Receiver

### 08-PASO-8-ec2-curl-hello-world.jpg
- **Contenido:** Curl desde la EC2 (sh-5.2$) al EKS LB
- Origen: EC2 VM IP 10.0.1.91
- Destino: EKS LB `af64d506b79384a59b65da19c810c604-b65bbac1d1da5d88.elb.us-east-1.amazonaws.com`
- Response: HTTP/1.1 200 OK + `hello world`
- Server: istio-envoy ✓

---

## PASO 9 — AuthPolicy modificada para permitir sender-vm (screenshot)

### 09-PASO-9-authpolicy-sender-vm-principals.jpg
- **Contenido:** AuthPolicy aplicada con 2 principals
- Comando: `kubectl apply -f authorization-policy-with-vm.yaml --context cluster1-eks`
- `kubectl describe authorizationpolicy receiver-allow-ingress-only`
- Action: ALLOW
- Principals:
  1. `cluster.local/ns/default/sa/receiver-gateway-istio`
  2. `cluster.local/ns/default/sa/sender-vm` ✓

---

## Resumen

| # | Imagen | PASO | Evidencia |
|---|--------|------|-----------|
| 1 | 01-PASO-2a-gke-cluster-overview.jpg | PASO 2 | GKE cluster Running |
| 2 | 02-PASO-2b-gke-nodes-e2-medium.jpg | PASO 2 | GKE 2 nodos Ready |
| 3 | 03-PASO-3a-eks-cluster-overview.jpg | PASO 3 | EKS cluster Active |
| 4 | 03-PASO-3b-eks-console-pods.jpg | PASO 3 | Pods receiver Running |
| 5 | 04-PASO-3c-receiver-curl-hello-world.jpg | PASO 3 | curl → hello world |
| 6 | 05-PASO-4-sender-gke-logs-hello-world.jpg | PASO 4 | Sender logs hello world |
| 7 | 06-PASO-6-pod-x-rbac-access-denied.jpg | PASO 6 | RBAC access denied |
| 8 | 07-PASO-7-workloadentry-sender-vm.jpg | PASO 7 | VM en mesh |
| 9 | 08-PASO-8-ec2-curl-hello-world.jpg | PASO 8 | EC2 → hello world |
| 10 | 09-PASO-9-authpolicy-sender-vm-principals.jpg | PASO 9 | 2 principals AuthPolicy |
