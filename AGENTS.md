# AGENTS.md — Camunda 8 Helm Recipes

Context for AI agents working in this repository.

---

## What This Repository Does

Provides reusable `Makefiles` and composable Helm values files (`camunda-values.yaml.d/`) to install Camunda 8 Platform (8.9+, Helm Chart 14+) into Kubernetes. It is a Community Extension project (Proof-of-Concept lifecycle), not an official Camunda product.

---

## Directory Structure

```
camunda-8-helm-recipes/
├── makefiles/                   # Shared, reusable Makefile modules (.mk files)
├── camunda-values.yaml.d/       # Reusable Helm values files, composed per recipe
├── recipes/                     # Complete deployment scenarios
│   ├── camunda/                 # Camunda installation recipes
│   │   ├── Makefile             # Meta-makefile: runs test across all sub-recipes
│   │   ├── basic-ingress-nginx-tls/
│   │   ├── oidc-ingress-nginx-tls/
│   │   ├── oidc-gateway-traefik-tls/   # Traefik + OpenSearch + external Postgres + OIDC
│   │   ├── oidc-gateway-traefik-tls-es/ # Traefik + Elasticsearch + internal Postgres + OIDC
│   │   ├── rdbms-postgres/
│   │   └── rdbms-postgres-oidc/
│   ├── gateway-traefik/         # Traefik gateway controller base recipe
│   ├── ingress-nginx/           # Standalone nginx ingress setup
│   ├── letsencrypt/             # cert-manager + Let's Encrypt issuers
│   ├── kind/                    # Local Kind cluster
│   ├── aws/eks/                 # AWS EKS cluster
│   ├── aws/eks-and-aurora-postgres/
│   ├── aws/eks-dual-region/     # Dual-region EKS with VPC peering + CoreDNS chaining
│   ├── azure/aks/               # Azure AKS cluster
│   ├── google/gke/              # Google GKE cluster
│   ├── tls-self-signed-certs/   # Self-signed cert generation
│   └── metrics/                 # Prometheus + Grafana stack
└── config.bk.mk                 # Example root config (copy to config.mk to override)
```

---

## How `camunda-values.yaml` Is Generated

This is the core mechanism — understand it before modifying any values files.

The `camunda-values.yaml` target in `makefiles/camunda.mk` runs a two-stage pipeline:

**Stage 1 — yq deep merge:**
```bash
yq eval-all '. as $item ireduce ({}; . * $item)' $(CAMUNDA_HELM_VALUES)
```
Merges all files listed in `CAMUNDA_HELM_VALUES` in order. Later files override earlier ones. **Arrays are not merged — they are replaced entirely by the last file that defines them.**

**Stage 2 — sed substitution:**
Replaces placeholders (`<PLACEHOLDER_NAME>`) with variable values from `config.mk`. Placeholders include:
`<CAMUNDA_VERSION>`, `<YOUR_HOSTNAME>`, `<CAMUNDA_NAMESPACE>`, `<CAMUNDA_CLUSTER_SIZE>`, `<KEYCLOAK_*>`, `<IDENTITY_EXT_URL>`, `<ORCHESTRATION_EXT_URL>`, `<OPTIMIZE_EXT_URL>`, `<CONSOLE_EXT_URL>`, `<WEB_MODELER_EXT_URL>`, `<REPLY_EMAIL>`, `<POSTGRES_HOST>`, `<POSTGRES_KEYCLOAK_HOST>`, `<POSTGRES_KEYCLOAK_DB>`, `<POSTGRES_KEYCLOAK_USERNAME>`, `<POSTGRES_MODELER_HOST>`, `<POSTGRES_MODELER_DB>`, `<POSTGRES_MODELER_USERNAME>`, `<POSTGRES_IDENTITY_DB>`, `<POSTGRES_IDENTITY_USERNAME>`, `<POSTGRES_CAMUNDA_HOST>`, `<POSTGRES_CAMUNDA_DB>`, `<POSTGRES_CAMUNDA_USERNAME>`, `<OPENSEARCH_PROTOCOL>`, `<OPENSEARCH_HOST>`, `<OPENSEARCH_PORT>`, `<OPENSEARCH_USERNAME>`.

**Output:** `./camunda-values.yaml` (gitignored, regenerated each time).

---

## Recipe Structure

Each recipe under `recipes/camunda/` contains:

| File | Purpose |
|------|---------|
| `Makefile` | Includes root variables, recipe config, and shared `.mk` files |
| `config.mk` | Default variable values for this recipe (overridable via root `config.mk`) |
| `my-camunda-values.yaml` | Recipe-specific Helm overrides (last in merge order) |
| `sample-camunda-values.yaml` | **Golden reference** — expected output of `make camunda-values.yaml` |

### Configuration Variable Precedence (highest wins)

1. Command-line: `make HOST_NAME=foo`
2. Root `config.mk` (user/project overrides, not committed)
3. Recipe `config.mk` (recipe defaults, committed)
4. `.mk` file defaults

### Camunda Recipes Summary

| Recipe | Helm Values Composed | Key Features |
|--------|----------------------|--------------|
| `basic-ingress-nginx-tls` | elasticsearch, ingress-nginx, metrics, connectors-enabled, orchestration-elasticsearch, my-camunda-values | Minimal setup; Elasticsearch backend |
| `oidc-ingress-nginx-tls` | elasticsearch, ingress-nginx, metrics, oidc, identity-keycloak-internal-postgres, modeler-enabled, modeler-internal-postgres, orchestration-elasticsearch, enable-multitenancy, my-camunda-values | Full auth stack; Keycloak, Identity, Web Modeler, multi-tenancy |
| `oidc-gateway-traefik-tls` | enable-opensearch, metrics, oidc, identity-keycloak-external-postgres, modeler-enabled, modeler-external-postgres, orchestration-opensearch, optimize-opensearch, console-enabled, my-camunda-values | Traefik IngressRoute CRDs; OpenSearch; external Postgres for Keycloak, Modeler, Identity |
| `oidc-gateway-traefik-tls-es` | enable-elasticsearch, metrics, oidc, identity-keycloak-internal-postgres, modeler-enabled, modeler-internal-postgres, orchestration-elasticsearch, orchestration-oidc, enable-multitenancy, my-camunda-values | Traefik IngressRoute CRDs; Elasticsearch; internal Postgres |
| `rdbms-postgres` | orchestration-rdbms-postgres, my-camunda-values | External Aurora/Postgres backend; no ingress |
| `rdbms-postgres-oidc` | enable-ingress-nginx, identity-keycloak-external-postgres, connectors-oidc, orchestration-rdbms-postgres, orchestration-oidc, my-camunda-values | External Postgres + Keycloak OIDC for Orchestration and Connectors; ingress nginx (HTTP, no TLS) |

---

## The `makefiles/` Modules

| File | Purpose | Key Targets |
|------|---------|-------------|
| `camunda.mk` | Camunda install/uninstall | `camunda`, `camunda-values.yaml`, `install-camunda`, `dry-run-camunda`, `create-camunda-credentials`, `update-camunda`, `clean-camunda`, `template`, `port-*`, `pods` |
| `test.mk` | Test framework | `test` — generates values, diffs vs. sample, cleans up |
| `kind.mk` | Local Kind clusters | `kube-kind`, `clean-kube-kind`, `use-kube` |
| `aws-eks.mk` | AWS EKS | `kube-aws`, `oidc-provider`, `install-ebs-csi-controller-addon`, `scale-down`, `scale-up`, `kube-upgrade`, `ingress-aws-ip-from-service`, `update-route53-dns`, `connect-eks` |
| `aws-aurora.mk` | AWS Aurora RDS | `create-aurora-db`, `setup-all-dbs`, `allow-eks-to-rds`, `test-aurora-from-eks`, `destroy-aurora-db` — all targets pass `--region $(AWS_REGION)` |
| `aws-vpc.mk` | AWS VPC utilities | Minimal |
| `azure-aks.mk` | Azure AKS | `kube-aks`, `kube-agic`, `ingress-nginx-azure`, `connect-aks` |
| `azure-common.mk` | Azure shared setup | `check-az` |
| `google-gke.mk` | Google GKE | `kube-gke`, `node-pool`, `ssd-storageclass`, `scale-*`, `connect-gke` |
| `google-common.mk` | Google shared setup | `check-gcloud` |
| `ingress-nginx.mk` | Nginx ingress | `ingress-ip-from-service`, `ingress-hostname-from-service`, `annotate-ingress-proxy-buffer-size` |
| `letsencrypt.mk` | Let's Encrypt / cert-manager | `cert-manager`, `letsencrypt-staging`, `letsencrypt-prod` (both honour `INGRESS_CLASS`), `request-certificate`, `delete-certificate`, `annotate-ingress-tls`, `get-cert-requests`, `get-cert-orders`, `cacerts-staging` |
| `tls-self-signed-cert.mk` | Self-signed certs (OpenSSL) | `create-custom-certs`, `create-tls-secret`, `create-grpc-tls-secret` |
| `tls-keystore.mk` | Java keystore/truststore | `create-keystore`, `create-truststore`, `create-keystore-secret` |
| `metrics.mk` | Prometheus + Grafana | `metrics`, `create-grafana-credentials`, `port-grafana`, `port-prometheus` |
| `keycloak.mk` | Keycloak admin | `create-keycloak-admin-user`, `keycloak-password` |

---

## The `camunda-values.yaml.d/` Files

| File | What It Configures |
|------|-------------------|
| `oidc.yaml` | **Core OIDC/Keycloak config** — sets `global.identity.auth.enabled: true`, issuer URLs, backend URLs, client redirect URLs, Keycloak admin connection (`global.identity.keycloak.url`). Always combine with one of the identity-keycloak-*.yaml files. |
| `connectors-enabled.yaml` | `connectors.enabled: true` |
| `connectors-disabled.yaml` | `connectors.enabled: false` |
| `connectors-oidc.yaml` | OIDC auth for Connectors |
| `enable-elasticsearch.yaml` | `elasticsearch.enabled: true` |
| `enable-opensearch.yaml` | `global.opensearch.enabled: true` with URL/auth placeholders |
| `orchestration-elasticsearch.yaml` | Global Elasticsearch enabled, Zeebe secondary storage = elasticsearch |
| `orchestration-opensearch.yaml` | Zeebe secondary storage = OpenSearch |
| `orchestration-rdbms-postgres.yaml` | Zeebe secondary storage via JDBC (external Postgres); disables Elasticsearch |
| `orchestration-oidc.yaml` | OIDC auth for Zeebe/Orchestration |
| `optimize-opensearch.yaml` | Optimize connected to OpenSearch |
| `console-enabled.yaml` | Console component with context path `/console` and component URL map |
| `enable-ingress-nginx.yaml` | Global ingress class=nginx, TLS, HTTP + gRPC hosts with `<YOUR_HOSTNAME>` placeholder |
| `enable-metrics.yaml` | Prometheus ServiceMonitor |
| `enable-multitenancy.yaml` | Multi-tenant mode |
| `identity-keycloak-internal-postgres.yaml` | Identity + Keycloak + bundled Postgres; context path `/management` |
| `identity-keycloak-external-postgres.yaml` | Identity + Keycloak + external Postgres; context path `/management` |
| `modeler-enabled.yaml` | Web Modeler with context path `/modeler`, mail config, gRPC/REST URLs |
| `modeler-internal-postgres.yaml` | Web Modeler uses bundled Postgres |
| `modeler-external-postgres.yaml` | Web Modeler uses external Postgres (`<POSTGRES_MODELER_HOST>`) |
| `enable-identity-postgres.yaml` | Internal Postgres for Identity |
| `custom-registry.yaml` | Override container image registry |
| `modeler-debug.yaml` | DEBUG logging for Web Modeler |

---

## Testing

### How It Works

`makefiles/test.mk` provides a `test` target that:
1. Runs `make camunda-values.yaml` (always regenerates from scratch)
2. Diffs output against `sample-camunda-values.yaml`
3. On pass: prints PASS, deletes generated file
4. On fail: prints diff, deletes generated file, exits 1

### Running Tests

```bash
# Single recipe
make -C recipes/camunda/basic-ingress-nginx-tls test

# All Camunda recipes (fails fast)
make -C recipes/camunda test
```

### Updating Golden References

When a recipe change is intentional, update `sample-camunda-values.yaml`:

```bash
make -C recipes/camunda/basic-ingress-nginx-tls camunda-values.yaml
cp recipes/camunda/basic-ingress-nginx-tls/camunda-values.yaml \
   recipes/camunda/basic-ingress-nginx-tls/sample-camunda-values.yaml
```

Commit the updated `sample-camunda-values.yaml`.

---

## Secrets & Credentials

Passwords are **never stored in config files or git**. The `create-camunda-credentials` target (in `camunda.mk`) creates a Kubernetes secret named `camunda-credentials` with keys for all components. YAML values files reference this secret via `existingSecret` / `existingSecretKey`.

The `DEFAULT_PASSWORD` variable in recipe `config.mk` is used by `create-camunda-credentials`. Default is `changeme` — override in root `config.mk` for real deployments.

---

## Common Patterns & Gotchas

- **Array merge limitation**: `yq` replaces arrays entirely. If multiple values files set the same array key (e.g., `zeebe.env`), only the last one wins. Consolidate array definitions into a single file or into `my-camunda-values.yaml`.
- **Root `config.mk`**: Create a `config.mk` at repo root to override variables (e.g., `HOST_NAME`, `AWS_REGION`, `HOSTED_ZONE_NAME`) without touching committed files. This file is gitignored.
- **`ingress-aws-ip-from-service`**: Resolves the ELB IP via `dig` on the hostname from the ingress-nginx service — does NOT use the AWS ENI API (which only works for Classic LBs, not NLBs).
- **`update-route53-dns`**: Upserts A records for `HOST_NAME` and `grpc.HOST_NAME` in Route 53. Requires `HOSTED_ZONE_NAME` (the zone domain name, e.g. `aws.c8sm.com`) — the target looks up the zone ID automatically. Do not set `HOSTED_ZONE_ID`.
- **`-include` vs `include`**: Recipes use `-include $(root)/config.mk` (dash = don't fail if missing) for the user's root override, and `include ./config.mk` (no dash) for the recipe's own defaults.
- **`camunda-values.yaml` is always deleted first**: The `camunda-values.yaml` target depends on `delete-camunda-values`, ensuring a clean regeneration every time.
- **Cloud provider recipes are independent of Camunda recipes**: Provision your cluster with a cloud recipe first, then use a Camunda recipe to install.
- **`connect-gke` / `connect-eks` / `connect-aks`**: Use these instead of `use-kube` when switching between environments during the day. Each target checks whether the cloud session is still valid, re-authenticates interactively if expired (`gcloud auth login` / `aws sso login` / `az login`), updates the kubectl context, and prints a status banner showing the active cloud, account/identity, cluster, region, and current kubectl context.
- **`global.identity.auth.enabled: true` is required (Helm chart 14+)**: The Helm chart gates the entire Identity→Keycloak admin connection (and the `keycloak.url` block in the Identity configmap) behind `global.identity.auth.enabled`. Without it, Identity falls back to `localhost:18080`. This flag is now set in `oidc.yaml` so all OIDC recipes inherit it automatically.
- **Traefik + cert-manager: certificates are not automatic**: The `annotate-ingress-tls` targets only work with standard Kubernetes `Ingress` resources (nginx). Traefik `IngressRoute` CRDs are not watched by cert-manager. Use `make request-certificate` (from `letsencrypt.mk`) to explicitly create a cert-manager `Certificate` resource that produces the `TLS_SECRET_NAME` secret referenced by the IngressRoute.
- **`INGRESS_CLASS` for Let's Encrypt issuers**: `letsencrypt-staging` and `letsencrypt-prod` targets now substitute `<INGRESS_CLASS>` in the ClusterIssuer YAML. Default is `nginx`. Set `INGRESS_CLASS ?= traefik` in your recipe's `config.mk` when using Traefik so the ACME HTTP-01 solver routes challenges through the correct ingress controller.
- **Test suite uses recipe defaults, not root `config.mk`**: `sample-camunda-values.yaml` files are generated with the recipe's own default variable values (e.g., `HOST_NAME=example.com`). Tests are designed for CI where no root `config.mk` exists. Running `make test` locally will fail if your root `config.mk` overrides any of those variables.

---

## Compatibility

- Camunda Platform 8.9+
- Camunda Helm Chart 14+
- For older versions: [camunda-8-helm-profiles](https://github.com/camunda-community-hub/camunda-8-helm-profiles)
- Official docs: https://docs.camunda.io/docs/self-managed/deployment/helm/
