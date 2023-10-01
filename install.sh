#!/bin/bash
# Prompt the user for custom fields

read -p "Enter your domain for Traefik: " TRAEFIK_DOMAIN
read -p "Enter your email for ACME: " ACME_MAIL

# Get the list of valid timezones
valid_timezones=$(timedatectl list-timezones)

# Prompt the user to enter the timezone
read -p "Enter your timezone (e.g. America/Denver): " TZ

# Check if the entered timezone is valid
while ! echo "$valid_timezones" | grep -q "^$TZ$"; do
    echo "Invalid timezone entered."
    read -p "Would you like to view the list of valid timezones? (yes/no): " view_list
    if [ "$view_list" == "yes" ]; then
        echo -e "\n$valid_timezones\n"
    fi
    read -p "Please enter a valid timezone: " TZ
done

read -p "Enter HTTP username: " HTTP_USER
echo "Note: Password input will be hidden for security reasons."
read -s -p "Enter HTTP password: " HTTP_PASSWORD
echo

# Ask user if they want to set unique passwords for each service
read -p "Would you like to set unique passwords for each service? (yes/no): " unique_passwords
echo

if [ "$unique_passwords" == "yes" ]; then
    read -s -p "Enter MySQL root password: " MYSQL_ROOT_PASSWORD
    echo
    read -p "Enter MySQL database name (e.g. nextcloud): " MYSQL_DATABASE
    read -p "Enter MySQL user: " MYSQL_USER
    read -s -p "Enter MySQL password: " MYSQL_PASSWORD
    echo
    read -p "Enter Nextcloud admin user: " NEXTCLOUD_ADMIN_USER
    read -s -p "Enter Nextcloud admin password: " NEXTCLOUD_ADMIN_PASSWORD
    echo
    read -s -p "Enter Portainer admin password: " PORTAINER_ADMIN_PASSWORD
    echo
    read -s -p "Enter Flood password for Deluge RPC daemon: " FLOOD_PASSWORD
    echo
    read -s -p "Enter Calibre password: " CALIBRE_PASSWORD
    echo

else
    read -s -p "Enter a common password for all services: " common_password
    echo
    MYSQL_ROOT_PASSWORD=$common_password
    MYSQL_DATABASE="nextcloud"
    MYSQL_USER="nextcloud"
    MYSQL_PASSWORD=$common_password
    NEXTCLOUD_ADMIN_USER="admin"
    NEXTCLOUD_ADMIN_PASSWORD=$common_password
    PORTAINER_ADMIN_PASSWORD=$common_password
    FLOOD_PASSWORD=$common_password
    CALIBRE_PASSWORD=$common_password
fi

# Warning for WireGuard setup
echo "Warning: If you would like to set up WireGuard, please ensure you have your private and public keys available."

read -p "Enter WireGuard endpoint: " WIREGUARD_ENDPOINT
read -p "Enter WireGuard port: " WIREGUARD_PORT
read -p "Enter WireGuard public key: " WIREGUARD_PUBLIC_KEY
read -s -p "Enter WireGuard private key: " WIREGUARD_PRIVATE_KEY
echo

# Define the content of the .env file using the user's input
env_content="
CHECK_FOR_OUTDATED_CONFIG=true
DOCKER_COMPOSE_BINARY=\"docker compose\"
TRAEFIK_DOMAIN=${TRAEFIK_DOMAIN}
ACME_MAIL=${ACME_MAIL}
TZ=\"${TZ}\"
HTTP_USER=${HTTP_USER}
HTTP_PASSWORD='${HTTP_PASSWORD}'
HOST_CONFIG_PATH=\"/data/config\"
HOST_MEDIA_PATH=\"/data/torrents\"
DOWNLOAD_SUBFOLDER=\"deluge\"
PGID=1000
PUID=1000
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_DATABASE=${MYSQL_DATABASE}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER}
NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD}
PORTAINER_ADMIN_PASSWORD=${PORTAINER_ADMIN_PASSWORD}
FLOOD_PASSWORD=${FLOOD_PASSWORD}
FLOOD_AUTOCREATE_USER_IN_DELUGE_DAEMON=false
CALIBRE_PASSWORD=${CALIBRE_PASSWORD}
WIREGUARD_ENDPOINT=${WIREGUARD_ENDPOINT}
WIREGUARD_PORT=${WIREGUARD_PORT}
WIREGUARD_PUBLIC_KEY=${WIREGUARD_PUBLIC_KEY}
WIREGUARD_PRIVATE_KEY=${WIREGUARD_PRIVATE_KEY}
WIREGUARD_ADDRESS=10.0.0.1/24
"

# Write the content to the .env file in the current directory
echo "$env_content" > .env

# Output a message indicating that the .env file has been created
echo "The .env file has been created with the specified content."

# Update the package list and install dependencies
sudo apt update
sudo apt install -y curl jq apt-transport-https ca-certificates curl software-properties-common

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Add current user to docker group
sudo usermod -aG docker $USER
echo "User added to docker group. Please log out and log back in for the changes to take effect."

# Install Docker Compose
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.tag_name')
if [ -z "$COMPOSE_VERSION" ]; then
    echo "Failed to get the latest Docker Compose version. Exiting."
    exit 1
fi

COMPOSE_URL="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
echo "Downloading Docker Compose from $COMPOSE_URL"

# Download Docker Compose binary and make it executable
sudo curl -L "$COMPOSE_URL" -o /usr/local/bin/docker-compose
if [ $? -ne 0 ]; then
    echo "Failed to download Docker Compose. Exiting."
    exit 1
fi

# Print debug information about the downloaded file
echo "Debug Information:"
ls -l /usr/local/bin/docker-compose
file /usr/local/bin/docker-compose

# Check if the downloaded file has a non-zero size
if [ ! -s /usr/local/bin/docker-compose ]; then
    echo "The downloaded file is empty. Exiting."
    sudo rm /usr/local/bin/docker-compose
    exit 1
fi

# Check if the downloaded file is a binary
if ! file /usr/local/bin/docker-compose | grep -q "executable"; then
    echo "The downloaded file is not a valid binary. Exiting."
    sudo rm /usr/local/bin/docker-compose
    exit 1
fi

sudo chmod +x /usr/local/bin/docker-compose
if [ $? -ne 0 ]; then
    echo "Failed to make Docker Compose executable. Exiting."
    exit 1
fi

# Verify the installation
docker-compose --version
if [ $? -ne 0 ]; then
    echo "Docker Compose is not correctly installed. Exiting."
    exit 1
fi

# Install yq using the latest version URL
sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq

# Download and run the local-persist installation script
LOCAL_PERSIST_INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/MatchbookLab/local-persist/v1.3.0/scripts/install.sh"
curl -fsSL "$LOCAL_PERSIST_INSTALL_SCRIPT_URL" -o local-persist-install.sh
chmod +x local-persist-install.sh
sudo ./local-persist-install.sh

# Remove the installation script after running it
rm local-persist-install.sh

# Create necessary directories
sudo mkdir -p /data/config /data/torrents

# Get the absolute path to the seedbox directory
SEEDBOX_DIR=$(pwd)

# Run init.sh from the current directory with sudo
sudo bash init.sh

# Run run-seedbox.sh
