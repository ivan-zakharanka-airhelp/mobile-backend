╔══════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                        MOBILE-BACKEND — FULL SYSTEM FLOW                             ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════╝

 ┌─[ 1. YOU TYPE A COMMAND ]─────────────────────────────────────────────────────────────────────────┐
 │                                                                                                     │
 │    make setup         make up          make k8s-setup         make k8s              make deploy    │
 │  first-time install  Docker Compose    create k3d cluster   Skaffold dev loop    prod → Hetzner    │
 │    (one time)       + NestJS watch       (one time)         (k3d K8s)                              │
 │                                                                                                     │
 └────────┬──────────────────┬───────────────────┬────────────────────┬─────────────────────┬─────────┘
          │                  │                   │                    │                     │
          ▼                  ▼                   ▼                    ▼                     ▼
 ┌─[ 2. ENTRY FILE: Makefile ]─────────────────────────────────────────────────────────────────────────┐
 │                                                                                                     │
 │  Every make target maps to:  npm run <script> -w <workspace>  OR  docker compose / skaffold / bash  │
 │                                                                                                     │
 └────────┬──────────────────┬───────────────────┬────────────────────┬─────────────────────┬─────────┘
          │                  │                   │                    │                     │
          ▼                  ▼                   ▼                    ▼                     ▼
 ┌─[ 3. MONOREPO: npm workspaces ]─────────────────────────────────────────────────────────────────────┐
 │                                                                                                     │
 │    package.json  (root)                       "workspaces": ["apps/*", "packages/*"]                │
 │    └──────────┬─────────────────────────────────────────────────────────────┐                       │
 │               │                                                             │                       │
 │  ┌────────────▼──────────────────┐          ┌───────────────────────────────▼─────────────────┐    │
 │  │ packages/database/            │◄─────────│ apps/auth-api/                                  │    │
 │  │ (@mobile-backend/database)    │  depends │ (@mobile-backend/auth-api)                      │    │
 │  │                               │   via    │                                                 │    │
 │  │  prisma/schema/base.prisma    │  package │  src/main.ts       ← entry: NestFactory.create │    │
 │  │   └─ DB connection config     │  .json   │       │                                         │    │
 │  │                               │          │       ▼                                         │    │
 │  │  src/prisma.service.ts        │          │  src/app.module.ts                              │    │
 │  │   └─ PrismaClient + lifecycle │          │       ├─ imports PrismaModule ──────────────────┤    │
 │  │                               │          │       └─ imports HealthModule                   │    │
 │  │  src/prisma.module.ts         │          │                                                 │    │
 │  │   └─ @Global() NestJS module  │          │  src/health/                                    │    │
 │  │                               │          │   ├─ health.module.ts (imports TerminusModule) │    │
 │  │  src/index.ts                 │          │   └─ health.controller.ts                       │    │
 │  │   └─ exports PrismaModule,    │          │      ├─ GET /health       (liveness)            │    │
 │  │      PrismaService            │          │      └─ GET /health/ready (DB ping via Prisma) │    │
 │  └───────────────────────────────┘          └─────────────────────────────────────────────────┘    │
 │                                                                                                     │
 └────────┬──────────────────┬─────────────────────────────────┬────────────────────┬─────────────────┘
          │                  │                                 │                    │
  make up │                  │ make k8s                        │                    │ make deploy
          │                  │                                 │                    │
          ▼                  ▼                                 ▼                    ▼
 ┌─[ 4. LOCAL DEV ]────┐ ┌─[ 5. BUILD ARTIFACTS ]───────────────┐              ┌─[ 6. CI/CD ]──────────┐
 │                     │ │                                       │              │                       │
 │ docker-compose.yaml │ │ TypeScript: tsc + nest build          │              │ .github/workflows/    │
 │  └─ Postgres :5433  │ │  └─ packages/database/dist/           │              │  ├─ ci.yaml  (on PR)  │
 │                     │ │  └─ apps/auth-api/dist/               │              │  └─ deploy.yaml       │
 │ NestJS on host      │ │                                       │              │     (on merge→main)   │
 │  reads .env from    │ │ Prisma: prisma generate               │              │                       │
 │   apps/auth-api/.env│ │  └─ node_modules/.prisma/client/      │              │ GitHub Actions:       │
 │                     │ │                                       │              │  → docker build       │
 │ Prisma CLI reads    │ │ Docker: apps/auth-api/Dockerfile      │              │  → docker push ghcr   │
 │  packages/database/ │ │  (context = repo root, workspace-     │              │  → SSH kubectl apply  │
 │  .env               │ │   aware multi-stage)                  │              │     to Hetzner k3s    │
 │                     │ │  └─ image: auth-api:latest            │              │                       │
 └─────────────────────┘ └───────────────────┬───────────────────┘              └───────────┬───────────┘
                                             │                                              │
                                             ▼                                              ▼
 ┌─[ 7. SKAFFOLD ORCHESTRATES ]──────────────────────────────────────────────────────────────────────┐
 │                                                                                                    │
 │   skaffold.yaml                                                                                    │
 │     build: { local.useBuildkit: false }     ← avoids Colima/buildx issues                          │
 │     build.artifacts: Dockerfile above       ← produces image                                       │
 │     manifests.kustomize.paths:                                                                     │
 │        └─ infra/k8s/overlays/local  ──────────────────────────────────────────┐                   │
 │     deploy.kubectl: {}                      ← "use kubectl to apply"           │                   │
 │     portForward: auth-api-service → :3000   ← tunnel for localhost:3000        │                   │
 │                                                                                │                   │
 └────────────────────────────────────────────────────────────────────────────────┼───────────────────┘
                                                                                  │
                                                                                  ▼
 ┌─[ 8. KUSTOMIZE: base + overlay ]──────────────────────────────────────────────────────────────────┐
 │                                                                                                    │
 │   overlays/local/kustomization.yaml                          base/kustomization.yaml              │
 │    resources:                                                 resources:                           │
 │     - ../../base  ──────────────────────────────────────►      - namespace.yaml    (Namespace)   │
 │     - secrets.yaml (DATABASE_URL for k3d)                      - auth-api-deployment.yaml (Depl.) │
 │    patches:                                                    - auth-api-service.yaml   (Service)│
 │     - ingress-patch.yaml  (web entrypoint, no Host)            - ingress.yaml  (Middlewares +    │
 │     - remove /spec/tls  (no Let's Encrypt in k3d)                                IngressRoute)    │
 │                                                                                                    │
 │   Production deploy reads base/ directly → TLS + Host(`api.yourapp.com`) + websecure kept intact  │
 │                                                                                                    │
 └───────────────────────────────────────────────────┬────────────────────────────────────────────────┘
                                                     │
                                                     ▼
 ┌─[ 9. KUBERNETES RESOURCES (applied in dependency order) ]─────────────────────────────────────────┐
 │                                                                                                    │
 │   ①  Namespace: mobile-backend                    ← isolated "room" for all resources              │
 │           │                                                                                        │
 │           ▼                                                                                        │
 │   ②  Secret: db-credentials                       ← DATABASE_URL sits in etcd                      │
 │           │                                                                                        │
 │           ▼                                                                                        │
 │   ③  Deployment: auth-api (replicas: 1) ────► ReplicaSet ────► Pod                                │
 │           │                          env: DATABASE_URL ← Secret/db-credentials.url                 │
 │           │                          container: auth-api:latest (the built image)                  │
 │           │                          livenessProbe:  GET /health       every 15s                   │
 │           │                          readinessProbe: GET /health/ready every 10s                   │
 │           │                          resources: 128Mi-384Mi, 100m-500m CPU                         │
 │           │                                                                                        │
 │           ▼                                                                                        │
 │   ④  Service: auth-api-service      ← stable DNS, selects pods with label app=auth-api            │
 │           │                                                                                        │
 │           ▼                                                                                        │
 │   ⑤  Middlewares (Traefik CRDs):    rate-limit │ rate-limit-auth │ security-headers │ api-strip   │
 │           │                                                                                        │
 │           ▼                                                                                        │
 │   ⑥  IngressRoute: api-gateway      ← routes /api/* to auth-api-service via middlewares           │
 │                                                                                                    │
 └───────────────────────────────────────────────────┬────────────────────────────────────────────────┘
                                                     │
                                                     ▼
 ┌─[ 10. REQUEST FLOW (runtime) ]────────────────────────────────────────────────────────────────────┐
 │                                                                                                    │
 │   Browser: http://localhost:8080/api/health                                                        │
 │        │                                                                                           │
 │        ▼                                                                                           │
 │   k3d proxy container (Docker port map 8080 → 80)                                                  │
 │        │                                                                                           │
 │        ▼                                                                                           │
 │   Traefik (in kube-system, listens on :80 = "web" entryPoint)                                      │
 │        │                                                                                           │
 │        ▼                                                                                           │
 │   IngressRoute match: PathPrefix(`/api`)                                                           │
 │        │                                                                                           │
 │        ▼                                                                                           │
 │   Pipeline: rate-limit → security-headers → api-strip (/api/health → /health)                     │
 │        │                                                                                           │
 │        ▼                                                                                           │
 │   Service auth-api-service:3000  ──► load-balances to matching pods                               │
 │        │                                                                                           │
 │        ▼                                                                                           │
 │   Pod (container: auth-api)                                                                        │
 │        │                                                                                           │
 │        ▼                                                                                           │
 │   NestJS: HealthController.liveness() → {"status":"ok"}                                           │
 │                                                                                                    │
 │   ─────────────────────────────────────────────────────────────────────────────────────────────   │
 │                                                                                                    │
 │   Alternative path: http://localhost:3000/health                                                   │
 │        │                                                                                           │
 │        └──► Skaffold port-forward tunnel ──► Service ──► Pod  (bypasses Traefik)                  │
 │                                                                                                    │
 └────────────────────────────────────────────────────────────────────────────────────────────────────┘


 ╔══════════════════════════════════════════════════════════════════════════════════════════════════╗
 ║  FILE RESPONSIBILITY CHEAT-SHEET                                                                  ║
 ╠══════════════════════════════════════════════════════════════════════════════════════════════════╣
 ║  Makefile                  → developer-facing command aliases                                     ║
 ║  package.json (root)       → declares workspace layout                                            ║
 ║  packages/database/*       → shared Prisma client, reusable NestJS module                         ║
 ║  apps/auth-api/src/*       → the actual service code (health check only for now)                  ║
 ║  apps/auth-api/Dockerfile  → multi-stage container build (uses repo root as context)              ║
 ║  infra/docker/*            → local Postgres via Docker Compose (DX convenience)                   ║
 ║  infra/k8s/base/*          → production-accurate K8s manifests (TLS, Host, websecure)             ║
 ║  infra/k8s/overlays/local/ → k3d-specific patches (web entryPoint, no TLS, local secrets)         ║
 ║  skaffold.yaml             → build + kustomize + deploy + port-forward loop                       ║
 ║  .github/workflows/*       → CI (PR) + deploy (main→Hetzner)                                      ║
 ║  .env.example files        → document required env vars (per package that needs them)             ║
 ╚══════════════════════════════════════════════════════════════════════════════════════════════════╝