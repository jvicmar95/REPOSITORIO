# 📊 Stack de Monitorización: Grafana, Prometheus, Loki

Este entorno despliega un stack completo de observabilidad sobre Kubernetes utilizando manifiestos YAML gestionados por Argo CD. Incluye:

- ✅ **Prometheus** para métricas.
- ✅ **Grafana** para visualización.
- ✅ **Loki + Promtail** para logs.
- ✅ **Dashboards auto-provisionados** mediante ConfigMaps.

---

## 📁 Estructura

---

## 🖼️ Vista previa del stack

### 🔸 Dashboard de estado general

![Dashboard 1](./imagenes_readme/app_monitorizacion_1.png)

### 🔸 Logs centralizados (Loki)

![Dashboard 2](./imagenes_readme/app_monitorizacion_2.png)

### 🔸 Prometheus y alertas

![Dashboard 3](./imagenes_readme/app_monitorizacion_3.png)

### 🔸 Estado del clúster Kubernetes

![Dashboard 4](./imagenes_readme/app_monitorizacion_4.png)

### 🔸 Panel de nodos (Gráfico circular)

![Dashboard 5](./imagenes_readme/app_monitorizacion_5.png)

---

## 🚀 Despliegue con Argo CD

Asegúrate de tener Argo CD apuntando a este path:


