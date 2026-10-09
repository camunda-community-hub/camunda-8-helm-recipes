# Provision Elasticsearch with the ECK operator

Camunda 8.10 (Helm chart 15) no longer bundles Elasticsearch. This recipe installs the
[ECK operator](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html) and an Elasticsearch cluster,
following the [Camunda reference architecture](https://docs.camunda.io/docs/self-managed/deployment/helm/configure/operator-based-infrastructure/#elasticsearch-deployment).

Run it before installing a Camunda recipe that uses Elasticsearch
(`orchestration-elasticsearch.yaml`, `optimize-elasticsearch.yaml`).

## What you get
- ECK operator in the `elastic-system` namespace
- An `Elasticsearch` resource named `elasticsearch` in `CAMUNDA_NAMESPACE` (default `camunda`)
- Service `elasticsearch-es-http:9200` (plain HTTP inside the cluster) and secret `elasticsearch-es-elastic-user`
  (the `elastic` user password), which the Camunda values fragments reference

## Prerequisites
- A Kubernetes cluster provisioned and accessible.
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed.
- At least `ES_NODE_COUNT` Kubernetes nodes (pods use required anti-affinity), with enough CPU and memory.

## Install
```sh
make
```

Override sizing in the root `config.mk`, for example:
```make
ES_NODE_COUNT ?= 3
ES_CPU_REQUEST ?= 4
ES_CPU_LIMIT ?= 4
ES_MEMORY ?= 8Gi
ES_STORAGE_SIZE ?= 128Gi
```

## Useful targets
| Target | What it does |
|---|---|
| `make elasticsearch-status` | Show the cluster, pods and volumes |
| `make elasticsearch-password` | Print the `elastic` user password |
| `make port-elasticsearch` | Port-forward to `localhost:9200` |

## Uninstall
```sh
make clean              # deletes the Elasticsearch cluster and its data (keeps the operator)
make clean-eck-operator # removes the operator and CRDs, only if no other clusters use it
```

## Notes
- `ES_VERSION` should be the latest version in the
  [Camunda supported environments matrix](https://docs.camunda.io/docs/reference/supported-environments/).
- TLS is disabled for in-cluster traffic, as in the Camunda reference. Enable it for production.
