# Camunda 8 Helm Profile: Metrics

This folder contains a [Makefile](Makefile) that can be used to install and configure Prometheus and Grafana into an existing Kubernetes Cluster. 

## Features

This profile provides:
- **Prometheus**:  installed via the Prometheus Community Helm Chart
- **Grafana**: installed via the Prometheus Community Helm Chart

## Prerequisites

- An existing Kubernetes cluster using Kind, Google, AWS or Azure, etc
- `helm` version 3.7.0 or later
- GNU `make`

## Install

By default, the Grafana admin password is set inside [./config.mk](./config.mk). To override the default password,
Create a `config.mk` at the root of this project and override the `GRAFANA_PASSWORD` variable to set a custom Grafana admin password:

Open a terminal and run:

```sh
make
```
## Uninstall
```sh
make clean
```

# Grafana connection details:  

```shell
make url-grafana
```

## Camunda SaaS metrics

Scrape a Camunda SaaS cluster with the Prometheus installed by this recipe, and get a Zeebe dashboard for it.
It uses the [Cluster Metrics endpoint](https://docs.camunda.io/docs/components/saas/monitoring/cluster-metrics-endpoint/),
which you activate on the cluster's **Monitoring** tab in Camunda Hub. The IP the scrape comes from must be on the
cluster's IP allowlist, if it has one.

Set these in the root `config.mk` (not committed):

```makefile
SAAS_METRICS_HOST = <metrics endpoint host, without https:// and path>
SAAS_CLUSTER_ID = <cluster id>
SAAS_METRICS_USERNAME = <monitoring username>
SAAS_METRICS_PASSWORD = <monitoring password>
```

```bash
cd recipes/metrics
make saas-scrape        # Secret + ScrapeConfig, series get the label environment="saas". No Prometheus restart
make saas-dashboard     # generate dashboards/zeebe-saas.json, then import it in Grafana (Dashboards > New > Import)
make clean-saas-scrape  # remove the Secret and ScrapeConfig
```

`saas-dashboard` builds the dashboard from the Zeebe dashboard Grafana serves, so it follows upstream. Grafana loads that
one when its pod starts, so restart Grafana first to pick up a newer upstream version. The cluster dropdown lists every
cluster scraped with `environment="saas"`, and the dashboard opens on `SAAS_CLUSTER_ID` when it is set.

Limits: `saas-scrape` handles one cluster (fixed resource names). SaaS exposes no Kubernetes metrics, so the CPU, network and disk
panels stay empty. Metric names depend on the Camunda version of the cluster.
