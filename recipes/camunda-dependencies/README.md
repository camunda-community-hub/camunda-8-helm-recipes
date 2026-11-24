# Camunda dependencies

Installs the third party services Camunda 8.10 (Helm chart 15) needs, by running the existing single-purpose recipes
in order. Chart 15 bundles none of them. Nothing here is cloud specific: it only needs a working kube context, so it
works the same on GKE, AKS, EKS and Kind. Cloud specific steps (cluster, storage class, DNS records) stay in the cloud
recipes.

| Flag | Default | Recipe |
|---|---|---|
| `WITH_TRAEFIK` | `true` | `gateway-traefik` |
| `WITH_CERT_MANAGER` | `true` | `letsencrypt` (cert-manager + Let's Encrypt ClusterIssuer) |
| `WITH_POSTGRES` | `true` | `postgres` (CloudNativePG) |
| `WITH_KEYCLOAK` | `true` | `keycloak` (Keycloak operator, needs Postgres) |
| `WITH_ELASTICSEARCH` | `true` | `elasticsearch` (ECK) |
| `WITH_METRICS` | `false` | `metrics` (kube-prometheus-stack) |

## Usage

```bash
make KUBE_CONTEXT=<context> CAMUNDA_NAMESPACE=camunda HOST_NAME=<host>
make WITH_POSTGRES=false WITH_KEYCLOAK=false          # for example a second region without its own Keycloak
```

`CAMUNDA_NAMESPACE`, `INGRESS_CLASS` and `KEYCLOAK_INGRESS` are passed down to the sub-recipes.
Pass region-specific values on the command line, so they win over the root `config.mk`.

## Cleanup

`make clean` with the same flags removes everything in reverse order, custom resources (and their PVCs) before their
operators.
