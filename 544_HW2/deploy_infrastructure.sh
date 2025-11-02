#!/bin/bash
set -euo pipefail

KEY_PATH="my-key-pair.pem"
PUBLIC_IP_FILE="instance_ip.txt"
REGION="us-east-2"

if [ ! -f "$PUBLIC_IP_FILE" ]; then
  echo "Public IP file $PUBLIC_IP_FILE not found. Run create_infrastructure.sh first."
  exit 1
fi

PUBLIC_IP=$(cat "$PUBLIC_IP_FILE")
if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" == "None" ]; then
  echo "Public IP not found in $PUBLIC_IP_FILE"
  exit 1
fi

echo "Waiting until SSH is reachable on $PUBLIC_IP (this may take a minute)..."
# Wait until SSH port is open
until ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@"$PUBLIC_IP" "echo ok" >/dev/null 2>&1; do
  echo -n "."
  sleep 5
done
echo
echo "SSH reachable. Running remote commands to install NGINX..."

ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@"$PUBLIC_IP" <<'REMOTE_CMD'
sudo apt update -y
sudo apt install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx
echo "<html><body><h1>Welcome to My NGINX Site!</h1></body></html>" | sudo tee /var/www/html/index.html
REMOTE_CMD

echo "NGINX installed and basic page deployed at http://$PUBLIC_IP"

# Optionally create an AMI snapshot of this configured instance for scaling
INSTANCE_ID=$(cat instance_id.txt)
if [ -n "$INSTANCE_ID" ]; then
  echo "Creating AMI from instance $INSTANCE_ID..."
  AMI_ID=$(aws ec2 create-image --instance-id "$INSTANCE_ID" --name "MyCustomNGINX-AMI-$(date +%Y%m%d%H%M%S)" --no-reboot --region "$REGION" --query "ImageId" --output text)
  echo "Created AMI: $AMI_ID"
  echo "$AMI_ID" > ami_id.txt
fi

echo "deploy_infrastructure.sh finished."
