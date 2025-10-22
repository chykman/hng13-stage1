#!/bin/bash

# === Logging and Error Handling ===
LOG_FILE="deploy_$(date +%Y%m%d).log"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'show_error "Unexpected error occurred. Check $LOG_FILE for details."' ERR

# === Helper Functions ===
show_message() {
    echo "➡️ $1"
}

show_error() {
    echo "❌ ERROR: $1"
    exit 1
}

# === Step 1: Collect Parameters ===
show_message "Collecting deployment details..."

read -p "Enter Git Repository URL: " REPO_URL
[ -z "$REPO_URL" ] && show_error "Repository URL is required."
[[ "$REPO_URL" != *.git ]] && REPO_URL="${REPO_URL}.git"

read -p "Enter Personal Access Token (PAT): " PAT
echo
[ -z "$PAT" ] && show_error "PAT is required."

read -p "Enter Branch name [main]: " BRANCH
BRANCH=${BRANCH:-main}

read -p "Enter SSH Username [ubuntu]: " SSH_USER
SSH_USER=${SSH_USER:-ubuntu}

read -p "Enter Server IP Address: " SSH_HOST
[ -z "$SSH_HOST" ] && show_error "Server IP is required."

read -p "Enter SSH Key Path: " SSH_KEY
[ ! -f "$SSH_KEY" ] && show_error "SSH key file not found at: $SSH_KEY"

read -p "Enter Application Internal Port: " APP_PORT
[[ ! "$APP_PORT" =~ ^[0-9]+$ ]] && show_error "Port must be a number."

echo
show_message "✅ Parameters collected:"
echo "Repo URL: $REPO_URL"
echo "Branch: $BRANCH"
echo "SSH User: $SSH_USER"
echo "Server IP: $SSH_HOST"
echo "SSH Key: $SSH_KEY"
echo "App Port: $APP_PORT"
echo

# === Step 2: Clone or Update Repository ===
REPO_NAME=$(basename "$REPO_URL" .git)
AUTH_REPO_URL="https://${PAT}@${REPO_URL#https://}"
git ls-remote "$AUTH_REPO_URL" &>/dev/null || show_error "Repository not found or access denied."

if [ -d "$REPO_NAME" ]; then
    show_message "Folder '$REPO_NAME' exists. Checking if it's a Git repo..."
    if [ -d "$REPO_NAME/.git" ]; then
        show_message "✅ It's a Git repo. Pulling latest changes..."
        cd "$REPO_NAME" || show_error "Failed to enter repo directory."
        git fetch origin
        git checkout "$BRANCH"
        git pull origin "$BRANCH"
    else
        show_message "⚠️ Not a Git repo. Re-cloning..."
        rm -rf "$REPO_NAME"
        git clone -b "$BRANCH" "$AUTH_REPO_URL" || show_error "Failed to clone."
        cd "$REPO_NAME" || show_error "Failed to enter cloned repo."
    fi
else
    show_message "Cloning repository..."
    git clone -b "$BRANCH" "$AUTH_REPO_URL" || show_error "Failed to clone."
    cd "$REPO_NAME" || show_error "Failed to enter cloned repo."
fi

show_message "✅ Repository is ready and on branch '$BRANCH'"

# === Step 3: Verify Docker Setup ===
if [ -f "docker-compose.yml" ]; then
    show_message "✅ Found docker-compose.yml"
elif [ -f "Dockerfile" ]; then
    show_message "✅ Found Dockerfile"
else
    show_error "No Dockerfile or docker-compose.yml found."
fi

# === Step 4: Test SSH Connection ===
show_message "Testing SSH connection to $SSH_USER@$SSH_HOST..."
ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SSH_USER@$SSH_HOST" 'echo "✅ SSH connection successful."' || show_error "SSH connection failed."

ping -c 2 "$SSH_HOST" &>/dev/null && show_message "✅ Ping successful." || show_message "⚠️ Ping failed."

# === Step 5: Prepare Remote Environment ===
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$SSH_HOST" <<EOF
  echo "🔧 Updating system packages..."
  sudo apt update -y && sudo apt upgrade -y

  echo "📦 Installing Docker, Docker Compose, and Nginx..."
  sudo apt install -y docker.io nginx curl

  echo "🔗 Adding user to Docker group..."
  sudo usermod -aG docker \$USER

  echo "🚀 Enabling and starting services..."
  sudo systemctl enable docker
  sudo systemctl start docker
  sudo systemctl enable nginx
  sudo systemctl start nginx

  echo "🔍 Confirming versions..."
  docker --version
  docker-compose --version || echo "⚠️ Docker Compose not found"
  nginx -v
EOF

# === Step 6: Transfer and Deploy Application ===
cd ..
tar -czf "${REPO_NAME}.tar.gz" "$REPO_NAME"
scp -i "$SSH_KEY" "${REPO_NAME}.tar.gz" "$SSH_USER@$SSH_HOST:~/"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$SSH_HOST" <<EOF
  tar -xzf "${REPO_NAME}.tar.gz"
  cd "$REPO_NAME"

  echo "🐳 Deploying Docker containers..."
  if [ -f docker-compose.yml ]; then
    sudo docker-compose down
    sudo docker-compose up -d
  elif [ -f Dockerfile ]; then
    sudo docker stop myapp || true
    sudo docker rm myapp || true
    sudo docker build -t myapp .
    sudo docker run -d --name myapp -p ${APP_PORT}:${APP_PORT} myapp
  fi

  echo "📋 Container status:"
  sudo docker ps
EOF

# === Step 7: Configure Nginx Reverse Proxy ===
ssh -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" <<EOF
  echo "🛠️ Configuring Nginx reverse proxy..."

  cat <<NGINX | sudo tee /etc/nginx/sites-available/default
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://localhost:${APP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGINX

  echo "🔄 Reloading Nginx..."
  sudo nginx -t && sudo systemctl reload nginx
EOF

# === Step 8: Validate Deployment ===
ssh -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" <<EOF
  echo "🔍 Validating deployment..."

  echo "Docker status:"
  sudo systemctl status docker | head -n 10

  echo "Nginx status:"
  sudo systemctl status nginx | head -n 10

  echo "Testing app endpoint:"
  curl -I http://localhost
EOF

# === Step 9: Optional Cleanup ===
if [[ "$1" == "--cleanup" ]]; then
  show_message "🧹 Cleaning up remote resources..."
  ssh -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" <<EOF
    sudo docker stop myapp || true
    sudo docker rm myapp || true
    sudo docker network prune -f
    sudo rm -rf ~/$(basename "$REPO_NAME")
    sudo rm -f ~/$(basename "$REPO_NAME").tar.gz
    echo "✅ Cleanup complete."
EOF
  exit 0
fi

show_message "🎉 Deployment complete. Check $LOG_FILE for full logs."
