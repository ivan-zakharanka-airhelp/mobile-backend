#!/usr/bin/env bash
#
# cleanup-manual-resources.sh — ONE-TIME cleanup of resources created by hand
# before the Terraform flow was in place. Safe to skip if you've never created
# anything manually.
#
# What gets deleted (if it exists):
#   - EC2 instance: ivan-auth-learning
#   - Elastic IP: ivan-auth-learning-eip (tagged)
#   - RDS instance: ivan-auth-learning (no final snapshot)
#   - RDS subnet group: ivan-auth-learning-sg
#   - Security groups: ivan-auth-learning-ec2, ivan-auth-learning-rds
#   - Key pair: ivan-auth-learning
#
# Does NOT touch:
#   - Local SSH key at ~/.ssh/aws_learning_ed25519(.pub)
#   - Local password file at ~/.aws-auth-learning-db-password.txt
#   - Any VPC / subnets (those are shared AirHelp infrastructure)

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

[ -z "${AWS_PROFILE:-}" ] && { echo -e "${RED}AWS_PROFILE not set.${NC} Run: export AWS_PROFILE=development"; exit 1; }

echo -e "${YELLOW}One-time cleanup of manually-created AWS resources in $AWS_PROFILE:${NC}"
echo
read -rp "Continue? (y/N) " confirm
[[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo "Aborted."; exit 0; }

say() { echo -e "\n${GREEN}▸${NC} $1"; }
soft() { echo "  $1"; }

# ── 1. EC2 instance ──
say "Looking for EC2 instance 'ivan-auth-learning'"
EC2_ID=$(aws ec2 describe-instances \
  --filters 'Name=tag:Name,Values=ivan-auth-learning' 'Name=instance-state-name,Values=running,stopped,pending' \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)
if [ -n "$EC2_ID" ] && [ "$EC2_ID" != "None" ]; then
  soft "Terminating $EC2_ID"
  aws ec2 terminate-instances --instance-ids "$EC2_ID" >/dev/null
  aws ec2 wait instance-terminated --instance-ids "$EC2_ID"
  soft "Terminated"
else
  soft "None found"
fi

# ── 2. Elastic IP ──
say "Looking for Elastic IPs tagged with Project=auth-service-learning"
ALLOC_IDS=$(aws ec2 describe-addresses \
  --filters 'Name=tag:Project,Values=auth-service-learning' \
  --query 'Addresses[].AllocationId' --output text 2>/dev/null)
for ID in $ALLOC_IDS; do
  soft "Releasing $ID"
  aws ec2 release-address --allocation-id "$ID" 2>&1 || soft "(already released or in use)"
done
[ -z "$ALLOC_IDS" ] && soft "None found"

# ── 3. RDS instance ──
say "Looking for RDS instance 'ivan-auth-learning'"
if aws rds describe-db-instances --db-instance-identifier ivan-auth-learning >/dev/null 2>&1; then
  soft "Deleting (skip-final-snapshot=true)"
  aws rds delete-db-instance \
    --db-instance-identifier ivan-auth-learning \
    --skip-final-snapshot --delete-automated-backups >/dev/null
  soft "Waiting for deletion (takes ~3-5 minutes)..."
  aws rds wait db-instance-deleted --db-instance-identifier ivan-auth-learning
  soft "Deleted"
else
  soft "None found"
fi

# ── 4. RDS subnet group ──
say "Looking for DB subnet group 'ivan-auth-learning-sg'"
if aws rds describe-db-subnet-groups --db-subnet-group-name ivan-auth-learning-sg >/dev/null 2>&1; then
  aws rds delete-db-subnet-group --db-subnet-group-name ivan-auth-learning-sg >/dev/null
  soft "Deleted"
else
  soft "None found"
fi

# ── 5. Security groups ──
say "Looking for security groups 'ivan-auth-learning-ec2' and 'ivan-auth-learning-rds'"
for SG_NAME in ivan-auth-learning-ec2 ivan-auth-learning-rds; do
  SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
  if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    soft "Deleting $SG_NAME ($SG_ID)"
    aws ec2 delete-security-group --group-id "$SG_ID" 2>&1 || soft "(may have dependencies — retry later)"
  else
    soft "$SG_NAME not found"
  fi
done

# ── 6. Key pair ──
say "Looking for key pair 'ivan-auth-learning'"
if aws ec2 describe-key-pairs --key-names ivan-auth-learning >/dev/null 2>&1; then
  aws ec2 delete-key-pair --key-name ivan-auth-learning >/dev/null
  soft "Deleted"
else
  soft "None found"
fi

echo
echo -e "${GREEN}Cleanup complete.${NC} You can now safely run 'make aws-up'."
echo
echo "Verify:"
echo "  aws ec2 describe-instances --filters 'Name=tag:Project,Values=auth-service-learning' --query 'Reservations[].Instances[?State.Name!=\`terminated\`].[InstanceId,State.Name]' --output table"
