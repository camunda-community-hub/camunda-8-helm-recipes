# Camunda 8 with nginx Ingress, TLS & Elasticsearch

Sample of how to configure Camunda 8.10 (Helm chart 15) with nginx ingress and tls.

## Features

This profile provides:
- **Orchestration Cluster**: Zeebe, Operate and Tasklist with an Elasticsearch backend, behind nginx ingress with TLS
- **Connectors**
- No authentication (no Keycloak or Identity)

## Prerequisites

Chart 15 does not bundle Elasticsearch. Install it first with its own recipe:

```bash
make -C ../../elasticsearch   # ECK operator + Elasticsearch
```

Also needed:
- An existing Kubernetes cluster using Kind, Google, AWS or Azure, etc, with an nginx ingress controller (see [`recipes/ingress-nginx`](../../ingress-nginx))
- `kubectl` configured to connect to your cluster
- `helm` version 4 (Helm 3 works but is end of life in 2027) and `yq`
- GNU `make`

## Helm values file

Run `make camunda-values.yaml` to generate a `camunda-values.yaml` file. 

## Install

```bash
make
```

## Verify Installation

Check that all pods are running:

```bash
make pods
```

## Uninstall

```bash
make clean
```

This will remove the Camunda installation and clean up all resources.

## Use Cases

This profile is good to understand how to configure Camunda 8.10 with nginx ingress and tls for network access

## Customization

To customize this profile:

1. Edit [`my-camunda-values.yaml`](my-camunda-values.yaml) for additional overrides
2. Modify `config.mk` at the root project to ovverride default settings found in config.mk
3. Create additional value files in `../camunda-values.yaml.d/` for reusable configurations

## Troubleshooting

### Pods not starting
- Check resource availability: `kubectl describe nodes`
- Check pod events: `kubectl describe pod <pod-name> -n camunda`

### Out of memory errors
- Even though this is a minimal setup, ensure your cluster has sufficient memory
- Consider reducing replica counts further if needed

### Cannot access services
- Verify port forwarding is active
- Check service status: `kubectl get svc -n camunda`