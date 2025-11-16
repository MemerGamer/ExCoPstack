#!/bin/bash
set -e

# ExCoPstack GKE Cleanup Script
# This script removes all ExCoPstack resources from Kubernetes and GKE
# but preserves the Artifact Registry and Docker images

echo "=========================================="
echo "ExCoPstack GKE Cleanup"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Should match setup.sh
PROJECT_ID="${GCP_PROJECT_ID:-}"
REGION="${GCP_REGION:-us-central1}"
ZONE="${GCP_ZONE:-us-central1-a}"
CLUSTER_NAME="${GKE_CLUSTER_NAME:-excop-cluster}"

# Check for required tools
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Error: gcloud CLI is not installed${NC}"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}Warning: kubectl not found${NC}"
fi

# Get project ID
if [ -z "$PROJECT_ID" ]; then
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    if [ -z "$CURRENT_PROJECT" ]; then
        echo -e "${RED}Error: GCP_PROJECT_ID not set and no default project configured${NC}"
        exit 1
    fi
    PROJECT_ID="$CURRENT_PROJECT"
fi

echo -e "${BLUE}Using project: ${PROJECT_ID}${NC}"
echo -e "${BLUE}Cluster: ${CLUSTER_NAME}${NC}"
echo ""
echo -e "${YELLOW}This will delete:${NC}"
echo "  - GKE cluster: ${CLUSTER_NAME}"
echo "  - All Kubernetes resources in 'excop' namespace"
echo ""
echo -e "${GREEN}This will preserve:${NC}"
echo "  - Artifact Registry and all Docker images"
echo ""

read -p "Are you sure you want to proceed? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Step 1: Delete Kubernetes resources
echo -e "${YELLOW}Step 1: Deleting Kubernetes resources...${NC}"

# Get cluster credentials if cluster exists
if gcloud container clusters describe "$CLUSTER_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" &>/dev/null; then
    
    echo -e "${BLUE}Getting cluster credentials...${NC}"
    gcloud container clusters get-credentials "$CLUSTER_NAME" \
        --zone="$ZONE" \
        --project="$PROJECT_ID" 2>/dev/null || true
    
    if kubectl cluster-info &> /dev/null; then
        K8S_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../k8s" && pwd)"
        
        echo -e "${BLUE}Deleting Kubernetes resources...${NC}"
        
        # Delete in reverse order of creation
        kubectl delete -f "${K8S_DIR}/ingress.yaml" --ignore-not-found=true || true
        kubectl delete -f "${K8S_DIR}/cobol-frontend-service.yaml" --ignore-not-found=true || true
        kubectl delete -f "${K8S_DIR}/cobol-frontend-deployment.yaml" --ignore-not-found=true || true
        kubectl delete -f "${K8S_DIR}/php-api-service.yaml" --ignore-not-found=true || true
        kubectl delete -f "${K8S_DIR}/php-api-deployment.yaml" --ignore-not-found=true || true
        kubectl delete -f "${K8S_DIR}/excel-services.yaml" --ignore-not-found=true || true
        kubectl delete -f "${K8S_DIR}/excel-statefulset.yaml" --ignore-not-found=true || true
        kubectl delete -f "${K8S_DIR}/excel-shared-pvc.yaml" --ignore-not-found=true || true
        kubectl delete -f "${K8S_DIR}/secret.yaml" --ignore-not-found=true || true
        kubectl delete -f "${K8S_DIR}/configmap.yaml" --ignore-not-found=true || true
        kubectl delete -f "${K8S_DIR}/storageclass.yaml" --ignore-not-found=true || true
        kubectl delete -f "${K8S_DIR}/namespace.yaml" --ignore-not-found=true || true
        
        # Also delete PVCs created by StatefulSet
        echo -e "${BLUE}Cleaning up StatefulSet PVCs...${NC}"
        kubectl delete pvc -n excop -l app=excel,component=database --ignore-not-found=true || true
        kubectl delete pvc excel-shared-storage -n excop --ignore-not-found=true || true
        
        # Delete namespace if it still exists
        kubectl delete namespace excop --ignore-not-found=true || true
        
        echo -e "${GREEN}Kubernetes resources deleted${NC}"
    else
        echo -e "${YELLOW}Could not connect to cluster, skipping Kubernetes resource deletion${NC}"
    fi
else
    echo -e "${YELLOW}Cluster '${CLUSTER_NAME}' does not exist, skipping Kubernetes resource deletion${NC}"
fi

# Step 2: Delete GKE cluster
echo -e "${YELLOW}Step 2: Deleting GKE cluster...${NC}"

if gcloud container clusters describe "$CLUSTER_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" &>/dev/null; then
    
    echo -e "${BLUE}Deleting GKE cluster '${CLUSTER_NAME}'...${NC}"
    gcloud container clusters delete "$CLUSTER_NAME" \
        --zone="$ZONE" \
        --project="$PROJECT_ID" \
        --quiet
    
    echo -e "${GREEN}GKE cluster deleted${NC}"
else
    echo -e "${YELLOW}Cluster '${CLUSTER_NAME}' does not exist${NC}"
fi

echo ""
echo -e "${GREEN}=========================================="
echo "Cleanup Complete!"
echo "==========================================${NC}"
echo ""
echo -e "${GREEN}Preserved:${NC}"
echo "  - Artifact Registry and all Docker images"
echo ""
echo -e "${YELLOW}To view preserved images:${NC}"
ARTIFACT_REGISTRY_NAME="${ARTIFACT_REGISTRY_NAME:-excop-registry}"
echo "  gcloud artifacts docker images list ${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REGISTRY_NAME}"
echo ""
echo -e "${YELLOW}To completely remove Artifact Registry (if needed):${NC}"
echo "  gcloud artifacts repositories delete ${ARTIFACT_REGISTRY_NAME} \\"
echo "    --location=${REGION} \\"
echo "    --project=${PROJECT_ID}"
