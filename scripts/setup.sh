#!/bin/bash
set -e

# ExCoPstack GKE Setup Script
# This script sets up Google Cloud Artifact Registry, builds and pushes images,
# creates/connects to GKE cluster, and deploys the application

echo "=========================================="
echo "ExCoPstack GKE Setup"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Update these values
PROJECT_ID="${GCP_PROJECT_ID:-}"
REGION="${GCP_REGION:-us-central1}"
ZONE="${GCP_ZONE:-us-central1-a}"
CLUSTER_NAME="${GKE_CLUSTER_NAME:-excop-cluster}"
ARTIFACT_REGISTRY_NAME="${ARTIFACT_REGISTRY_NAME:-excop-registry}"
ARTIFACT_REGISTRY_REPO="${ARTIFACT_REGISTRY_NAME:-excop-registry}"

# Check for required tools
echo -e "${BLUE}Checking prerequisites...${NC}"

if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Error: gcloud CLI is not installed${NC}"
    echo "Install from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}Warning: kubectl not found, will install via gcloud${NC}"
fi

# Get or set project ID
if [ -z "$PROJECT_ID" ]; then
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    if [ -z "$CURRENT_PROJECT" ]; then
        echo -e "${RED}Error: GCP_PROJECT_ID not set and no default project configured${NC}"
        echo "Set it with: export GCP_PROJECT_ID=your-project-id"
        echo "Or configure with: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    PROJECT_ID="$CURRENT_PROJECT"
    echo -e "${YELLOW}Using project: ${PROJECT_ID}${NC}"
else
    gcloud config set project "$PROJECT_ID" > /dev/null 2>&1
fi

# Enable required APIs
echo -e "${BLUE}Enabling required GCP APIs...${NC}"
gcloud services enable container.googleapis.com --project="$PROJECT_ID" 2>/dev/null || true
gcloud services enable artifactregistry.googleapis.com --project="$PROJECT_ID" 2>/dev/null || true

# Step 1: Create Artifact Registry if not exists
echo -e "${YELLOW}Step 1: Setting up Artifact Registry...${NC}"
ARTIFACT_REGISTRY_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REGISTRY_REPO}"

if gcloud artifacts repositories describe "$ARTIFACT_REGISTRY_REPO" \
    --location="$REGION" \
    --project="$PROJECT_ID" &>/dev/null; then
    echo -e "${GREEN}Artifact Registry '${ARTIFACT_REGISTRY_REPO}' already exists${NC}"
else
    echo -e "${YELLOW}Creating Artifact Registry '${ARTIFACT_REGISTRY_REPO}'...${NC}"
    gcloud artifacts repositories create "$ARTIFACT_REGISTRY_REPO" \
        --repository-format=docker \
        --location="$REGION" \
        --description="ExCoPstack Docker images" \
        --project="$PROJECT_ID"
    echo -e "${GREEN}Artifact Registry created${NC}"
fi

# Configure Docker authentication
echo -e "${YELLOW}Configuring Docker authentication...${NC}"
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# Step 2: Build and push images
echo -e "${YELLOW}Step 2: Building and pushing Docker images...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Build PHP API image
echo -e "${BLUE}Building PHP API image...${NC}"
cd "${PROJECT_ROOT}/php-api"
PHP_IMAGE="${ARTIFACT_REGISTRY_URL}/php-api:latest"
docker build -t "$PHP_IMAGE" .
docker push "$PHP_IMAGE"
echo -e "${GREEN}PHP API image pushed: ${PHP_IMAGE}${NC}"

# Build COBOL frontend image
echo -e "${BLUE}Building COBOL frontend image...${NC}"
cd "${PROJECT_ROOT}/cobol"
COBOL_IMAGE="${ARTIFACT_REGISTRY_URL}/cobol-frontend:latest"
docker build -t "$COBOL_IMAGE" .
docker push "$COBOL_IMAGE"
echo -e "${GREEN}COBOL frontend image pushed: ${COBOL_IMAGE}${NC}"

cd "$PROJECT_ROOT"

# Step 3: Create GKE cluster if not exists
echo -e "${YELLOW}Step 3: Setting up GKE cluster...${NC}"

if gcloud container clusters describe "$CLUSTER_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" &>/dev/null; then
    echo -e "${GREEN}GKE cluster '${CLUSTER_NAME}' already exists${NC}"
else
    echo -e "${YELLOW}Creating GKE cluster '${CLUSTER_NAME}'...${NC}"
    gcloud container clusters create "$CLUSTER_NAME" \
        --zone="$ZONE" \
        --num-nodes=3 \
        --machine-type=e2-medium \
        --enable-autoscaling \
        --min-nodes=3 \
        --max-nodes=6 \
        --enable-autorepair \
        --enable-autoupgrade \
        --project="$PROJECT_ID"
    echo -e "${GREEN}GKE cluster created${NC}"
fi

# Step 4: Get cluster credentials
echo -e "${YELLOW}Step 4: Getting cluster credentials...${NC}"
gcloud container clusters get-credentials "$CLUSTER_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID"

# Verify connection
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

echo -e "${GREEN}Connected to cluster${NC}"

# Step 5: Update Kubernetes manifests with image references
echo -e "${YELLOW}Step 5: Updating Kubernetes manifests with image references...${NC}"

K8S_DIR="${PROJECT_ROOT}/k8s"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy manifests to temp directory for modification
cp -r "${K8S_DIR}"/* "$TEMP_DIR/"

# Update PHP API deployment
sed -i.bak "s|image:.*php-api.*|image: ${PHP_IMAGE}|g" "$TEMP_DIR/php-api-deployment.yaml"
rm -f "$TEMP_DIR/php-api-deployment.yaml.bak"

# Update COBOL frontend deployment
sed -i.bak "s|image:.*cobol.*|image: ${COBOL_IMAGE}|g" "$TEMP_DIR/cobol-frontend-deployment.yaml"
rm -f "$TEMP_DIR/cobol-frontend-deployment.yaml.bak"

# Step 6: Apply Kubernetes manifests
echo -e "${YELLOW}Step 6: Deploying to Kubernetes...${NC}"

echo -e "${BLUE}Creating namespace...${NC}"
kubectl apply -f "$TEMP_DIR/namespace.yaml"

echo -e "${BLUE}Creating StorageClass...${NC}"
kubectl apply -f "$TEMP_DIR/storageclass.yaml"

echo -e "${BLUE}Creating ConfigMap...${NC}"
kubectl apply -f "$TEMP_DIR/configmap.yaml"

echo -e "${BLUE}Creating Secret...${NC}"
kubectl apply -f "$TEMP_DIR/secret.yaml"

echo -e "${BLUE}Creating shared Excel storage PVC...${NC}"
kubectl apply -f "$TEMP_DIR/excel-shared-pvc.yaml"

echo -e "${BLUE}Creating Excel StatefulSet cluster (3 nodes)...${NC}"
kubectl apply -f "$TEMP_DIR/excel-statefulset.yaml"

echo -e "${BLUE}Creating Excel services...${NC}"
kubectl apply -f "$TEMP_DIR/excel-services.yaml"

echo -e "${BLUE}Creating PHP API deployment...${NC}"
kubectl apply -f "$TEMP_DIR/php-api-deployment.yaml"

echo -e "${BLUE}Creating PHP API service...${NC}"
kubectl apply -f "$TEMP_DIR/php-api-service.yaml"

echo -e "${BLUE}Creating COBOL frontend deployment...${NC}"
kubectl apply -f "$TEMP_DIR/cobol-frontend-deployment.yaml"

echo -e "${BLUE}Creating COBOL frontend service...${NC}"
kubectl apply -f "$TEMP_DIR/cobol-frontend-service.yaml"

echo -e "${BLUE}Creating Ingress...${NC}"
kubectl apply -f "$TEMP_DIR/ingress.yaml"

echo ""
echo -e "${GREEN}=========================================="
echo "Deployment Complete!"
echo "==========================================${NC}"
echo ""

# Wait for pods to be ready
echo -e "${YELLOW}Waiting for pods to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=excel,component=database -n excop --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=php-api,component=backend -n excop --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=cobol-frontend,component=frontend -n excop --timeout=300s || true

echo ""
echo -e "${GREEN}Current Status:${NC}"
kubectl get all -n excop

echo ""
echo -e "${BLUE}=========================================="
echo "Setup Summary"
echo "==========================================${NC}"
echo -e "Project ID: ${GREEN}${PROJECT_ID}${NC}"
echo -e "Region: ${GREEN}${REGION}${NC}"
echo -e "Cluster: ${GREEN}${CLUSTER_NAME}${NC}"
echo -e "Artifact Registry: ${GREEN}${ARTIFACT_REGISTRY_URL}${NC}"
echo ""
echo -e "${YELLOW}Images pushed:${NC}"
echo "  - ${PHP_IMAGE}"
echo "  - ${COBOL_IMAGE}"
echo ""
echo -e "${YELLOW}To check pod status:${NC}"
echo "  kubectl get pods -n excop"
echo ""
echo -e "${YELLOW}To view logs:${NC}"
echo "  kubectl logs -n excop -l app=php-api --tail=50"
echo "  kubectl logs -n excop -l app=cobol-frontend --tail=50"
echo "  kubectl logs -n excop excel-cluster-0 --tail=50"
echo ""
echo -e "${YELLOW}To access the application:${NC}"
echo "  kubectl port-forward -n excop svc/cobol-frontend-service 8888:80"
echo "  Then open: http://localhost:8888"
echo ""
echo -e "${YELLOW}To get Ingress IP:${NC}"
echo "  kubectl get ingress -n excop"

