.PHONY: help test lint build up down status lag topics urp dlq tail redis \
        chaos-broker chaos-consumer chaos-slow chaos-errors chaos-redis chaos-off \
        policy-test alert-test validate fmt tf-validate plan-offline release clean

ENV ?= dev
TF  := terraform -chdir=infra/gcp/envs/$(ENV)

# Use python3 if a bare `python` isn't on PATH (e.g. Ubuntu / WSL2).
PYTHON := $(shell command -v python 2>/dev/null || command -v python3)
PIP    := $(PYTHON) -m pip

help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# --- app -------------------------------------------------------------------
test: ## Run the app unit tests
	cd app && $(PIP) install -q -r requirements.txt -r requirements-dev.txt && $(PYTHON) -m pytest -q

lint: ## Lint the app
	cd app && $(PYTHON) -m ruff check .

build: ## Build the container image
	docker build --build-arg VERSION=local -t kafka-sre:local app

# --- local platform (kind) ----------------------------------------------------
up: ## Create cluster + monitoring + Kafka + apps + ArgoCD (~10 min first time)
	./scripts/setup.sh

down: ## Delete the kind cluster and stop port-forwards
	./scripts/teardown.sh

status: ## Kafka health, pods, consumer lag, ArgoCD, firing alerts
	./scripts/status.sh

# --- everyday Kafka operations ---------------------------------------------
lag: ## Consumer group offsets and lag per partition
	./scripts/kafka.sh lag

topics: ## Partitions, leaders, replicas, ISR
	./scripts/kafka.sh topics

urp: ## Under-replicated partitions only
	./scripts/kafka.sh urp

dlq: ## Last events on the dead-letter topic (with failure reason)
	./scripts/kafka.sh dlq

tail: ## A few live events from price-updates
	./scripts/kafka.sh tail

redis: ## A few stored prices from Redis
	./scripts/kafka.sh redis

# --- chaos drills --------------------------------------------------------------
chaos-broker: ## Kill one Kafka node -> URP, KafkaBrokerDown, self-healing
	./scripts/chaos.sh broker

chaos-consumer: ## Scale consumers to 0 -> StreamConsumerDown, lag grows
	./scripts/chaos.sh consumer

chaos-slow: ## Slow consumers -> lag, latency > 5 s, freshness SLO burn
	./scripts/chaos.sh slow

chaos-errors: ## 20% processing failures -> DLQ, StreamProcessingErrorsHigh
	./scripts/chaos.sh errors

chaos-redis: ## Stop Redis -> StreamSinkUnavailable, retries without data loss
	./scripts/chaos.sh redis

chaos-off: ## Undo every drill, re-enable GitOps self-heal
	./scripts/chaos.sh off

# --- checks (the same ones CI runs) ---------------------------------------------
policy-test: ## Unit-test the Rego policies
	conftest fmt --check policy && conftest verify --policy policy

alert-test: ## Unit-test alerts, routing and runbook links (promtool, amtool)
	./scripts/test-alerts.sh

validate: ## Render kafka/ and k8s/ and run the policies on them
	kubectl kustomize kafka > /tmp/kafka-sre-rendered-kafka.yaml
	kubectl kustomize k8s > /tmp/kafka-sre-rendered-apps.yaml
	conftest test --policy policy --namespace kafka /tmp/kafka-sre-rendered-kafka.yaml
	conftest test --policy policy --namespace k8s /tmp/kafka-sre-rendered-apps.yaml

# --- GCP track ------------------------------------------------------------------
fmt: ## Format Terraform
	terraform fmt -recursive infra

tf-validate: ## Validate Terraform for $(ENV) (no backend, no credentials)
	$(TF) init -backend=false && $(TF) validate

plan-offline: ## Plan $(ENV) without GCP credentials + run the policy gate
	printf 'terraform {\n  backend "local" {}\n}\n' > infra/gcp/envs/$(ENV)/backend_override.tf
	$(TF) init -input=false -reconfigure
	GOOGLE_OAUTH_ACCESS_TOKEN=offline $(TF) plan -input=false -refresh=false -lock=false \
		-var project_id=offline-project -out=tf.plan
	$(TF) show -json tf.plan > plan.json
	conftest test --policy policy --namespace main plan.json
	rm -f infra/gcp/envs/$(ENV)/backend_override.tf

# --- release --------------------------------------------------------------------
release: ## Tag a release: make release VERSION=0.2.0
	@test -n "$(VERSION)" || (echo "usage: make release VERSION=x.y.z" && exit 1)
	@echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || (echo "VERSION must be x.y.z" && exit 1)
	git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	git push origin "v$(VERSION)"

clean: ## Remove local plan artifacts
	rm -f plan.json /tmp/kafka-sre-rendered-*.yaml
	find infra -name 'tf.plan' -delete
	find infra -name 'backend_override.tf' -delete
	find infra -name 'terraform.tfstate*' -path '*envs*' -delete
