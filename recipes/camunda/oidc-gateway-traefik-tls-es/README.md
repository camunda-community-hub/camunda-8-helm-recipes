# Camunda 8 with OIDC, Traefik Gateway, TLS & Elasticsearch

Sample of how to configure Camunda 8.10 (Helm chart 15) with Traefik IngressRoute CRDs and TLS certificates.
Keycloak is used for OIDC authentication. All components share a single domain with context-path routing, consistent with the nginx ingress recipes.

## Features

This recipe provides:
- **Traefik IngressRoute CRDs** — HTTP→HTTPS redirect, path-based routing, gRPC routing for Zeebe
- **Keycloak and Identity** — OIDC authentication, Keycloak run by the Keycloak operator, Identity on CloudNativePG PostgreSQL
- **Orchestration Cluster** — Zeebe broker with embedded Operate & Tasklist, Elasticsearch backend
- **Connectors** — with OIDC authentication
- **Optimize** — connected to Elasticsearch
- **Camunda Hub** — Web Modeler and Console in one component, on CloudNativePG PostgreSQL
- **Elasticsearch** — run by the ECK operator
- **Multi-tenancy** — enabled

## Prerequisites

Chart 15 does not bundle Elasticsearch, Keycloak or PostgreSQL. Install them first with their own recipes:

```bash
make -C ../../elasticsearch   # ECK operator + Elasticsearch
make -C ../../postgres        # CloudNativePG operator + pg-identity, pg-keycloak, pg-hub
make -C ../../keycloak        # Keycloak operator + Keycloak (set KEYCLOAK_INGRESS ?= none, Traefik routes /auth)
```

Also needed:
- An existing Kubernetes cluster with **Traefik** installed (see [`recipes/gateway-traefik`](../../gateway-traefik))
- Traefik CRDs (`IngressRoute`, `IngressRouteTCP`, `Middleware`) available in the cluster
- A TLS secret (or cert-manager) for your domain — see [`recipes/letsencrypt`](../../letsencrypt)
- `kubectl` configured to connect to your cluster
- `helm` version 4 (Helm 3 works but is end of life in 2027) and `yq`
- GNU `make`

## Configuration

The `camunda-values.yaml` is composed from reusable fragments in [`camunda-values.yaml.d/`](../../../camunda-values.yaml.d/):

| Fragment | Purpose |
|---|---|
| `enable-metrics.yaml` | Prometheus ServiceMonitor |
| `oidc.yaml` | OIDC authentication (issuer URLs, client secrets, redirects, Keycloak admin connection) |
| `identity-enabled.yaml` | Management Identity on external PostgreSQL |
| `hub-enabled.yaml` | Camunda Hub (replaces Web Modeler and Console) on external PostgreSQL |
| `orchestration-elasticsearch.yaml` | Orchestration with Elasticsearch secondary storage |
| `orchestration-oidc.yaml` | OIDC configuration for Orchestration |
| `optimize-elasticsearch.yaml` | Optimize connected to Elasticsearch |
| `enable-multitenancy.yaml` | Multi-tenancy support |

See [`my-camunda-values.yaml`](./my-camunda-values.yaml) for additional overrides (resources, env vars).

## Helm values file

Run `make camunda-values.yaml` to generate a `camunda-values.yaml` file.

## Install

```bash
make
```

This will:
1. Generate `camunda-values.yaml` from the composed fragments
2. Create the `camunda-credentials` Kubernetes secret
3. Install Camunda via Helm
4. Generate and apply Traefik IngressRoute manifests

## Verify Installation

Check that all pods are running:

```bash
make pods
```

## Uninstall

```bash
make clean
```

This removes the Traefik IngressRoutes, uninstalls the Camunda Helm release, and deletes the namespace.

## Customization

To customize this recipe:

1. Edit [`my-camunda-values.yaml`](my-camunda-values.yaml) for additional overrides
2. Modify `config.mk` at the root project to override default settings found in `config.mk`
3. Create additional value files in [`camunda-values.yaml.d/`](../../../camunda-values.yaml.d/) for reusable configurations

Key variables to set in your root `config.mk`:

```makefile
HOST_NAME = my-camunda.example.com
TLS_SECRET_NAME = my-tls-secret

# All component URLs default to https://$(HOST_NAME) — override individually if needed:
# OPTIMIZE_EXT_URL = https://my-camunda.example.com
```

## Troubleshooting

### Pods not starting
- Check resource availability: `kubectl describe nodes`
- Check pod events: `kubectl describe pod <pod-name> -n camunda`

### OIDC / SSO errors
- Verify `HOST_NAME` resolves to the Traefik address and that https://HOST_NAME/auth is reachable
- Ensure the `issuerBackendUrl` points to the cluster-internal Keycloak service
- Check Keycloak realm and client configuration

### Identity cannot connect to Keycloak
- Ensure `global.identity.auth.enabled: true` is set (handled by `oidc.yaml`)
- Confirm the `keycloak-service` service is running: `kubectl get svc keycloak-service -n camunda`

### Traefik routes not working
- Verify CRDs are installed: `kubectl get crd ingressroutes.traefik.io`
- Check IngressRoute status: `kubectl get ingressroute -n camunda`
- Review Traefik logs: `kubectl logs -l app.kubernetes.io/name=traefik`
