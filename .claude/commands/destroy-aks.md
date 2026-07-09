---
description: Tear down an Azure AKS Camunda 8 environment. Removes Camunda then deletes the AKS cluster and resource group.
---

You are helping tear down an Azure AKS Camunda 8 environment. This is **irreversible** — the AKS cluster and all resources will be permanently deleted.

Before doing anything:
1. Confirm the `DEPLOYMENT_NAME` with the user (read it from root `config.mk` or ask them to state it explicitly).
2. Ask for explicit confirmation: "This will permanently destroy the `<DEPLOYMENT_NAME>` cluster and all associated resources. Type YES to continue."
3. Only proceed after receiving YES.

The root of the repo is at the git root — find it with `git rev-parse --show-toplevel`.

---

## Step 1 — Remove Camunda

```
cd <root>/recipes/camunda/oidc-gateway-traefik-tls-es && make clean
```

This removes the Camunda Helm release, ingress routes, and deletes the `camunda` namespace.

## Step 2 — Delete GCP DNS records

```
cd <root>/recipes/gateway-traefik && make delete-gcp-dns
```

Removes the two A records from GCP Cloud DNS zone `aks`:
- `${DEPLOYMENT_NAME}.aks.c8sm.com`
- `grpc.${DEPLOYMENT_NAME}.aks.c8sm.com`

If `gcloud` is not authenticated, tell the user to run `! gcloud auth login`.

## Step 3 — Delete AKS cluster, metrics, and resource group

```
cd <root>/recipes/azure/aks && make clean
```

This runs `clean-ingress`, `clean-metrics`, and `clean-kube` in sequence:
- Removes Prometheus + Grafana (`clean-metrics`)
- Removes the AKS cluster (`az aks delete`)
- Deletes the Azure resource group `${DEPLOYMENT_NAME}-rg` (`az group delete`)

If `az` session has expired, tell the user to run `! az login` first.

Do NOT ask for confirmation again — the user already confirmed with YES at the start. Just run it.

Deletion takes several minutes. After it completes, verify the resource group is gone:
```
az group show --name <DEPLOYMENT_NAME>-rg
```
