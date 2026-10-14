# File-based secret store for Camunda 8.10

Camunda 8.10 resolves `camunda.secrets.NAME` references in processes from a secret store, so credentials stay out of
process models, job variables and Helm values. This recipe sets up the **file store**: a Kubernetes Secret that the chart
mounts read-only at `/etc/camunda/secrets`, one file per key. It suits development, testing and simple setups.
For production, consider AWS Secrets Manager or GCP Secret Manager.

It creates the Secret `camunda-process-secrets` in the Camunda namespace. The Helm side is the values fragment
[`orchestration-secret-store-file.yaml`](../../../camunda-values.yaml.d/orchestration-secret-store-file.yaml),
which a Camunda recipe composes into its `CAMUNDA_HELM_VALUES`. The `oidc-gateway-traefik-tls-es` recipe already does.

## Define secrets

Add a `SECRET_<NAME>` variable per secret to the **root `config.mk`** (gitignored). The `SECRET_` prefix is removed to
get the secret name, so this line creates a secret `MYAPI_SECRET`:

```makefile
SECRET_MYAPI_SECRET = 123xyz
```

A process reads it as `=camunda.secrets.MYAPI_SECRET`. Names with dashes need backticks in FEEL,
for example `` =camunda.secrets.`my-key` ``.

You can also pass one on the command line: `make SECRET_MYAPI_SECRET=123xyz`.

Rules:
- Only variables set in a `config.mk` or on the `make` command line are used. Plain shell environment variables
  named `SECRET_*` are ignored, so nothing unexpected from your shell ends up in the Secret.
- Use `=`, not `?=`. With `?=`, a shell environment variable of the same name takes precedence over the config value,
  and the variable is then ignored like any other environment variable.
- A name may only contain letters, digits, `_` and `-`, and be at most 240 characters. Dots are not resolvable, so
  `make` stops with an error for them.
- Make treats `$` and `#` specially in a `config.mk`. Write a literal `$` as `$$` and a literal `#` as `\#`.
  For example, the value `pa$word#1` is written `SECRET_X = pa$$word\#1`.
- Do not put values in a committed `config.mk` (such as this recipe's). Use the root `config.mk`.

## Install

Run this before installing Camunda, because the Orchestration pods mount the Secret and wait for it to exist.

```bash
make
```

It prints the secret names it found, never the values. With no `SECRET_*` variables, it creates an empty Secret so
the pods can still start.

## Add, change or remove a secret later

Edit the `SECRET_*` lines and run `make` again. It updates the Secret in place and removes keys you deleted.
Kubernetes refreshes the mounted files after a short delay, and the Orchestration Cluster caches resolved values
(20 seconds by default), so a change can take a minute or so to show up.

If you add the fragment to a release that is already running, create the Secret first, then run `make update-camunda`
in the Camunda recipe.

## Uninstall

```bash
make clean
```

## Notes

- Only one secret store is allowed per physical tenant, and its id must be `default`.
- Legacy connector secrets (`{{secrets.NAME}}`) are separate: they come from `SECRET_` environment variables on the Connectors pod.
- A process that uses `camunda.secrets.NAME` with no store configured gets a "secret resolution error" incident.
