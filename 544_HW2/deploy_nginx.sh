#!/bin/bash

KEY_PATH="my-key-pair.pem"
PUBLIC_IP=$(cat instance_ip.txt)

if [ -z "$PUBLIC_IP" ]; then
  echo "Public IP not found."
  exit 1
fi

echo "Deploying NGINX to $PUBLIC_IP..."

ssh -o "StrictHostKeyChecking=no" -i $KEY_PATH ubuntu@$PUBLIC_IP << 'EOF'
sudo apt update -y
sudo apt install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx
echo "<html><body><h1>Welcome to My NGINX Site!</h1></body></html>" | sudo tee /var/www/html/index.html
EOF

echo "Site deployed at: http://$PUBLIC_IP"
