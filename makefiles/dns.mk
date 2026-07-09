# ---------------------------------------------------------------------------
# DNS management — Route 53 (AWS) and Cloud DNS (GCP)
# ---------------------------------------------------------------------------

GCP_DNS_ZONE ?= aks
DNS_TTL ?= 60

# Traefik service defaults (used by GCP DNS targets to look up the LB IP)
TRAEFIK_NAMESPACE ?= traefik
TRAEFIK_RELEASE_NAME ?= traefik

# Upserts A records in GCP Cloud DNS for HOST_NAME and grpc.HOST_NAME pointing to the Traefik LB IP.
# Requires HOST_NAME (e.g. mydeployment.aks.c8sm.com) and GCP_DNS_ZONE (default: aks) to be set.
# Usage: make update-gcp-dns
.PHONY: update-gcp-dns
update-gcp-dns:
	@echo "Getting Traefik LoadBalancer IP..."
	@IP=$$(kubectl get service $(TRAEFIK_RELEASE_NAME) -n $(TRAEFIK_NAMESPACE) \
		--output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null); \
	if [ -z "$$IP" ]; then \
		echo "❌ No IP found for Traefik service. Is Traefik running and does it have an external IP?"; exit 1; \
	fi; \
	echo "Traefik IP: $$IP"; \
	for HOST in "$(HOST_NAME)." "grpc.$(HOST_NAME)."; do \
		echo "Upserting GCP DNS record: $$HOST → $$IP (zone: $(GCP_DNS_ZONE))"; \
		gcloud dns record-sets delete "$$HOST" --type=A --zone=$(GCP_DNS_ZONE) --quiet 2>/dev/null || true; \
		gcloud dns record-sets create "$$HOST" --type=A --ttl=$(DNS_TTL) --rrdatas="$$IP" --zone=$(GCP_DNS_ZONE); \
	done; \
	echo "✅ DNS updated: $(HOST_NAME) → $$IP"; \
	echo "✅ DNS updated: grpc.$(HOST_NAME) → $$IP"

# Deletes the GCP Cloud DNS A records for HOST_NAME and grpc.HOST_NAME.
# Usage: make delete-gcp-dns
.PHONY: delete-gcp-dns
delete-gcp-dns:
	@echo "Deleting GCP DNS records for $(HOST_NAME) and grpc.$(HOST_NAME) from zone $(GCP_DNS_ZONE)..."
	-gcloud dns record-sets delete "$(HOST_NAME)." --type=A --zone=$(GCP_DNS_ZONE) --quiet
	-gcloud dns record-sets delete "grpc.$(HOST_NAME)." --type=A --zone=$(GCP_DNS_ZONE) --quiet
	@echo "✅ DNS records deleted (or were already absent)"

# Upserts an A record in Route 53 pointing HOST_NAME to the ingress-nginx ELB IP.
# Requires HOSTED_ZONE_NAME (e.g. aws.c8sm.com) and HOST_NAME to be set (override in root config.mk).
# Usage: make update-route53-dns
.PHONY: update-route53-dns
update-route53-dns:
	@echo "Looking up ELB hostname from ingress-nginx service..."
	@ELB_HOSTNAME=$$(kubectl get service ingress-nginx-controller -n ingress-nginx \
		--output jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
	if [ -z "$$ELB_HOSTNAME" ]; then \
		echo "❌ No ELB hostname found. Is ingress-nginx running?"; exit 1; \
	fi; \
	echo "ELB Hostname: $$ELB_HOSTNAME"; \
	IP=$$(dig +short $$ELB_HOSTNAME | head -1); \
	if [ -z "$$IP" ]; then \
		echo "❌ Could not resolve $$ELB_HOSTNAME to an IP address."; exit 1; \
	fi; \
	echo "Looking up Route 53 hosted zone ID for $(HOSTED_ZONE_NAME)..."; \
	ZONE_ID=$$(aws route53 list-hosted-zones-by-name \
		--dns-name $(HOSTED_ZONE_NAME) \
		--max-items 1 \
		--query "HostedZones[0].Id" \
		--output text | cut -d'/' -f3); \
	if [ -z "$$ZONE_ID" ] || [ "$$ZONE_ID" = "None" ]; then \
		echo "❌ Could not find hosted zone for $(HOSTED_ZONE_NAME)"; exit 1; \
	fi; \
	echo "Zone ID: $$ZONE_ID"; \
	echo "Upserting Route 53 A records: $(HOST_NAME) and grpc.$(HOST_NAME) → $$IP"; \
	aws route53 change-resource-record-sets \
		--hosted-zone-id $$ZONE_ID \
		--change-batch '{"Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"$(HOST_NAME)","Type":"A","TTL":60,"ResourceRecords":[{"Value":"'"$$IP"'"}]}},{"Action":"UPSERT","ResourceRecordSet":{"Name":"grpc.$(HOST_NAME)","Type":"A","TTL":60,"ResourceRecords":[{"Value":"'"$$IP"'"}]}}]}' \
		--no-cli-pager; \
	echo "✅ DNS updated: $(HOST_NAME) → $$IP"; \
	echo "✅ DNS updated: grpc.$(HOST_NAME) → $$IP"
