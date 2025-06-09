#!/bin/bash

set -euo pipefail

# Variables
ZBX_IP="52.142.44.11"
ZBX_DB="zabbix"
ZBX_USER="zabbix"
ZBX_PASS="zabbix"
DATA_DIR="/data/zabbix"
PGDATA="${DATA_DIR}/pgsql/data"
CERT_DIR="${DATA_DIR}/ssl"
UI_DIR="${DATA_DIR}/ui"
ZBX_CONF_PHP="${UI_DIR}/conf/zabbix.conf.php"
NGINX_CONF="/etc/nginx/conf.d/zabbix.conf"
PHP_INI="/etc/php.ini"
PHP_POOL="/etc/php-fpm.d/www.conf"

echo "🚀 Iniciando instalación de Zabbix..."

# Limpieza previa
dnf remove -y zabbix-* postgresql-server nginx || true
rm -rf /var/lib/pgsql /etc/zabbix /etc/nginx/conf.d/zabbix.conf "$CERT_DIR" "$UI_DIR"
dnf clean all

# Repositorio Zabbix
rpm -Uvh https://repo.zabbix.com/zabbix/7.2/release/rhel/9/noarch/zabbix-release-latest-7.2.el9.noarch.rpm

# Instalación de paquetes
dnf install -y zabbix-server-pgsql zabbix-web-pgsql zabbix-nginx-conf \
  zabbix-sql-scripts zabbix-selinux-policy zabbix-agent postgresql-server \
  nginx openssl php php-pgsql php-fpm policycoreutils-python-utils

# Inicialización de PostgreSQL en nueva ruta
mkdir -p "$PGDATA"
chown -R postgres:postgres "$DATA_DIR"
chmod 700 "$PGDATA"
sudo -u postgres /usr/bin/initdb -D "$PGDATA"

# Override de PGDATA
mkdir -p /etc/systemd/system/postgresql.service.d
cat > /etc/systemd/system/postgresql.service.d/override.conf <<EOF
[Service]
Environment=PGDATA=${PGDATA}
EOF

# SELinux para PostgreSQL
semanage fcontext --add --equal /var/lib/pgsql "${DATA_DIR}/pgsql"
restorecon -Rv "${DATA_DIR}/pgsql"

# Arrancar PostgreSQL
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now postgresql

# Crear base de datos y usuario
sudo -u postgres psql <<EOF
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${ZBX_USER}') THEN
      CREATE ROLE ${ZBX_USER} WITH LOGIN PASSWORD '${ZBX_PASS}';
   END IF;
END
\$\$;
SELECT 'CREATE DATABASE ${ZBX_DB} OWNER ${ZBX_USER}' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${ZBX_DB}')\gexec
GRANT ALL PRIVILEGES ON DATABASE ${ZBX_DB} TO ${ZBX_USER};
EOF

# Importar esquema
zcat /usr/share/zabbix/sql-scripts/postgresql/server.sql.gz | sudo -u ${ZBX_USER} psql ${ZBX_DB}

# Autenticación PostgreSQL
PG_HBA="${PGDATA}/pg_hba.conf"
sed -i 's/^\(local\s\+all\s\+all\s\+\)peer/\1md5/' "$PG_HBA"
sed -i 's/^\(host\s\+all\s\+all\s\+127\.0\.0\.1\/32\s\+\)ident/\1md5/' "$PG_HBA"
sed -i 's/^\(host\s\+all\s\+all\s\+::1\/128\s\+\)ident/\1md5/' "$PG_HBA"
systemctl restart postgresql

# Configurar zabbix_server.conf
mv /etc/zabbix "${DATA_DIR}/etc"
ln -s "${DATA_DIR}/etc" /etc/zabbix
sed -i "s/^# DBPassword=/DBPassword=${ZBX_PASS}/" /etc/zabbix/zabbix_server.conf

# Certificados SSL
mkdir -p "$CERT_DIR"
openssl req -x509 -nodes -days 1825 -newkey rsa:2048 \
  -keyout "$CERT_DIR/zabbix.key" -out "$CERT_DIR/zabbix.crt" \
  -subj "/C=ES/ST=None/L=None/O=Zabbix/CN=${ZBX_IP}"
semanage fcontext -a -t httpd_sys_content_t "${CERT_DIR}(/.*)?"
restorecon -Rv "${CERT_DIR}"

# Configurar PHP
sed -i 's/^post_max_size = .*/post_max_size = 32M/' "$PHP_INI"
sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 16M/' "$PHP_INI"
sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
sed -i 's/^max_input_time = .*/max_input_time = 300/' "$PHP_INI"

for param in "post_max_size:32M" "upload_max_filesize:16M" "max_execution_time:300" "max_input_time:300"; do
  key="${param%%:*}"
  val="${param##*:}"
  if grep -q "^\s*php_value\[$key\]" "$PHP_POOL"; then
    sed -i "s|^\s*php_value\[$key\].*|php_value[$key] = $val|" "$PHP_POOL"
  else
    echo "php_value[$key] = $val" >> "$PHP_POOL"
  fi
done

# Preparar interfaz web
mkdir -p "$UI_DIR"
cp -a /usr/share/zabbix/ui/* "$UI_DIR/"
semanage fcontext -a -t httpd_sys_content_t "${UI_DIR}(/.*)?"
restorecon -Rv "${UI_DIR}"

# Configurar nginx
cat > "$NGINX_CONF" <<EOF
server {
    listen       8443 ssl;
    server_name  ${ZBX_IP};

    ssl_certificate      ${CERT_DIR}/zabbix.crt;
    ssl_certificate_key  ${CERT_DIR}/zabbix.key;

    root ${UI_DIR};

    index index.php;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        fastcgi_pass unix:/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF

# Configurar zabbix.conf.php
mkdir -p "$(dirname "$ZBX_CONF_PHP")"
cat > "$ZBX_CONF_PHP" <<EOF
<?php
\$DB['TYPE']     = 'POSTGRESQL';
\$DB['SERVER']   = 'localhost';
\$DB['PORT']     = '5432';
\$DB['DATABASE'] = '${ZBX_DB}';
\$DB['USER']     = '${ZBX_USER}';
\$DB['PASSWORD'] = '${ZBX_PASS}';

\$ZBX_SERVER      = 'localhost';
\$ZBX_SERVER_PORT = '10051';
\$ZBX_SERVER_NAME = 'Zabbix Server';

\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
EOF
ln -sf "$ZBX_CONF_PHP" /usr/share/zabbix/ui/conf/zabbix.conf.php

# Archivo de prueba PHP
echo "<?php phpinfo(); ?>" > "${UI_DIR}/info.php"

# Arranque de servicios
systemctl enable --now zabbix-server zabbix-agent nginx php-fpm

# Final
echo "✅ Instalación completada. Accede a:"
echo "🌐 https://${ZBX_IP}:8443"
echo "🧪 https://${ZBX_IP}:8443/info.php (verifica PHP)"
