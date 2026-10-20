.PHONY: metrics
metrics: create-grafana-credentials
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add stable https://charts.helm.sh/stable
	helm repo update prometheus-community stable
	helm install metrics prometheus-community/kube-prometheus-stack --wait -f $(root)/recipes/metrics/prometheus-operator-values.yml --set prometheusOperator.tlsProxy.enabled=false --namespace default
	kubectl apply -f $(root)/recipes/metrics/grafana-load-balancer.yml -n default
	@${MAKE} grafana-password

.PHONY: grafana-password
grafana-password:
	@echo "Grafana Admin Username: "
	@kubectl get secret grafana-credentials --namespace default \
		-o jsonpath="{.data.admin-user}" | base64 --decode
	@echo ""
	@echo "Grafana Admin Password: "
	@kubectl get secret grafana-credentials --namespace default \
		-o jsonpath="{.data.admin-password}" | base64 --decode
	@echo ""

.PHONY: update-metrics
update-metrics:
	helm upgrade metrics prometheus-community/kube-prometheus-stack --wait -f $(root)/recipes/metrics/prometheus-operator-values.yml --set prometheusOperator.tlsProxy.enabled=false --namespace default

.PHONY: clean-metrics
clean-metrics:
	-kubectl delete -f $(root)/recipes/metrics/grafana-load-balancer.yml -n default
	-helm uninstall metrics --namespace default
	-kubectl delete secret grafana-credentials metrics-kube-prometheus-st-admission -n default
#	-kubectl delete -f $(include-dir)/ssd-storageclass.yaml -n default
	-kubectl delete pvc -l app.kubernetes.io/name=prometheus -n default
	-kubectl delete pvc -l app.kubernetes.io/name=grafana -n default
	-kubectl get crd -o name | grep 'monitoring.coreos.com' | xargs kubectl delete

.PHONY: saas-scrape
saas-scrape:
	@test -n "$(SAAS_METRICS_HOST)" -a -n "$(SAAS_CLUSTER_ID)" -a -n "$(SAAS_METRICS_USERNAME)" -a -n "$(SAAS_METRICS_PASSWORD)" || \
		(echo "Set SAAS_METRICS_HOST, SAAS_CLUSTER_ID, SAAS_METRICS_USERNAME and SAAS_METRICS_PASSWORD in the root config.mk" && exit 1)
	-kubectl delete secret camunda-saas-metrics --namespace default
	kubectl create secret generic camunda-saas-metrics \
	  --from-literal=username=$(SAAS_METRICS_USERNAME) \
	  --from-literal=password=$(SAAS_METRICS_PASSWORD) \
	  --namespace default
	sed -e "s/<SAAS_METRICS_HOST>/$(SAAS_METRICS_HOST)/g" \
	    -e "s/<SAAS_CLUSTER_ID>/$(SAAS_CLUSTER_ID)/g" \
	    $(root)/recipes/metrics/saas-scrapeconfig.yaml | kubectl apply -n default -f -

# Generates a Zeebe dashboard for SaaS clusters from the Zeebe dashboard Grafana serves (the one the chart downloads when
# the Grafana pod starts), so it follows upstream changes. Restart Grafana to pick up a newer upstream version.
# Edits: new uid and title, no "All" for the cluster variable, and the cluster dropdown lists only environment="saas" series.
# When SAAS_CLUSTER_ID is set, the dashboard opens on that cluster. Otherwise Grafana selects the first one.
# The result is generated, so it is gitignored. Import it in Grafana: Dashboards > New > Import.
SAAS_DASHBOARD_SOURCE_UID ?= zeebe-dashboard
SAAS_DASHBOARD_UID ?= zeebe-saas-dashboard
SAAS_DASHBOARD_TITLE ?= Zeebe (SaaS)
SAAS_DASHBOARD_FILE ?= $(root)/recipes/metrics/dashboards/zeebe-saas.json
SAAS_DASHBOARD_PORT ?= 13000

define _SAAS_DASHBOARD_JQ
.dashboard
| del(.id)
| .uid = $$uid
| .title = $$title
| .tags = ["saas"]
| .version = 0
| .templating.list |= map(
    if .name == "cluster" then
      .includeAll = false
      | del(.allValue)
      | .query.query = "label_values(atomix_role{environment=\"saas\"}, cluster)"
      | .options = []
      | if $$cluster != "" then .current = {text: $$cluster, value: $$cluster} else del(.current) end
    else . end)
endef
export _SAAS_DASHBOARD_JQ

.PHONY: saas-dashboard # generate the Zeebe dashboard JSON for SaaS clusters from the dashboard Grafana serves
saas-dashboard:
	@mkdir -p $(dir $(SAAS_DASHBOARD_FILE))
	@kubectl port-forward svc/metrics-grafana $(SAAS_DASHBOARD_PORT):80 -n default >/dev/null 2>&1 & PF_PID=$$!; \
	trap "kill $$PF_PID 2>/dev/null" EXIT; \
	for i in 1 2 3 4 5 6 7 8 9 10; do curl -sf localhost:$(SAAS_DASHBOARD_PORT)/api/health >/dev/null && break; sleep 1; done; \
	GRAFANA_USER=$$(kubectl get secret grafana-credentials -n default -o jsonpath='{.data.admin-user}' | base64 --decode); \
	GRAFANA_PASS=$$(kubectl get secret grafana-credentials -n default -o jsonpath='{.data.admin-password}' | base64 --decode); \
	curl -sf -u "$$GRAFANA_USER:$$GRAFANA_PASS" localhost:$(SAAS_DASHBOARD_PORT)/api/dashboards/uid/$(SAAS_DASHBOARD_SOURCE_UID) \
	  | jq -e --arg uid '$(SAAS_DASHBOARD_UID)' --arg title '$(SAAS_DASHBOARD_TITLE)' --arg cluster '$(SAAS_CLUSTER_ID)' "$$_SAAS_DASHBOARD_JQ" \
	  > $(SAAS_DASHBOARD_FILE).tmp \
	  && jq -e '.panels | length > 0' $(SAAS_DASHBOARD_FILE).tmp >/dev/null \
	  && mv $(SAAS_DASHBOARD_FILE).tmp $(SAAS_DASHBOARD_FILE) \
	  || { rm -f $(SAAS_DASHBOARD_FILE).tmp; echo "Could not fetch dashboard $(SAAS_DASHBOARD_SOURCE_UID) from Grafana"; exit 1; }
	@echo "Wrote $(SAAS_DASHBOARD_FILE) (import it in Grafana: Dashboards > New > Import)"

.PHONY: clean-saas-scrape
clean-saas-scrape:
	-kubectl delete scrapeconfig camunda-saas --namespace default
	-kubectl delete secret camunda-saas-metrics --namespace default

.PHONY: port-grafana
port-grafana:
	kubectl port-forward svc/metrics-grafana-loadbalancer 8080:80 -n default

.PHONY: port-prometheus
port-prometheus:
	kubectl port-forward svc/metrics-kube-prometheus-st-prometheus 9090:9090 -n default

.PHONY: url-grafana
url-grafana: grafana-password
	@echo "Grafana URL: "
	@echo http://$(shell kubectl get services metrics-grafana-loadbalancer -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}')/d/zeebe-dashboard/zeebe?var-namespace=$(namespace)
	@echo ""

.PHONY: open-grafana
open-grafana:
	xdg-open http://$(shell kubectl get services metrics-grafana-loadbalancer -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}')/d/zeebe-dashboard/zeebe?var-namespace=$(namespace) &

.PHONY: create-grafana-credentials
create-grafana-credentials:
	-kubectl delete secret grafana-credentials --namespace default
	kubectl create secret generic grafana-credentials \
	  --from-literal=admin-user=camunda \
	  --from-literal=admin-password=$(GRAFANA_PASSWORD) \
	  --namespace default