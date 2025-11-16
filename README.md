<div align="center">

# ExCoPstack

> exhausting combo. excel as a “database”? imagine suffocating your data with spreadsheets before cobol drags it back to the stone age, and php pretending it’s modern. excop? more like excruciatingly copious trash. put this stack to rest before someone reports it for crimes against tech. lowkey a disaster wrapped in legacy garbage. boomers confirmed.
>
> ~ [roastedby.ai](https://www.roastedby.ai)

[![Excel](https://img.shields.io/badge/Excel-6F99A6.svg?style=for-the-badge)](https://www.microsoft.com/en-us/microsoft-365/excel)
[![COBOL](https://img.shields.io/badge/COBOL-5D4F85.svg?style=for-the-badge)](https://gnucobol.sourceforge.io/)
[![PHP](https://img.shields.io/badge/PHP-6F99A6.svg?style=for-the-badge)](https://www.php.net/)

## A "most wanted list" project with: Excel, Cobol, PHP stack

</div>

![ui](./ui.png)

## Tech Stack:

- COBOL - Frontend
- PHP - Backend
- Excel - Database

The communication between COBOL and PHP is done via a **CSV REST API**.

## Running the Project

```bash
docker compose up -d
```

## Stopping the Project

```bash
docker compose down
```

## Accessing the Project

```plaintext
open http://localhost:8888 in your browser
```

## Accessing the PHP API

```plaintext
http://localhost:9000/api/
```

## Accessing the Excel File

- Open the [Excel file](./storage/wanted.xlsx) with Microsoft Excel

## Kubernetes Deployment (GKE Compatible)

ExCoPstack is fully configured for deployment on **Google Kubernetes Engine (GKE)**.

### Quick Deploy to GKE

```bash
# Set your GCP project
export GCP_PROJECT_ID=your-project-id

# Run automated setup (creates cluster, builds images, deploys everything)
./scripts/setup.sh
```

The setup script automatically:
- Creates/uses Google Cloud Artifact Registry
- Builds and pushes Docker images
- Creates/connects to GKE cluster
- Deploys all Kubernetes resources

### Kubernetes Features

- **2 Deployments** (COBOL Frontend, PHP API) with replicas and rolling updates
- **6 Services** for service discovery
- **Ingress** resource (GKE GCE Ingress)
- **ConfigMap and Secret** usage
- **StatefulSet** with 3-node Excel cluster (1 primary R/W, 2 replicas R/O)
- **StorageClass** for persistent volumes

### Architecture

```mermaid
graph TB
    subgraph GKE["GKE Cluster"]
        subgraph Frontend["COBOL Frontend (Deployment)"]
            F1[Pod 1]
            F2[Pod 2]
        end
        
        subgraph Backend["PHP API (Deployment)"]
            P1[Pod 1]
            P2[Pod 2]
            P3[Pod 3]
        end
        
        subgraph Excel["Excel Cluster (StatefulSet)"]
            E0[excel-cluster-0<br/>Primary R/W]
            E1[excel-cluster-1<br/>Replica R/O]
            E2[excel-cluster-2<br/>Replica R/O]
        end
        
        Frontend -->|API Calls| Backend
        Backend -->|Read/Write| E0
        Backend -.->|Read Only| E1
        Backend -.->|Read Only| E2
    end
    
    Ingress[Ingress<br/>GCE Load Balancer] --> Frontend
    Ingress -->|/api| Backend
    
    style E0 fill:#90EE90
    style E1 fill:#FFE4B5
    style E2 fill:#FFE4B5
    style Frontend fill:#E6F3FF
    style Backend fill:#FFF0E6
```

### Documentation

- **Kubernetes Deployment Guide**: [K8S_DEPLOYMENT.md](./K8S_DEPLOYMENT.md)
- **Setup Scripts**: [scripts/README.md](./scripts/README.md)
- **Cleanup**: `./scripts/cleanup.sh` (preserves Artifact Registry)

### Requirements

- Google Cloud Platform account with billing enabled
- `gcloud` CLI installed and configured
- `docker` installed and running

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=MemerGamer/ExCoPstack&type=date&legend=top-left)](https://www.star-history.com/#MemerGamer/ExCoPstack&type=date&legend=top-left)

## License

[MIT](./LICENSE)
