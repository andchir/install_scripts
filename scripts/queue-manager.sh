#!/bin/bash

#===============================================================================
#
#   Queue Manager - Automated Installation Script
#   For Ubuntu 24.04 LTS
#
#   This script automatically installs and configures:
#   - Git, Python 3, MySQL, Nginx, Certbot
#   - Clones the queue-manager repository
#   - Sets up Python virtual environment with all dependencies
#   - Configures MySQL database
#   - Creates systemd services for Gunicorn (FastAPI) startup
#   - Optionally sets up WebSocket server with supervisor (if second domain provided)
#   - Configures Nginx as reverse proxy
#   - Obtains SSL certificate via Let's Encrypt
#
#   Repository: https://github.com/andchir/queue-manager
#
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# Color definitions for beautiful output
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# Configuration variables
#-------------------------------------------------------------------------------
REPO_URL="https://github.com/andchir/queue-manager.git"
APP_NAME="queue-manager"
SERVICE_NAME="queue_manager_server"
SOCKET_PATH="/run/queue_manager_gunicorn.sock"
PYTHON_VERSION="python3"
INSTALLER_USER="installer_user"
WS_SERVICE_NAME="queue-websocket"
WS_PORT="8765"

# These will be set after user setup
CURRENT_USER=""
HOME_DIR=""
INSTALL_DIR=""
VENV_DIR=""
DOMAIN_NAME=""
WS_DOMAIN_NAME=""

#-------------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------------

show_usage() {
    echo "Usage: $0 <domain_name> [websocket_domain_name]"
    echo ""
    echo "Arguments:"
    echo "  domain_name             The main domain for the Queue Manager API (e.g., queue.example.com)"
    echo "  websocket_domain_name   Optional: domain for WebSocket server with SSL (e.g., ws.queue.example.com)"
    echo ""
    echo "Example:"
    echo "  $0 queue.example.com"
    echo "  $0 queue.example.com ws.queue.example.com"
    echo ""
    echo "Note: This script must be run as root or with sudo."
    exit 1
}

validate_domain() {
    local domain="$1"
    # Basic domain validation regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        print_info "Please enter a valid domain (e.g., queue.example.com)"
        exit 1
    fi
}

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}${WHITE}$1${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}➜${NC} ${WHITE}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✔${NC} ${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} ${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}✖${NC} ${RED}$1${NC}"
}

print_info() {
    echo -e "${MAGENTA}ℹ${NC} ${WHITE}$1${NC}"
}

generate_password() {
    # Generate a secure random password
    openssl rand -base64 24 | tr -d '/+=' | head -c 20
}

generate_uuid() {
    # Generate a UUID for API key
    python3 -c "import uuid; print(str(uuid.uuid4()))"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root!"
        print_info "Run with: sudo $0 <domain_name> [websocket_domain_name]"
        exit 1
    fi
}

setup_installer_user() {
    print_header "Setting Up Installer User"

    # Check if installer_user already exists
    if id "$INSTALLER_USER" &>/dev/null; then
        print_info "User '$INSTALLER_USER' already exists"
    else
        print_step "Creating user '$INSTALLER_USER'..."
        useradd -m -s /bin/bash "$INSTALLER_USER"
        print_success "User '$INSTALLER_USER' created"
    fi

    # Add user to sudo group for necessary operations
    print_step "Adding '$INSTALLER_USER' to sudo group..."
    usermod -aG sudo "$INSTALLER_USER"
    print_success "User added to sudo group"

    # Set up variables for the installer user
    CURRENT_USER="$INSTALLER_USER"
    HOME_DIR=$(eval echo ~$INSTALLER_USER)
    INSTALL_DIR="$HOME_DIR/$APP_NAME"
    VENV_DIR="$INSTALL_DIR/venv"

    print_success "Installer user configured: $INSTALLER_USER"
    print_info "Home directory: $HOME_DIR"
    print_info "Installation directory: $INSTALL_DIR"
}

check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        print_warning "This script is designed for Ubuntu. Proceed with caution on other distributions."
    fi
}

#-------------------------------------------------------------------------------
# Main installation functions
#-------------------------------------------------------------------------------

show_banner() {
    clear
    echo ""
    echo -e "${CYAN}   ╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${BOLD}${WHITE}Queue Manager${NC}                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${MAGENTA}Automated Installation Script for Ubuntu 24.04${NC}                         ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${WHITE}This script will install and configure:${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Git, Python 3, MySQL Server, Nginx, Certbot                          ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} FastAPI application with Gunicorn                                    ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Optional WebSocket server with Supervisor                            ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} Systemd services for auto-start                                      ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}   ${GREEN}•${NC} SSL certificate via Let's Encrypt                                    ${CYAN}║${NC}"
    echo -e "${CYAN}   ║${NC}                                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}   ╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

parse_arguments() {
    # Check if domain name argument is provided
    if [[ $# -lt 1 ]] || [[ -z "$1" ]]; then
        print_error "Domain name is required!"
        show_usage
    fi

    DOMAIN_NAME="$1"
    validate_domain "$DOMAIN_NAME"

    print_header "Domain Configuration"
    print_success "Main domain configured: $DOMAIN_NAME"

    # Check for optional WebSocket domain
    if [[ $# -ge 2 ]] && [[ -n "$2" ]]; then
        WS_DOMAIN_NAME="$2"
        validate_domain "$WS_DOMAIN_NAME"
        print_success "WebSocket domain configured: $WS_DOMAIN_NAME"
        print_info "WebSocket server will be installed with SSL certificate"
    else
        print_info "No WebSocket domain provided - WebSocket server will not be configured"
    fi
}

install_dependencies() {
    print_header "Installing System Dependencies"

    # Set non-interactive mode for all package installations
    export DEBIAN_FRONTEND=noninteractive

    print_step "Updating package lists..."
    apt-get update -qq
    print_success "Package lists updated"

    print_step "Installing Git..."
    apt-get install -y -qq git > /dev/null 2>&1
    print_success "Git installed"

    print_step "Installing Python 3 and development tools..."
    apt-get install -y -qq python3 python3-pip python3-venv python3-dev > /dev/null 2>&1
    print_success "Python 3 installed"

    print_step "Installing MySQL Server..."
    apt-get install -y -qq mysql-server libmysqlclient-dev pkg-config > /dev/null 2>&1
    print_success "MySQL Server installed"

    print_step "Installing Nginx..."
    apt-get install -y -qq nginx > /dev/null 2>&1
    print_success "Nginx installed"

    print_step "Installing Certbot for SSL certificates..."
    apt-get install -y -qq certbot python3-certbot-nginx > /dev/null 2>&1
    print_success "Certbot installed"

    print_step "Installing additional dependencies..."
    apt-get install -y -qq build-essential libffi-dev libssl-dev curl wget > /dev/null 2>&1
    print_success "Additional dependencies installed"

    print_step "Installing FFmpeg..."
    apt-get install -y -qq ffmpeg > /dev/null 2>&1
    print_success "FFmpeg installed"

    # Install supervisor if WebSocket domain is specified
    if [[ -n "$WS_DOMAIN_NAME" ]]; then
        print_step "Installing Supervisor for WebSocket server..."
        apt-get install -y -qq supervisor > /dev/null 2>&1
        print_success "Supervisor installed"
    fi

    print_success "All system dependencies installed successfully!"
}

clone_repository() {
    print_header "Setting Up Repository"

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        print_info "Repository already exists at $INSTALL_DIR"
        print_step "Discarding local changes..."
        su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && git checkout ." > /dev/null 2>&1
        print_success "Local changes discarded"
        print_step "Pulling latest updates..."
        su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && git pull" > /dev/null 2>&1
        print_success "Repository updated successfully"
    else
        if [[ -d "$INSTALL_DIR" ]]; then
            print_warning "Directory $INSTALL_DIR exists but is not a git repository."
            print_step "Backing up existing directory..."
            mv "$INSTALL_DIR" "${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
            print_success "Backup created"
        fi

        print_step "Cloning repository to $INSTALL_DIR..."
        su - "$CURRENT_USER" -c "git clone '$REPO_URL' '$INSTALL_DIR'" > /dev/null 2>&1
        print_success "Repository cloned successfully"
    fi

    cd "$INSTALL_DIR"
    print_info "Working directory: $INSTALL_DIR"
}

setup_python_environment() {
    print_header "Setting Up Python Virtual Environment"

    if [[ -d "$VENV_DIR" ]]; then
        print_info "Virtual environment already exists at $VENV_DIR"
        print_step "Using existing virtual environment..."
    else
        print_step "Creating virtual environment..."
        su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && $PYTHON_VERSION -m venv '$VENV_DIR'" > /dev/null 2>&1
        print_success "Virtual environment created"
    fi

    print_step "Upgrading pip..."
    su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && source '$VENV_DIR/bin/activate' && pip install --upgrade pip" > /dev/null 2>&1
    print_success "Pip upgraded"

    print_step "Installing/updating Python dependencies (this may take a few minutes)..."
    su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && source '$VENV_DIR/bin/activate' && pip install -r requirements.txt" > /dev/null 2>&1
    print_success "All Python dependencies installed/updated"
}

configure_mysql() {
    print_header "Configuring MySQL Database"

    DB_NAME="queue_manager"
    DB_USER="queue_manager_user"

    print_step "Starting MySQL service..."
    systemctl start mysql
    systemctl enable mysql > /dev/null 2>&1
    print_success "MySQL service started"

    print_step "Checking if database '$DB_NAME' exists..."
    if mysql -e "USE $DB_NAME" 2>/dev/null; then
        print_info "Database '$DB_NAME' already exists"
    else
        print_step "Creating database '$DB_NAME'..."
        mysql -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        print_success "Database created"
    fi

    print_step "Checking if database user '$DB_USER' exists..."
    USER_EXISTS=$(mysql -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = '$DB_USER' AND host = 'localhost');")
    if [[ "$USER_EXISTS" == "1" ]]; then
        print_info "Database user '$DB_USER' already exists"
        print_warning "Existing database user password will NOT be changed to protect existing applications."
        print_info "If this application cannot connect to the database,"
        print_info "please manually update the password or provide existing credentials in the .env file."
        # Generate a placeholder password for the summary - actual connection will use .env file
        DB_PASSWORD="(existing user - check .env file)"
    else
        DB_PASSWORD=$(generate_password)
        print_step "Creating database user '$DB_USER'..."
        mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
        print_success "Database user created"
    fi

    print_step "Granting privileges..."
    mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    print_success "Database privileges granted"

    # Save credentials for later use
    export DB_NAME DB_USER DB_PASSWORD
}

create_env_file() {
    print_header "Creating Environment Configuration"

    # Check if .env file already exists
    if [[ -f "$INSTALL_DIR/.env" ]]; then
        print_info ".env file already exists at $INSTALL_DIR/.env"
        print_step "Skipping .env file creation to preserve existing configuration..."
        print_success "Using existing .env file"

        # Read existing API key from .env for later use
        if [[ -f "$INSTALL_DIR/.env" ]]; then
            API_KEY=$(grep "^API_KEYS=" "$INSTALL_DIR/.env" | cut -d'=' -f2)
            export API_KEY
        fi
        return
    fi

    # Check if database user exists but we don't have the password
    # This can happen if user was created previously but .env was deleted
    if [[ "$DB_PASSWORD" == "(existing user - check .env file)" ]]; then
        print_error "Database user '$DB_USER' exists but no .env file found with credentials."
        print_info "Please manually create $INSTALL_DIR/.env with the correct MYSQL_CONNECTION_STRING"
        print_info "Or reset the database user password in MySQL and create the .env file."
        print_info ""
        print_info "Example .env file content:"
        print_info "  MYSQL_CONNECTION_STRING=$DB_USER:<password>@localhost/$DB_NAME?charset=utf8mb4"
        exit 1
    fi

    API_KEY=$(generate_uuid)

    # Determine if WebSocket should be enabled
    if [[ -n "$WS_DOMAIN_NAME" ]]; then
        WS_ENABLED="true"
    else
        WS_ENABLED="false"
    fi

    print_step "Creating .env file..."

    # Create .env file using .env-dest as template
    cat > "$INSTALL_DIR/.env" << EOF
APP_NAME=Queue Manager
APP_SERVER_NAME=$DOMAIN_NAME
ADMIN_EMAIL=admin@$DOMAIN_NAME
API_KEYS=$API_KEY
USE_TASK_API_KEYS=False
SQLITE_DB_NAME=app_database.db
MYSQL_CONNECTION_STRING=$DB_USER:$DB_PASSWORD@localhost/$DB_NAME?charset=utf8mb4
MAX_EXECUTION_TIME=14400
MAX_STORE_TIME=43200
WS_ENABLED=$WS_ENABLED
WS_PORT=$WS_PORT
GDRIVE_FOLDER_ID=
YADISK_TOKEN=
TG_BOT_TOKEN=
TG_CHAT_ID=
EOF

    chown "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR/.env"
    chmod 600 "$INSTALL_DIR/.env"
    print_success ".env file created with secure permissions"

    print_info "Database credentials saved in .env file"

    # Save API key for summary
    export API_KEY
}

setup_alembic() {
    print_header "Setting Up Database Migrations"

    print_step "Copying alembic configuration..."
    if [[ -f "$INSTALL_DIR/alembic.ini-dest" ]]; then
        if [[ ! -f "$INSTALL_DIR/alembic.ini" ]]; then
            su - "$CURRENT_USER" -c "cp '$INSTALL_DIR/alembic.ini-dest' '$INSTALL_DIR/alembic.ini'"
            print_success "Alembic configuration copied"
        else
            print_info "Alembic configuration already exists"
        fi
    else
        print_warning "alembic.ini-dest not found, skipping alembic configuration"
    fi

    print_step "Running database migrations..."
    su - "$CURRENT_USER" -c "cd '$INSTALL_DIR' && source '$VENV_DIR/bin/activate' && alembic upgrade head" > /dev/null 2>&1 || {
        print_warning "Database migrations failed or no migrations to run"
        print_info "You may need to run migrations manually: alembic upgrade head"
    }
    print_success "Database migrations completed"

    # Create index for performance
    print_step "Creating database index for queue UUID..."
    mysql -e "USE $DB_NAME; CREATE INDEX IF NOT EXISTS queue_uuid ON queue(uuid);" 2>/dev/null || {
        print_info "Index already exists or table not yet created"
    }
    print_success "Database optimization completed"
}

create_systemd_service() {
    print_header "Creating Systemd Service"

    print_step "Creating socket file..."

    tee /etc/systemd/system/${SERVICE_NAME}.socket > /dev/null << EOF
[Unit]
Description=gunicorn socket for $APP_NAME

[Socket]
ListenStream=$SOCKET_PATH
SocketUser=www-data
SocketMode=600

[Install]
WantedBy=sockets.target
EOF

    print_success "Socket file created"

    print_step "Creating service file..."

    tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=gunicorn daemon for $APP_NAME
Requires=${SERVICE_NAME}.socket
After=network.target

[Service]
User=$CURRENT_USER
Group=www-data
WorkingDirectory=$INSTALL_DIR
ExecStart=$VENV_DIR/bin/gunicorn \\
          --access-logfile - \\
          --error-logfile '$INSTALL_DIR/gunicorn-errors.txt' \\
          --timeout 120 \\
          --workers 3 \\
          --worker-class uvicorn.workers.UvicornWorker \\
          --bind unix:$SOCKET_PATH \\
          main:app

[Install]
WantedBy=multi-user.target
EOF

    print_success "Service file created"

    print_step "Reloading systemd daemon..."
    systemctl daemon-reload
    print_success "Systemd daemon reloaded"

    print_step "Enabling and starting socket..."
    systemctl enable ${SERVICE_NAME}.socket > /dev/null 2>&1
    systemctl start ${SERVICE_NAME}.socket
    print_success "Socket enabled and started"

    # Check if service already exists and is active, then restart; otherwise start
    if systemctl is-active --quiet ${SERVICE_NAME}.service; then
        print_step "Service already running, restarting..."
        systemctl restart ${SERVICE_NAME}.service
        print_success "Service restarted"
    else
        print_step "Starting service..."
        systemctl start ${SERVICE_NAME}.service
        print_success "Service started"
    fi
}

setup_websocket_server() {
    # Only setup if WebSocket domain is provided
    if [[ -z "$WS_DOMAIN_NAME" ]]; then
        return
    fi

    print_header "Setting Up WebSocket Server"

    print_step "Creating Supervisor configuration for WebSocket server..."

    tee /etc/supervisor/conf.d/$WS_SERVICE_NAME.conf > /dev/null << EOF
[program:$WS_SERVICE_NAME]
command=$VENV_DIR/bin/python $INSTALL_DIR/web/server.py
directory=$INSTALL_DIR
user=$CURRENT_USER
autostart=true
autorestart=true
stderr_logfile=/var/log/$WS_SERVICE_NAME.err.log
stdout_logfile=/var/log/$WS_SERVICE_NAME.out.log
stderr_logfile_maxbytes=100MB
stdout_logfile_maxbytes=100MB
environment=PATH="$VENV_DIR/bin"
EOF

    print_success "Supervisor configuration created"

    print_step "Reloading Supervisor..."
    supervisorctl reread > /dev/null 2>&1
    supervisorctl update > /dev/null 2>&1
    print_success "Supervisor reloaded"

    # Start or restart the WebSocket server
    if supervisorctl status $WS_SERVICE_NAME 2>/dev/null | grep -q "RUNNING"; then
        print_step "WebSocket server already running, restarting..."
        supervisorctl restart $WS_SERVICE_NAME > /dev/null 2>&1
        print_success "WebSocket server restarted"
    else
        print_step "Starting WebSocket server..."
        supervisorctl start $WS_SERVICE_NAME > /dev/null 2>&1
        print_success "WebSocket server started"
    fi

    print_info "WebSocket server running on port $WS_PORT"
}

configure_nginx() {
    print_header "Configuring Nginx for Main Domain"

    # Check if SSL certificate already exists - if so, skip nginx configuration
    # to preserve the existing HTTPS configuration created by certbot
    if [[ -d "/etc/letsencrypt/live/$DOMAIN_NAME" ]]; then
        print_info "SSL certificate for $DOMAIN_NAME already exists"
        print_step "Skipping Nginx configuration to preserve existing HTTPS settings..."
        print_success "Using existing Nginx configuration"
        return
    fi

    print_step "Creating Nginx configuration..."

    tee /etc/nginx/sites-available/$DOMAIN_NAME > /dev/null << EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;

    access_log /var/log/nginx/${DOMAIN_NAME}_access.log;
    error_log /var/log/nginx/${DOMAIN_NAME}_error.log;

    # Redirect HTTP to HTTPS (will be enabled after SSL setup)
    # return 301 https://\$server_name\$request_uri;

    location = /favicon.ico {
        access_log off;
        log_not_found off;
    }

    location /static/ {
        alias $INSTALL_DIR/static/;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:$SOCKET_PATH;
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }

    client_max_body_size 100M;
}
EOF

    print_success "Nginx configuration created"

    print_step "Enabling site..."
    ln -sf /etc/nginx/sites-available/$DOMAIN_NAME /etc/nginx/sites-enabled/
    print_success "Site enabled"

    print_step "Testing Nginx configuration..."
    if nginx -t > /dev/null 2>&1; then
        print_success "Nginx configuration is valid"
    else
        print_error "Nginx configuration test failed"
        nginx -t
        exit 1
    fi

    print_step "Restarting Nginx..."
    systemctl restart nginx
    print_success "Nginx restarted"
}

configure_nginx_websocket() {
    # Only configure if WebSocket domain is provided
    if [[ -z "$WS_DOMAIN_NAME" ]]; then
        return
    fi

    print_header "Configuring Nginx for WebSocket Domain"

    # Check if SSL certificate already exists - if so, skip nginx configuration
    if [[ -d "/etc/letsencrypt/live/$WS_DOMAIN_NAME" ]]; then
        print_info "SSL certificate for $WS_DOMAIN_NAME already exists"
        print_step "Skipping Nginx WebSocket configuration to preserve existing HTTPS settings..."
        print_success "Using existing Nginx WebSocket configuration"
        return
    fi

    print_step "Creating Nginx WebSocket configuration..."

    tee /etc/nginx/sites-available/$WS_DOMAIN_NAME > /dev/null << EOF
server {
    listen 80;
    server_name $WS_DOMAIN_NAME;

    access_log /var/log/nginx/${WS_DOMAIN_NAME}_access.log;
    error_log /var/log/nginx/${WS_DOMAIN_NAME}_error.log;

    # Redirect HTTP to HTTPS (will be enabled after SSL setup)
    # return 301 https://\$server_name\$request_uri;

    location / {
        proxy_pass http://127.0.0.1:$WS_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 3600s;
    }
}
EOF

    print_success "Nginx WebSocket configuration created"

    print_step "Enabling WebSocket site..."
    ln -sf /etc/nginx/sites-available/$WS_DOMAIN_NAME /etc/nginx/sites-enabled/
    print_success "WebSocket site enabled"

    print_step "Testing Nginx configuration..."
    if nginx -t > /dev/null 2>&1; then
        print_success "Nginx configuration is valid"
    else
        print_error "Nginx configuration test failed"
        nginx -t
        exit 1
    fi

    print_step "Reloading Nginx..."
    systemctl reload nginx
    print_success "Nginx reloaded"
}

setup_ssl_certificate() {
    print_header "Setting Up SSL Certificate for Main Domain"

    # Check if SSL certificate already exists
    if [[ -d "/etc/letsencrypt/live/$DOMAIN_NAME" ]]; then
        print_info "SSL certificate for $DOMAIN_NAME already exists"
        print_step "Skipping certificate creation..."
        print_success "Using existing SSL certificate"

        # Make sure certbot timer is enabled for renewals
        print_step "Ensuring automatic renewal is enabled..."
        systemctl enable certbot.timer > /dev/null 2>&1
        systemctl start certbot.timer
        print_success "Automatic certificate renewal enabled"
        return
    fi

    print_info "Obtaining SSL certificate from Let's Encrypt..."
    print_info "Make sure DNS is properly configured and pointing to this server."

    print_step "Running Certbot..."

    # Run certbot with automatic configuration
    if certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos --register-unsafely-without-email --redirect; then
        print_success "SSL certificate obtained and configured"

        print_step "Setting up automatic renewal..."
        systemctl enable certbot.timer > /dev/null 2>&1
        systemctl start certbot.timer
        print_success "Automatic certificate renewal enabled"
    else
        print_warning "SSL certificate setup failed. You can run it manually later:"
        print_info "certbot --nginx -d $DOMAIN_NAME"
    fi
}

setup_ssl_certificate_websocket() {
    # Only setup if WebSocket domain is provided
    if [[ -z "$WS_DOMAIN_NAME" ]]; then
        return
    fi

    print_header "Setting Up SSL Certificate for WebSocket Domain"

    # Check if SSL certificate already exists
    if [[ -d "/etc/letsencrypt/live/$WS_DOMAIN_NAME" ]]; then
        print_info "SSL certificate for $WS_DOMAIN_NAME already exists"
        print_step "Skipping certificate creation..."
        print_success "Using existing SSL certificate"
        return
    fi

    print_info "Obtaining SSL certificate from Let's Encrypt..."
    print_info "Make sure DNS is properly configured and pointing to this server."

    print_step "Running Certbot for WebSocket domain..."

    # Run certbot with automatic configuration
    if certbot --nginx -d "$WS_DOMAIN_NAME" --non-interactive --agree-tos --register-unsafely-without-email --redirect; then
        print_success "SSL certificate obtained and configured for WebSocket"
    else
        print_warning "SSL certificate setup failed for WebSocket domain. You can run it manually later:"
        print_info "certbot --nginx -d $WS_DOMAIN_NAME"
    fi
}

add_user_to_www_data() {
    print_header "Configuring User Permissions"

    print_step "Adding $CURRENT_USER to www-data group..."
    usermod -aG www-data "$CURRENT_USER"
    print_success "User added to www-data group"

    print_step "Adding www-data to $INSTALLER_USER group..."
    usermod -aG "$INSTALLER_USER" www-data
    print_success "www-data added to $INSTALLER_USER group (allows nginx access to static files)"

    print_step "Setting directory permissions..."
    chown -R "$CURRENT_USER":www-data "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
    print_success "Directory permissions configured"
}

show_completion_message() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                                                                              ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}   ${BOLD}${WHITE}✔ Installation Completed Successfully!${NC}                                   ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                                              ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    print_header "Installation Summary"

    echo -e "${WHITE}Application Details:${NC}"
    echo -e "  ${CYAN}•${NC} Domain:        ${BOLD}https://$DOMAIN_NAME${NC}"
    echo -e "  ${CYAN}•${NC} Install path:  ${BOLD}$INSTALL_DIR${NC}"
    echo -e "  ${CYAN}•${NC} Virtual env:   ${BOLD}$VENV_DIR${NC}"
    echo ""

    echo -e "${WHITE}Database Details:${NC}"
    echo -e "  ${CYAN}•${NC} Database:      ${BOLD}$DB_NAME${NC}"
    echo -e "  ${CYAN}•${NC} User:          ${BOLD}$DB_USER${NC}"
    echo -e "  ${CYAN}•${NC} Password:      ${BOLD}(stored in .env file)${NC}"
    echo ""

    echo -e "${WHITE}API Configuration:${NC}"
    echo -e "  ${CYAN}•${NC} API Key:       ${BOLD}$API_KEY${NC}"
    echo ""

    if [[ -n "$WS_DOMAIN_NAME" ]]; then
        echo -e "${WHITE}WebSocket Server:${NC}"
        echo -e "  ${CYAN}•${NC} Domain:        ${BOLD}wss://$WS_DOMAIN_NAME${NC}"
        echo -e "  ${CYAN}•${NC} Port:          ${BOLD}$WS_PORT${NC}"
        echo -e "  ${CYAN}•${NC} Status:        ${BOLD}sudo supervisorctl status $WS_SERVICE_NAME${NC}"
        echo ""
    fi

    echo -e "${WHITE}Service Management:${NC}"
    echo -e "  ${CYAN}•${NC} Check status:  ${BOLD}sudo systemctl status ${SERVICE_NAME}${NC}"
    echo -e "  ${CYAN}•${NC} Restart:       ${BOLD}sudo systemctl restart ${SERVICE_NAME}${NC}"
    echo -e "  ${CYAN}•${NC} View logs:     ${BOLD}sudo journalctl -u ${SERVICE_NAME}${NC}"
    echo ""

    echo -e "${WHITE}API Endpoints:${NC}"
    echo -e "  ${CYAN}•${NC} Swagger UI:    ${BOLD}https://$DOMAIN_NAME/docs${NC}"
    echo -e "  ${CYAN}•${NC} ReDoc:         ${BOLD}https://$DOMAIN_NAME/redoc${NC}"
    echo ""

    echo -e "${YELLOW}Important:${NC}"
    echo -e "  ${CYAN}•${NC} API Key is stored in: ${BOLD}$INSTALL_DIR/.env${NC}"
    echo -e "  ${CYAN}•${NC} Please save the API Key in a secure location"
    echo -e "  ${CYAN}•${NC} Use the API Key in the X-API-Key header for authentication"
    echo ""

    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "  ${CYAN}1.${NC} Visit ${BOLD}https://$DOMAIN_NAME/docs${NC} to explore the API"
    echo -e "  ${CYAN}2.${NC} Test API connection with: ${BOLD}curl -H 'X-API-Key: $API_KEY' https://$DOMAIN_NAME/${NC}"
    if [[ -n "$WS_DOMAIN_NAME" ]]; then
        echo -e "  ${CYAN}3.${NC} Connect to WebSocket at: ${BOLD}wss://$WS_DOMAIN_NAME${NC}"
    fi
    echo ""

    print_success "Thank you for using Queue Manager!"
    echo ""
}

#-------------------------------------------------------------------------------
# Main execution
#-------------------------------------------------------------------------------

main() {
    # Parse command line arguments first (before any output)
    parse_arguments "$@"

    # Pre-flight checks
    check_root
    check_ubuntu

    # Show welcome banner
    show_banner

    # Setup installer user and switch context
    setup_installer_user

    echo ""
    print_info "Starting installation. This may take several minutes..."
    print_info "Main Domain: $DOMAIN_NAME"
    if [[ -n "$WS_DOMAIN_NAME" ]]; then
        print_info "WebSocket Domain: $WS_DOMAIN_NAME"
    fi
    print_info "User: $CURRENT_USER"
    echo ""

    # Execute installation steps
    install_dependencies
    clone_repository
    setup_python_environment
    configure_mysql
    create_env_file
    setup_alembic
    add_user_to_www_data
    create_systemd_service
    setup_websocket_server
    configure_nginx
    configure_nginx_websocket
    setup_ssl_certificate
    setup_ssl_certificate_websocket

    # Show completion message
    show_completion_message
}

# Run the script
main "$@"
