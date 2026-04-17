# Mobile backend

A learning project that implements a production-grade authentication service using the same infrastructure patterns used in larger multi-service platforms, but at smaller scale. Runs on a single AWS EC2 instance with k3s (lightweight Kubernetes).

**Learning goals:** practice full Kubernetes deployment lifecycle, CI/CD pipelines, Traefik ingress with TLS, and kustomize overlays — exercised against a realistic application (auth with JWT, refresh token rotation, OAuth).
Generic backend for a React Native + Expo mobile app. npm workspaces monorepo with NestJS services, deployed to k3s on Hetzner.

See [Architecture.md](Architecture.md) for the full design document.

## Stack

- **Runtime:** Node.js 22 + TypeScript 5.x + NestJS 11
- **Data:** PostgreSQL 16 + Prisma 6
- **Infra:** Docker, k3s (prod on EC2), k3d (local K8s), Skaffold, kustomize
- **CI/CD:** GitHub Actions → GHCR → SSH deploy to k3s

## Prerequisites

- Node.js 22 (see `.nvmrc`)
- Docker and Docker Compose (Docker Desktop or Colima on macOS)
- kubectl (for K8s deployment)
- k3d (optional, for local K8s testing)
- Skaffold (optional, for K8s dev loop)

## Quick Start

```bash
# First-time setup (installs deps, starts Postgres, runs migrations)
make setup

# Daily development (starts Postgres + auth-api in watch mode)
make up

# Stop everything
make down
```

The auth API will be available at `http://localhost:3000`. Health check: `http://localhost:3000/health`.

## Available Commands

Run `make help` to see all commands:

| Command | Description |
|---|---|
| `make setup` | First-time project setup (one command) |
| `make install` | Install deps + generate Prisma + build database package |
| `make up` | Start Postgres + auth-api dev server |
| `make down` | Stop local services |
| `make build` | Build all packages and apps |
| `make db-migrate` | Run Prisma migrations |
| `make db-studio` | Open Prisma Studio |
| `make lint` | Lint code |
| `make test` | Run unit tests |
| `make test-e2e` | Run e2e tests |
| `make k8s-setup` | Create local k3d cluster |
| `make k8s` | Start Skaffold dev loop |
| `make deploy` | Build, push, deploy to production |

## Project Structure

```
apps/
  auth-api/          - Authentication service (NestJS)
packages/
  database/          - Shared Prisma schema, client, and NestJS module
infra/
  docker/            - Docker Compose for local Postgres
  k8s/
    base/            - Production-accurate K8s manifests
    overlays/local/  - k3d-specific patches for local dev
  scripts/           - k3s/k3d setup scripts
.github/workflows/   - CI/CD pipelines
```

### Adding a new service

1. Create `apps/<service-name>/` with a new NestJS app
2. Add the database package to its `package.json` dependencies
3. Import `PrismaModule` from the database package in the app module
4. Add Prisma models to `packages/database/prisma/schema/<domain>.prisma`
5. Create K8s manifests in `infra/k8s/base/` and a Skaffold artifact for the new service

## Local Development

By default, local development uses **Docker Compose** for Postgres while NestJS runs directly on the host. This gives the fastest feedback loop — file changes trigger instant reloads without rebuilding containers.

```bash
make setup   # one-time
make up      # daily: Postgres (Docker Compose) + NestJS watch mode
```

If you want the full Kubernetes experience locally (test manifests, ingress routing, probes, resource limits), use **k3d** + **Skaffold** instead:

```bash
make k8s-setup   # one-time: creates a local k3d cluster
make k8s         # builds Docker image, deploys to k3d, port-forwards to localhost:3000
```

k3d runs k3s inside Docker, so the app behaves in local dev the same way it does in production — same Traefik ingress, same health probes, same resource constraints. macOS can't run k3s directly (k3s is Linux-only), so k3d creates Docker containers that act as Linux nodes and runs k3s inside them. Docker Desktop or Colima provides the container runtime.

**Port conflicts:** If you already have Postgres running on port 5433, stop it before running `make up`, or change the port in `infra/docker/docker-compose.yaml`.

## Deployment

Production runs on an AWS EC2 instance (~$12/mo for a `t4g.small`) with k3s installed. Postgres runs either on AWS RDS (~$13/mo) or self-hosted on the same EC2 instance to reduce cost.

See `infra/scripts/setup-k3s.sh` for initial server setup.

```bash
make deploy
```

Or merge to `main` to trigger the GitHub Actions deploy workflow.
