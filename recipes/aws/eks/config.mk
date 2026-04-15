# Theses are the default values used by this recipe
# Create a config.mk file in the root directory of this project to override variables for your specific environment

DEPLOYMENT_NAME ?= mydeployment

# Cloud environment and K8s cluster
AWS_REGION ?= ca-central-1
AWS_ZONES ?= ['ca-central-1a', 'ca-central-1b']

# Route 53 hosted zone name for the domain used by HOST_NAME (override in root config.mk)
HOSTED_ZONE_NAME ?= example.com

AWS_MACHINE_TYPE ?= c6i.4xlarge
CLUSTER_VERSION ?= 1.34
VOLUME_SIZE ?= 100

DESIRED_SIZE ?= 3
MIN_SIZE ?= 1
MAX_SIZE ?= 6

