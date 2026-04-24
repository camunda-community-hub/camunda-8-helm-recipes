# Dual-Region EKS — Infrastructure Recipe

Provisions two AWS EKS clusters with VPC peering and DNS chaining for a dual-region Camunda deployment. Camunda installation is handled by a separate downstream recipe.

> For architecture details, failure scenarios, and operational procedures see [docs/eks-dual-region-playbook.md](docs/eks-dual-region-playbook.md).

## Prerequisites

- AWS CLI installed and authenticated (`aws sts get-caller-identity`)
- [eksctl](https://eksctl.io/) installed
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed
- [Helm](https://helm.sh/docs/intro/install/) >= 3.19
- GNU `make`

## Quick Start

### 1. Configure

Edit the shared config in `config.mk`:

```makefile
DEPLOYMENT_NAME ?= mydeployment   # clusters: mydeployment-region0, mydeployment-region1
AWS_MACHINE_TYPE ?= m5.2xlarge
DESIRED_SIZE     ?= 4
```

Edit region-specific config in `region0/config.mk` and `region1/config.mk`:

```makefile
# region0/config.mk
AWS_REGION_0 ?= us-west-1
AWS_ZONES_0  ?= 'us-west-1a', 'us-west-1b'
VPC_CIDR_0   ?= 10.195.0.0/16   # must not overlap with VPC_CIDR_1
```

```makefile
# region1/config.mk
AWS_REGION_1 ?= us-west-2
AWS_ZONES_1  ?= 'us-west-2a', 'us-west-2b'
VPC_CIDR_1   ?= 10.196.0.0/16   # must not overlap with VPC_CIDR_0
```

> Override any value without editing committed files by creating a `config.mk` at the project root.

### 2. Create clusters (run in parallel)

**Terminal 1:**
```sh
make -C region0
```

**Terminal 2:**
```sh
make -C region1
```

Each cluster takes ~15-20 minutes. Each creates an EKS cluster with the VPC CIDR set, OIDC enabled, and the EBS CSI driver addon installed.

### 3. Wire up networking

Once both clusters are running:

```sh
make
```

This runs `configure-vpc-peering` then `configure-dns` in sequence.

### 4. Verify DNS

```sh
make test-dns
```

Both regions should resolve each other's namespace across the cluster boundary.

### 5. Deploy Camunda

Use a downstream Camunda recipe targeting both clusters. See `recipes/camunda/` for available options.

## Make Targets

### Region directories (`region0/` and `region1/`)

| Target | Description |
|--------|-------------|
| `make` | Create the EKS cluster (`kube`) |
| `make clean` | Delete the EKS cluster |

### Parent directory (`eks-dual-region/`)

| Target | Description |
|--------|-------------|
| `make` | VPC peering + DNS chaining |
| `make configure-vpc-peering` | Full VPC peering setup |
| `make vpc-peering-status` | Show current peering status |
| `make clean-vpc-peering` | Delete VPC peering |
| `make configure-dns` | Deploy DNS LBs and patch CoreDNS |
| `make test-dns` | Test cross-region DNS resolution |
| `make add-contexts` | Add both clusters to kubeconfig |
| `make verify-contexts` | Check kubectl contexts are configured |
| `make clean` | Remove VPC peering (clusters remain) |

## Uninstall

```sh
# Remove networking
make clean

# Delete clusters
make -C region0 clean
make -C region1 clean
```
