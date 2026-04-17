.DEFAULT_GOAL := help
.PHONY: help setup install up down db-up db-migrate db-studio build lint test test-e2e \
        k8s-setup k8s deploy \
        aws-up aws-bootstrap aws-down aws-status aws-ssh aws-deploy aws-cleanup-manual

# ── First-time setup ──

setup: install db-up db-migrate  ## First-time project setup (one command)

install:                         ## Install all workspace deps + generate Prisma + build database package
	npm install
	npm run generate -w @mobile-backend/database
	npm run build -w @mobile-backend/database

# ── Local development (no K8s, fastest feedback loop) ──

up: db-up                        ## Start Postgres + NestJS in watch mode
	npm run start:dev -w @mobile-backend/auth-api

down:                            ## Stop local services
	docker compose -f infra/docker/docker-compose.yaml down

db-up:                           ## Start Postgres container
	docker compose -f infra/docker/docker-compose.yaml up -d

db-migrate:                      ## Run Prisma migrations
	npm run migrate -w @mobile-backend/database

db-studio:                       ## Open Prisma Studio (DB GUI)
	npm run studio -w @mobile-backend/database

# ── Build ──

build:                           ## Build all packages and apps
	npm run build -w @mobile-backend/database
	npm run build -w @mobile-backend/auth-api

# ── K8s local development (test K8s behavior on MacBook) ──

k8s-setup:                       ## Create k3d cluster (one-time)
	bash infra/scripts/setup-k3d.sh

k8s:                             ## Start Skaffold dev loop against local k3d
	skaffold dev --port-forward

# ── AWS infrastructure (Terraform + cloud-init + k8s bootstrap) ──

aws-cleanup-manual:              ## ONE-TIME — delete resources created before Terraform was in place.
	bash infra/scripts/cleanup-manual-resources.sh

aws-up:                          ## Provision AWS (Terraform) + bootstrap k8s. AWS_PROFILE required.
	cd infra/terraform && terraform init -upgrade && terraform apply -auto-approve
	bash infra/scripts/aws-bootstrap.sh

aws-bootstrap:                   ## Re-run K8s bootstrap only (idempotent). Useful after ingress/secret changes.
	bash infra/scripts/aws-bootstrap.sh

aws-down:                        ## Destroy everything (AWS + local kubeconfig). Prompts for confirmation.
	bash infra/scripts/aws-teardown.sh

aws-status:                      ## Show Terraform outputs + pod status.
	@cd infra/terraform && terraform output 2>/dev/null || echo "No Terraform state — nothing provisioned"
	@echo ""
	@kubectl --context aws-k3s get pods -n mobile-backend 2>/dev/null || echo "Cluster not reachable"

aws-ssh:                         ## SSH to the current EC2 instance.
	ssh -i ~/.ssh/aws_learning_ed25519 ubuntu@$$(cd infra/terraform && terraform output -raw public_ip)

aws-deploy:                      ## Build + push image + rollout on AWS k3s (manual deploy).
	$(eval IMAGE := ghcr.io/ivan-zakharanka-airhelp/mobile-backend/auth-api:manual-$(shell date +%Y%m%d-%H%M%S))
	docker build --platform linux/arm64 -t $(IMAGE) -f apps/auth-api/Dockerfile .
	docker push $(IMAGE)
	kubectl --context aws-k3s set image -n mobile-backend deployment/auth-api auth-api=$(IMAGE)
	kubectl --context aws-k3s rollout status -n mobile-backend deployment/auth-api --timeout=120s

# ── Legacy Skaffold deploy target (kept for reference) ──

deploy:                          ## Build, push, deploy via Skaffold (alternative to make aws-deploy).
	skaffold run --default-repo ghcr.io/ivan-zakharanka-airhelp

# ── Quality ──

lint:                            ## Lint all code
	npm run lint -w @mobile-backend/auth-api

test:                            ## Run unit tests
	npm test -w @mobile-backend/auth-api

test-e2e:                        ## Run e2e tests
	npm run test:e2e -w @mobile-backend/auth-api

# ── Help ──

help:                            ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'
