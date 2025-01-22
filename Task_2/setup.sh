#!/bin/bash

# check root user
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (use sudo)."
  exit 1
fi

echo "Installing Docker, Docker Compose, and security tools..."
apt update -y && apt install -y docker.io docker-compose openssl nmap

# external storage for DB data
echo "Setting up secure external storage for the database..."
DB_VOLUME="/mnt/db_data"
mkdir -p $DB_VOLUME
chmod 700 $DB_VOLUME
chown 1000:1000 $DB_VOLUME

echo "Generating self-signed SSL certificates for Nginx..."
CERT_DIR="./certs"
mkdir -p $CERT_DIR
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout $CERT_DIR/server.key -out $CERT_DIR/server.crt \
  -subj "/CN=localhost"

echo "Deploying containers with Docker Compose..."
docker-compose -f deployment.yaml up -d

# Install Trivy for container scanning
echo "Installing Trivy for container security scanning..."
curl -s https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh

# Install Nikto for web server scanning
echo "Installing Nikto for web server scanning..."
apt install -y nikto

# Install OWASP ZAP for DAST
echo "Installing OWASP ZAP for Dynamic Application Security Testing..."
docker pull owasp/zap2docker-stable
# Create directories for results
RESULTS_DIR="./security_results"
mkdir -p $RESULTS_DIR

# Container security scanning using Trivy
echo "Scanning containers for vulnerabilities using Trivy..."
TRIVY_OUTPUT="$RESULTS_DIR/trivy_results.txt"
docker ps -q | while read container_id; do
  echo "Scanning container $container_id with Trivy..."
  docker_image=$(docker inspect --format='{{.Config.Image}}' "$container_id")
  trivy image --format table --output "$TRIVY_OUTPUT" "$docker_image"
done

# Web server scanning using Nikto
echo "Scanning Nginx web server for vulnerabilities using Nikto..."
NIKTO_OUTPUT="$RESULTS_DIR/nikto_results.txt"
nikto -h https://localhost -o "$NIKTO_OUTPUT"

# Network scanning using Nmap
echo "Scanning open ports and services with Nmap..."
NMAP_OUTPUT="$RESULTS_DIR/nmap_results.txt"
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -q) | while read ip; do
  echo "Scanning IP $ip with Nmap..."
  nmap -A "$ip" >> "$NMAP_OUTPUT"
done

# Dynamic Application Security Testing (DAST) using OWASP ZAP
echo "Running DAST scan using OWASP ZAP..."
ZAP_OUTPUT="$RESULTS_DIR/zap_results.txt"
docker run -d --name zap -p 8080:8080 owasp/zap2docker-stable
sleep 15  # Allow ZAP to initialize
docker exec -t zap zap-cli quick-scan --self-contained --start-url https://localhost > "$ZAP_OUTPUT"
docker stop zap && docker rm zap

# Displaying results in a table format
echo "Aggregating and displaying security scan results..."
echo
echo "======================= Security Scan Results ======================="
echo
echo "1. Container Security Scan (Trivy):"
cat "$TRIVY_OUTPUT"
echo
echo "2. Web Server Scan (Nikto):"
cat "$NIKTO_OUTPUT"
echo
echo "3. Network Scan (Nmap):"
cat "$NMAP_OUTPUT"
echo
echo "4. Dynamic Application Security Test (OWASP ZAP):"
cat "$ZAP_OUTPUT"
echo
echo "====================================================================="
echo "All results have been saved in the directory: $RESULTS_DIR"
