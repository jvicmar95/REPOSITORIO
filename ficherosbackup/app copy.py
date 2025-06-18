from flask import Flask, render_template, request, redirect, url_for, send_from_directory
import db
from datetime import datetime
import os
import shutil
import logging
from werkzeug.middleware.proxy_fix import ProxyFix
from calendar import monthrange
import calendar

# === Configurar logging ===
# LOG_DIR = '/app/logs'
# os.makedirs(LOG_DIR, exist_ok=True)
# log_file = os.path.join(LOG_DIR, 'tareas.log')

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    handlers=[
        logging.StreamHandler()
    ]
)


app = Flask(__name__)
app.wsgi_app = ProxyFix(app.wsgi_app)
db.init_db()

BACKUP_DIR = os.path.join(os.path.dirname(__file__), 'backups')
os.makedirs(BACKUP_DIR, exist_ok=True)

# === Filtro personalizado para fechas ===
@app.template_filter('to_datetime')
def to_datetime_filter(value, format='%Y-%m-%d'):
    try:
        return datetime.strptime(value, format)
    except Exception:
        return None

@app.route("/")
def home():
    return render_template("home.html")

@app.route("/tareas")
def index():
    tareas = db.obtener_tareas()
    pendientes = [t for t in tareas if t["estado"] == "pendiente"]
    en_progreso = [t for t in tareas if t["estado"] == "progreso"]
    completadas = [t for t in tareas if t["estado"] == "completada"]
    backups = sorted(os.listdir(BACKUP_DIR), reverse=True)[:3]

    app.logger.info(f"📄 Página principal cargada con {len(tareas)} tareas | IP: {request.remote_addr} | Agent: {request.user_agent}")
    return render_template("index.html", pendientes=pendientes, progreso=en_progreso, completadas=completadas, now=datetime.now(), backups=backups)

@app.route("/add", methods=["POST"])
def add():
    tarea = request.form.get("tarea", "").strip()
    etiqueta = request.form.get("etiqueta", "").strip()
    if tarea:
        db.agregar_tarea(tarea, etiqueta)
        app.logger.info(f"✔ Tarea agregada: '{tarea}' con etiqueta '{etiqueta}'")
    return redirect(url_for("index"))

@app.route("/delete/<int:tarea_id>")
def delete(tarea_id):
    db.eliminar_tarea(tarea_id)
    app.logger.warning(f"❌ Tarea eliminada (id={tarea_id}) | IP: {request.remote_addr}")
    return redirect(url_for("index"))

@app.route("/edit/<int:tarea_id>", methods=["POST"])
def edit(tarea_id):
    nuevo_texto = request.form.get("nuevo_texto", "").strip()
    if nuevo_texto:
        db.editar_tarea(tarea_id, nuevo_texto)
        app.logger.info(f"✏️ Tarea editada (id={tarea_id}): nuevo texto = '{nuevo_texto}'")
    return redirect(url_for("index"))

@app.route("/nota/<int:tarea_id>", methods=["POST"])
def nota(tarea_id):
    nota = request.form.get("nota", "").strip()
    db.actualizar_nota(tarea_id, nota)
    app.logger.info(f"📝 Nota actualizada (id={tarea_id})")
    return redirect(url_for("index"))

@app.route("/mover/<int:tarea_id>/<nuevo_estado>")
def mover(tarea_id, nuevo_estado):
    db.cambiar_estado(tarea_id, nuevo_estado)
    app.logger.info(f"🔁 Estado cambiado (id={tarea_id}) a '{nuevo_estado}'")
    return redirect(url_for("index"))

@app.route("/fecha/<int:tarea_id>", methods=["POST"])
def fecha(tarea_id):
    fecha_limite_str = request.form.get("fecha_limite", "").strip()
    fecha_limite = None
    if fecha_limite_str:
        try:
            datetime.strptime(fecha_limite_str, "%Y-%m-%d")
            fecha_limite = fecha_limite_str
        except ValueError:
            fecha_limite = None
    db.actualizar_fecha_limite(tarea_id, fecha_limite)
    app.logger.info(f"📅 Fecha límite actualizada (id={tarea_id}) a '{fecha_limite}'")
    return redirect(url_for("index"))

@app.route("/crear_backup", methods=["POST"])
def crear_backup():
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_name = f"backuptareas_{timestamp}.db"
    src = os.path.join(db.DATA_DIR, 'tareas.db')
    dst = os.path.join(BACKUP_DIR, backup_name)
    shutil.copy2(src, dst)

    backups = sorted(os.listdir(BACKUP_DIR))
    while len(backups) > 3:
        os.remove(os.path.join(BACKUP_DIR, backups[0]))
        backups.pop(0)

    app.logger.info(f"🗂 Backup creado: {backup_name}")
    return redirect(url_for("index"))

@app.route("/descargar_backup/<nombre_backup>")
def descargar_backup(nombre_backup):
    app.logger.info(f"⬇ Descarga de backup solicitada: {nombre_backup}")
    return send_from_directory(BACKUP_DIR, nombre_backup, as_attachment=True)

@app.route("/calendario")
def calendario():
    from flask import request
    tareas = db.obtener_tareas()

    # Obtener mes y año de la URL (si existen)
    hoy = datetime.now()
    anio = request.args.get("anio", default=hoy.year, type=int)
    mes = request.args.get("mes", default=hoy.month, type=int)

    # Corregir desbordes (mes 0 o 13)
    if mes < 1:
        mes = 12
        anio -= 1
    elif mes > 12:
        mes = 1
        anio += 1

    fecha_hoy = hoy.date()
    nombre_mes = calendar.month_name[mes].capitalize()
    dias_semana = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]

    cal = calendar.Calendar(firstweekday=0)
    semanas = cal.monthdatescalendar(anio, mes)

    eventos_por_dia = {}
    for t in tareas:
        if t["fecha_limite"]:
            try:
                fecha = datetime.strptime(t["fecha_limite"], "%Y-%m-%d").date()
                if fecha.year == anio and fecha.month == mes:
                    eventos_por_dia.setdefault(fecha.isoformat(), []).append(t["texto"])
            except Exception:
                continue

    # Mes anterior y siguiente
    mes_anterior = mes - 1
    anio_anterior = anio
    if mes_anterior < 1:
        mes_anterior = 12
        anio_anterior -= 1

    mes_siguiente = mes + 1
    anio_siguiente = anio
    if mes_siguiente > 12:
        mes_siguiente = 1
        anio_siguiente += 1

    return render_template(
        "calendario.html",
        nombre_mes=nombre_mes,
        anio=anio,
        dias_semana=dias_semana,
        calendario=semanas,
        eventos_por_dia=eventos_por_dia,
        mes=mes,
        fecha_hoy=fecha_hoy,
        mes_anterior=mes_anterior,
        anio_anterior=anio_anterior,
        mes_siguiente=mes_siguiente,
        anio_siguiente=anio_siguiente
    )

@app.route("/etiqueta/<int:tarea_id>", methods=["POST"])
def etiqueta(tarea_id):
    nueva_etiqueta = request.form.get("nueva_etiqueta", "").strip()
    if nueva_etiqueta:
        db.actualizar_etiqueta(tarea_id, nueva_etiqueta)
        app.logger.info(f"🏷 Etiqueta cambiada (id={tarea_id}) a '{nueva_etiqueta}'")
    return redirect(url_for("index"))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

