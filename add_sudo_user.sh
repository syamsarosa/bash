#!/bin/bash

# Generate random password
PASSWORD=$(openssl rand -base64 12)

# Create user exactly like adduser does
# Replace your-username with your actual username
useradd -m -k /etc/skel -s /bin/bash -U your-username

# Set password
# Replace $PASSWORD with your preferred password
echo "your-username:$PASSWORD" | chpasswd

# Add to sudo group
usermod -aG sudo your-username

# Log password securely (optional)
echo "$PASSWORD" > /root/your-username.pass
chmod 600 /root/your-username.pass
