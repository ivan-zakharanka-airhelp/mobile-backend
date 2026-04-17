# Authentication Service — Architecture & Infrastructure Plan

## Overview

A learning project that implements a production-grade authentication service using the same infrastructure patterns as a real multi-service platform, but at smaller scale. The service runs on a single AWS EC2 instance with **k3s** (lightweight, CNCF-certified Kubernetes) instead of a full managed cluster.

**Learning goals:**

1. Exercise the full Kubernetes deployment lifecycle — manifests, probes, ingress, secrets, rolling updates — on a real cluster, not a toy.
2. Build an end-to-end CI/CD pipeline: GitHub Actions → container registry → cluster deploy.
3. Understand how Traefik ingress, Let's Encrypt TLS, middlewares, and rate limiting fit together.
4. Get hands-on with kustomize overlays to keep production and local-dev manifests in sync.
5. Do all of the above with a realistic application concern (authentication with JWT, refresh-token rotation, OAuth) rather than a contrived example.

**Core principle:** pay the complexity cost only when you have the problem, not in anticipation of it. The service starts as a modular monolith with clean boundaries — if later growth demands splitting, the boundaries already exist.

---

## Architecture decisions and rationale

### Modular monolith over microservices (day one)

Auth and UserProfile are tightly coupled — auth creates users, profiles read/update them. With a shared DB, splitting them into separate services means paying the operational cost (network hops, deployment complexity, distributed debugging) with none of the benefits (independent scaling, independent data ownership). Starting as a modular monolith with clean module boundaries means:

- In-process communication (no latency, no serialization overhead)
- Single deployment unit (one Docker image, one pod, one health check)
- Code structured *as if* they're separate services (NestJS modules with explicit public APIs)
- When a module needs independent scaling or separate ownership, extraction is mechanical — the boundaries already exist

### k3s from the start

Reasons:

1. **Learning goal** — build and operate a real cluster end-to-end
2. **Parallels production patterns** used in larger environments (EKS, GKE) while staying runnable on a single VPS
3. **Scales without re-platforming** when traffic or complexity grows — the same manifests work on a multi-node cluster

k3s specifically because:

- Single binary, ~512 MB RAM footprint
- Production-grade (CNCF certified Kubernetes distribution)
- Traefik ingress controller pre-installed
- Runs comfortably on a small EC2 instance (~$12/mo for a `t4g.small`)

### Shared database with schema discipline

One PostgreSQL instance, but each module owns its tables exclusively. No cross-module joins allowed — modules communicate through NestJS service interfaces, not SQL. This makes future DB splitting mechanical: move the tables, update the connection string.

**Schema convention:**

```
auth_users          — owned by AuthModule
auth_refresh_tokens — owned by AuthModule
profile_profiles    — owned by UserProfileModule
profile_preferences — owned by UserProfileModule
```

Prefix tables with the owning module name. Prisma schema is split per module using Prisma's multi-file schema support.

### Monorepo with npm workspaces

All services, shared libraries, infrastructure code, and tooling in one repository. Polyrepo makes sense when separate teams have separate release cadences — not applicable here.

Uses npm workspaces to manage dependencies across packages:

```json
// root package.json
{ "workspaces": ["apps/*", "packages/*"] }
```

Shared code (Prisma schema, database client) lives in `packages/database/`. Each app in `apps/` depends on it via workspace symlinks — no publishing required.

---

## Tech stack

| Layer | Tool | Version | Why |
|---|---|---|---|
| Language | TypeScript | 5.x | Type safety, NestJS native |
| Runtime | Node.js | 22 LTS | Long-term support, stable |
| Framework | NestJS | 11.x | Module system, DI, transport-agnostic, Passport/JWT integration |
| ORM | Prisma | 6.x | Type-safe queries, clean migrations, multi-file schema |
| Database | PostgreSQL | 16 | AWS RDS in production, Docker Compose for local dev |
| Container runtime | Docker | 27.x | Build images for K8s |
| K8s (production) | k3s | latest stable | Lightweight, single-node, Traefik included |
| K8s (local dev) | k3d | latest stable | k3s-in-Docker for MacBook testing |
| Build/deploy bridge | Skaffold | 2.x | Watch → rebuild → redeploy loop |
| Manifest management | kustomize | built-in to kubectl | Base + overlay pattern for environments |
| CI/CD | GitHub Actions | — | Build, test, deploy on merge to main |
| Ingress | Traefik | (bundled with k3s) | TLS, routing, rate limiting, middlewares |
| Auth | @nestjs/passport + @nestjs/jwt | — | OAuth strategies (Google, Apple), JWT issuance |
| Health checks | @nestjs/terminus | — | Liveness + readiness probes for K8s |
| Validation | class-validator + class-transformer | — | DTO validation via decorators |
| Config | @nestjs/config | — | Env-based config with validation |

---

## Repository structure

```
auth-service/
├── package.json                       # npm workspaces root
│
├── packages/
│   └── database/                      # ── Shared database package ──
│       ├── src/
│       │   ├── prisma.service.ts      # PrismaClient wrapper with lifecycle hooks
│       │   ├── prisma.module.ts       # @Global() NestJS module
│       │   └── index.ts              # Re-exports PrismaModule + PrismaService
│       ├── prisma/
│       │   ├── schema/               # Multi-file Prisma schema
│       │   │   ├── base.prisma       # datasource + generator config
│       │   │   ├── auth.prisma       # User, RefreshToken models
│       │   │   └── profile.prisma    # Profile, Preference models
│       │   └── migrations/
│       ├── package.json
│       └── tsconfig.json
│
├── apps/
│   └── auth-api/                      # ── Auth service ──
│       ├── src/
│       │   ├── main.ts               # Bootstrap, listen on :3000
│       │   ├── app.module.ts         # Root module
│       │   │
│       │   ├── auth/                 # ── AuthModule ──
│       │   │   ├── auth.module.ts
│       │   │   ├── auth.controller.ts
│       │   │   ├── auth.service.ts
│       │   │   ├── strategies/
│       │   │   ├── guards/
│       │   │   └── dto/
│       │   │
│       │   ├── user-profile/         # ── UserProfileModule ──
│       │   │   ├── user-profile.module.ts
│       │   │   ├── user-profile.controller.ts
│       │   │   ├── user-profile.service.ts
│       │   │   └── dto/
│       │   │
│       │   ├── health/               # ── HealthModule ──
│       │   │   ├── health.module.ts
│       │   │   └── health.controller.ts
│       │   │
│       │   └── common/               # Shared within auth-api
│       │       ├── decorators/
│       │       ├── filters/
│       │       └── interceptors/
│       │
│       ├── test/
│       ├── Dockerfile                # Workspace-aware multi-stage build
│       ├── .env.example
│       ├── nest-cli.json
│       ├── tsconfig.json
│       └── package.json
│
├── infra/
│   ├── k8s/
│   │   ├── base/                     # Production-accurate manifests
│   │   │   ├── namespace.yaml
│   │   │   ├── auth-api-deployment.yaml
│   │   │   ├── auth-api-service.yaml
│   │   │   ├── ingress.yaml          # Middlewares + IngressRoute (TLS, Host)
│   │   │   └── kustomization.yaml
│   │   ├── overlays/
│   │   │   └── local/                # k3d-specific patches
│   │   │       ├── kustomization.yaml
│   │   │       ├── ingress-patch.yaml  # web entryPoint, no TLS
│   │   │       └── secrets.yaml        # Local DB credentials
│   │   ├── traefik-config.yaml       # HelmChartConfig for k3s Traefik
│   │   └── secrets.yaml.example
│   ├── docker/
│   │   └── docker-compose.yaml       # Local dev: Postgres only
│   └── scripts/
│       ├── setup-k3s.sh              # One-time k3s install on EC2
│       └── setup-k3d.sh              # One-time k3d cluster for local dev
│
├── Makefile                          # All DX commands (uses npm workspace flags)
├── skaffold.yaml                     # Skaffold config for K8s dev loop
├── .github/
│   └── workflows/
│       ├── ci.yaml                   # Lint, test, build on PR
│       └── deploy.yaml               # Build image, push, deploy on merge to main
├── .gitignore
├── .nvmrc                            # Node 22
└── README.md
```

**Adding a new service** (demonstrates monorepo extensibility):

1. Create `apps/<service-name>/` — new NestJS app with its own `package.json`, `Dockerfile`, `tsconfig.json`
2. Add the database package as a dependency in the new app's `package.json`
3. Import `PrismaModule` from the database package in the app module
4. Add Prisma models for the new domain to `packages/database/prisma/schema/<domain>.prisma`
5. Create `infra/k8s/base/<service-name>-deployment.yaml` and `-service.yaml`
6. Add a Skaffold artifact for the new service

---

## DX commands (Makefile)

All commands use npm workspace flags (`-w`) to target specific packages:

```makefile
# ── First-time setup ──
setup: install db-up db-migrate  ## First-time project setup (one command)

install:                         ## Install all workspace deps + generate Prisma + build database package

# ── Local development (no K8s, fastest feedback loop) ──
up: db-up                        ## Start Postgres + NestJS in watch mode
down:                            ## Stop local services
db-up:                           ## Start Postgres container
db-migrate:                      ## Run Prisma migrations
db-studio:                       ## Open Prisma Studio (DB GUI)
build:                           ## Build all packages and apps

# ── K8s local development ──
k8s-setup:                       ## Create k3d cluster (one-time)
k8s:                             ## Start Skaffold dev loop against local k3d

# ── Production ──
deploy:                          ## Build, push, deploy to AWS k3s

# ── Quality ──
lint: test: test-e2e:
```

---

## Infrastructure details

### AWS setup

| Resource | Spec | Cost (approx) |
|---|---|---|
| EC2 instance | `t4g.small` — 2 vCPU, 2 GB RAM (ARM64, Graviton) | ~$12/mo |
| RDS PostgreSQL | `db.t4g.micro` — PG 16, 20 GB | ~$13/mo |
| **Total** | | **~$25/mo** |

Alternatively, self-host Postgres on the same EC2 instance to reduce cost and keep the learning experience more contained. That trades operational simplicity (backups, failover) for cost and learning value.

### k3s installation (one-time, on EC2)

```bash
# infra/scripts/setup-k3s.sh
curl -sfL https://get.k3s.io | sh -s - \
  --disable=servicelb \
  --write-kubeconfig-mode=644

# Copy kubeconfig to local machine for kubectl access
scp ubuntu@<ec2-public-ip>:/etc/rancher/k3s/k3s.yaml ~/.kube/config
# Edit server address in config to point to the EC2 public IP
```

ServiceLB is disabled because on a single-node setup the Traefik ingress uses hostPort (80/443) directly. No need for a load balancer abstraction.

### k3d setup (one-time, on MacBook for local dev)

```bash
# infra/scripts/setup-k3d.sh
k3d cluster create auth-service \
  --port "8080:80@loadbalancer" \
  --port "8443:443@loadbalancer" \
  --agents 0
```

### Traefik configuration

Traefik comes pre-installed with k3s. Customize via HelmChartConfig:

```yaml
# infra/k8s/traefik-config.yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |
    ports:
      web:
        redirectTo:
          port: websecure
      websecure:
        tls:
          enabled: true
    certificatesResolvers:
      letsencrypt:
        acme:
          email: your@email.com
          storage: /data/acme.json
          httpChallenge:
            entryPoint: web
    additionalArguments:
      - "--api.dashboard=false"
      - "--log.level=WARN"
```

### Ingress routing + middlewares

Production (base) IngressRoute uses:
- `entryPoints: [websecure]` — HTTPS only
- `Host('<your-domain>') && PathPrefix('/api')` — matches on domain
- `tls: { certResolver: letsencrypt }` — auto-provisioned TLS cert

Local (overlay) patches:
- `entryPoints: [web]` — plain HTTP on k3d's 8080→80 mapping
- `PathPrefix('/api')` only — no Host check
- `tls` block removed

See `infra/k8s/base/ingress.yaml` and `infra/k8s/overlays/local/` for the full manifests.

### Deployment + Service

```yaml
# infra/k8s/base/auth-api-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-api
  namespace: auth-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: auth-api
  template:
    metadata:
      labels:
        app: auth-api
    spec:
      containers:
        - name: auth-api
          image: auth-api:latest
          ports:
            - containerPort: 3000
          livenessProbe:
            httpGet: { path: /health, port: 3000 }
            initialDelaySeconds: 10
            periodSeconds: 15
          readinessProbe:
            httpGet: { path: /health/ready, port: 3000 }
            initialDelaySeconds: 5
            periodSeconds: 10
          resources:
            requests: { memory: "128Mi", cpu: "100m" }
            limits:   { memory: "384Mi", cpu: "500m" }
          env:
            - name: DATABASE_URL
              valueFrom: { secretKeyRef: { name: db-credentials, key: url } }
            - name: JWT_SECRET
              valueFrom: { secretKeyRef: { name: auth-secrets, key: jwt-secret } }
            - name: JWT_REFRESH_SECRET
              valueFrom: { secretKeyRef: { name: auth-secrets, key: jwt-refresh-secret } }
            - name: GOOGLE_CLIENT_ID
              valueFrom: { secretKeyRef: { name: oauth-secrets, key: google-client-id } }
            - name: GOOGLE_CLIENT_SECRET
              valueFrom: { secretKeyRef: { name: oauth-secrets, key: google-client-secret } }
---
apiVersion: v1
kind: Service
metadata:
  name: auth-api-service
  namespace: auth-service
spec:
  selector:
    app: auth-api
  ports:
    - port: 3000
      targetPort: 3000
```

---

## Auth flow detail

### JWT token lifecycle

```
Access token:  15 min TTL — short-lived, stateless, carries userId + email only
Refresh token: 30 day TTL — opaque (random string), stored server-side in DB
```

Client-side storage strategy is the client's concern — the server only cares about token validity and rotation semantics.

### Endpoints

```
POST   /auth/register          — email + password → creates user + profile, returns tokens
POST   /auth/login             — email + password → returns access + refresh tokens
POST   /auth/refresh           — refresh token → rotates both tokens (old refresh invalidated)
POST   /auth/logout            — invalidates refresh token server-side
GET    /auth/oauth/google      — initiates Google OAuth flow
GET    /auth/oauth/google/callback
GET    /auth/oauth/apple       — initiates Apple Sign In flow
GET    /auth/oauth/apple/callback
```

### Token rotation flow

1. Client sends request with expired access token → gets 401
2. Client sends refresh token to `/auth/refresh`
3. Server validates refresh token exists in DB and is not expired
4. Server deletes old refresh token, creates new refresh + access tokens
5. Server returns both new tokens
6. If refresh token is reused (already deleted), server invalidates ALL refresh tokens for that user (breach detection)

### Account linking (OAuth + email collision)

When a user signs in with an OAuth provider and the email already exists from a previous email/password registration:

1. Server detects email match
2. Server links the OAuth provider to the existing account (adds a row to `auth_oauth_providers`)
3. Server returns tokens for the existing account
4. User's profile remains intact — no duplicate accounts

---

## Database schema (Prisma)

### base.prisma

```prisma
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

generator client {
  provider = "prisma-client-js"
}
```

### auth.prisma

```prisma
model AuthUser {
  id             String              @id @default(uuid()) @db.Uuid
  email          String              @unique
  passwordHash   String?             @map("password_hash")
  emailVerified  Boolean             @default(false) @map("email_verified")
  createdAt      DateTime            @default(now()) @map("created_at")
  updatedAt      DateTime            @updatedAt @map("updated_at")

  refreshTokens  AuthRefreshToken[]
  oauthProviders AuthOAuthProvider[]
  profile        ProfileProfile?

  @@map("auth_users")
}

model AuthRefreshToken {
  id        String   @id @default(uuid()) @db.Uuid
  token     String   @unique
  userId    String   @map("user_id") @db.Uuid
  expiresAt DateTime @map("expires_at")
  createdAt DateTime @default(now()) @map("created_at")

  user AuthUser @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@index([userId])
  @@index([expiresAt])
  @@map("auth_refresh_tokens")
}

model AuthOAuthProvider {
  id          String @id @default(uuid()) @db.Uuid
  userId      String @map("user_id") @db.Uuid
  provider    String // "google" | "apple"
  providerUid String @map("provider_uid")

  user AuthUser @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@unique([provider, providerUid])
  @@index([userId])
  @@map("auth_oauth_providers")
}
```

### profile.prisma

```prisma
model ProfileProfile {
  id          String   @id @default(uuid()) @db.Uuid
  userId      String   @unique @map("user_id") @db.Uuid
  displayName String?  @map("display_name")
  avatarUrl   String?  @map("avatar_url")
  locale      String   @default("en")
  timezone    String   @default("UTC")
  createdAt   DateTime @default(now()) @map("created_at")
  updatedAt   DateTime @updatedAt @map("updated_at")

  user AuthUser @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@map("profile_profiles")
}
```

**Note:** The `ProfileProfile.user` relation references `AuthUser` — this is the one cross-module FK allowed at the DB level because user identity is fundamental. The application code in UserProfileModule does NOT import AuthModule's services directly. Instead, AuthModule exposes a `userId` after authentication, and UserProfileModule uses that ID to query its own tables.

---

## Docker setup

### Dockerfile (apps/auth-api/Dockerfile)

Build context is the repo root (not the app directory) so workspace dependencies resolve correctly. Multi-stage build with separate `build` and `production` stages — the final image contains only compiled JS + production node_modules.

See `apps/auth-api/Dockerfile` for the full source.

### docker-compose.yaml (local dev only)

```yaml
# infra/docker/docker-compose.yaml
services:
  postgres:
    image: postgres:16-alpine
    ports:
      - "5433:5432"
    environment:
      POSTGRES_USER: dev
      POSTGRES_PASSWORD: dev
      POSTGRES_DB: auth_service
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dev"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  pgdata:
```

### Skaffold config

```yaml
# skaffold.yaml
apiVersion: skaffold/v4beta11
kind: Config
metadata:
  name: auth-service
build:
  local:
    useBuildkit: false
  artifacts:
    - image: auth-api
      context: .
      docker:
        dockerfile: apps/auth-api/Dockerfile
manifests:
  kustomize:
    paths:
      - infra/k8s/overlays/local
deploy:
  kubectl: {}
portForward:
  - resourceType: service
    resourceName: auth-api-service
    namespace: auth-service
    port: 3000
    localPort: 3000
```

---

## CI/CD (GitHub Actions)

### CI — on every PR

```yaml
# .github/workflows/ci.yaml
name: CI
on: [pull_request]
jobs:
  check:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: test
        ports: ["5432:5432"]
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
      - run: npm ci
      - run: npm run generate -w @auth-service/database
      - run: npm run build -w @auth-service/database
      - run: npm run lint -w @auth-service/auth-api
      - run: npm run build -w @auth-service/auth-api
      - run: npm run migrate:deploy -w @auth-service/database
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/test
      - run: npm test -w @auth-service/auth-api
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/test
```

### Deploy — on merge to main

```yaml
# .github/workflows/deploy.yaml
name: Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v5
        with:
          context: .
          file: apps/auth-api/Dockerfile
          push: true
          tags: ghcr.io/${{ github.repository }}/auth-api:${{ github.sha }}
      - name: Deploy to k3s on EC2
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ubuntu
          key: ${{ secrets.SERVER_SSH_KEY }}
          script: |
            kubectl set image deployment/auth-api \
              auth-api=ghcr.io/${{ github.repository }}/auth-api:${{ github.sha }} \
              -n auth-service
            kubectl rollout status deployment/auth-api -n auth-service --timeout=120s
```

---

## Learning milestones

### Milestone 1 — Infrastructure end-to-end (local only)

**Goal:** Fully working local setup — Docker Compose, k3d, Skaffold, kustomize overlays.

- Monorepo with npm workspaces
- HealthModule deployable to k3d
- Docker Compose for local dev, k3d + Skaffold for "production-like" local dev
- kustomize base + local overlay working
- Makefile as single entry point for all DX

**Status:** ✅ Done.

### Milestone 2 — Real application code

**Goal:** A realistic service to deploy, not just a health check.

- Prisma auth + profile models, initial migration
- AuthModule — registration, login, bcrypt, JWT issuance
- Refresh token rotation with reuse detection
- UserProfileModule — CRUD with guards
- Google OAuth strategy (testable via browser)
- Apple Sign In strategy (requires Apple Developer setup — optional)
- DTO validation, error middleware, response envelope

### Milestone 3 — Production on AWS

**Goal:** The service running on a real cloud host, reachable from the internet.

- EC2 instance with k3s installed
- RDS Postgres (or self-hosted on the same EC2 for cost)
- Domain pointed at the EC2 IP
- Traefik + Let's Encrypt TLS working
- GitHub Actions deploying on merge to main
- Secrets managed manually (`kubectl apply -f secrets.yaml`, gitignored)

### Milestone 4 — Production hygiene

**Goal:** Learn patterns used in larger systems.

- Helm charts (replace raw manifests) — values per environment
- Sealed Secrets or External Secrets Operator
- Grafana + Loki for logs + basic dashboards
- Horizontal Pod Autoscaler (even with single replica, to learn configuration)
- Staging environment (second namespace or k3d profile)
- Redis for session caching / rate-limit state

### When to split the monolith — concrete signals

Do NOT split preemptively. Split when you observe one of these:

1. **Independent scaling need** — auth endpoint gets 10x more traffic than profile endpoints
2. **Independent deployment need** — profile changes ship daily, auth changes ship weekly with security review
3. **Team boundary** — a second developer/team owns a specific module full-time
4. **Technology divergence** — a module needs a different runtime, language, or database type

---

## API contract overview

All responses follow a consistent envelope:

```json
{
  "data": { ... },
  "meta": { "timestamp": "2026-04-16T12:00:00Z" }
}
```

Error responses:

```json
{
  "error": {
    "code": "AUTH_INVALID_CREDENTIALS",
    "message": "Invalid email or password"
  },
  "meta": { "timestamp": "2026-04-16T12:00:00Z" }
}
```

### Auth endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | /auth/register | No | Register with email + password |
| POST | /auth/login | No | Login, returns access + refresh tokens |
| POST | /auth/refresh | No (refresh token in body) | Rotate tokens |
| POST | /auth/logout | Yes (access token) | Invalidate refresh token |
| GET | /auth/oauth/google | No | Redirect to Google OAuth |
| GET | /auth/oauth/google/callback | No | Google OAuth callback |
| GET | /auth/oauth/apple | No | Redirect to Apple Sign In |
| GET | /auth/oauth/apple/callback | No | Apple Sign In callback |

### UserProfile endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | /users/me | Yes | Get current user's profile |
| PATCH | /users/me | Yes | Update current user's profile |
| GET | /users/:id | Yes | Get another user's public profile |

---

## Environment variables

```bash
# .env.example

# Database
DATABASE_URL=postgresql://dev:dev@localhost:5433/auth_service

# JWT
JWT_SECRET=change-me-in-production
JWT_REFRESH_SECRET=change-me-in-production-too
JWT_ACCESS_TTL=15m
JWT_REFRESH_TTL=30d

# OAuth — Google
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GOOGLE_CALLBACK_URL=https://<your-domain>/api/auth/oauth/google/callback

# OAuth — Apple
APPLE_CLIENT_ID=
APPLE_TEAM_ID=
APPLE_KEY_ID=
APPLE_PRIVATE_KEY_PATH=

# App
PORT=3000
NODE_ENV=development
```

---

## Security checklist

- [ ] Passwords hashed with bcrypt (cost factor 12)
- [ ] Refresh token rotation with reuse detection
- [ ] Rate limiting on auth endpoints (10 req/min per IP via Traefik)
- [ ] Global rate limiting (100 req/s via Traefik)
- [ ] Security headers (HSTS, X-Frame-Options, X-Content-Type-Options)
- [ ] CORS configured (restrict to known origins)
- [ ] Input validation on all DTOs (class-validator)
- [ ] Database credentials in K8s Secrets (not in code)
- [ ] TLS everywhere (Let's Encrypt via Traefik)
- [ ] Access tokens short-lived (15 min)
- [ ] Refresh tokens stored server-side (not JWT — opaque tokens in DB)
- [ ] No sensitive data in JWT payload (only userId and email)
- [ ] Apple Sign In verified server-side (verify identity token)
- [ ] Health endpoints don't expose internal state

---

## Implementation order

When coding this project, follow this sequence:

1. ~~**Scaffold NestJS project + npm workspaces**~~ — ✅ Done.
2. ~~**Set up Prisma**~~ — ✅ Done (base config only). Auth + profile models added in step 5.
3. ~~**PrismaModule**~~ — ✅ Done. `@Global()` module in `packages/database/`.
4. ~~**HealthModule**~~ — ✅ Done.
5. ~~**Dockerize**~~ — ✅ Done.
6. ~~**K8s manifests (base + overlays)**~~ — ✅ Done.
7. ~~**Skaffold + Makefile**~~ — ✅ Done.
8. ~~**GitHub Actions**~~ — ✅ Done.
9. **Prisma auth + profile models** — add `auth.prisma` and `profile.prisma` to `packages/database/prisma/schema/`, run initial migration.
10. **AuthModule — registration + login** — email/password, bcrypt, JWT issuance.
11. **AuthModule — refresh token rotation** — DB-backed refresh tokens, rotation, reuse detection.
12. **Common utilities** — CurrentUser decorator, HttpExceptionFilter, TransformInterceptor.
13. **UserProfileModule** — CRUD endpoints, auto-create profile on registration.
14. **AuthModule — Google OAuth** — Passport Google strategy, account linking.
15. **AuthModule — Apple Sign In** — Passport Apple strategy, account linking (optional — requires Apple Developer account).
16. **AWS setup** — provision EC2, install k3s, provision RDS (or self-host Postgres on EC2), deploy.

Each step should be independently testable before moving to the next.
