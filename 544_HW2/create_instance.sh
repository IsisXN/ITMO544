#!/bin/bash

AMI_ID="ami-0c5ddb3560e768732" # Replace with the AMI ID you got
INSTANCE_TYPE="t3.micro"
KEY_NAME="my-key-pair"
SECURITY_GROUP="ITMO-444-544-lab-security-group"
REGION="us-east-2"

SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --group-names $SECURITY_GROUP --region $REGION --query "SecurityGroups[0].GroupId" --output text)

echo "Creating EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances --image-id $AMI_ID --count 1 --instance-type $INSTANCE_TYPE --key-name $KEY_NAME --security-group-ids $SECURITY_GROUP_ID --region $REGION --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ITMO-444-544-Web-Server}]' --output text --query 'Instances[0].InstanceId')

echo "Instance created: $INSTANCE_ID"

echo "Waiting for instance to be in running state..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION

PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

if [ "$PUBLIC_IP" == "None" ]; then
  echo "No public IP assigned."
  exit 1
fi

echo "Instance is running. Public IP: $PUBLIC_IP"
echo $INSTANCE_ID > instance_id.txt
echo $PUBLIC_IP > instance_ip.txt
