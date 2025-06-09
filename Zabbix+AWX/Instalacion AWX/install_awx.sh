#Pasos:
#Crear en /opt el directorio AWX
#En /opt/AWX crear el script .sh llamado instalacion_AWX_K3_HTTPS_LOCAL.sh
#Dar permisos al script con chmod +x
#Ejecutar el script ./instalacion_AWX_K3_HTTPS_LOCAL.sh
#Acceder al portal de AWX 
#---------------------------------------------------------
#Código del script instalacion_AWX_K3_HTTPS_LOCAL.sh: 
 
#!/bin/bash
 
set -e
 
# Variables
AWX_VERSION="2.19.1"
AWX_HOST="awx.local"
POSTGRES_PASS="Ansible123!"
ADMIN_PASS="Ansible123!"
DATA_DIR="/data"
K3S_VERSION="v1.29.6+k3s2"
AWX_DIR="$HOME/awx-on-k3s"
 
echo "🔧 Cambiando al directorio home..."
cd ~
 
# Verificar si el directorio ya existe y eliminarlo si es necesario
if [ -d "$AWX_DIR" ]; then
  echo "🧹 Eliminando directorio existente $AWX_DIR..."
  sudo rm -rf "$AWX_DIR"
fi
 
# -------------------------
# 1. Instalar dependencias
# -------------------------
echo "📦 Instalando dependencias (git, curl)..."
sudo dnf install -y git curl
 
# -------------------------
# 2. Instalar K3s
# -------------------------
echo "🐳 Instalando K3s versión ${K3S_VERSION}..."
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${K3S_VERSION} sh -s - --write-kubeconfig-mode 644
 
# Verificar que K3s está corriendo
echo "✅ Verificando que K3s esté activo..."
sudo systemctl is-active --quiet k3s && echo "K3s está activo" || (echo "K3s no está activo" && exit 1)
 
# ---------------------------
# 3. Clonar repositorio de K3
# ---------------------------
echo "📁 Clonando el repositorio AWX-On-K3s..."
git clone https://github.com/kurokobo/awx-on-k3s.git
cd awx-on-k3s
git checkout $AWX_VERSION
 
# -------------------------
# 4. Instalar AWX Operator
# -------------------------
echo "🚀 Aplicando el operador AWX..."
kubectl apply -k operator
 
# ----------------------------------
# 5. Generar certificado autofirmado
# ----------------------------------
echo "🔐 Generando certificado TLS autofirmado..."
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -out ./base/tls.crt -keyout ./base/tls.key \
  -subj "/CN=${AWX_HOST}/O=Naturgy" \
  -addext "subjectAltName = DNS:${AWX_HOST}"
 
kubectl create secret tls awx-secret-tls \
  --cert=./base/tls.crt \
  --key=./base/tls.key
 
# -----------------------
# 6. Actualizar AWX_HOST 
# ----------------------
echo "🛠️ Configurando hostname en base/awx.yaml..."
sed -i "s/hostname: .*/hostname: ${AWX_HOST}/" base/awx.yaml
 
# ---------------------------------------------- 
# 7.Establecer contraseñas en kustomization.yaml
# ----------------------------------------------
echo "🔑 Configurando contraseñas en base/kustomization.yaml..."
sed -i "s/password=.*/password=${POSTGRES_PASS}/" base/kustomization.yaml
sed -i "/name: awx-admin-password/,/literals:/ s/password=.*/password=${ADMIN_PASS}/" base/kustomization.yaml
 
# ----------------------------------
# 8. Preparar volúmenes persistentes
# ----------------------------------
echo "📂 Creando directorios persistentes..."
sudo mkdir -p ${DATA_DIR}/postgres-15
sudo mkdir -p ${DATA_DIR}/projects
sudo chown 1000:0 ${DATA_DIR}/projects
 
# -----------------
# 9. Desplegar AWX
# -----------------
echo "📦 Desplegando AWX..."
kubectl apply -k base
 
# -------------------------
# 10. Esperar estado de pods
# -------------------------
echo "📦 Esperando a que el namespace 'awx' tenga recursos..."
 
until kubectl get ns awx &>/dev/null; do
  echo "⌛ Namespace 'awx' aún no existe, reintentando..."
  sleep 5
done
 
while true; do
  PODS=$(kubectl get pods -n awx --no-headers 2>/dev/null || true)
 
  if [[ -z "$PODS" ]]; then
    echo "⌛ Aún no hay pods inicializados, reintentando..."
    sleep 10
    continue
  fi
 
  echo "⏳ Verificando estado de los pods en 'awx'..."
  echo "$PODS"
 
  ALL_READY=true
  MIGRATION_COMPLETED=false
 
  while read -r line; do
    POD_NAME=$(echo "$line" | awk '{print $1}')
    READY=$(echo "$line" | awk '{print $2}')
    STATUS=$(echo "$line" | awk '{print $3}')
 
    # Verificar errores en los pods
    if [[ "$STATUS" == "Error" || "$STATUS" == "CrashLoopBackOff" ]]; then
      echo "❌ Error detectado en el pod '$POD_NAME' con estado '$STATUS'"
      kubectl describe pod "$POD_NAME" -n awx
      exit 1
    fi
 
    # Validar estado del pod de migración
    if [[ "$POD_NAME" == awx-migration* ]]; then
      if [[ "$STATUS" == "Completed" ]]; then
        MIGRATION_COMPLETED=true
      else
        ALL_READY=false
        break
      fi
      continue
    fi
 
    # Validar estado de los demás pods
    if [[ "$STATUS" != "Running" ]]; then
      ALL_READY=false
      break
    fi
 
    if [[ "$READY" != */* ]]; then
      ALL_READY=false
      break
    fi
 
    READY_COUNT=$(echo "$READY" | cut -d'/' -f1)
    TOTAL_COUNT=$(echo "$READY" | cut -d'/' -f2)
 
    if [[ "$READY_COUNT" != "$TOTAL_COUNT" ]]; then
      ALL_READY=false
      break
    fi
  done <<< "$PODS"
 
  if [[ "$ALL_READY" = true && "$MIGRATION_COMPLETED" = true ]]; then
    echo "✅ Todos los pods están en estado correcto y la instalación ha finalizado."
    break
  fi
 
  echo "⌛ Aún no están listos todos los pods. Actualizando estado cada 5 segundos, por favor espere..."
  sleep 5
done
 
# -------------------------
# 11. Resultado final
# -------------------------
 
echo -e "\n✅ Estado final de los pods:"
kubectl get pods -n awx
 
echo -e "\n🎉 ¡AWX se ha instalado correctamente!"
echo "🔗 Accede desde: https://${AWX_HOST}"
echo "👤 Usuario: admin"
echo "🔑 Contraseña: ${ADMIN_PASS}"