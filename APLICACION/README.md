# 📦 Despliegue de Aplicación Flask en Kubernetes con Docker

Este proyecto contiene los pasos para construir, subir y desplegar una aplicación Flask en un clúster de Kubernetes, utilizando Docker y almacenamiento persistente.

---

## 🐳 Construcción y subida de la imagen a Docker Hub

### 1. Acceder a WSL desde Windows

```bash
wsl -d Ubuntu
```

### 2. Verificar sesión en Docker

```bash
docker login
docker info  # Verifica que estás logueado con el usuario correcto
```

### 3. Construcción y subida de la imagen

```bash
docker build -t jvicmar95/aplicacionjorge:v4 .
docker push jvicmar95/aplicacionjorge:v4
```

---

## ☸️ Despliegue en Kubernetes

### 1. Crear namespace

```bash
kubectl create namespace aplicacion
```

### 2. Crear volumen persistente (`pvc-aplicacion.yaml`)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: aplicacion-pvc
  namespace: aplicacion
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: do-block-storage
```

### 3. Crear servicio tipo NodePort (`service-aplicacion.yaml`)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: aplicacion-service
  namespace: aplicacion
spec:
  selector:
    app: aplicacion
  ports:
    - protocol: TCP
      port: 80
      targetPort: 5000
      nodePort: 30080
  type: NodePort
```

### 4. Crear el deployment (`deployment-aplicacion.yaml`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aplicacion
  namespace: aplicacion
  labels:
    app: aplicacion
spec:
  replicas: 1
  selector:
    matchLabels:
      app: aplicacion
  template:
    metadata:
      labels:
        app: aplicacion
    spec:
      containers:
        - name: flask
          image: jvicmar95/aplicacionjorge:v1
          ports:
            - containerPort: 5000
          volumeMounts:
            - name: datos
              mountPath: /app/data
      volumes:
        - name: datos
          persistentVolumeClaim:
            claimName: aplicacion-pvc
```

### 5. Aplicar todo

```bash
kubectl apply -f pvc-aplicacion.yaml
kubectl apply -f service-aplicacion.yaml
kubectl apply -f deployment-aplicacion.yaml
```

---

## 🌐 Acceso a la aplicación

### Opción 1: Por NodePort (IP pública o minikube)

```bash
kubectl get svc -n aplicacion
```

### Opción 2: Por port-forward

```bash
kubectl port-forward svc/aplicacion-service 8080:80 -n aplicacion
```

Accede desde: [http://localhost:8080](http://localhost:8080)

---

## ✅ Resumen de comandos clave

```bash
wsl -d Ubuntu
docker login
docker info
docker build -t jvicmar95/aplicacionjorge:v1 .
docker push jvicmar95/aplicacionjorge:v1
kubectl create namespace aplicacion
kubectl apply -f pvc-aplicacion.yaml
kubectl apply -f service-aplicacion.yaml
kubectl apply -f deployment-aplicacion.yaml
kubectl port-forward svc/aplicacion-service 8080:80 -n aplicacion
```

---

## 🧠 Autor

Creado por Jorge Vicente (usuario de Docker Hub: `jvicmar95`)