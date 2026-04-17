#!/usr/bin/env bash
#
# aws-teardown.sh — destroys all AWS resources provisioned by Terraform.
# Removes the local kubeconfig and deletes the aws-k3s context from ~/.kube/config.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$PROJECT_ROOT/infra/terraform"
KUBECONFIG_PATH="$HOME/.kube/k3s-aws.yaml"
CONTEXT_NAME="aws-k3s"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

[ -z "${AWS_PROFILE:-}" ] && { echo -e "${RED}AWS_PROFILE not set.${NC} Run: export AWS_PROFILE=development"; exit 1; }
[ ! -d "$TF_DIR" ] && { echo -e "${RED}Terraform directory not found: $TF_DIR${NC}"; exit 1; }

echo -e "${YELLOW}This will destroy all Terraform-managed AWS resources in $AWS_PROFILE:${NC}"
echo "  - EC2 instance + Elastic IP"
echo "  - RDS instance (no final snapshot) — ALL DATA LOST"
echo "  - Security groups"
echo "  - DB subnet group"
echo "  - EC2 key pair"
echo
read -rp "Destroy everything? (y/N) " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

cd "$TF_DIR"
terraform destroy -auto-approve

# Clean up local kubeconfig so we don't leak stale contexts
if [ -f "$KUBECONFIG_PATH" ]; then
  rm -f "$KUBECONFIG_PATH"
  echo -e "${GREEN}✓${NC} Removed $KUBECONFIG_PATH"
fi

# Remove aws-k3s context from main kubeconfig (if it exists)
if kubectl config get-contexts "$CONTEXT_NAME" >/dev/null 2>&1; then
  kubectl config delete-context "$CONTEXT_NAME" >/dev/null 2>&1 || true
  kubectl config delete-cluster "$CONTEXT_NAME" >/dev/null 2>&1 || true
  kubectl config delete-user    "$CONTEXT_NAME" >/dev/null 2>&1 || true
  echo -e "${GREEN}✓${NC} Removed $CONTEXT_NAME context from ~/.kube/config"
fi

echo -e "${GREEN}Done.${NC} Verify nothing lingers:"
echo "  aws ec2 describe-instances --filters 'Name=tag:Project,Values=auth-service-learning' \\"
echo "    --query 'Reservations[].Instances[?State.Name!=\`terminated\`].[InstanceId,State.Name]'"
