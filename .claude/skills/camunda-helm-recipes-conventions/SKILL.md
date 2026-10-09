---
name: camunda-helm-recipes-conventions
description: Explains how the camunda-8-helm-recipes repo is organized and the conventions and best practices to follow when adding or changing a recipe, values fragment, or makefile module (directory layout, recipe anatomy, config precedence, placeholders, chart 14 vs chart 15 fragments, golden-file tests, secrets). Use when working on files under recipes/, camunda-values.yaml.d/ or makefiles/, or when asked how the project is structured.
---

# Camunda 8 Helm Recipes: structure and conventions

`AGENTS.md` is the full reference (targets, placeholders, file purposes); read it for detail. This skill is the
map plus the rules to follow when changing things. Check the code before relying on any file named here.

## Layout and what each part is for
| Path | Role |
|---|---|
| `recipes/camunda/<name>/` | Camunda install recipes: pure values composition + golden test |
| `recipes/<platform>/<name>/` | Cluster/platform recipes (`aws`, `azure`, `google`, `kind`) |
| `recipes/<platform>/include/` | Manifests and templates shared by that platform's recipes (`*.tpl.yaml`, sed placeholders) |
| `recipes/{ingress-nginx,tls-self-signed-certs,metrics,...}/` | Single-purpose infrastructure recipes |
| `recipes/kind/hub/` | Combined recipe: provisions Kind + dependencies and installs Camunda (like `aws/eks-and-aurora-postgres`) |
| `camunda-values.yaml.d/` | Reusable single-concern Helm values fragments, composed per recipe |
| `makefiles/*.mk` | Shared make modules, one concern each (platform, ingress, TLS, Keycloak, Camunda, test) |

Principle: provision the platform first, then install Camunda; each piece is its own recipe or module so it can be
reused. Prefer reusing an existing module or recipe over duplicating logic.

## Recipe anatomy
`Makefile` (root detection, `-include $(root)/config.mk`, `include ./config.mk`, then `include` the modules),
`config.mk` (defaults, always `?=`), `my-camunda-values.yaml` (recipe-specific overrides, last in the merge),
`sample-camunda-values.yaml` (golden output), `README.md` (prerequisites, usage, cleanup, limitations).
Copy the boilerplate from an existing recipe; the depth of `root` (`../..` vs `../../..`) depends on the directory.

Variable precedence, highest first: CLI > root `config.mk` (user-specific, gitignored, never commit) > recipe
`config.mk` > defaults inside `.mk` files.

## Values fragments (`camunda-values.yaml.d/`)
- `camunda-values.yaml` = yq deep merge of `CAMUNDA_HELM_VALUES` in order, then sed replaces `<PLACEHOLDER>` tokens
  with `config.mk` variables (list lives in `makefiles/camunda.mk`). To add a placeholder, add the variable in
  `config.mk` AND the sed line in `camunda.mk`.
- Arrays are replaced, never merged: the last file defining an array wins (e.g. `zeebe.env`, `global.extraManifests`).
- One concern per file, named `{component}-{setting}.yaml`, `enable-{feature}.yaml` or `orchestration-{backend}.yaml`,
  with a header comment saying what it does and what it pairs or conflicts with.
- Chart versions: most fragments target chart 14 (Camunda 8.9). Chart 15 (8.10) changed keys (e.g. `global.host`
  replaced `global.ingress.host`, no bundled Keycloak/PostgreSQL, Hub replaces Web Modeler/Console). Chart 15 fragments
  live flat in the same directory with distinct names (`hub-enabled`, `oidc-external-keycloak`, `ingress-nginx-host`,
  `identity-own-hostname`) and a header comment naming the chart. Do not edit a chart 14 fragment to make it work
  on chart 15 (it would break the 8.9 recipes).
- Small extra Kubernetes objects can ride along in values via `global.extraManifests` instead of separate manifests.
- Secrets never go in YAML: use the `existingSecret` pattern; `make create-camunda-credentials` builds
  `camunda-credentials` from `DEFAULT_PASSWORD` (the project default is `changeme`; local-only recipes may override).
- Preserve the existing typo in `orchaestration-dual-region-postgres.yaml`; other files reference it.

## Make modules and manifests
- One concern per `.mk`; targets are `.PHONY`, named for what they do; no hardcoded hosts, names or passwords.
- Platform-specific steps (cluster, ingress controller install) live in that platform's module
  (`makefiles/ingress-nginx.mk` says the `ingress-nginx` target belongs to each platform's makefile).
- Manifests are templates (`*.tpl.yaml`) with `<PLACEHOLDER>` tokens filled by sed in the target, kept in the
  platform's `include/`, like `recipes/aws/include/cluster.tpl.yaml`.
- Extend a shared module additively and keep default behavior unchanged. Example: `CA_KEY_PASS` makes the TLS
  module non-interactive only when set.
- Anything needing `sudo` (e.g. `/etc/hosts`) is a documented manual step with a preflight check that prints the
  exact command; never automated silently.
- Generated artifacts (`camunda-values.yaml`, `cluster.yaml`, certs) are gitignored; add new generated paths to `.gitignore`.

## Testing and validation
- `make test` in a Camunda recipe regenerates `camunda-values.yaml` and diffs it against
  `sample-camunda-values.yaml`; the pipeline is deterministic. After an intentional change, regenerate and copy
  to the sample, and review the diff.
- New Camunda recipes must be added to `CAMUNDA_RECIPES` in `recipes/camunda/Makefile`; relative paths such as
  `../kind/hub` work. The suite stops at the first failure.
- Tests use recipe defaults, not your root `config.mk`; a local override can fail them.
- Golden tests only prove the YAML is stable, not that it is valid. Also run
  `helm template camunda camunda/camunda-platform --version <chart> -n camunda -f camunda-values.yaml` against
  the target chart (use an explicit alpha version for prereleases); it catches removed keys and failed constraints.
- As of 2026-10-01 the golden samples for `oidc-ingress-nginx-tls` and `oidc-gateway-traefik-tls` already fail on a
  pristine `HEAD`. Verify with a `git archive HEAD` copy before assuming your change broke them.

## Checklist for a new or changed recipe
1. Reuse existing modules, recipes and fragments; add new ones only for new concerns.
2. Defaults in `config.mk`, overrides never committed; no secrets in YAML.
3. `make test` passes for the recipe; `helm template` against the target chart succeeds.
4. Add or update `sample-camunda-values.yaml`, `README.md` (prerequisites, usage, cleanup, known limitations) and the
   `AGENTS.md` recipe/fragment tables.
5. Document manual steps and destructive commands (`clean` deletes things) clearly.
6. Separate unrelated changes into separate branches/PRs (this repo is worked on through a fork + feature branch).
