#!/bin/bash
set -euo pipefail

REGION="us-east-2"           # change if you want a different region
AMI_OWNER="099720109477"     # canonical Ubuntu owner

echo "Using region: $REGION"

# 1) Create a VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region "$REGION" --query "Vpc.VpcId" --output text)
echo "Created VPC: $VPC_ID"
echo "$VPC_ID" > vpc_id.txt

# 2) Create Subnets in two AZs
SUBNET_ID_1=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.1.0/24 --availability-zone "${REGION}a" --region "$REGION" --query "Subnet.SubnetId" --output text)
SUBNET_ID_2=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.2.0/24 --availability-zone "${REGION}b" --region "$REGION" --query "Subnet.SubnetId" --output text)
echo "Created Subnets: $SUBNET_ID_1, $SUBNET_ID_2"
echo "$SUBNET_ID_1 $SUBNET_ID_2" > subnet_ids.txt

# 3) Create and attach Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway --region "$REGION" --query "InternetGateway.InternetGatewayId" --output text)
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" --region "$REGION"
echo "Created and attached Internet Gateway: $IGW_ID"
echo "$IGW_ID" > igw_id.txt

# 4) Create Route Table, add default route, associate with subnets
RTB_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$REGION" --query "RouteTable.RouteTableId" --output text)
aws ec2 create-route --route-table-id "$RTB_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" --region "$REGION"
aws ec2 associate-route-table --subnet-id "$SUBNET_ID_1" --route-table-id "$RTB_ID" --region "$REGION" >/dev/null
aws ec2 associate-route-table --subnet-id "$SUBNET_ID_2" --route-table-id "$RTB_ID" --region "$REGION" >/dev/null
echo "Created and associated Route Table: $RTB_ID"
echo "$RTB_ID" > route_table_id.txt

# 5) Create SSH Key Pair and save locally
if [ ! -f my-key-pair.pem ]; then
  aws ec2 create-key-pair --key-name my-key-pair --key-type 'ed25519' --query 'KeyMaterial' --output text > my-key-pair.pem
  chmod 400 my-key-pair.pem
  echo "Created SSH key pair my-key-pair.pem"
else
  echo "Key file my-key-pair.pem already exists locally; assuming key pair is already present or using existing."
fi

# 6) Create Security Group and open SSH and HTTP
MY_IP=$(curl -s ifconfig.me)/32 || MY_IP="0.0.0.0/0"
SG_ID=$(aws ec2 create-security-group --group-name ITMO-444-544-lab-security-group --description "Security group for SSH and HTTP access" --vpc-id "$VPC_ID" --region "$REGION" --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$MY_IP" --region "$REGION" || true
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 --region "$REGION" || true
echo "Security Group created: $SG_ID"
echo "$SG_ID" > security_group_id.txt

# 7) Find Ubuntu Jammy (22.04) AMI for the region
AMI_ID=$(aws ec2 describe-images --owners "$AMI_OWNER" --region "$REGION" --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" "Name=architecture,Values=x86_64" "Name=virtualization-type,Values=hvm" --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" --output text)
echo "Found AMI ID: $AMI_ID"
echo "$AMI_ID" > ami_id.txt

# 8) Launch an EC2 instance in SUBNET_ID_1
INSTANCE_ID=$(aws ec2 run-instances --image-id "$AMI_ID" --count 1 --instance-type t3.micro --key-name my-key-pair --security-group-ids "$SG_ID" --subnet-id "$SUBNET_ID_1" --associate-public-ip-address --region "$REGION" --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ITMO-444-544-Web-Server}]" --query "Instances[0].InstanceId" --output text)
echo "Instance created: $INSTANCE_ID"
echo "$INSTANCE_ID" > instance_id.txt

# Wait for running
echo "Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "Instance is running. Public IP: $PUBLIC_IP"
echo "$PUBLIC_IP" > instance_ip.txt

echo "create_infrastructure.sh completed successfully."
