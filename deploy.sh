#!/bin/bash
# ============================================
# HNG13 Stage 1 - Automated Docker Deployment
# Author: Michael Akande
# ============================================

set -euo pipefail

# -------- CONFIG --------
LOGFILE="deploy_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -i "$LOGFILE") 2>&1

error_exit() {
  echo "[ERROR] $1" >&2
  exit 1
}

# -------- VARIABLES --------
read -p "Git repo URL: " REPO_URL
read -p "Branch (default: main): " BRANCH
BRANCH=${BRANCH:-main}
read -p "Server IP: " SERVER_IP
read -p "SSH username: " SSH_USER
read -p "Path to PEM key: " SSH_KEY_PATH
read -p "App port (default: 80): " APP_PORT
APP_PORT=${APP_PORT:-80}

REMOTE_DIR="hng13-stage1-deploy"

# -------- CHECK REQUIREMENTS --------
for cmd in git ssh rsync; do
  command -v "$cmd" >/dev/null 2>&1 || error_exit "$cmd is required but not installed."
done

if [ -z "$GITHUB_PAT" ]; then
  error_exit "Environment variable GITHUB_PAT not set. Run: export GITHUB_PAT='your_token'"
fi

echo "=== Starting HNG13 Stage 1 Deployment ==="
echo "Logging to $LOGFILE"
echo

# -------- CLONE REPOSITORY --------
REPO_DIR=$(basename "$REPO_URL" .git)
if [ -d "$REPO_DIR" ]; then
  echo "[INFO] Repo exists. Pulling latest changes..."
  cd "$REPO_DIR" && git pull origin "$BRANCH"
else
  echo "[INFO] Cloning repository..."
  git clone -b "$BRANCH" "https://${GITHUB_PAT}@${REPO_URL#https://}" || error_exit "Git clone failed."
  cd "$REPO_DIR"
fi

# Validate docker file
[ -f "Dockerfile" ] || [ -f "docker-compose.yml" ] || error_exit "No Dockerfile or docker-compose.yml found."

echo "[INFO] Repository ready."

# -------- SSH TEST --------
echo "[INFO] Testing SSH connectivity..."
ssh -i "$SSH_KEY_PATH" -o BatchMode=yes -o ConnectTimeout=10 "$SSH_USER@$SERVER_IP" "echo SSH OK" \
  || error_exit "SSH connection failed."

# -------- REMOTE SETUP --------
echo "[INFO] Preparing remote environment..."
ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" <<'EOF'
set -e
sudo dnf update -y
sudo dnf install -y docker nginx
sudo systemctl enable --now docker nginx
sudo usermod -aG docker $USER || true

# Install Docker Compose v2
if ! command -v docker-compose >/dev/null 2>&1; then
  sudo curl -L https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
fi

docker --version
docker-compose version
nginx -v
EOF


# -------- TRANSFER PROJECT --------
echo "[INFO] Transferring project to remote server..."
# Fallback to scp for Windows Git Bash reliability
scp -i "$SSH_KEY_PATH" -r ./* "$SSH_USER@$SERVER_IP:/home/$SSH_USER/$REMOTE_DIR/"

# -------- DEPLOY APPLICATION --------
echo "[INFO] Deploying Docker container..."
ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" <<EOF
set -e
cd $REMOTE_DIR

if [ -f docker-compose.yml ]; then
  echo "[REMOTE] Using docker-compose..."
  sudo docker-compose down || true
  sudo docker-compose up -d --build
else
  echo "[REMOTE] Using Dockerfile..."
  sudo docker stop hng13_app || true
  sudo docker rm hng13_app || true
  sudo docker build -t hng13_app .
  sudo docker run -d -p $APP_PORT:$APP_PORT --name hng13_app hng13_app
fi
EOF

# -------- CONFIGURE NGINX --------
echo "[INFO] Configuring NGINX reverse proxy..."
ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" <<'EOF'
set -e
sudo bash -c 'cat > /etc/nginx/conf.d/hng13_app.conf' <<'CFG'
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
CFG
sudo nginx -t
sudo systemctl reload nginx
EOF

# -------- VALIDATION --------
echo "[INFO] Validating deployment..."
ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SERVER_IP" <<'EOF'
echo "===== Docker containers ====="
docker ps
echo "===== Local NGINX test ====="
curl -I localhost || true
EOF

echo
echo "✅ Deployment completed successfully!"
echo "Visit: http://$SERVER_IP/"
echo "Log file: $LOGFILE"