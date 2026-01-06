#!/bin/bash

#===============================================================================
#
#   iRedMail - Automated Installation Script
#   For Ubuntu 24.04 LTS
#
#   This script automatically installs and configures:
#   - iRedMail mail server (complete mail solution)
#   - Nginx web server
#   - Backend database (MariaDB/MySQL/PostgreSQL/OpenLDAP)
#   - Postfix, Dovecot, Amavisd, ClamAV, SpamAssassin
#   - Roundcube webmail
#   - SSL certificate via Let's Encrypt
#
#   Creates a fully functional mail server with webmail interface.
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
APP_NAME="iredmail"
INSTALLER_USER="installer_user"
IREDMAIL_VERSION="1.7.4"

# These will be set after user setup
CURRENT_USER=""
HOME_DIR=""
INSTALL_DIR=""

# Domain configuration
DOMAIN_NAME=""
BACKEND_TYPE=""

#-------------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------------

show_usage() {
    echo "Usage: $0 <domain_name> [backend_type]"
    echo ""
    echo "Arguments:"
    echo "  domain_name              The domain name for mail server (e.g., mail.example.com)"
    echo "  backend_type             (Optional) Database backend: mariadb, mysql, pgsql, or ldap"
    echo "                           Default: mariadb"
    echo ""
    echo "Backend options:"
    echo "  mariadb                  Use MariaDB as backend (recommended, default)"
    echo "  mysql                    Use MySQL as backend"
    echo "  pgsql                    Use PostgreSQL as backend"
    echo "  ldap                     Use OpenLDAP as backend"
    echo ""
    echo "Examples:"
    echo "  $0 mail.example.com"
    echo "  $0 mail.example.com mariadb"
    echo "  $0 mail.example.com pgsql"
    echo ""
    echo "Note: This script must be run as root or with sudo."
    exit 1
}

validate_domain() {
    local domain="$1"
    # Basic domain validation regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        print_info "Please enter a valid domain (e.g., mail.example.com)"
        exit 1
    fi
}

validate_backend() {
    local backend="$1"
    case "$backend" in
        mariadb|mysql|pgsql|ldap)
            return 0
            ;;
        *)
            print_error "Invalid backend type: $backend"
            print_info "Valid options: mariadb, mysql, pgsql, ldap"
            exit 1
            ;;
    esac
}

print_header() {
    echo ""
    echo -e "${CYAN}+------------------------------------------------------------------------------+${NC}"
    echo -e "${CYAN}|${NC}  ${BOLD}${WHITE}$1${NC}"
    echo -e "${CYAN}+------------------------------------------------------------------------------+${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}>${NC} ${WHITE}$1${NC}"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} ${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} ${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}[X]${NC} ${RED}$1${NC}"
}

print_info() {
    echo -e "${MAGENTA}[i]${NC} ${WHITE}$1${NC}"
}

generate_password() {
    # Generate a secure random password
    openssl rand -base64 24 | tr -d '/+=' | head -c 20
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root!"
        print_info "Run with: sudo $0 <domain_name> [backend_type]"
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

    print_success "Installer user configured: $INSTALLER_USER"
    print_info "Home directory: $HOME_DIR"
    print_info "Installation directory: $INSTALL_DIR"
}

check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        print_warning "This script is designed for Ubuntu. Proceed with caution on other distributions."
    fi

    # Check Ubuntu version
    if grep -q "Ubuntu 24.04" /etc/os-release 2>/dev/null; then
        print_success "Ubuntu 24.04 detected"
    else
        print_warning "This script is optimized for Ubuntu 24.04"
    fi
}

check_system_requirements() {
    print_header "Checking System Requirements"

    # Check memory
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [[ $total_mem -lt 3500 ]]; then
        print_warning "System has ${total_mem}MB RAM. iRedMail recommends at least 4GB for production."
    else
        print_success "Memory check passed: ${total_mem}MB RAM"
    fi

    # Check if UIDs/GIDs 2000-2004 are available
    print_step "Checking required UIDs/GIDs availability..."
    local uid_conflict=0
    for uid in 2000 2001 2002 2003 2004; do
        if getent passwd $uid &>/dev/null; then
            print_warning "UID $uid is already in use"
            uid_conflict=1
        fi
        if getent group $uid &>/dev/null; then
            print_warning "GID $uid is already in use"
            uid_conflict=1
        fi
    done

    if [[ $uid_conflict -eq 0 ]]; then
        print_success "Required UIDs/GIDs (2000-2004) are available"
    else
        print_error "Some required UIDs/GIDs are already in use. iRedMail requires UIDs/GIDs 2000-2004 to be available."
        exit 1
    fi

    # Check if port 25 is open (we can't really check if firewall allows it, but we can check if something is listening)
    if netstat -tuln 2>/dev/null | grep -q ':25 ' || ss -tuln 2>/dev/null | grep -q ':25 '; then
        print_warning "Port 25 appears to be in use. iRedMail will configure Postfix on this port."
    else
        print_success "Port 25 is available"
    fi

    # Check for existing mail components that might conflict
    print_step "Checking for conflicting mail components..."
    local conflicts=0
    for service in postfix dovecot sendmail exim4; do
        if systemctl is-active --quiet $service 2>/dev/null; then
            print_warning "Service $service is running. iRedMail requires a fresh system."
            conflicts=1
        fi
    done

    if [[ $conflicts -eq 1 ]]; then
        print_warning "Found running mail services. iRedMail is designed for fresh installations."
        print_info "Continuing anyway, but this may cause issues..."
    else
        print_success "No conflicting mail services detected"
    fi
}

#-------------------------------------------------------------------------------
# Main installation functions
#-------------------------------------------------------------------------------

show_banner() {
    clear
    echo ""
    echo -e "${CYAN}   +-------------------------------------------------------------------------+${NC}"
    echo -e "${CYAN}   |${NC}                                                                         ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${BOLD}${WHITE}iRedMail Mail Server${NC}                                                ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${MAGENTA}Automated Installation Script for Ubuntu 24.04${NC}                       ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}                                                                         ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${WHITE}This script will install and configure:${NC}                              ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} iRedMail $IREDMAIL_VERSION                                                  ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} Nginx web server                                                   ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} Database backend (MariaDB/MySQL/PostgreSQL/OpenLDAP)               ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} Postfix, Dovecot, Amavisd, ClamAV, SpamAssassin                    ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} Roundcube webmail                                                  ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}   ${GREEN}*${NC} SSL certificate via Let's Encrypt                                  ${CYAN}|${NC}"
    echo -e "${CYAN}   |${NC}                                                                         ${CYAN}|${NC}"
    echo -e "${CYAN}   +-------------------------------------------------------------------------+${NC}"
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

    # Check for optional backend type (second positional argument)
    if [[ -n "$2" ]]; then
        BACKEND_TYPE="$2"
        validate_backend "$BACKEND_TYPE"
    else
        BACKEND_TYPE="mariadb"  # Default to MariaDB
    fi

    print_header "Configuration"
    print_success "Domain configured: $DOMAIN_NAME"
    print_success "Backend type: $BACKEND_TYPE"
}

set_hostname() {
    print_header "Setting Hostname"

    local current_hostname=$(hostname -f 2>/dev/null || hostname)

    if [[ "$current_hostname" == "$DOMAIN_NAME" ]]; then
        print_info "Hostname already set to: $DOMAIN_NAME"
        print_success "Hostname configuration complete"
        return
    fi

    print_step "Setting FQDN hostname to: $DOMAIN_NAME"

    # Set hostname
    hostnamectl set-hostname "$DOMAIN_NAME" 2>/dev/null || {
        echo "$DOMAIN_NAME" > /etc/hostname
        hostname "$DOMAIN_NAME"
    }

    # Update /etc/hosts
    print_step "Updating /etc/hosts..."
    local short_hostname=$(echo "$DOMAIN_NAME" | cut -d'.' -f1)

    # Remove old entries for 127.0.1.1 if they exist
    sed -i '/^127\.0\.1\.1/d' /etc/hosts

    # Add new entry
    echo "127.0.1.1 $DOMAIN_NAME $short_hostname" >> /etc/hosts

    # Verify
    local new_hostname=$(hostname -f 2>/dev/null || hostname)
    if [[ "$new_hostname" == "$DOMAIN_NAME" ]]; then
        print_success "Hostname set to: $new_hostname"
    else
        print_warning "Hostname verification shows: $new_hostname (expected: $DOMAIN_NAME)"
    fi
}

install_dependencies() {
    print_header "Installing System Dependencies"

    # Set non-interactive mode for all package installations
    export DEBIAN_FRONTEND=noninteractive

    print_step "Updating package lists..."
    apt-get update -qq
    print_success "Package lists updated"

    print_step "Installing required packages..."
    apt-get install -y -qq gzip dialog wget curl openssl > /dev/null 2>&1
    print_success "Required packages installed"

    print_step "Installing certbot for SSL certificates..."
    apt-get install -y -qq certbot > /dev/null 2>&1
    print_success "Certbot installed"

    print_success "All system dependencies installed successfully!"
}

download_iredmail() {
    print_header "Downloading iRedMail"

    # Check if installation directory exists
    if [[ -d "$INSTALL_DIR" ]]; then
        print_info "iRedMail directory already exists at $INSTALL_DIR"

        # Check if it's a git repository or just extracted files
        if [[ -d "$INSTALL_DIR/.git" ]]; then
            print_step "Updating existing iRedMail repository..."
            cd "$INSTALL_DIR"
            sudo -u "$CURRENT_USER" git checkout . 2>/dev/null || true
            sudo -u "$CURRENT_USER" git pull origin master 2>/dev/null || {
                print_warning "Git pull failed, will re-download"
                cd "$HOME_DIR"
                rm -rf "$INSTALL_DIR"
            }
        else
            # Check version if possible
            if [[ -f "$INSTALL_DIR/conf/global" ]]; then
                current_version=$(grep "PROG_VERSION=" "$INSTALL_DIR/conf/global" | cut -d"'" -f2)
                if [[ "$current_version" == "$IREDMAIL_VERSION" ]]; then
                    print_success "iRedMail $IREDMAIL_VERSION is already downloaded"
                    return
                else
                    print_info "Updating iRedMail from $current_version to $IREDMAIL_VERSION"
                fi
            fi
        fi
    fi

    # Download iRedMail if directory doesn't exist or needs update
    if [[ ! -d "$INSTALL_DIR" ]] || [[ ! -f "$INSTALL_DIR/iRedMail.sh" ]]; then
        DOWNLOAD_URL="https://github.com/iredmail/iRedMail/archive/refs/tags/${IREDMAIL_VERSION}.tar.gz"
        TEMP_FILE="/tmp/iredmail-${IREDMAIL_VERSION}.tar.gz"

        print_step "Downloading iRedMail $IREDMAIL_VERSION..."
        sudo -u "$CURRENT_USER" wget -q -O "$TEMP_FILE" "$DOWNLOAD_URL"
        print_success "Download completed"

        print_step "Extracting iRedMail..."
        cd "$HOME_DIR"
        sudo -u "$CURRENT_USER" tar -xzf "$TEMP_FILE"

        # Rename to standard directory name
        if [[ -d "$HOME_DIR/iRedMail-${IREDMAIL_VERSION}" ]]; then
            if [[ -d "$INSTALL_DIR" ]]; then
                rm -rf "$INSTALL_DIR"
            fi
            sudo -u "$CURRENT_USER" mv "$HOME_DIR/iRedMail-${IREDMAIL_VERSION}" "$INSTALL_DIR"
        fi

        rm -f "$TEMP_FILE"
        print_success "iRedMail extracted to: $INSTALL_DIR"
    fi

    # Set permissions
    chown -R "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR"
    chmod +x "$INSTALL_DIR/iRedMail.sh"

    print_success "iRedMail ready at: $INSTALL_DIR"
}

create_config_file() {
    print_header "Creating iRedMail Configuration"

    CONFIG_FILE="$INSTALL_DIR/config"

    # Check if config file already exists
    if [[ -f "$CONFIG_FILE" ]]; then
        print_info "Configuration file already exists"
        print_step "Preserving existing configuration..."
        print_success "Using existing iRedMail configuration"
        return
    fi

    print_step "Generating secure passwords..."
    local admin_password=$(generate_password)
    local vmail_db_bind_passwd=$(generate_password)
    local vmail_db_admin_passwd=$(generate_password)
    local mlmmjadmin_api_token=$(generate_password)
    local iredapd_db_passwd=$(generate_password)
    local iredadmin_db_passwd=$(generate_password)
    local roundcube_db_passwd=$(generate_password)
    local sogo_db_passwd=$(generate_password)
    local amavisd_db_passwd=$(generate_password)
    local iredapd_srs_secret=$(generate_password)
    local first_domain=$(echo "$DOMAIN_NAME" | sed 's/^mail\.//' | sed 's/^smtp\.//')

    print_success "Passwords generated"

    # Map backend type to iRedMail format
    local backend_orig=""
    local backend=""
    case "$BACKEND_TYPE" in
        mariadb)
            backend_orig="MARIADB"
            backend="MYSQL"
            ;;
        mysql)
            backend_orig="MARIADB"
            backend="MYSQL"
            ;;
        pgsql)
            backend_orig="PGSQL"
            backend="PGSQL"
            ;;
        ldap)
            backend_orig="OPENLDAP"
            backend="OPENLDAP"
            ;;
    esac

    print_step "Creating configuration file for $backend_orig backend..."

    # Create config file
    cat > "$CONFIG_FILE" << EOF
# iRedMail configuration file
# Generated by automated installation script

# Storage
export STORAGE_BASE_DIR='/var/vmail'

# Web server
export WEB_SERVER='NGINX'

# Backend
export BACKEND_ORIG='${backend_orig}'
export BACKEND='${backend}'

# First mail domain
export FIRST_DOMAIN='${first_domain}'

# Admin password (for postmaster@${first_domain})
export DOMAIN_ADMIN_PASSWD_PLAIN='${admin_password}'

# Database passwords
export VMAIL_DB_BIND_PASSWD='${vmail_db_bind_passwd}'
export VMAIL_DB_ADMIN_PASSWD='${vmail_db_admin_passwd}'
export MLMMJADMIN_API_AUTH_TOKEN='${mlmmjadmin_api_token}'
export IREDAPD_DB_PASSWD='${iredapd_db_passwd}'
export IREDADMIN_DB_PASSWD='${iredadmin_db_passwd}'
export RCM_DB_PASSWD='${roundcube_db_passwd}'
export SOGO_DB_PASSWD='${sogo_db_passwd}'
export AMAVISD_DB_PASSWD='${amavisd_db_passwd}'
export IREDAPD_SRS_SECRET='${iredapd_srs_secret}'

# Optional components
export USE_IREDADMIN='YES'
export USE_ROUNDCUBE='YES'
export USE_AWSTATS='NO'
export USE_FAIL2BAN='YES'
export USE_NETDATA='YES'

# OpenLDAP specific (only used if backend is OPENLDAP)
export LDAP_SUFFIX='dc=${first_domain//./,dc=}'
export LDAP_ADMIN_PW='${admin_password}'
export LDAP_ROOTDN='cn=Manager,${LDAP_SUFFIX}'

EOF

    chown "$CURRENT_USER":"$CURRENT_USER" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    print_success "Configuration file created: $CONFIG_FILE"

    # Save credentials to a separate file for the report
    CREDENTIALS_FILE="$HOME_DIR/.iredmail-credentials"
    cat > "$CREDENTIALS_FILE" << EOF
# iRedMail Installation Credentials
# Domain: ${first_domain}
# Installation Date: $(date)

# Webmail and Admin Panel Access
# URL: https://${DOMAIN_NAME}
# Admin Email: postmaster@${first_domain}
# Admin Password: ${admin_password}

# Database Credentials
VMAIL_DB_BIND_USER=vmail
VMAIL_DB_BIND_PASSWORD=${vmail_db_bind_passwd}
VMAIL_DB_ADMIN_USER=vmailadmin
VMAIL_DB_ADMIN_PASSWORD=${vmail_db_admin_passwd}
IREDAPD_DB_PASSWORD=${iredapd_db_passwd}
IREDADMIN_DB_PASSWORD=${iredadmin_db_passwd}
ROUNDCUBE_DB_PASSWORD=${roundcube_db_passwd}
SOGO_DB_PASSWORD=${sogo_db_passwd}
AMAVISD_DB_PASSWORD=${amavisd_db_passwd}

# API Tokens
MLMMJADMIN_API_TOKEN=${mlmmjadmin_api_token}
IREDAPD_SRS_SECRET=${iredapd_srs_secret}

EOF

    chown "$CURRENT_USER":"$CURRENT_USER" "$CREDENTIALS_FILE"
    chmod 600 "$CREDENTIALS_FILE"

    print_info "Credentials saved to: $CREDENTIALS_FILE"
}

run_iredmail_installer() {
    print_header "Running iRedMail Installer"

    # Check if iRedMail is already installed
    if [[ -f "$INSTALL_DIR/config" ]] && [[ -f "/root/.iredmail/kv/iredmail_installation_finished" ]]; then
        print_info "iRedMail installation appears to be complete"
        print_success "Skipping installation (already installed)"
        return
    fi

    print_step "Starting automated iRedMail installation..."
    print_warning "This may take 15-30 minutes depending on your system..."

    cd "$INSTALL_DIR"

    # Run iRedMail installer with all automation flags
    AUTO_USE_EXISTING_CONFIG_FILE=y \
    AUTO_INSTALL_WITHOUT_CONFIRM=y \
    AUTO_CLEANUP_REMOVE_SENDMAIL=y \
    AUTO_CLEANUP_REPLACE_FIREWALL_RULES=y \
    AUTO_CLEANUP_RESTART_FIREWALL=y \
    AUTO_CLEANUP_REPLACE_MYSQL_CONFIG=y \
    bash iRedMail.sh

    if [[ $? -eq 0 ]]; then
        print_success "iRedMail installation completed successfully!"
    else
        print_error "iRedMail installation failed!"
        print_info "Check installation logs at: $INSTALL_DIR/runtime/install.log"
        exit 1
    fi
}

configure_ssl() {
    print_header "Configuring SSL Certificate"

    # Check if SSL certificate already exists
    if [[ -d "/etc/letsencrypt/live/$DOMAIN_NAME" ]]; then
        print_info "SSL certificate for $DOMAIN_NAME already exists"
        print_success "Using existing SSL certificate"
        return
    fi

    print_step "Obtaining SSL certificate from Let's Encrypt..."
    print_info "This requires port 80 to be accessible from the internet"

    # Stop nginx temporarily if it's running to allow certbot standalone
    systemctl stop nginx 2>/dev/null || true

    # Obtain certificate
    certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email \
        -d "$DOMAIN_NAME" 2>&1 | tee /tmp/certbot.log

    if [[ $? -eq 0 ]] && [[ -d "/etc/letsencrypt/live/$DOMAIN_NAME" ]]; then
        print_success "SSL certificate obtained successfully"

        # Update iRedMail Nginx configuration to use the new certificate
        print_step "Updating Nginx configuration to use SSL certificate..."

        # Find and update nginx config
        nginx_conf="/etc/nginx/sites-available/00-default-ssl.conf"
        if [[ -f "$nginx_conf" ]]; then
            # Backup original config
            cp "$nginx_conf" "${nginx_conf}.backup"

            # Update SSL certificate paths
            sed -i "s|ssl_certificate .*|ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;|" "$nginx_conf"
            sed -i "s|ssl_certificate_key .*|ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;|" "$nginx_conf"

            print_success "Nginx SSL configuration updated"
        fi

        # Restart nginx
        systemctl start nginx
        systemctl reload nginx 2>/dev/null || true

        print_success "SSL certificate configured"
    else
        print_warning "Failed to obtain SSL certificate"
        print_info "You may need to:"
        print_info "  1. Ensure port 80 is open and accessible"
        print_info "  2. Verify DNS records point to this server"
        print_info "  3. Run 'certbot certonly --nginx -d $DOMAIN_NAME' manually after installation"

        # Start nginx anyway
        systemctl start nginx
    fi
}

create_installation_report() {
    print_header "Creating Installation Report"

    REPORT_FILE="$HOME_DIR/iredmail-installation-report.txt"
    CREDENTIALS_FILE="$HOME_DIR/.iredmail-credentials"

    # Extract first domain from config
    local first_domain=$(grep "^export FIRST_DOMAIN=" "$INSTALL_DIR/config" 2>/dev/null | cut -d"'" -f2)
    [[ -z "$first_domain" ]] && first_domain=$(echo "$DOMAIN_NAME" | sed 's/^mail\.//' | sed 's/^smtp\.//')

    # Read admin password from credentials file
    local admin_password=""
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        admin_password=$(grep "^# Admin Password:" "$CREDENTIALS_FILE" | awk '{print $4}')
    fi

    cat > "$REPORT_FILE" << EOF
================================================================================
                    iRedMail Installation Report
================================================================================

Installation completed: $(date)
iRedMail Version: ${IREDMAIL_VERSION}
Domain: ${first_domain}
Hostname: ${DOMAIN_NAME}
Backend: ${BACKEND_TYPE}

================================================================================
                        Access Information
================================================================================

Webmail (Roundcube): https://${DOMAIN_NAME}/mail
Admin Panel (iRedAdmin): https://${DOMAIN_NAME}/iredadmin

Admin Credentials:
  Email: postmaster@${first_domain}
  Password: ${admin_password}

================================================================================
                        Server Components
================================================================================

Web Server: Nginx
Mail Server: Postfix + Dovecot
Webmail: Roundcube
Admin Panel: iRedAdmin
Anti-spam: SpamAssassin + Amavisd
Anti-virus: ClamAV
Backend: ${BACKEND_TYPE}

================================================================================
                        Important Files
================================================================================

Installation directory: ${INSTALL_DIR}
Configuration file: ${INSTALL_DIR}/config
Installation log: ${INSTALL_DIR}/runtime/install.log
Installation tips: ${INSTALL_DIR}/iRedMail.tips
Credentials file: ${CREDENTIALS_FILE}
SSL certificate: /etc/letsencrypt/live/${DOMAIN_NAME}/

================================================================================
                        Next Steps
================================================================================

1. Configure DNS Records:
   - Add MX record pointing to ${DOMAIN_NAME}
   - Add SPF record: "v=spf1 mx ~all"
   - Add DKIM record (see ${INSTALL_DIR}/iRedMail.tips)
   - Add DMARC record: "v=DMARC1; p=none; rua=mailto:postmaster@${first_domain}"

2. Test your mail server:
   - Send test email to postmaster@${first_domain}
   - Check webmail at https://${DOMAIN_NAME}/mail
   - Access admin panel at https://${DOMAIN_NAME}/iredadmin

3. Security:
   - All passwords are stored in: ${CREDENTIALS_FILE}
   - Keep this file secure (permissions: 600)
   - Consider changing the default admin password

4. SSL Certificate Renewal:
   - Certificate will auto-renew via certbot
   - Check renewal: certbot renew --dry-run

================================================================================
                        Useful Commands
================================================================================

# Check mail queue
postqueue -p

# Check mail logs
tail -f /var/log/mail.log

# Restart services
systemctl restart postfix
systemctl restart dovecot
systemctl restart nginx

# Test SMTP
telnet localhost 25

# Check iRedAPD
systemctl status iredapd

================================================================================

For more information, documentation, and support:
- Official documentation: https://docs.iredmail.org/
- Community forum: https://forum.iredmail.org/
- Installation tips: ${INSTALL_DIR}/iRedMail.tips

================================================================================
EOF

    chown "$CURRENT_USER":"$CURRENT_USER" "$REPORT_FILE"
    chmod 644 "$REPORT_FILE"

    print_success "Installation report created: $REPORT_FILE"
}

display_final_message() {
    print_header "Installation Complete!"

    # Extract first domain from config
    local first_domain=$(grep "^export FIRST_DOMAIN=" "$INSTALL_DIR/config" 2>/dev/null | cut -d"'" -f2)
    [[ -z "$first_domain" ]] && first_domain=$(echo "$DOMAIN_NAME" | sed 's/^mail\.//' | sed 's/^smtp\.//')

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}${WHITE}iRedMail has been successfully installed!${NC}                                ${GREEN}║${NC}"
    echo -e "${GREEN}╟────────────────────────────────────────────────────────────────────────────╢${NC}"
    echo -e "${GREEN}║${NC}                                                                            ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${CYAN}Webmail:${NC}      https://${DOMAIN_NAME}/mail                                ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${CYAN}Admin Panel:${NC}  https://${DOMAIN_NAME}/iredadmin                          ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                                            ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${YELLOW}Admin Email:${NC}  postmaster@${first_domain}                               ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${YELLOW}Password:${NC}     (see installation report)                                ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                                            ${GREEN}║${NC}"
    echo -e "${GREEN}╟────────────────────────────────────────────────────────────────────────────╢${NC}"
    echo -e "${GREEN}║${NC}  ${MAGENTA}Important Files:${NC}                                                        ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}    • Installation report: ${HOME_DIR}/iredmail-installation-report.txt    ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}    • Credentials: ${HOME_DIR}/.iredmail-credentials                        ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}    • Tips: ${INSTALL_DIR}/iRedMail.tips                                    ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                                            ${GREEN}║${NC}"
    echo -e "${GREEN}╟────────────────────────────────────────────────────────────────────────────╢${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}${WHITE}Next Steps:${NC}                                                              ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}    1. Configure DNS records (MX, SPF, DKIM, DMARC)                        ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}    2. Test webmail and admin panel access                                 ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}    3. Send test emails                                                    ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}    4. Review installation report for details                              ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                                            ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    print_info "For detailed information, check: $HOME_DIR/iredmail-installation-report.txt"
    echo ""
}

#-------------------------------------------------------------------------------
# Main script execution
#-------------------------------------------------------------------------------

main() {
    show_banner

    # Validate environment
    check_root
    check_ubuntu
    parse_arguments "$@"

    # Setup
    setup_installer_user
    check_system_requirements
    set_hostname

    # Install
    install_dependencies
    download_iredmail
    create_config_file
    run_iredmail_installer

    # Post-installation
    configure_ssl
    create_installation_report
    display_final_message
}

# Run main function with all arguments
main "$@"
