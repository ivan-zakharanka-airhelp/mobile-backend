#!/usr/bin/env bash
set -euo pipefail

# Create a local k3d cluster for development
# Requires: k3d (https://k3d.io), Docker (via Colima or Docker Desktop)

CLUSTER_NAME="mobile-backend"

if k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
  echo "Cluster '$CLUSTER_NAME' already exists. Delete it first with: k3d cluster delete $CLUSTER_NAME"
  exit 1
fi

# On Colima, k3d's embedded DNS can fail to resolve public registries.
# Disable k3d's DNS fix and let k3s use the host DNS directly.
export K3D_FIX_DNS=0

echo "Creating k3d cluster '$CLUSTER_NAME'..."
k3d cluster create "$CLUSTER_NAME" \
  --port "8080:80@loadbalancer" \
  --port "8443:443@loadbalancer" \
  --agents 0

echo ""
echo "Waiting for system pods..."
kubectl wait --for=condition=Ready pod --all -n kube-system --timeout=180s 2>/dev/null || {
  echo ""
  echo "Some system pods are not ready yet. Check with: kubectl get pods -n kube-system"
  echo "If pods are stuck pulling images, Colima's DNS may need a restart: colima restart"
}

echo ""
echo "Cluster ready. Verify with: kubectl get nodes"
echo "API available at: http://localhost:8080"
