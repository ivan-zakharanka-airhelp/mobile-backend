.DEFAULT_GOAL := help
.PHONY: help setup install up down db-up db-migrate db-studio build lint test test-e2e k8s-setup k8s deploy

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

# ── Production ──

deploy:                          ## Build, push, deploy to Hetzner k3s
	skaffold run --default-repo ghcr.io/your-org

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
