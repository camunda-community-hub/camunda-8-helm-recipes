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
│   │   └── rdbms-postgres/
│   ├── kind/                    # Local Kind cluster
│   ├── aws/eks/                 # AWS EKS cluster
│   ├── aws/eks-and-aurora-postgres/
│   ├── azure/aks/               # Azure AKS cluster
│   ├── google/gke/              # Google GKE cluster
│   ├── ingress-nginx/           # Standalone ingress setup
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
Replaces 21 placeholders (`<PLACEHOLDER_NAME>`) with variable values from `config.mk`. Placeholders include:
`<CAMUNDA_VERSION>`, `<YOUR_HOSTNAME>`, `<CAMUNDA_NAMESPACE>`, `<CAMUNDA_CLUSTER_SIZE>`, `<KEYCLOAK_*>`, `<IDENTITY_*>`, `<ORCHESTRATION_*>`, `<WEB_MODELER_*>`, `<CONSOLE_*>`, `<POSTGRES_*>` (8 database vars).

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
| `oidc-ingress-nginx-tls` | same as above + connectors-oidc, identity-keycloak-internal-postgres, modeler-enabled, modeler-internal-postgres, orchestration-oidc, enable-multitenancy, my-camunda-values | Full auth stack; Keycloak, Identity, Web Modeler, multi-tenancy |
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
| `letsencrypt.mk` | Let's Encrypt / cert-manager | `cert-manager`, `letsencrypt-staging`, `letsencrypt-prod`, `annotate-ingress-tls`, `cacerts-staging` |
| `tls-self-signed-cert.mk` | Self-signed certs (OpenSSL) | `create-custom-certs`, `create-tls-secret`, `create-grpc-tls-secret` |
| `tls-keystore.mk` | Java keystore/truststore | `create-keystore`, `create-truststore`, `create-keystore-secret` |
| `metrics.mk` | Prometheus + Grafana | `metrics`, `create-grafana-credentials`, `port-grafana`, `port-prometheus` |
| `keycloak.mk` | Keycloak admin | `create-keycloak-admin-user`, `keycloak-password` |

---

## The `camunda-values.yaml.d/` Files

| File | What It Configures |
|------|-------------------|
| `connectors-enabled.yaml` | `connectors.enabled: true` |
| `connectors-disabled.yaml` | `connectors.enabled: false` |
| `connectors-oidc.yaml` | OIDC auth for Connectors |
| `enable-elasticsearch.yaml` | `elasticsearch.enabled: true` |
| `orchestration-elasticsearch.yaml` | Global Elasticsearch enabled, Zeebe secondary storage = elasticsearch |
| `orchestration-rdbms-postgres.yaml` | Zeebe secondary storage via JDBC (external Postgres); disables Elasticsearch |
| `orchestration-oidc.yaml` | OIDC auth for Zeebe/Orchestration |
| `enable-ingress-nginx.yaml` | Global ingress class=nginx, TLS, HTTP + gRPC hosts with `<YOUR_HOSTNAME>` placeholder |
| `enable-metrics.yaml` | Prometheus ServiceMonitor |
| `enable-multitenancy.yaml` | Multi-tenant mode |
| `identity-keycloak-internal-postgres.yaml` | Full Keycloak + Identity + internal Postgres; maps external URLs and secrets |
| `modeler-enabled.yaml` | Web Modeler with context path `/modeler`, mail config, gRPC/REST URLs |
| `modeler-internal-postgres.yaml` | Web Modeler uses bundled Postgres |
| `modeler-external-postgres.yaml` | Web Modeler uses external Postgres |
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

---

## Compatibility

- Camunda Platform 8.9+
- Camunda Helm Chart 14+
- For older versions: [camunda-8-helm-profiles](https://github.com/camunda-community-hub/camunda-8-helm-profiles)
- Official docs: https://docs.camunda.io/docs/self-managed/deployment/helm/
