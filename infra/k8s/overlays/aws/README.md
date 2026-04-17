# AWS k3s overlay

Applied against the single-node k3s cluster running on the `ivan-auth-learning` EC2 instance (eu-west-1).

## What's here

- Inherits namespace, Deployment, Service from `base/`
- Skips `base/ingress.yaml` — production ingress needs a real domain + Let's Encrypt TLS, not yet set up
- Rewrites the image name from the `auth-api` placeholder (used by local k3d/Skaffold) to the GHCR path

## Deploy

### CI / automated (on merge to main)

`deploy.yaml` workflow uses `kubectl set image` with the git SHA. It bypasses this kustomization's `newTag` at runtime — that's intentional and fine. No file changes needed in git.

### Manual (for testing or hotfix)

Build + push an image first:

```bash
IMAGE=ghcr.io/ivan-zakharanka-airhelp/mobile-backend/auth-api:manual-N
docker build --platform linux/arm64 -t $IMAGE -f apps/auth-api/Dockerfile .
docker push $IMAGE
```

Then update the overlay and apply. Two options:

**Option 1 — using the `kustomize` CLI (recommended):**

```bash
cd infra/k8s/overlays/aws
kustomize edit set image auth-api=ghcr.io/ivan-zakharanka-airhelp/mobile-backend/auth-api:manual-N
kubectl --context aws-k3s apply -k .
# Commit the change if you want the repo to reflect the manually-deployed state:
git add kustomization.yaml && git commit -m "deploy: bump to manual-N"
```

**Option 2 — imperative (fast path, no git update):**

```bash
kubectl --context aws-k3s set image -n mobile-backend \
  deployment/auth-api \
  auth-api=ghcr.io/ivan-zakharanka-airhelp/mobile-backend/auth-api:manual-N
kubectl --context aws-k3s rollout status -n mobile-backend deployment/auth-api
```

## Verify

```bash
# Pod status
kubectl --context aws-k3s get pods -n mobile-backend

# Currently deployed image
kubectl --context aws-k3s get deployment auth-api -n mobile-backend \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

# Port-forward + hit health
kubectl --context aws-k3s port-forward -n mobile-backend svc/auth-api-service 3000:3000 &
curl http://localhost:3000/health/ready
kill %1
```

## Future additions

- `ingress-patch.yaml` — once you have a domain pointed at the EC2 IP, a patch that enables Traefik ingress (HTTP-only first, then Let's Encrypt TLS)
- `hpa.yaml` — HorizontalPodAutoscaler, even with 1 replica minimum, to learn the configuration
