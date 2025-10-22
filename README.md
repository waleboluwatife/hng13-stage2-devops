# HNG13 DevOps Stage 1 - Automated Deployment

This repository contains a Bash script (`deploy.sh`) that automates Dockerized application deployment on a remote Linux server.

## Features
- Parameter collection (repo URL, PAT, SSH, port)
- Docker, Docker Compose, and NGINX setup
- Reverse proxy configuration
- Automatic build, run, and validation

## Usage
1. Make script executable:
   ```bash
   chmod +x deploy.sh
