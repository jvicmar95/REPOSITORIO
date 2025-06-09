#!/bin/bash

set -euo pipefail

ZBX_IP="40.117.43.69"
ZBX_DB="zabbix"
ZBX_USER="zabbix"
ZBX_PASS="zabbix"
CERT_DIR="/etc/ssl/zabbix"
NGINX_CONF="/etc/nginx/conf.d/zabbix.conf"
PG_HBA="/var/lib/pgsql/data/pg_hba.conf"
PHP_INI="/etc/php.ini"
PHP_POOL="/etc/php-fpm.d/www.conf"
ZBX_CONF_PHP="/usr/share/zabbix/ui/conf/zabbix.conf.php"

echo "🚀 [INICIO] Instalación de Zabbix 7.2 con PostgreSQL y Nginx..."

# 🧹 Paso 0: Limpieza previa
echo "🧹 [CLEAN] Eliminando configuraciones previas..."
dnf remove -y zabbix-* postgresql-server nginx || true
rm -rf /var/lib/pgsql /etc/zabbix /etc/nginx/conf.d/zabbix.conf "$CERT_DIR" "$ZBX_CONF_PHP"
dnf clean all

# 📦 Paso 1: Instalar repositorio Zabbix
echo "📦 [REPO] Instalando repositorio Zabbix..."
rpm -Uvh https://repo.zabbix.com/zabbix/7.2/release/rhel/9/noarch/zabbix-release-latest-7.2.el9.noarch.rpm

# 📦 Paso 2: Instalar paquetes necesarios
echo "📦 [PKG] Instalando Zabbix, PostgreSQL, Nginx y dependencias..."
dnf install -y zabbix-server-pgsql zabbix-web-pgsql zabbix-nginx-conf zabbix-sql-scripts zabbix-selinux-policy zabbix-agent postgresql-server nginx openssl php php-pgsql php-fpm

# 🛠️ Paso 3: Inicializar y arrancar PostgreSQL
echo "🛠️ [DB] Inicializando base de datos PostgreSQL..."
postgresql-setup --initdb
systemctl enable --now postgresql

# 🧑‍💻 Paso 4: Crear usuario y base de datos Zabbix
echo "🧑‍💻 [DB] Creando usuario y base de datos Zabbix en PostgreSQL..."
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

# 🧩 Paso 5: Importar esquema inicial
echo "🧩 [DB] Importando esquema de base de datos..."
zcat /usr/share/zabbix/sql-scripts/postgresql/server.sql.gz | sudo -u ${ZBX_USER} psql ${ZBX_DB}

# 🔐 Paso 6: Configurar pg_hba.conf para md5
echo "🔐 [DB] Configurando pg_hba.conf..."
sed -i 's/^\(local\s\+all\s\+all\s\+\)peer/\1md5/' "$PG_HBA"
sed -i 's/^\(host\s\+all\s\+all\s\+127\.0\.0\.1\/32\s\+\)ident/\1md5/' "$PG_HBA"
sed -i 's/^\(host\s\+all\s\+all\s\+::1\/128\s\+\)ident/\1md5/' "$PG_HBA"

# 🔄 Paso 7: Reiniciar PostgreSQL
echo "🔄 [DB] Reiniciando PostgreSQL..."
systemctl restart postgresql

# ⚙️ Paso 8: Configurar Zabbix server
echo "⚙️ [ZBX] Configurando Zabbix Server..."
sed -i "s/^# DBPassword=/DBPassword=${ZBX_PASS}/" /etc/zabbix/zabbix_server.conf

# 🔏 Paso 9: Crear certificado autofirmado
echo "🔏 [SSL] Generando certificado SSL autofirmado..."
mkdir -p "$CERT_DIR"
openssl req -x509 -nodes -days 1825 -newkey rsa:2048 \
    -keyout "$CERT_DIR/zabbix.key" -out "$CERT_DIR/zabbix.crt" \
    -subj "/C=ES/ST=None/L=None/O=Zabbix/CN=${ZBX_IP}"

# 🌐 Paso 10: Configurar Nginx con SSL y ruta UI
echo "🌐 [NGINX] Configurando Nginx con SSL..."
cat > "$NGINX_CONF" <<EOF
server {
    listen       8443 ssl;
    server_name  ${ZBX_IP};

    ssl_certificate      ${CERT_DIR}/zabbix.crt;
    ssl_certificate_key  ${CERT_DIR}/zabbix.key;

    root /usr/share/zabbix/ui;

    index index.php;

    location / {
        try_files \$uri \$uri/ =404;
    }
    location ~ \.php$ {
        fastcgi_pass unix:/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF

# ⚙️ Paso 11: Ajustar configuración PHP
echo "⚙️ [PHP] Ajustando configuración PHP en /etc/php.ini..."
sed -i 's/^post_max_size = .*/post_max_size = 32M/' "$PHP_INI"
sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 16M/' "$PHP_INI"
sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
sed -i 's/^max_input_time = .*/max_input_time = 300/' "$PHP_INI"

# ⚙️ Paso 12: Ajustar configuración PHP-FPM pool
echo "⚙️ [PHP-FPM] Ajustando configuración PHP-FPM pool..."
for param in "post_max_size:32M" "upload_max_filesize:16M" "max_execution_time:300" "max_input_time:300"; do
    key="${param%%:*}"
    val="${param##*:}"
    if grep -q "^\s*php_value\[$key\]" "$PHP_POOL"; then
        sed -i "s|^\s*php_value\[$key\].*|php_value[$key] = $val|" "$PHP_POOL"
    else
        echo "php_value[$key] = $val" >> "$PHP_POOL"
    fi
done

# 🧪 Paso 13: Crear archivo info.php
echo "🧪 [TEST] Creando archivo info.php para pruebas..."
echo "<?php phpinfo(); ?>" > /usr/share/zabbix/ui/info.php

# 🛠️ Paso 14: Crear configuración automática para omitir setup.php
echo "🛠️ [ZBX] Creando archivo zabbix.conf.php..."
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

# 🚀 Paso 15: Habilitar y arrancar servicios
echo "🚀 [START] Habilitando y arrancando servicios..."
systemctl enable --now zabbix-server zabbix-agent nginx php-fpm

# ✅ Fin
echo "✅ [FIN] Instalación completada con éxito."
echo "-----------------------------------------"
echo "🌐 Accede a la interfaz web desde:"
echo "  👉 https://${ZBX_IP}:8443/"
echo "  👉 https://${ZBX_IP}:8443/info.php  (verifica configuración PHP)"
echo ""
echo "🔐 Credenciales base de datos:"
echo "  👤 Usuario: ${ZBX_USER}"
echo "  🔑 Contraseña: ${ZBX_PASS}"
echo "  💾 Base de datos: ${ZBX_DB}"
echo "-----------------------------------------"
