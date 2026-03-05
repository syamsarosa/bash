#!/bin/bash

##############################################
# NOTE: You must have sudo user to run this script. If you don't, install it using add_sudo_user.sh script
##############################################

##############################################
# Ensure script is run as root
##############################################
if [ "$EUID" -ne 0 ]; then
  echo "Please run using: sudo bash setup_classes.sh"
  exit
fi

##############################################
# Update server package and install required dependency
##############################################
echo "===== INSTALLING DOCKER DEPENDENCIES ====="
apt update
apt install apt-transport-https ca-certificates curl software-properties-common -y

##############################################
# Create Keyring and add Docker GPG to server's keyring
##############################################
echo "===== ADD DOCKER GPG KEYRING ====="
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc

##############################################
# Add latest Docker repository to APT
##############################################
echo "===== ADDING LATEST DOCKER REPOSITORY ====="
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update

##############################################
# Install Docker
##############################################
echo "===== INSTALLING DOCKER ====="
apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

##############################################
# Verify Docker Installation
##############################################
echo "===== VERIFYING DOCKER ====="
docker --version

##############################################
# Add user to Docker group
##############################################
echo "===== ADDING SUDO USER TO DOCKER GROUP ====="
usermod -aG docker $USER