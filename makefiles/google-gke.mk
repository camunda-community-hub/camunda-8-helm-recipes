.PHONY: clean-files
clean-files:
	rm -f .disks
	rm -f camunda-values.yaml

ifeq ($(GCP_USE_SPOT),true)
  SPOT_FLAG := --spot
else
  SPOT_FLAG :=
endif

.PHONY: kube-gke
kube-gke:
	@echo "Creating GKE cluster '$(DEPLOYMENT_NAME)' (spot=$(GCP_USE_SPOT), machine=$(GCP_MACHINE_TYPE), min=$(MIN_SIZE), max=$(MAX_SIZE))"
	gcloud config set project $(GCP_PROJECT)
	gcloud container clusters create $(DEPLOYMENT_NAME) \
	  --region $(GCP_REGION) \
	  --num-nodes=1 \
	  --enable-autoscaling --min-nodes=$(MIN_SIZE) --max-nodes=$(MAX_SIZE) \
	  --enable-ip-alias \
	  --machine-type=$(GCP_MACHINE_TYPE) \
	  --disk-type "pd-ssd" \
	  $(SPOT_FLAG) \
	  --maintenance-window=4:00 \
	  --release-channel=regular \
	  --cluster-version=latest
	gcloud container clusters list
	# kubectl apply -f $(root)/google/include/ssd-storageclass-gke.yaml
	gcloud config set project $(GCP_PROJECT)
	gcloud container clusters get-credentials $(DEPLOYMENT_NAME) --region $(GCP_REGION)

.PHONY: ssd-storageclass
ssd-storageclass:
	kubectl apply -f $(root)/recipes/google/include/ssd-storageclass-gke.yaml

.PHONY: kube
kube: kube-gke

.PHONY: node-pool # create an additional Kubernetes node pool
node-pool:
	gcloud beta container node-pools create "pool-c3-standard-8" \
	  --project $(GCP_PROJECT) \
	  --cluster $(DEPLOYMENT_NAME) \
	  --region $(GCP_REGION) \
	  --machine-type "c3-standard-8" \
	  --disk-type "pd-ssd" \
	  --spot \
	  --num-nodes=0 \
	  --enable-autoscaling --total-min-nodes "0" --total-max-nodes "64" --location-policy "ANY" \
	  --node-taints dedicated=high-performance:PreferNoSchedule
	  --enable-autoupgrade \
	  --enable-autorepair \
	  --max-surge-upgrade 0 --max-unavailable-upgrade 1
#	  --node-version "1.27.3-gke.1700" \
#	  --image-type "COS_CONTAINERD" \
#	  --disk-size "100" \
#	  --metadata disable-legacy-endpoints=true \
#	  --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \

# original command suggested by Web Console:
# gcloud beta container --project "camunda-researchanddevelopment" node-pools create "pool-c3-standard-8" --cluster "falko-benchmark-16" --zone "europe-west1-b" --node-version "1.27.3-gke.1700" --machine-type "c3-standard-8" --image-type "COS_CONTAINERD" --disk-type "pd-ssd" --disk-size "100" --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" --spot --enable-autoscaling --total-min-nodes "0" --total-max-nodes "64" --location-policy "ANY" --enable-autoupgrade --enable-autorepair --max-surge-upgrade 0 --max-unavailable-upgrade 1

STANDARD_POOL_NAME ?= pool-standard
STANDARD_POOL_MIN_NODES ?= 1
STANDARD_POOL_MAX_NODES ?= 6

# Step 1: create a standard (non-spot) node pool with autoscaling
.PHONY: node-pool-standard
node-pool-standard:
	gcloud container node-pools create "$(STANDARD_POOL_NAME)" \
	  --project $(GCP_PROJECT) \
	  --cluster $(DEPLOYMENT_NAME) \
	  --region $(GCP_REGION) \
	  --machine-type $(GCP_MACHINE_TYPE) \
	  --disk-type "pd-ssd" \
	  --num-nodes=1 \
	  --enable-autoscaling --min-nodes=$(STANDARD_POOL_MIN_NODES) --max-nodes=$(STANDARD_POOL_MAX_NODES) \
	  --enable-autoupgrade \
	  --enable-autorepair

# Step 2: cordon all spot nodes so no new pods are scheduled onto them
.PHONY: cordon-spot-nodes
cordon-spot-nodes:
	kubectl get nodes -l cloud.google.com/gke-spot=true -o name | xargs kubectl cordon

# Step 3: drain spot nodes, migrating all pods to the standard pool
.PHONY: drain-spot-nodes
drain-spot-nodes:
	kubectl get nodes -l cloud.google.com/gke-spot=true -o name | \
	  xargs -I{} kubectl drain {} --ignore-daemonsets --delete-emptydir-data

# Run steps 1-3 in sequence to fully migrate to the standard node pool
.PHONY: migrate-to-standard-pool
migrate-to-standard-pool: node-pool-standard cordon-spot-nodes drain-spot-nodes
	@echo "Migration complete. All pods are now running on standard (non-spot) nodes."
	@echo "Run 'kubectl get nodes' and 'kubectl get pods -o wide' to verify."

# Tear down the standard pool and restore spot nodes (run after demo)
.PHONY: restore-spot-pool
restore-spot-pool:
	kubectl get nodes -l cloud.google.com/gke-spot=true -o name | xargs kubectl uncordon
	gcloud container node-pools delete "$(STANDARD_POOL_NAME)" \
	  --project $(GCP_PROJECT) \
	  --cluster $(DEPLOYMENT_NAME) \
	  --region $(GCP_REGION) \
	  --quiet

.PHONY: clean-kube-gke
clean-kube-gke:
#	-kubectl delete pvc --all
	@echo "Please check the console if all PVCs have been deleted: https://console.cloud.google.com/compute/disks?authuser=0&project=$(GCP_PROJECT)&supportedpurview=project"
	gcloud container clusters delete $(DEPLOYMENT_NAME) --region $(GCP_REGION) --async --quiet
	gcloud container clusters list

.PHONY: clean-kube
clean-kube: clean-kube-gke

.PHONY: use-kube
use-kube:
	gcloud config set project $(GCP_PROJECT)
	gcloud container clusters get-credentials $(DEPLOYMENT_NAME) --region $(GCP_REGION)

.PHONY: connect-gke
connect-gke:
	@echo "--- Connecting to GKE ---"
	@gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q "@" || \
		(echo "GCP session expired. Re-authenticating..." && gcloud auth login)
	gcloud config set project $(GCP_PROJECT)
	gcloud container clusters get-credentials $(DEPLOYMENT_NAME) --region $(GCP_REGION)
	@echo ""
	@echo "✅ Active cloud:  GCP (Google Cloud)"
	@echo "   Project:       $$(gcloud config get-value project 2>/dev/null)"
	@echo "   Account:       $$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null)"
	@echo "   Cluster:       $(DEPLOYMENT_NAME) [$(GCP_REGION)]"
	@echo "   kubectl ctx:   $$(kubectl config current-context 2>/dev/null)"

.PHONY: urls
urls:
	@echo "Cluster: https://console.cloud.google.com/kubernetes/clusters/details/$(GCP_REGION)/$(DEPLOYMENT_NAME)/details?project=$(GCP_PROJECT)"
	@echo "Workloads: https://console.cloud.google.com/kubernetes/workload_/gcloud/$(GCP_REGION)/$(DEPLOYMENT_NAME)?project=$(project)"

# List pvcs associated with the cluster
.PHONY: disks
disks:
	gcloud compute disks list --filter="zone ~ $(GCP_REGION) AND users ~ $(DEPLOYMENT_NAME) AND name ~ pvc"

.PHONY: ingress-nginx
ingress-nginx:
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
	helm repo update ingress-nginx
	helm search repo ingress-nginx
	helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace --wait


