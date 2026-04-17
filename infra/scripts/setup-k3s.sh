#!/usr/bin/env bash
set -euo pipefail

# Install k3s on a Hetzner VPS (or any Linux server)
# Run this once on the production server

echo "Installing k3s..."
curl -sfL https://get.k3s.io | sh -s - \
  --disable=servicelb \
  --write-kubeconfig-mode=644

echo ""
echo "k3s installed. Next steps:"
echo "  1. Copy kubeconfig to your local machine:"
echo "     scp root@\$(hostname -I | awk '{print \$1}'):/etc/rancher/k3s/k3s.yaml ~/.kube/config"
echo "  2. Edit ~/.kube/config — change 'server: https://127.0.0.1:6443' to your server's public IP"
echo "  3. Verify: kubectl get nodes"
