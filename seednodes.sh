#!/bin/bash

# ===============================================================
#   _____ ______ ______ _____    _   _  ____  _____  ______  _____ 
#  / ____|  ____|  ____|  __ \  | \ | |/ __ \|  __ \|  ____|/ ____|
# | (___ | |__  | |__  | |  | | |  \| | |  | | |  | | |__  | (___  
#  \___ \|  __| |  __| | |  | | | . ` | |  | | |  | |  __|  \___ \ 
#  ____) | |____| |____| |__| | | |\  | |__| | |__| | |____ ____) |
# |_____/|______|______|_____/  |_| \_|\____/|_____/|______|_____/ 
#                                                                  
#                       OFFICIAL SCRIPT                           
# ===============================================================

# ===== Colors =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SYSTEM_EMAIL="support@seednodes.fun"
TIMEZONE="Asia/Karachi"
ADMIN_USER="admin"
ADMIN_EMAIL="admin@seednodes.fun"

# ================= MENU ====================
clear
clear
echo "================================================================="
echo "   _____ ______ ______ _____    _   _  ____  _____  ______  _____ "
echo "  / ____|  ____|  ____|  __ \  | \ | |/ __ \|  __ \|  ____|/ ____|"
echo " | (___ | |__  | |__  | |  | | |  \| | |  | | |  | | |__  | (___  "
echo "  \___ \|  __| |  __| | |  | | | . \` | |  | | |  | |  __|  \___ \ "
echo "  ____) | |____| |____| |__| | | |\  | |__| | |__| | |____ ____) |"
echo " |_____/|______|______|_____/  |_| \_|\____/|_____/|______|_____/ "
echo "================================================================="
echo -e "${BLUE}=================================================================${NC}"
echo -e "${CYAN}   OFFICIAL SEEDNODES INSTALL SCRIPT${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""
echo -e "${YELLOW}1) Enable Ports (UFW Firewall)${NC}"
echo -e "${YELLOW}2) Install SSL Certificates (Certbot)${NC}"
echo -e "${YELLOW}3) Install Pterodactyl Panel${NC}"
echo -e "${YELLOW}4) Install Wings${NC}"
echo -e "${YELLOW}5) Install Both Panel + Wings${NC}"
echo -e "${RED}6) Uninstall Pterodactyl${NC}"
echo -e "${RED}7) Uninstall Wings${NC}"
echo -e "${RED}8) Uninstall Both${NC}"
echo -e "${RED}9) Wipe Wings Data${NC}"
echo -e "${GREEN}10) Exit${NC}"
echo -e "${BLUE}=================================================================${NC}"
read -rp "Choose an option [1-10]: " OPTION

# ============ FUNCTIONS ===============

enable_ports() {
    apt install ufw -y
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
    echo -e "${GREEN}✅ Firewall ports enabled.${NC}"
}

install_ssl() {
    read -rp "Enter domain for SSL: " PANEL_DOMAIN
    apt update
    apt install -y certbot python3-certbot-nginx
    certbot certonly --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos -m "$SYSTEM_EMAIL"
    echo -e "${GREEN}✅ SSL Certificate installed for $PANEL_DOMAIN${NC}"
}

install_panel() {
    read -rp "Enter domain for Pterodactyl Panel: " PANEL_DOMAIN
    read -rsp "Enter admin password for Panel: " ADMIN_PASS
    echo ""

    apt update
    apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
    apt update
    apt -y install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
    # Setup Database
    DB_PASS=$(openssl rand -base64 16)
    mysql -u root <<MYSQL_SCRIPT
CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
CREATE DATABASE panel;
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT

    # Setup Panel
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl || exit

        cat > /var/www/pterodactyl/.env <<EOL
APP_ENV=production
APP_DEBUG=false
APP_KEY=$APP_KEY
APP_THEME=pterodactyl
APP_TIMEZONE=$TIMEZONE
APP_URL=https://$PANEL_DOMAIN
APP_LOCALE=en
APP_ENVIRONMENT_ONLY=true

LOG_CHANNEL=daily
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=debug

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=panel
DB_USERNAME=pterodactyl
DB_PASSWORD=$DB_PASS

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

CACHE_DRIVER=file
QUEUE_CONNECTION=redis
SESSION_DRIVER=file

HASHIDS_SALT=
HASHIDS_LENGTH=8

MAIL_MAILER=smtp
MAIL_HOST=smtp.example.com
MAIL_PORT=25
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=$SYSTEM_EMAIL
MAIL_FROM_NAME="Pterodactyl Panel"
# You should set this to your domain to prevent it defaulting to 'localhost', causing
# mail servers such as Gmail to reject your mail.
#
# @see: https://github.com/pterodactyl/panel/pull/3110
# MAIL_EHLO_DOMAIN=panel.example.com
EOL
    
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
    php artisan key:generate --force

    php artisan migrate --seed --force

    chown -R www-data:www-data /var/www/pterodactyl/*

    # Create admin user
    php artisan p:user:make --email="$ADMIN_EMAIL" --username="$ADMIN_USER" --name="Admin" --password="$ADMIN_PASS" --admin=1

    # Remove old nginx default
    rm /etc/nginx/sites-enabled/default

    # Setup Pterodactyl Services
    cat > /etc/systemd/system/pteroq.service <<EOL
# Pterodactyl Queue Worker File
# ----------------------------------

[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
# On some systems the user and group might be different.
# Some systems use `apache` or `nginx` as the user and group.
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOL
    
    # Setup nginx
    cat > /etc/nginx/sites-available/pterodactyl.conf <<EOL
server {
    listen 80;
    server_name $PANEL_DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $PANEL_DOMAIN;

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    ssl_certificate /etc/letsencrypt/live/$PANEL_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$PANEL_DOMAIN/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
        include /etc/nginx/fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL

    sudo systemctl enable --now redis-server
    sudo systemctl enable --now pteroq.service

    ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    nginx -t && systemctl restart nginx

    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}✅ Pterodactyl Panel Installed${NC}"
    echo -e "Domain   : https://$PANEL_DOMAIN"
    echo -e "Admin    : $ADMIN_USER"
    echo -e "Email    : $ADMIN_EMAIL"
    echo -e "Password : $ADMIN_PASS"
    echo -e "${GREEN}=========================================${NC}"
}

install_wings() {
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    systemctl enable --now docker
    mkdir -p /etc/pterodactyl
    curl -L https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64 -o /usr/local/bin/wings
    chmod u+x /usr/local/bin/wings
    echo -e "${GREEN}✅ Wings installed.${NC}"
}

# ============= OPTIONS ==================
case $OPTION in
    1) enable_ports ;;
    2) install_ssl ;;
    3) install_panel ;;
    4) install_wings ;;
    5) install_panel && install_wings ;;
    6) rm -rf /var/www/pterodactyl /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf && echo -e "${RED}❌ Pterodactyl removed${NC}" ;;
    7) rm -rf /etc/pterodactyl /usr/local/bin/wings && echo -e "${RED}❌ Wings removed${NC}" ;;
    8) rm -rf /var/www/pterodactyl /etc/pterodactyl /usr/local/bin/wings && echo -e "${RED}❌ Panel + Wings removed${NC}" ;;
    9) rm -rf /var/lib/docker && echo -e "${RED}❌ Wings data wiped${NC}" ;;
    10) echo -e "${CYAN}Exiting...${NC}" ; exit 0 ;;
    *) echo -e "${RED}❌ Invalid option${NC}" ;;
esac
