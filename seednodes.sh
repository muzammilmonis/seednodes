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

    # Setup nginx
    cat > /etc/nginx/sites-available/pterodactyl.conf <<EOL
server {
    listen 80;
    server_name $PANEL_DOMAIN;
    root /var/www/pterodactyl/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOL

    ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/
    nginx -t && systemctl restart nginx

    echo "========================================="
    echo "✅ Pterodactyl Panel Installed"
    echo "Domain   : https://$PANEL_DOMAIN"
    echo "Database : panel"
    echo "DB User  : pterodactyl"
    echo "DB Pass  : $DB_PASS"
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
