#!/bin/bash

REGION="us-east-2"
INSTANCE_ID=$(cat instance_id.txt)

if [ -z "$INSTANCE_ID" ]; then
  echo "Instance ID not found."
  exit 1
fi

echo "Stopping instance $INSTANCE_ID..."
aws ec2 stop-instances --instance-ids $INSTANCE_ID --region $REGION
aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID --region $REGION
echo "Instance stopped."

echo "Terminating instance $INSTANCE_ID..."
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $REGION
aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID --region $REGION
echo "Instance terminated."
