# ExCoPstack Kubernetes Deployment Guide

This guide explains how to deploy the ExCoPstack application to Kubernetes, meeting all the examination criteria.

## Prerequisites

- Google Cloud Platform account with billing enabled
- `gcloud` CLI installed and configured
- `docker` installed and running
- `kubectl` (will be installed/configured automatically)
- Required GCP APIs enabled (container.googleapis.com, artifactregistry.googleapis.com)

## Quick Start (GKE)

The easiest way to deploy is using the automated setup script:

```bash
# Set your GCP project (or configure with gcloud config set project)
export GCP_PROJECT_ID=your-project-id
export GCP_REGION=us-central1
export GCP_ZONE=us-central1-a

# Run setup script
./scripts/setup.sh
```

The setup script will:

1. Create Artifact Registry (or use existing)
2. Build and push Docker images
3. Create GKE cluster (or connect to existing)
4. Get cluster credentials
5. Deploy all Kubernetes resources

To clean up (preserves Artifact Registry and images):

```bash
./scripts/cleanup.sh
```

## Architecture Overview

The ExCoPstack Kubernetes deployment consists of:

1. **COBOL Frontend** (Deployment) - Web application

   - 2 replicas
   - Rolling update strategy
   - Port 8080

2. **PHP API** (Deployment) - Backend service

   - 3 replicas
   - Rolling update strategy
   - Uses ConfigMap and Secret
   - Uses emptyDir for storage (allows multiple pods)
   - Port 9000

3. **Excel Cluster** (StatefulSet) - Database cluster

   - 3 nodes (1 primary R/W, 2 replicas R/O)
   - Persistent volumes via StorageClass
   - Each pod has its own PVC

4. **Services** - Service discovery (6 total)

   - `cobol-frontend-service` - Frontend access (ClusterIP)
   - `php-api-service` - API access (ClusterIP)
   - `excel-headless` - StatefulSet headless service (for pod discovery via DNS)
   - `excel-primary-service` - Primary Excel pod service (headless, routes to all pods)
   - `excel-replica-0-service` - Replica 0 service (headless, routes to all pods)
   - `excel-replica-1-service` - Replica 1 service (headless, routes to all pods)

   **Note:** To route to specific Excel pods, use DNS names:

   - Primary: `excel-cluster-0.excel-headless.excop.svc.cluster.local`
   - Replica 0: `excel-cluster-1.excel-headless.excop.svc.cluster.local`
   - Replica 1: `excel-cluster-2.excel-headless.excop.svc.cluster.local`

5. **Ingress** - External access

   - GKE GCE Ingress (not nginx)
   - Path-based routing
   - `/` → Frontend
   - `/api` → PHP API
   - Uses GKE LoadBalancer for external IP

6. **ConfigMap** - Application configuration

   - API endpoints
   - Environment variables

7. **Secret** - Sensitive data

   - API keys
   - Passwords (if needed)

8. **StorageClass** - Storage provisioning
   - `excop-excel-storage` - For Excel cluster StatefulSet PVCs (GKE pd-standard)
   - `excop-excel-shared-storage` - For shared storage (GKE pd-standard)
   - PHP API uses `emptyDir` (not PVC) to allow multiple pods

## Manual Deployment (Alternative)

If you prefer to deploy manually or are not using GKE:

### 1. Build Docker Images

First, build the Docker images:

```bash
# Build PHP API image
cd php-api
docker build -t excop-php-api:latest .

# Build COBOL frontend image
cd ../cobol
docker build -t excop-cobol:latest .
```

**Note:** For GKE, use the setup script which automatically builds and pushes to Artifact Registry.

### 2. Deploy to Kubernetes

**For GKE:** Use `./scripts/setup.sh` (recommended)

**For other clusters:** Deploy manually:

```bash
kubectl apply -f k8s/
```

**Note:** You may need to update image references in the YAML files to point to your container registry.

### 3. Verify Deployment

Check pod status:

```bash
kubectl get pods -n excop
```

All pods should be in `Running` state.

### 4. Access the Application

#### Option 1: Port Forward

```bash
# Frontend
kubectl port-forward -n excop svc/cobol-frontend-service 8888:80

# Then open: http://localhost:8888
```

#### Option 2: Ingress (GKE)

Get the Ingress IP:

```bash
kubectl get ingress -n excop
```

Then access via the external IP provided by GKE LoadBalancer.

## Manual Operations

### View Logs

```bash
# PHP API logs
kubectl logs -n excop -l app=php-api --tail=50

# COBOL frontend logs
kubectl logs -n excop -l app=cobol-frontend --tail=50

# Excel cluster primary pod
kubectl logs -n excop excel-cluster-0 --tail=50
```

### Scale Deployments

```bash
# Scale PHP API to 5 replicas
kubectl scale deployment php-api -n excop --replicas=5

# Scale COBOL frontend to 3 replicas
kubectl scale deployment cobol-frontend -n excop --replicas=3
```

### Rolling Update

```bash
# Trigger rolling update by updating image
kubectl set image deployment/php-api php-api=excop-php-api:v2 -n excop

# Monitor rollout
kubectl rollout status deployment/php-api -n excop
```

### Check Resources

```bash
# All resources in namespace
kubectl get all -n excop

# Persistent volumes
kubectl get pvc -n excop

# Services
kubectl get svc -n excop

# Ingress
kubectl get ingress -n excop
```

## Excel Cluster Architecture

The Excel cluster uses a StatefulSet with 3 pods implementing a primary/replica pattern:

- **excel-cluster-0** (Primary)

  - **Read-Write access**
  - Initializes Excel files on startup
  - Handles all write operations
  - Identified by pod index 0
  - Has its own PersistentVolumeClaim (1GB)

- **excel-cluster-1** (Replica 0)

  - **Read-Only access**
  - Identified by pod index 1
  - Has its own PersistentVolumeClaim (1GB)
  - Can be used for read operations (future enhancement)

- **excel-cluster-2** (Replica 1)
  - **Read-Only access**
  - Identified by pod index 2
  - Has its own PersistentVolumeClaim (1GB)
  - Can be used for read operations (future enhancement)

**Role Assignment:**

- Pods determine their role (primary vs replica) based on their pod index
- The pod index is extracted from the stable hostname (excel-cluster-0, excel-cluster-1, excel-cluster-2)
- Primary pod (index 0) initializes Excel files; replicas (index > 0) are read-only

**Storage:**

- Each StatefulSet pod has its own PersistentVolumeClaim via `volumeClaimTemplates`
- PHP API pods use `emptyDir` for storage (allows multiple pods, but data not shared between pods)
- In production, consider using GKE Filestore (NFS) for true shared storage

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl describe pod <pod-name> -n excop

# Check events
kubectl get events -n excop --sort-by='.lastTimestamp'
```

### Storage Issues

```bash
# Check PVC status
kubectl get pvc -n excop

# Check StorageClass
kubectl get storageclass
```

### Service Not Accessible

```bash
# Check service endpoints
kubectl get endpoints -n excop

# Test service from within cluster
kubectl run -it --rm debug --image=busybox --restart=Never -n excop -- wget -O- http://php-api-service:9000/api/wanted
```

### Ingress Not Working

```bash
# Check ingress status (GKE uses GCE Ingress, not nginx)
kubectl get ingress -n excop
kubectl describe ingress excop-ingress -n excop

# GKE Ingress can take 2-5 minutes to provision LoadBalancer IP
# Check for LoadBalancer service
kubectl get svc -n kube-system | grep ingress

# If no address after 5 minutes, check GCP console for Load Balancer
```

## Cleanup

### GKE Cleanup (Recommended)

The cleanup script removes the cluster and all Kubernetes resources but preserves Artifact Registry and Docker images:

```bash
./scripts/cleanup.sh
```

### Manual Cleanup

To remove all resources manually:

```bash
kubectl delete -f k8s/
```

**Note:** PVCs created by StatefulSet may need manual deletion:

```bash
kubectl delete pvc -n excop -l app=excel,component=database
```

To delete the GKE cluster:

```bash
gcloud container clusters delete excop-cluster \
  --zone=us-central1-a \
  --project=YOUR_PROJECT_ID
```

## Production Considerations

1. **Image Registry**: Using Google Cloud Artifact Registry (automated in setup script)
2. **Storage**:
   - Current: PHP API uses `emptyDir` (data not shared between pods)
   - Production: Use GKE Filestore (NFS) for ReadWriteMany shared storage
   - Alternative: Access Excel files via StatefulSet services/network
3. **Secrets**: Use proper secret management (e.g., Sealed Secrets, External Secrets, GCP Secret Manager)
4. **Monitoring**: Add Prometheus/Grafana for monitoring
5. **Logging**: Set up centralized logging (e.g., Cloud Logging, ELK stack)
6. **Backup**: Implement backup strategy for Excel files (GKE persistent disks can be snapshotted)
7. **Security**: Enable network policies, RBAC, and Pod Security Standards
8. **Resource Limits**: Adjust resource requests/limits based on actual usage
9. **High Availability**: Consider multi-zone deployments
10. **SSL/TLS**: Configure TLS certificates for Ingress (GKE Managed Certificates)
11. **Primary/Replica Sync**: Implement data replication from primary to replicas if needed

## Files Structure

```text
k8s/
├── namespace.yaml                    # Namespace definition
├── storageclass.yaml                 # StorageClass for Excel volumes (GKE pd-standard)
├── configmap.yaml                    # Application configuration
├── secret.yaml                       # Sensitive data
├── excel-shared-pvc.yaml            # Shared storage PVC (optional, not used by PHP API)
├── excel-statefulset.yaml           # Excel cluster StatefulSet (3 nodes: primary + 2 replicas)
├── excel-services.yaml              # Excel cluster services (headless + primary/replica services)
├── php-api-deployment.yaml          # PHP API deployment (uses emptyDir, not PVC)
├── php-api-service.yaml             # PHP API service
├── cobol-frontend-deployment.yaml   # COBOL frontend deployment
├── cobol-frontend-service.yaml      # COBOL frontend service
├── ingress.yaml                      # Ingress configuration (GKE GCE Ingress)
└── kustomization.yaml               # Kustomize configuration (optional)
```

**Note:** PHP API deployment uses `emptyDir` instead of the shared PVC to allow all 3 pods to start. Each pod has its own storage. For production, use GKE Filestore for true shared storage.

## Support

For issues or questions, please check:

- Kubernetes documentation: <https://kubernetes.io/docs/>
- Project README: [README.md](../README.md)
