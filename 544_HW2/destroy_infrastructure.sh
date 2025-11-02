#!/bin/bash
set -euo pipefail

REGION="us-east-2"

# Load saved IDs (some may be missing if earlier steps failed)
VPC_ID=$(cat vpc_id.txt 2>/dev/null || true)
SG_ID=$(cat security_group_id.txt 2>/dev/null || true)
INSTANCE_ID=$(cat instance_id.txt 2>/dev/null || true)
LAUNCH_TEMPLATE_NAME="MyNGINXLaunchTemplate"
ASG_NAME="MyNGINXAutoScalingGroup"
ALB_NAME="MyNGINXALB"
TG_NAME="MyNGINXTargetGroup"
KEY_NAME="my-key-pair"

echo "Starting cleanup..."

# 1) Delete Auto Scaling group (force delete)
if aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --region "$REGION" --query "AutoScalingGroups" --output text | grep -q "$ASG_NAME"; then
  echo "Deleting Auto Scaling Group $ASG_NAME..."
  aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "$ASG_NAME" --force-delete --region "$REGION" || true
else
  echo "Auto Scaling Group $ASG_NAME not found or already deleted."
fi

# 2) Delete launch template
if aws ec2 describe-launch-templates --launch-template-names "$LAUNCH_TEMPLATE_NAME" --region "$REGION" --query "LaunchTemplates" --output text >/dev/null 2>&1; then
  echo "Deleting launch template $LAUNCH_TEMPLATE_NAME..."
  aws ec2 delete-launch-template --launch-template-name "$LAUNCH_TEMPLATE_NAME" --region "$REGION" || true
fi

# 3) Delete ALB and target group (using elbv2)
ALB_ARN=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" --region "$REGION" --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null || true)
if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
  echo "Deleting ALB..."
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" --region "$REGION"
  # wait until deleted
  echo "Waiting for ALB to be deleted..."
  sleep 10
fi

TG_ARN=$(aws elbv2 describe-target-groups --names "$TG_NAME" --region "$REGION" --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null || true)
if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
  echo "Deleting target group..."
  aws elbv2 delete-target-group --target-group-arn "$TG_ARN" --region "$REGION"
fi

# 4) Terminate instance(s) if present
if [ -n "$INSTANCE_ID" ]; then
  echo "Terminating instance $INSTANCE_ID..."
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$REGION" || true
  aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$REGION" || true
fi

# 5) Delete Security Group
if [ -n "$SG_ID" ]; then
  echo "Deleting Security Group $SG_ID..."
  aws ec2 delete-security-group --group-id "$SG_ID" --region "$REGION" || true
fi

# 6) Delete Subnets
if [ -n "$VPC_ID" ]; then
  SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query "Subnets[].SubnetId" --output text || true)
  for s in $SUBNETS; do
    echo "Deleting subnet $s..."
    aws ec2 delete-subnet --subnet-id "$s" --region "$REGION" || true
  done
fi

# 7) Detach and delete Internet Gateway
if [ -n "$VPC_ID" ]; then
  IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --region "$REGION" --query "InternetGateways[0].InternetGatewayId" --output text 2>/dev/null || true)
  if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
    echo "Detaching and deleting internet gateway $IGW_ID..."
    aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$REGION" || true
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" --region "$REGION" || true
  fi
fi

# 8) Delete route tables (skipping main)
if [ -n "$VPC_ID" ]; then
  RTBS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query "RouteTables[].RouteTableId" --output text || true)
  for r in $RTBS; do
    echo "Deleting route table $r..."
    aws ec2 delete-route-table --route-table-id "$r" --region "$REGION" || true
  done
fi

# 9) Delete VPC
if [ -n "$VPC_ID" ]; then
  echo "Deleting VPC $VPC_ID..."
  aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION" || true
fi

# 10) Delete key pair from AWS and local file
echo "Deleting Key Pair $KEY_NAME from AWS..."
aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$REGION" || true
if [ -f "my-key-pair.pem" ]; then
  rm -f my-key-pair.pem
  echo "Deleted local key file my-key-pair.pem"
fi

# 11) Deregister AMI (if present)
AMI_ID=$(cat ami_id.txt 2>/dev/null || true)
if [ -n "$AMI_ID" ]; then
  echo "Deregistering AMI $AMI_ID..."
  aws ec2 deregister-image --image-id "$AMI_ID" --region "$REGION" || true
fi

# 12) Remove local files
rm -f instance_id.txt instance_ip.txt vpc_id.txt igw_id.txt subnet_ids.txt route_table_id.txt security_group_id.txt ami_id.txt alb_dns.txt

echo "Cleanup attempted. Note: some AWS resources may take time to be fully deleted."
