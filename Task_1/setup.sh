#!/bin/bash

# Ensure the script is run with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (use sudo)."
  exit 1
fi

echo "Installing Docker and Docker Compose..."
apt update -y && apt install -y docker.io docker-compose

echo "Creating a secure volume for the database..."
mkdir -p /mnt/db_data
chmod 700 /mnt/db_data
chown 1000:1000 /mnt/db_data  # Ensure it’s owned by a non-root user

echo "Starting containers with Docker Compose..."
docker-compose -f deployment.yaml up -d

echo "Setup complete! Your system is running."
