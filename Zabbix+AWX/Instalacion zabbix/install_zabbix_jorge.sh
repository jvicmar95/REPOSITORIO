#!/bin/bash

# ================================================================
# Script para instalar Zabbix Server + PostgreSQL + Apache en Rocky Linux 9
# Autor: Jorge (ajustado para Apache + php-fpm + puerto 8081)
# ================================================================

set -euo pipefail

# Colores e iconos
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
RED="\e[31m"
RESET="\e[0m"
ICON_OK="✔"
ICON_WARN="➜"
ICON_ERR="✖"
ICON_ACTION="⚙"

# Verificación de root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}${ICON_ERR} Este script debe ejecutarse como root (usa sudo)${RESET}"
    exit 1
fi

# Variables
LOG_FILE="/var/log/zabbix_install.log"
DB_PASSWORD="zabbix"
ZABBIX_VERSION="7.2"
PG_HBA="/var/lib/pgsql/data/pg_hba.conf"
ZABBIX_CONF="/etc/zabbix/zabbix_server.conf"
BACKUP_DIR="/var/backups/zabbix_install"
SWAP_FILE="/swapfile"

mkdir -p "$BACKUP_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

print_step()  { echo -e "${YELLOW}${ICON_ACTION} $1${RESET}"; }
print_ok()    { echo -e "${GREEN}${ICON_OK} $1${RESET}"; }
print_warn()  { echo -e "${BLUE}${ICON_WARN} $1${RESET}"; }
print_error() { echo -e "${RED}${ICON_ERR} $1${RESET}"; }

set_locale() {
    print_step "Estableciendo localización..."
    localectl set-locale LANG=es_ES.UTF-8
    print_ok "Localización configurada"
}

uninstall_zabbix() {
    print_step "INICIO DE DESINSTALACIÓN"
    systemctl stop zabbix-server zabbix-agent httpd php-fpm postgresql || true
    dnf remove -y zabbix-server-pgsql zabbix-web-pgsql \
        zabbix-sql-scripts zabbix-selinux-policy zabbix-agent \
        postgresql-server postgresql-contrib httpd php php-pgsql php-fpm || true
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS zabbix;" || true
    sudo -u postgres psql -c "DROP USER IF EXISTS zabbix;" || true
    rm -rf /var/lib/pgsql/data/*
    print_ok "Desinstalación completada"
    exit 0
}

check_or_create_swap() {
    print_step "Verificando swap..."
    if swapon --show | grep -q "$SWAP_FILE"; then
        print_ok "Swap ya existente"
    else
        dd if=/dev/zero of=$SWAP_FILE bs=1M count=2048
        chmod 600 $SWAP_FILE
        mkswap $SWAP_FILE
        swapon $SWAP_FILE
        print_ok "Swap activado"
    fi
}

backup_file() {
    local file=$1
    local name
    name=$(basename "$file")
    if [ -f "$file" ]; then
        print_step "Backup de $file"
        cp "$file" "${BACKUP_DIR}/${name}.bak"
        print_ok "Guardado en ${BACKUP_DIR}/${name}.bak"
    fi
}

install_packages() {
    print_step "Instalando paquetes necesarios..."
    local packages=(
        zabbix-server-pgsql zabbix-web-pgsql zabbix-sql-scripts
        zabbix-selinux-policy zabbix-agent
        postgresql-server postgresql-contrib
        httpd php php-pgsql php-fpm nano glibc-langpack-es
    )
    for pkg in "${packages[@]}"; do
        rpm -q "$pkg" &>/dev/null && print_ok "✔ $pkg ya instalado" || {
            dnf install -y "$pkg"
            print_ok "$pkg instalado"
        }
    done
}

initialize_postgres() {
    print_step "Inicializando PostgreSQL..."
    [ -f "/var/lib/pgsql/data/PG_VERSION" ] && print_ok "Ya inicializado" || {
        postgresql-setup --initdb
        print_ok "PostgreSQL inicializado"
    }
    systemctl enable --now postgresql
}

ensure_pg_hba_peer() {
    print_step "Ajustando pg_hba.conf..."
    sed -i "s/^local\s\+all\s\+all\s\+md5/local all all peer/" "$PG_HBA"
    sed -i "s/^host\s\+all\s\+all\s\+127\.0\.0\.1\/32\s\+md5/host all all 127.0.0.1\/32 md5/" "$PG_HBA"
    sed -i "s/^host\s\+all\s\+all\s\+::1\/128\s\+md5/host all all ::1\/128 md5/" "$PG_HBA"
    systemctl reload postgresql
    print_ok "pg_hba.conf actualizado"
}

setup_database() {
    print_step "Configurando base de datos..."
    sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='zabbix'" | grep -q 1 ||
        sudo -u postgres psql -c "CREATE USER zabbix WITH PASSWORD '${DB_PASSWORD}';"

    sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='zabbix'" | grep -q 1 ||
        sudo -u postgres psql -c "CREATE DATABASE zabbix OWNER zabbix;"

    print_ok "Usuario y base de datos Zabbix listos"
}

check_and_import_schema() {
    print_step "Importando esquema inicial de Zabbix..."
    local exists=$(sudo -u postgres psql -d zabbix -tAc "SELECT to_regclass('public.dbversion');")
    if [[ "$exists" == "dbversion" ]]; then
        print_ok "Esquema ya importado"
    else
        gunzip -c /usr/share/zabbix/sql-scripts/postgresql/server.sql.gz | sudo -u zabbix psql zabbix
        print_ok "Esquema importado con éxito"
    fi
}

configure_zabbix_conf() {
    backup_file "$ZABBIX_CONF"
    grep -q "^DBPassword=" "$ZABBIX_CONF" && \
        sed -i "s/^DBPassword=.*/DBPassword=${DB_PASSWORD}/" "$ZABBIX_CONF" || \
        echo "DBPassword=${DB_PASSWORD}" >> "$ZABBIX_CONF"
    print_ok "Archivo zabbix_server.conf configurado"
}

configure_apache() {
    print_step "Configurando Apache y PHP en puerto 8081..."

    # Corregir errores comunes como Listen 808181
    sed -i 's/^Listen 808181/Listen 8081/' /etc/httpd/conf/httpd.conf

    # Reemplazar todas las líneas Listen 80 por Listen 8081
    grep -rl '^Listen 80' /etc/httpd/ | xargs sed -i 's/^Listen 80/Listen 8081/'

    # Autorizar el puerto 8081 en SELinux para Apache
    if ! semanage port -l | grep -q 'http_port_t.*8081'; then
        print_step "Registrando puerto 8081 en SELinux..."
        semanage port -a -t http_port_t -p tcp 8081 || semanage port -m -t http_port_t -p tcp 8081
        print_ok "Puerto 8081 autorizado para Apache"
    fi

    # Configurar alias /zabbix
    cat <<EOF > /etc/httpd/conf.d/zabbix.conf
Alias /zabbix /usr/share/zabbix/ui

<Directory "/usr/share/zabbix/ui">
    Options FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
EOF

    # Ajustes PHP globales
    sed -i 's/^;date.timezone =/date.timezone = Europe\/Madrid/' /etc/php.ini
    sed -i 's/^post_max_size = .*/post_max_size = 16M/' /etc/php.ini
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 2M/' /etc/php.ini
    sed -i 's/^max_execution_time = .*/max_execution_time = 300/' /etc/php.ini
    sed -i 's/^max_input_time = .*/max_input_time = 300/' /etc/php.ini

    systemctl enable --now httpd php-fpm || true

    print_ok "PHP y Apache configurados correctamente para puerto 8081"
}
  

configure_pg_hba() {
    sed -i "s/^local\s\+all\s\+all\s\+peer/local all all md5/" "$PG_HBA"
    sed -i "s/^host\s\+all\s\+all\s\+127\.0\.0\.1\/32\s\+ident/host all all 127.0.0.1\/32 md5/" "$PG_HBA"
    sed -i "s/^host\s\+all\s\+all\s\+::1\/128\s\+ident/host all all ::1\/128 md5/" "$PG_HBA"
    print_ok "pg_hba.conf listo para conexiones md5"
}

grant_privileges() {
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE zabbix TO zabbix;"
    print_ok "Privilegios otorgados"
}

fix_web_config_permissions() {
    print_step "Asegurando permisos para guardar zabbix.conf.php"
    mkdir -p /etc/zabbix/web
    chown apache:apache /etc/zabbix/web
    chmod 755 /etc/zabbix/web
    print_ok "Permisos ajustados en /etc/zabbix/web"
}

restart_services_if_needed() {
    print_step "Reiniciando servicios..."
    local services=(postgresql zabbix-server zabbix-agent httpd php-fpm)
    for svc in "${services[@]}"; do
        systemctl restart "$svc" || systemctl enable --now "$svc"
        print_ok "Servicio $svc activo"
    done
}

# MAIN
if [[ "${1:-}" == "--uninstall" ]]; then
    uninstall_zabbix
fi

echo -e "${BLUE}### INICIO DE INSTALACIÓN: $(date)${RESET}"

check_or_create_swap
dnf update -y

print_step "Añadiendo repositorio de Zabbix..."
rpm -q zabbix-release &>/dev/null || {
    rpm -Uvh https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/release/rhel/9/noarch/zabbix-release-latest-${ZABBIX_VERSION}.el9.noarch.rpm
    dnf clean all
    print_ok "Repositorio añadido"
}

install_packages
initialize_postgres
ensure_pg_hba_peer
setup_database
check_and_import_schema
configure_zabbix_conf
configure_apache
configure_pg_hba
grant_privileges
set_locale
fix_web_config_permissions
restart_services_if_needed

SERVER_IP=$(curl -s ifconfig.me)
echo -e "${GREEN}${ICON_OK} Instalación completada correctamente${RESET}"
echo ""
echo -e "${BLUE}Accede desde tu navegador:${RESET}"
echo "http://${SERVER_IP}:8081/zabbix/"
echo ""
echo -e "${BLUE}### FIN DE INSTALACIÓN: $(date)${RESET}"
