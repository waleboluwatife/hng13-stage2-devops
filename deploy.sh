#!/bin/bash
set -euo pipefail   # stop on error, unset var, or pipe failure

LOGFILE="deploy_$(date +%Y%m%d).log"
exec > >(tee -i "$LOGFILE") 2>&1

error_exit() {
  echo "[ERROR] $1" >&2
  exit 1
}

check_cmd() {
  command -v "$1" >/dev/null 2>&1 || error_exit "$1 not found."
}

echo "=== HNG13 Stage 1 Automated Deployment ==="
read -rp "Git Repository URL: " REPO_URL
read -rp "Personal Access Token (PAT): " PAT
read -rp "Branch name [default=main]: " BRANCH
BRANCH=${BRANCH:-main}
read -rp "SSH Username: " SSH_USER
read -rp "Server IP Address: " SERVER_IP
read -rp "SSH Key Path: " SSH_KEY
read -rp "App internal port: " APP_PORT

REPO_DIR=$(basename "$REPO_URL" .git)

if [ -d "$REPO_DIR" ]; then
  echo "Repository exists, pulling latest changes..."
  cd "$REPO_DIR" && git pull origin "$BRANCH"
else
  echo "Cloning repository..."
  GIT_ASKPASS=$(mktemp)
  echo "echo $PAT" >"$GIT_ASKPASS"
  chmod +x "$GIT_ASKPASS"
  GIT_ASKPASS="$GIT_ASKPASS" git clone -b "$BRANCH" "https://${REPO_URL#https://}" || error_exit "Clone failed"
  cd "$REPO_DIR"
fi

[ -f "Dockerfile" ] || [ -f "docker-compose.yml" ] || error_exit "No Dockerfile or docker-compose.yml found."
