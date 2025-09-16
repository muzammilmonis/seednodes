#!/bin/bash

# ==================================================
#   _____  ______ ______  _____    _   _  ____  _____  ______  _____ 
#  / ____||  ____|  ____||  __ \  | \ | |/ __ \|  __ \|  ____||  __ \
# | (___  | |__  | |__   | |  | | |  \| | |  | | |  | | |__   | |__) |
#  \___ \ |  __| |  __|  | |  | | | . ` | |  | | |  | |  __|  |  _  /
#  ____) || |____| |____ | |__| | | |\  | |__| | |__| | |____ | | \ \
# |_____/ |______|______||_____/  |_| \_|\____/|______||_|  \_\
#
#             SEED NODES OFFICIAL SCRIPT
#     Installer: https://install.seednodes.fun
# ==================================================

set -e

# ensure root
if [[ $EUID -ne 0 ]]; then
    echo "Run this script as root (or with sudo)."
    exit 1
fi

# ------------ Functions ------------

ssl_setup() {
    read -p "Enter domain for SSL (e.g. panel.yourdomain.com): " ssl_domain
    apt update
    apt install -y certbot python3-certbot-nginx
    certbot --nginx -d "$ssl_domain"
    echo "SSL set up at domain: $ssl_domain"
}

install_panel() {
    echo "Installing Pterodactyl Panel..."
    # Official dependencies from docs :contentReference[oaicite:0]{index=0}
    apt update -y
    apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg

    # Add PHP repo
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php

    # Add Redis repo
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list

    apt update -y

    # Install PHP, MariaDB, Nginx, Redis etc :contentReference[oaicite:1]{index=1}
    apt install -y php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} \
        mariadb-server nginx tar unzip git redis-server

    # Composer
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    # Create panel folder
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl

    # Download panel
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage bootstrap/cache

    # Database setup
    read -p "Enter password for DB user 'pterodactyl': " panel_db_pass
    mysql -u root <<MYSQL_SCRIPT
CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${panel_db_pass}';
CREATE DATABASE panel;
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT

    # .env and Laravel artisan
    cp .env.example .env
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
    php artisan key:generate --force

    # Prompt for Nginx + SSL
    read -p "Enter domain for Panel (e.g. panel.yourdomain.com), or press enter to skip Nginx config: " panel_domain
    if [[ -n "$panel_domain" ]]; then
        # Create Nginx config
        cat <<EOF > /etc/nginx/sites-available/pterodactyl.conf
server {
    listen 80;
    server_name ${panel_domain};

    root /var/www/pterodactyl/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF
        ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/
        systemctl reload nginx

        # Ask SSL
        read -p "Do you want to enable SSL for ${panel_domain}? (y/n): " ssl_choice
        if [[ "$ssl_choice" == "y" || "$ssl_choice" == "Y" ]]; then
            ssl_setup
        fi
    fi

    echo "Pterodactyl Panel installation completed."
}

install_wings() {
    echo "Installing Pterodactyl Wings..."
    # Official commands from docs :contentReference[oaicite:2]{index=2}

    # Install Docker
    curl -sSL https://get.docker.com/ | bash
    systemctl enable --now docker

    # Create directory for Wings
    mkdir -p /etc/pterodactyl

    # Download wings binary
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        W_ARCH="amd64"
    else
        W_ARCH="arm64"
    fi
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${W_ARCH}"
    chmod +x /usr/local/bin/wings

    # Wings systemd service
    cat <<EOF > /etc/systemd/system/wings.service
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now wings

    echo "Pterodactyl Wings installation completed."
}

uninstall_panel() {
    echo "Uninstalling Panel..."
    systemctl stop nginx || true
    rm -rf /var/www/pterodactyl
    rm /etc/nginx/sites-available/pterodactyl.conf || true
    rm /etc/nginx/sites-enabled/pterodactyl.conf || true
    nginx -t && systemctl reload nginx || true
    echo "Panel removed."
}

uninstall_wings() {
    echo "Uninstalling Wings..."
    systemctl stop wings || true
    systemctl disable wings || true
    rm -f /usr/local/bin/wings
    rm -rf /etc/pterodactyl
    echo "Wings removed."
}

wipe_wings_data() {
    echo "Wiping Wings data (/var/lib/pterodactyl)..."
    systemctl stop wings || true
    rm -rf /var/lib/pterodactyl
    echo "Data wiped."
}

enable_ports() {
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
    ufw --force enable
    echo "Ports enabled."
}

show_banner() {
    clear
    echo "======================================"
    echo "        SEED NODES OFFICIAL SCRIPT     "
    echo "======================================"
}

# ------------ Main Menu ------------
while true; do
    show_banner
    echo "1) Enable Ports (UFW Firewall)"
    echo "2) Install Pterodactyl Panel"
    echo "3) Install Wings"
    echo "4) Install Both Panel + Wings"
    echo "5) Uninstall Panel"
    echo "6) Uninstall Wings"
    echo "7) Uninstall Both"
    echo "8) Wipe Wings Data"
    echo "9) Exit"
    echo
    read -p "Choose [1-9]: " choice
    case $choice in
        1) enable_ports ;;
        2) install_panel ;;
        3) install_wings ;;
        4) install_panel; install_wings ;;
        5) uninstall_panel ;;
        6) uninstall_wings ;;
        7) uninstall_panel; uninstall_wings ;;
        8) wipe_wings_data ;;
        9) echo "Goodbye."; exit 0 ;;
        *) echo "Invalid choice."; sleep 2 ;;
    esac
done
