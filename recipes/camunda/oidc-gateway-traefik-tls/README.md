# Camunda 8 with OIDC, Traefik Gateway & TLS

Sample of how to configure Camunda 8.9 with Traefik IngressRoute CRDs and TLS certificates.
Keycloak is used for OIDC authentication. All components share a single domain with context-path routing, consistent with the nginx ingress recipes.

## Features

This recipe provides:
- **Traefik IngressRoute CRDs** — HTTP→HTTPS redirect, path-based routing, gRPC routing for Zeebe
- **Keycloak and Identity** — OIDC authentication with external PostgreSQL
- **Orchestration Cluster** — Zeebe broker with embedded Operate & Tasklist
- **Connectors** — with OIDC authentication
- **Optimize** — connected to OpenSearch
- **Web Modeler** — webapp + websockets, external PostgreSQL
- **Console** — with managed release configuration
- **OpenSearch** — external cluster (Elasticsearch disabled)

## Prerequisites

- An existing Kubernetes cluster with **Traefik** installed (see [`recipes/gateway-traefik`](../../gateway-traefik))
- Traefik CRDs (`IngressRoute`, `IngressRouteTCP`, `Middleware`) available in the cluster
- **OpenSearch** cluster accessible from the Camunda namespace
- **External PostgreSQL** for Keycloak and Web Modeler databases
- A TLS secret (or cert-manager) for your domain
- `kubectl` configured to connect to your cluster
- `helm` version 3.7.0 or later
- GNU `make`

## Configuration

The `camunda-values.yaml` is composed from reusable fragments in [`camunda-values.yaml.d/`](../../../camunda-values.yaml.d/):

| Fragment | Purpose |
|---|---|
| `enable-opensearch.yaml` | Global OpenSearch connection |
| `enable-metrics.yaml` | Prometheus ServiceMonitor |
| `oidc.yaml` | OIDC authentication (issuer URLs, client secrets, redirects) |
| `identity-keycloak-external-postgres.yaml` | Identity + Keycloak + external database |
| `modeler-enabled.yaml` | Web Modeler base config |
| `modeler-external-postgres.yaml` | Modeler external database |
| `orchestration-opensearch.yaml` | Orchestration with OpenSearch |
| `optimize-opensearch.yaml` | Optimize connected to OpenSearch |
| `console-enabled.yaml` | Console with managed releases |

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
POSTGRES_HOST = 10.0.0.1
OPENSEARCH_HOST = opensearch.shared.svc.cluster.local
```

## Troubleshooting

### Pods not starting
- Check resource availability: `kubectl describe nodes`
- Check pod events: `kubectl describe pod <pod-name> -n camunda`

### OIDC / SSO errors
- Verify `KC_HOSTNAME` resolves to `HOST_NAME`
- Ensure the `issuerBackendUrl` points to the cluster-internal Keycloak service
- Check Keycloak realm and client configuration

### Traefik routes not working
- Verify CRDs are installed: `kubectl get crd ingressroutes.traefik.io`
- Check IngressRoute status: `kubectl get ingressroute -n camunda`
- Review Traefik logs: `kubectl logs -l app.kubernetes.io/name=traefik`

### OpenSearch connection issues
- Verify connectivity from the namespace
- Check credentials in the `camunda-credentials` secret
