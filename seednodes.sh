#!/bin/bash

# ==================================================
#   _____  ______ ______  _____    _   _  ____  _____  ______  _____
#  / ____||  ____|  ____||  __ \  | \ | |/ __ \|  __ \|  ____||  __ \
# | (___  | |__  | |__   | |  | | |  \| | |  | | |  | | |__   | |__) |
#  \___ \ |  __| |  __|  | |  | | | . ` | |  | | |  | |  __|  |  _  /
#  ____) || |____| |____ | |__| | | |\  | |__| | |__| | |____ | | \ \
# |_____/ |______|______||_____/  |_| \_|\____/|_____/|______||_|  \_\
#
#             SEED NODES OFFICIAL SCRIPT
# ==================================================

# Ensure we are root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root!" 
   exit 1
fi

apt update -y
apt install -y figlet lolcat curl gnupg lsb-release apt-transport-https software-properties-common

clear
figlet "SEED NODES" | lolcat
echo "==============================" | lolcat
echo "     OFFICIAL SCRIPT          " | lolcat
echo "==============================" | lolcat
echo

# ============ SSL SETUP ============
read -p "Do you want to enable SSL (y/n)? " enable_ssl
if [[ "$enable_ssl" == "y" || "$enable_ssl" == "Y" ]]; then
    read -p "Enter your domain name (example.com): " domain

    apt install -y certbot python3-certbot-nginx

    echo "Setting up SSL for domain: $domain ..."
    certbot certonly --nginx -d $domain

    echo "SSL certificates installed for $domain ✅"
    echo
else
    echo "Skipping SSL setup..."
    echo
fi

# ============ MENU ============
echo "1) Enable Ports (UFW Firewall)"
echo "2) Install Pterodactyl Panel"
echo "3) Install Wings"
echo "4) Install Both Panel + Wings"
echo "5) Uninstall Pterodactyl"
echo "6) Uninstall Wings"
echo "7) Uninstall Both"
echo "8) Wipe Wings Data"
echo

read -p "Choose an option [1-8]: " option

# =================== CASE MENU ==================
case $option in
    1)
        echo "Configuring UFW firewall..."
        apt install -y ufw
        ufw allow 22
        ufw allow 80
        ufw allow 443
        ufw allow 2022
        ufw allow 5657
        ufw allow 56423
        ufw allow 3306
        ufw allow 8080
        ufw allow 19132
        ufw allow 25565:25590/tcp
        ufw allow 25565:25590/udp
        ufw enable
        echo "Firewall rules applied ✅"
        ;;
    2)
        echo "Installing Pterodactyl Panel..."
        apt install -y mariadb-server mariadb-client redis-server
        systemctl enable mariadb --now
        systemctl enable redis-server --now

        # Database setup
        read -p "Enter DB Password for pterodactyl user: " dbpass
        mariadb -u root <<MYSQL_SCRIPT
CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$dbpass';
CREATE DATABASE panel;
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT

        # Panel install
        curl -sSL https://getcomposer.org/installer | php
        mv composer.phar /usr/local/bin/composer
        apt install -y php8.1-cli php8.1-mysql php8.1-pgsql php8.1-gd \
           php8.1-mbstring php8.1-bcmath php8.1-curl php8.1-xml unzip tar
        mkdir -p /var/www/pterodactyl
        cd /var/www/pterodactyl
        curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
        tar -xzvf panel.tar.gz
        chmod -R 755 storage/* bootstrap/cache/
        cp .env.example .env
        composer install --no-dev --optimize-autoloader
        php artisan key:generate --force
        php artisan p:environment:setup
        php artisan p:environment:database
        php artisan migrate --seed --force
        echo "Panel installed ✅"
        ;;
    3)
        echo "Installing Wings..."
        curl -sSL https://get.docker.com/ | sh
        systemctl enable --now docker
        mkdir -p /etc/pterodactyl
        curl -Lo /usr/local/bin/wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
        chmod +x /usr/local/bin/wings
        echo "Wings installed ✅"
        ;;
    4)
        echo "Installing Both Panel + Wings..."
        $0 2
        $0 3
        ;;
    5)
        echo "Uninstalling Panel..."
        rm -rf /var/www/pterodactyl
        mariadb -u root -e "DROP DATABASE panel; DROP USER 'pterodactyl'@'127.0.0.1';"
        echo "Panel removed ✅"
        ;;
    6)
        echo "Uninstalling Wings..."
        systemctl stop wings
        rm -f /usr/local/bin/wings
        rm -rf /etc/pterodactyl
        echo "Wings removed ✅"
        ;;
    7)
        echo "Removing Both Panel + Wings..."
        $0 5
        $0 6
        ;;
    8)
        echo "Wiping Wings Data..."
        rm -rf /var/lib/pterodactyl
        echo "Wings data wiped ✅"
        ;;
    *)
        echo "Invalid option!"
        ;;
esac
