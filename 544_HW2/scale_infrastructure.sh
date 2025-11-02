#!/bin/bash
set -euo pipefail

REGION="us-east-2"

# Load saved IDs
VPC_ID=$(cat vpc_id.txt)
SUBNETS=$(cat subnet_ids.txt)       # two IDs separated by space
SECURITY_GRP_ID=$(cat security_group_id.txt)
AMI_ID=$(cat ami_id.txt)
if [ -z "$AMI_ID" ]; then
  echo "AMI ID not found (ami_id.txt). Run deploy_infrastructure.sh to create AMI."
  exit 1
fi

# Convert subnet ids to comma separated for autoscaling vpc-zone-identifier
VPC_ZONE_IDENTIFIER=$(echo "$SUBNETS" | tr ' ' ',')

# 1) Create Launch Template
LAUNCH_TEMPLATE_NAME="MyNGINXLaunchTemplate"
echo "Creating launch template $LAUNCH_TEMPLATE_NAME..."
LAUNCH_TEMPLATE_ID=$(aws ec2 create-launch-template \
  --launch-template-name "$LAUNCH_TEMPLATE_NAME" \
  --version-description "v1" \
  --launch-template-data "{\"ImageId\":\"$AMI_ID\",\"InstanceType\":\"t3.micro\",\"KeyName\":\"my-key-pair\",\"SecurityGroupIds\":[\"$SECURITY_GRP_ID\"]}" \
  --region "$REGION" --query "LaunchTemplate.LaunchTemplateId" --output text)

echo "Created Launch Template: $LAUNCH_TEMPLATE_ID"

# 2) Create Target Group (for ALB)
TG_NAME="MyNGINXTargetGroup"
echo "Creating target group $TG_NAME..."
TG_ARN=$(aws elbv2 create-target-group --name "$TG_NAME" --protocol HTTP --port 80 --vpc-id "$VPC_ID" --target-type instance --region "$REGION" --query "TargetGroups[0].TargetGroupArn" --output text)
echo "Target Group ARN: $TG_ARN"

# 3) Create Application Load Balancer (ALB)
ALB_NAME="MyNGINXALB"
echo "Creating ALB $ALB_NAME..."
# Use the two subnets for ALB
SUBNET_ARGS=$(echo "$SUBNETS" | awk '{print "--subnets "$1" "$2}')
ALB_ARN=$(aws elbv2 create-load-balancer --name "$ALB_NAME" --scheme internet-facing $(echo $SUBNET_ARGS) --security-groups "$SECURITY_GRP_ID" --region "$REGION" --query "LoadBalancers[0].LoadBalancerArn" --output text)
ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --region "$REGION" --query "LoadBalancers[0].DNSName" --output text)
echo "Created ALB: $ALB_ARN with DNS: $ALB_DNS"

# 4) Create Listener for port 80 to forward to target group
echo "Creating listener on ALB to forward HTTP:80 to target group"
aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn="$TG_ARN" --region "$REGION" >/dev/null
echo "Listener created."

# 5) Create Auto Scaling Group
ASG_NAME="MyNGINXAutoScalingGroup"
echo "Creating Auto Scaling Group $ASG_NAME..."
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --launch-template "LaunchTemplateId=$LAUNCH_TEMPLATE_ID,Version=1" \
  --min-size 2 --max-size 5 --desired-capacity 2 \
  --vpc-zone-identifier "$VPC_ZONE_IDENTIFIER" \
  --target-group-arns "$TG_ARN" \
  --region "$REGION"

echo "Auto Scaling Group created: $ASG_NAME"

echo "scale_infrastructure.sh finished. ALB DNS: $ALB_DNS"

# Save ALB DNS to file
echo "$ALB_DNS" > alb_dns.txt
