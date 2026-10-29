# HIPAA-style AWS reference build. Run from WSL2 Ubuntu.
TF := terraform -chdir=terraform

.PHONY: help init plan up data upload invoke verify scan down test check

help:
	@grep -E '^[a-z]+:.*## ' Makefile | sed 's/:.*## /\t/'

init: ## Download providers
	$(TF) init

plan: ## Show what would be created (no changes)
	$(TF) plan -out=tfplan

up: ## Create the environment (asks for confirmation)
	$(TF) apply

data: ## Generate synthetic patients with Synthea (Docker)
	./data/generate.sh

upload: ## Upload synthetic records as the ingest role
	./scripts/upload.sh

invoke: ## Run the app: read records inside the VPC, print aggregates
	aws lambda invoke --function-name $$($(TF) output -raw app_function_name) \
	  --cli-binary-format raw-in-base64-out --payload '{}' /dev/stdout

verify: ## Prove each control works; saves evidence/verify-*.txt
	./scripts/verify.sh

scan: ## Prowler: CIS + HIPAA checks; reports to evidence/prowler/
	mkdir -p evidence/prowler
	docker run --rm -v $(HOME)/.aws:/home/prowler/.aws:ro -v $(CURDIR)/evidence/prowler:/home/prowler/output \
	  prowlercloud/prowler:latest aws -f $$($(TF) output -raw region) \
	  --compliance hipaa_aws --output-formats csv html -o /home/prowler/output

down: ## Delete everything this project created
	$(TF) destroy

test: ## Unit tests for the Lambda (no AWS)
	python3 -m unittest discover -s tests -v

check: ## Format + validate + checkov (no AWS)
	$(TF) fmt -check -recursive
	$(TF) init -backend=false -input=false >/dev/null
	$(TF) validate
	checkov -d terraform --framework terraform --quiet --compact
