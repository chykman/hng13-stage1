# HNG13 Stage 1 Task – DevOps Deployment Script

This repository contains a production-grade Bash script (`deploy.sh`) developed for the HNG13 DevOps Stage 1 task. The script automates the deployment of a Dockerized application to a remote Linux server, handling everything from environment setup to reverse proxy configuration.

## 🚀 What the Script Does

The `deploy.sh` script performs the following steps:

1. **Collects Deployment Parameters**  
   Prompts for GitHub repo details, server credentials, and app port.

2. **Clones the GitHub Repository Locally**  
   Validates access and pulls the latest code from the specified branch.

3. **Verifies Docker Setup**  
   Ensures the project contains a `Dockerfile` or `docker-compose.yml`.

4. **Tests SSH Connectivity**  
   Confirms remote access using the provided SSH key and credentials.

5. **Prepares the Remote Environment**  
   Installs Docker, Docker Compose, and Nginx. Adds user to Docker group and starts services.

6. **Deploys the Dockerized Application**  
   Transfers the project to the server, builds and runs containers, and validates container health.

7. **Configures Nginx as a Reverse Proxy**  
   Dynamically sets up Nginx to forward traffic from port 80 to the app’s internal port.

8. **Validates Deployment**  
   Checks Docker and Nginx status, and tests the app endpoint using `curl`.

9. **Implements Logging and Error Handling**  
   Logs all actions to a timestamped file and traps unexpected errors.

10. **Ensures Idempotency and Cleanup**  
    Safely re-runs without breaking existing setups. Includes a `--cleanup` flag to remove deployed resources.

---

## 🛠️ Usage Instructions

### 1. Make the script executable
```bash
chmod +x deploy.sh

