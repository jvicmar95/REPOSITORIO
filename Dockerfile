# Imagen base oficial de Python
FROM python:3.11-slim

# Establecer el directorio de trabajo
WORKDIR /app

# Copiar todos los archivos necesarios al contenedor
COPY . .

# Instalar las dependencias necesarias
RUN pip install --no-cache-dir -r requirements.txt

# Exponer el puerto que utiliza Flask
EXPOSE 5000

# Comando para ejecutar la aplicación
CMD ["python", "app.py"]
