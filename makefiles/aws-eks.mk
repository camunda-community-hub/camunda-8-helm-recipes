cluster.yaml: clean-cluster-yaml
	sed "s/<DEPLOYMENT_NAME>/$(DEPLOYMENT_NAME)/g; \
	     s/<CLUSTER_VERSION>/$(CLUSTER_VERSION)/g; \
	     s/<REGION>/$(AWS_REGION)/g; \
	     s/<MACHINE_TYPE>/$(AWS_MACHINE_TYPE)/g; \
	     s/<MIN_SIZE>/$(MIN_SIZE)/g; \
	     s/<DESIRED_SIZE>/$(DESIRED_SIZE)/g; \
	     s/<MAX_SIZE>/$(MAX_SIZE)/g; \
	     s/<VOLUME_SIZE>/$(VOLUME_SIZE)/g; \
	     s|<ZONES>|[$(AWS_ZONES)]|g;" \
	     $(root)/recipes/aws/include/cluster.tpl.yaml > cluster.yaml

.PHONY: clean-cluster-yaml
clean-cluster-yaml:
	rm -rf cluster.yaml

.PHONY: oidc-provider
oidc-provider:
	eksctl utils associate-iam-oidc-provider --cluster $(DEPLOYMENT_NAME) --approve --region $(AWS_REGION)

.PHONY: install-ebs-csi-controller-addon
install-ebs-csi-controller-addon:
ifeq "1.23" "$(word 1, $(sort 1.23 $(CLUSTER_VERSION)))"
	@echo "need to install ebs-csi-controller-addon";
	$(MAKE) ebs-csi-controller-addon
endif

#https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html
.PHONY: ebs-csi-controller-addon
ebs-csi-controller-addon: ebs-csi-attach-role-policy create-ebs-csi-addon annotate-ebs-csi-sa restart-ebs-csi-controller

.PHONY: fetch-id-values
fetch-id-values:
	@echo "Fetching OIDC and account identifiers..."
	$(eval oidc_id := $(shell aws eks describe-cluster --name $(DEPLOYMENT_NAME) --region $(AWS_REGION) --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5))
	$(eval account_id := $(shell aws sts get-caller-identity --query Account --output text))

.PHONY: create-ebs-csi-controller-role-def
create-ebs-csi-controller-role-def:fetch-id-values
# 1. Fetch OIDC Provider id and AccountId, and create the aws-ebs-csi-driver-trust-policy.json file
	sed "s/<account_id>/$(account_id)/g; s/<region>/$(AWS_REGION)/g; s/<oidc_id>/$(oidc_id)/g;" $(root)/recipes/aws/include/ebs-csi-driver-trust-policy-template.json > ebs-csi-driver-trust-policy.json

.PHONY: create-ebs-csi-role
create-ebs-csi-role: create-ebs-csi-controller-role-def
# 2. Create the IAM Role - to be run only once, the script will throw error if the role exists already
	-aws iam create-role \
	  --role-name AmazonEKS_EBS_CSI_DriverRole_Cluster_$(DEPLOYMENT_NAME) \
	  --assume-role-policy-document file://"ebs-csi-driver-trust-policy.json";
	@echo "waiting 20 seconds to create the required role";
	@sleep 20;

.PHONY: ebs-csi-attach-role-policy
ebs-csi-attach-role-policy: create-ebs-csi-role
# 3.Attach the role to the IAM policy
	aws iam attach-role-policy \
	  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
	  --role-name AmazonEKS_EBS_CSI_DriverRole_Cluster_$(DEPLOYMENT_NAME)

.PHONY: create-ebs-csi-addon
create-ebs-csi-addon: fetch-id-values
# 4. Add the aws-ebs-csi-driver addon to the cluster
	aws eks create-addon --cluster-name $(DEPLOYMENT_NAME) --region $(AWS_REGION) --addon-name aws-ebs-csi-driver \
	  --service-account-role-arn arn:aws:iam::$(account_id):role/AmazonEKS_EBS_CSI_DriverRole_Cluster_$(DEPLOYMENT_NAME);
	@echo "waiting 20 seconds to create the aws-ebs-csi-driver addon";
	@sleep 20;

.PHONY: annotate-ebs-csi-sa
annotate-ebs-csi-sa: fetch-id-values
# 5. Annotate the ebs-csi-controller-sa svc account
	kubectl annotate serviceaccount ebs-csi-controller-sa \
		-n kube-system \
		eks.amazonaws.com/role-arn=arn:aws:iam::$(account_id):role/AmazonEKS_EBS_CSI_DriverRole_Cluster_$(DEPLOYMENT_NAME) \
		--overwrite

.PHONY: restart-ebs-csi-controller
restart-ebs-csi-controller:
# 6. Restart ebs-csi-controller  if required
	kubectl rollout restart deployment ebs-csi-controller -n kube-system

.PHONY: kube-aws
kube-aws: cluster.yaml
	eksctl create cluster -f cluster.yaml
	rm -f $(root)/aws/ingress/nginx/tls/cluster.yaml
	kubectl apply -f $(root)/recipes/aws/include/ssd-storageclass-aws.yaml
	kubectl patch storageclass ssd -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
	kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

.PHONY: kube
kube: kube-aws

.PHONY: kube-upgrade
kube-upgrade:
	eksctl upgrade cluster --name=$(DEPLOYMENT_NAME) --version=$(CLUSTER_VERSION) --approve

.PHONY: detach-role-policy-mapping
detach-role-policy-mapping:
	-aws iam detach-role-policy \
	  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
	  --role-name AmazonEKS_EBS_CSI_DriverRole_Cluster_$(DEPLOYMENT_NAME)

.PHONY: delete-iam-role
delete-iam-role: detach-role-policy-mapping
	-aws iam delete-role \
	  --role-name AmazonEKS_EBS_CSI_DriverRole_Cluster_$(DEPLOYMENT_NAME)
	-rm ebs-csi-driver-trust-policy.json

.PHONY: clean-kube-aws
clean-kube-aws: use-kube clean-cluster-yaml delete-iam-role
	eksctl delete cluster --name $(DEPLOYMENT_NAME) --region $(AWS_REGION)

.PHONY: clean-kube
clean-kube: clean-kube-aws

.PHONY: use-kube
use-kube:
	eksctl utils write-kubeconfig -c $(DEPLOYMENT_NAME) --region $(AWS_REGION)

.PHONY: connect-eks
connect-eks:
	@echo "--- Connecting to EKS ---"
	@aws sts get-caller-identity > /dev/null 2>&1 || \
		(echo "AWS session expired. Re-authenticating..." && aws sso login)
	eksctl utils write-kubeconfig -c $(DEPLOYMENT_NAME) --region $(AWS_REGION)
	@echo ""
	@echo "✅ Active cloud:  AWS (Amazon Web Services)"
	@echo "   Account:       $$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)"
	@echo "   Identity:      $$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null)"
	@echo "   Cluster:       $(DEPLOYMENT_NAME) [$(AWS_REGION)]"
	@echo "   kubectl ctx:   $$(kubectl config current-context 2>/dev/null)"
	@echo ""
	@echo "Verifying kubectl connectivity..."
	@if kubectl get nodes --request-timeout=10s > /dev/null 2>&1; then \
		echo "✅ kubectl:        connected ($$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ') nodes ready)"; \
	else \
		echo "❌ kubectl:        cannot reach cluster — token may be expired, run 'aws sso login' or check your kubeconfig"; \
	fi

.PHONY: urls
urls:
	@echo "Cluster: https://$(AWS_REGION).console.aws.amazon.com/eks/home?region=$(AWS_REGION)#/clusters/$(DEPLOYMENT_NAME)"

.PHONY: ingress-nginx
ingress-nginx:
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
	helm repo update ingress-nginx
	helm search repo ingress-nginx
	helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace --wait

.PHONY: check-aws-cli
check-aws-cli:
	@echo "Checking AWS authentication..."
	@aws sts get-caller-identity --query "Arn" --output text > /dev/null 2>&1 || \
		(echo "❌ Error: AWS token is expired or missing. Run 'aws sso login' or refresh your credentials." && exit 1)
	@echo "✅ AWS session is valid: $$(aws sts get-caller-identity --query 'Arn' --output text)"

.PHONY: scale-to-zero
scale-down: check-aws-cli
	@echo "Scaling all node groups in cluster $(DEPLOYMENT_NAME) to 0..."
	@for ng in $$(eksctl get nodegroup --cluster $(DEPLOYMENT_NAME) --region $(AWS_REGION) -o json | grep -o '"Name":"[^"]*"' | cut -d'"' -f4); do \
		echo "Scaling node group $$ng to 0..."; \
		eksctl scale nodegroup --cluster $(DEPLOYMENT_NAME) --region $(AWS_REGION) --name $$ng --nodes 0 --nodes-min 0; \
	done
	@echo "✅ All node groups scaled to 0."

.PHONY: scale-up-nodegroup
scale-up-nodegroup: check-aws-cli
	@echo "Scaling node group $(NODEGROUP_NAME) in cluster $(DEPLOYMENT_NAME) to $(SCALE_SIZE) (min=$(SCALE_MIN), max=$(SCALE_MAX))..."
	eksctl scale nodegroup --cluster $(DEPLOYMENT_NAME) --region $(AWS_REGION) --name $(NODEGROUP_NAME) --nodes $(SCALE_SIZE) --nodes-min $(SCALE_MIN) --nodes-max $(SCALE_MAX)
	@echo "✅ Node group $(NODEGROUP_NAME) scaled to $(SCALE_SIZE)."

.PHONY: scale-up
scale-up:
	$(MAKE) scale-up-nodegroup NODEGROUP_NAME=$(NODEGROUP_NAME) SCALE_SIZE=$(DESIRED_SIZE)

.PHONY: ingress-aws-ip-from-service
ingress-aws-ip-from-service:
	@echo "Waiting for ingress-nginx-controller LoadBalancer hostname..."
	@ELB_HOSTNAME=""; \
	while [ -z "$$ELB_HOSTNAME" ]; do \
		ELB_HOSTNAME=$$(kubectl get service ingress-nginx-controller -n ingress-nginx \
			--output jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
		[ -z "$$ELB_HOSTNAME" ] && echo "Still waiting..." && sleep 5; \
	done; \
	echo "ELB Hostname: $$ELB_HOSTNAME"; \
	IP=$$(dig +short $$ELB_HOSTNAME | head -1); \
	echo "ELB IP: $$IP"

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