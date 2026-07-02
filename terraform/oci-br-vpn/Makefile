NAMESPACE   ?= $(shell oci os ns get --query 'data' --raw-output 2>/dev/null)
BUCKET      = terraform-state
STATE_KEY   = oci-br-vpn/terraform.tfstate
STATE_FILE  = terraform.tfstate

.PHONY: pull-state push-state plan apply destroy

pull-state:
	@echo "==> Pulling state from OCI Object Storage..."
	@oci os object get \
		--namespace $(NAMESPACE) \
		--bucket-name $(BUCKET) \
		--name $(STATE_KEY) \
		--file $(STATE_FILE) 2>/dev/null && echo "==> State pulled." || echo "==> No remote state found, starting fresh."

push-state:
	@echo "==> Pushing state to OCI Object Storage..."
	@oci os object put \
		--namespace $(NAMESPACE) \
		--bucket-name $(BUCKET) \
		--name $(STATE_KEY) \
		--file $(STATE_FILE) \
		--force
	@echo "==> State pushed."

plan: pull-state
	terraform plan

apply: pull-state
	terraform apply
	@$(MAKE) push-state

destroy: pull-state
	terraform destroy
	@$(MAKE) push-state
