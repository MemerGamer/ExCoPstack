# ExCoPstack Scripts

This directory contains automation scripts for deploying ExCoPstack to Google Kubernetes Engine (GKE).

## Scripts

### `setup.sh`

Complete GKE setup and deployment script. This script:

1. **Creates/uses Artifact Registry**
   - Creates Google Cloud Artifact Registry if it doesn't exist
   - Uses existing registry if present
   - Configures Docker authentication

2. **Builds and pushes Docker images**
   - Builds PHP API image
   - Builds COBOL frontend image
   - Pushes both to Artifact Registry

3. **Creates/connects to GKE cluster**
   - Creates GKE cluster if it doesn't exist
   - Connects to existing cluster if present
   - Configures cluster with autoscaling (3-6 nodes)

4. **Deploys application**
   - Updates Kubernetes manifests with correct image references
   - Applies all Kubernetes resources
   - Waits for pods to be ready

**Usage:**

```bash
# Set environment variables (optional, will use gcloud defaults if not set)
export GCP_PROJECT_ID=your-project-id
export GCP_REGION=us-central1
export GCP_ZONE=us-central1-a
export GKE_CLUSTER_NAME=excop-cluster
export ARTIFACT_REGISTRY_NAME=excop-registry

# Run setup
./scripts/setup.sh
```

**Requirements:**
- `gcloud` CLI installed and authenticated
- `docker` installed and running
- GCP project with billing enabled
- Required APIs enabled (script enables them automatically)

### `cleanup.sh`

Removes all ExCoPstack resources from GKE while preserving Artifact Registry and Docker images.

**What it removes:**
- GKE cluster
- All Kubernetes resources (deployments, services, ingress, etc.)
- Persistent volumes and claims
- Namespace

**What it preserves:**
- Artifact Registry repository
- All Docker images in Artifact Registry

**Usage:**

```bash
# Set same environment variables as setup.sh
export GCP_PROJECT_ID=your-project-id
export GCP_REGION=us-central1
export GCP_ZONE=us-central1-a
export GKE_CLUSTER_NAME=excop-cluster

# Run cleanup
./scripts/cleanup.sh
```

## Environment Variables

All scripts support the following environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `GCP_PROJECT_ID` | (from gcloud config) | GCP project ID |
| `GCP_REGION` | `us-central1` | GCP region |
| `GCP_ZONE` | `us-central1-a` | GCP zone |
| `GKE_CLUSTER_NAME` | `excop-cluster` | GKE cluster name |
| `ARTIFACT_REGISTRY_NAME` | `excop-registry` | Artifact Registry repository name |

## Example Workflow

```bash
# 1. Set up GCP project
gcloud config set project your-project-id

# 2. Authenticate (if not already done)
gcloud auth login
gcloud auth application-default login

# 3. Run setup
./scripts/setup.sh

# 4. Use the application
kubectl port-forward -n excop svc/cobol-frontend-service 8888:80
# Open http://localhost:8888

# 5. When done, cleanup (preserves images)
./scripts/cleanup.sh
```

## Troubleshooting

### "gcloud CLI is not installed"
Install from: https://cloud.google.com/sdk/docs/install

### "Cannot connect to Kubernetes cluster"
- Ensure you've run `gcloud auth login`
- Check that the cluster exists: `gcloud container clusters list`
- Verify project: `gcloud config get-value project`

### "Docker build fails"
- Ensure Docker is running: `docker ps`
- Check Docker authentication: `gcloud auth configure-docker`

### "Image pull errors"
- Verify images exist: `gcloud artifacts docker images list REGION-docker.pkg.dev/PROJECT/REPO`
- Check cluster has access to Artifact Registry (usually automatic with Workload Identity)

### "Cluster creation fails"
- Check billing is enabled: `gcloud billing accounts list`
- Verify quotas: `gcloud compute project-info describe --project=PROJECT_ID`
- Check required APIs are enabled

## Cost Considerations

**Note:** Costs vary by region and are approximate. Check [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator) for exact pricing.

### Estimated Monthly Costs (us-central1, 24/7 operation):

- **GKE Cluster Management**: ~$73/month (flat fee)
- **Compute Nodes**: ~$73/month for 3 e2-medium nodes
  - e2-medium: ~$0.0335/hour per node
  - 3 nodes × $0.0335/hour × 730 hours/month ≈ $73/month
- **Artifact Registry**: 
  - First 0.5 GB: Free
  - Additional: $0.10/GB/month
  - Typical usage: <$1/month for small projects
- **Load Balancer (Ingress)**: ~$18/month base + data transfer
  - Base forwarding rule: ~$18/month
  - Data processing: ~$0.008/GB
- **Persistent Disks**: ~$0.17/GB/month (pd-standard)
  - 3 Excel cluster PVCs (1GB each): ~$0.51/month
  - Shared storage (1GB): ~$0.17/month

**Total Estimated Monthly Cost**: ~$165-200 for 24/7 operation

### Cost Reduction Strategies:

- **Delete cluster when not in use** (images preserved in Artifact Registry)
- **Use preemptible nodes** (up to 80% savings, but can be terminated)
- **Scale down during off-hours** (reduce node count)
- **Use smaller machine types** (e2-small instead of e2-medium)
- **Single-zone deployment** (reduces network costs)

### Free Tier Credits:

New Google Cloud accounts receive $300 in free credits, which can cover several months of development/testing.

