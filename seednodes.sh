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

SYSTEM_EMAIL="support@seednodes.fun"
TIMEZONE="Asia/Karachi"
ADMIN_USER="admin"
ADMIN_EMAIL="admin@seednodes.fun"

# ================= MENU ====================
clear
echo "================================================================="
echo "   _____ ______ ______ _____    _   _  ____  _____  ______  _____ "
echo "  / ____|  ____|  ____|  __ \  | \ | |/ __ \|  __ \|  ____|/ ____|"
echo " | (___ | |__  | |__  | |  | | |  \| | |  | | |  | | |__  | (___  "
echo "  \___ \|  __| |  __| | |  | | | . \` | |  | | |  | |  __|  \___ \ "
echo "  ____) | |____| |____| |__| | | |\  | |__| | |__| | |____ ____) |"
echo " |_____/|______|______|_____/  |_| \_|\____/|_____/|______|_____/ "
echo "================================================================="
echo "                      OFFICIAL SCRIPT"
echo "================================================================="
echo ""
echo ""
echo "1) Enable Ports (UFW Firewall)"
echo "2) Install SSL Certificates (Certbot)"
echo "3) Install Pterodactyl Panel"
echo "4) Install Wings"
echo "5) Install Both Panel + Wings"
echo "6) Uninstall Pterodactyl"
echo "7) Uninstall Wings"
echo "8) Uninstall Both"
echo "9) Wipe Wings Data"
echo "10) Exit"
echo "============================================"
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
    echo "✅ Firewall ports enabled."
}

install_ssl() {
    read -rp "Enter domain for SSL: " PANEL_DOMAIN
    apt update
    apt install -y certbot python3-certbot-nginx
    certbot certonly --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos -m "$SYSTEM_EMAIL"
    echo "✅ SSL Certificate installed for $PANEL_DOMAIN"
}

install_panel() {
    read -rp "Enter domain for Pterodactyl Panel: " PANEL_DOMAIN
    read -rsp "Enter admin password for Panel: " ADMIN_PASS
    echo ""

    apt update
    apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
    add-apt-repository -y ppa:ondrej/php
    apt update
    apt -y install php8.1 php8.1-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,curl,common,zip}
    apt -y install mariadb-server mariadb-client redis-server nginx tar unzip git
    curl -sL https://deb.nodesource.com/setup_20.x | bash -
    apt -y install nodejs
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer

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
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
    cp .env.example .env
    composer install --no-dev --optimize-autoloader
    php artisan key:generate --force

    # Auto setup environment file
    sed -i "s|APP_URL=.*|APP_URL=https://$PANEL_DOMAIN|" .env
    sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_PASS|" .env
    sed -i "s|DB_DATABASE=.*|DB_DATABASE=panel|" .env
    sed -i "s|DB_USERNAME=.*|DB_USERNAME=pterodactyl|" .env
    sed -i "s|APP_TIMEZONE=.*|APP_TIMEZONE=$TIMEZONE|" .env
    sed -i "s|MAIL_FROM_ADDRESS=.*|MAIL_FROM_ADDRESS=$SYSTEM_EMAIL|" .env

    php artisan migrate --seed --force

    # Create admin user
    php artisan p:user:make --email="$ADMIN_EMAIL" --username="$ADMIN_USER" --name="Admin" --password="$ADMIN_PASS" --admin=1

    # Remove old nginx
    rm /etc/nginx/sites-enabled/default
    # Setup nginx
    cat > /etc/nginx/sites-available/pterodactyl.conf <<EOL
server {
    # Replace the example <domain> with your domain name or IP address
    listen 80;
    server_name $PANEL_DOMAIN;
    return 301 https://$server_name$request_uri;
}

server {
    # Replace the example <domain> with your domain name or IP address
    listen 443 ssl http2;
    server_name $PANEL_DOMAIN;

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    # allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    # SSL Configuration - Replace the example <domain> with your domain
    ssl_certificate /etc/letsencrypt/live/$PANEL_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$PANEL_DOMAIN/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    # See https://hstspreload.org/ before uncommenting the line below.
    # add_header Strict-Transport-Security "max-age=15768000; preload;";
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
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

    ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    nginx -t && systemctl restart nginx

    echo "========================================="
    echo "✅ Pterodactyl Panel Installed"
    echo "Domain   : https://$PANEL_DOMAIN"
    echo "Admin    : $ADMIN_USER"
    echo "Email    : $ADMIN_EMAIL"
    echo "Password : $ADMIN_PASS"
    echo "========================================="
}

install_wings() {
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    systemctl enable --now docker
    mkdir -p /etc/pterodactyl
    curl -L https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64 -o /usr/local/bin/wings
    chmod u+x /usr/local/bin/wings
    echo "✅ Wings installed."
}

# ============= OPTIONS ==================
case $OPTION in
    1) enable_ports ;;
    2) install_ssl ;;
    3) install_panel ;;
    4) install_wings ;;
    5) install_panel && install_wings ;;
    6) rm -rf /var/www/pterodactyl /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf ;;
    7) rm -rf /etc/pterodactyl /usr/local/bin/wings ;;
    8) rm -rf /var/www/pterodactyl /etc/pterodactyl /usr/local/bin/wings ;;
    9) rm -rf /var/lib/docker ;;
    10) exit 0 ;;
    *) echo "❌ Invalid option" ;;
esac
