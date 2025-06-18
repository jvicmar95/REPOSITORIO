from flask import Flask, render_template, request, redirect, url_for, send_from_directory, session
import db
from datetime import datetime
import os
import shutil
import logging
from werkzeug.middleware.proxy_fix import ProxyFix
from calendar import Calendar
import calendar
import sqlite3

# === Configuración inicial ===
app = Flask(__name__)
app.wsgi_app = ProxyFix(app.wsgi_app)
app.secret_key = "una_clave_segura"
db.init_db()

BACKUP_DIR = os.path.join(os.path.dirname(__file__), 'backups')
os.makedirs(BACKUP_DIR, exist_ok=True)

# === Logging ===
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    handlers=[logging.StreamHandler()]
)

# Configurar logger werkzeug para que use formato y nivel INFO
logger = logging.getLogger('werkzeug')
logger.setLevel(logging.INFO)
for handler in logger.handlers[:]:
    logger.removeHandler(handler)
stream_handler = logging.StreamHandler()
stream_handler.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s [%(levelname)s] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
stream_handler.setFormatter(formatter)
logger.addHandler(stream_handler)

# === Filtro de fecha ===
@app.template_filter('to_datetime')
def to_datetime_filter(value, format='%Y-%m-%d'):
    try:
        return datetime.strptime(value, format)
    except Exception:
        return None

# === Login y Logout ===
@app.route("/login", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        usuario = request.form["username"]
        contrasena = request.form["password"]
        if db.verificar_usuario(usuario, contrasena):
            session["usuario"] = usuario
            return redirect(url_for("home"))
        else:
            error = "Credenciales inválidas"
    return render_template("login.html", error=error)

@app.route("/logout")
def logout():
    session.pop("usuario", None)
    return redirect(url_for("login"))

# === Rutas protegidas ===
@app.route("/")
def home():
    if "usuario" not in session:
        return redirect(url_for("login"))
    return render_template("home.html", usuario=session["usuario"])

@app.route("/tareas")
def index():
    if "usuario" not in session:
        return redirect(url_for("login"))
    tareas = db.obtener_tareas()
    pendientes = [t for t in tareas if t["estado"] == "pendiente"]
    en_progreso = [t for t in tareas if t["estado"] == "progreso"]
    completadas = [t for t in tareas if t["estado"] == "completada"]
    backups = sorted(os.listdir(BACKUP_DIR), reverse=True)[:3]
    return render_template("index.html", pendientes=pendientes, progreso=en_progreso, completadas=completadas, backups=backups, now=datetime.now(), usuario=session["usuario"])

@app.route("/add", methods=["POST"])
def add():
    if "usuario" not in session:
        return redirect(url_for("login"))
    tarea = request.form.get("tarea", "").strip()
    etiqueta = request.form.get("etiqueta", "").strip()
    if tarea:
        db.agregar_tarea(tarea, etiqueta)
    return redirect(url_for("index"))

@app.route("/delete/<int:tarea_id>")
def delete(tarea_id):
    if "usuario" not in session:
        return redirect(url_for("login"))
    db.eliminar_tarea(tarea_id)
    return redirect(url_for("index"))

@app.route("/edit/<int:tarea_id>", methods=["POST"])
def edit(tarea_id):
    if "usuario" not in session:
        return redirect(url_for("login"))
    nuevo_texto = request.form.get("nuevo_texto", "").strip()
    if nuevo_texto:
        db.editar_tarea(tarea_id, nuevo_texto)
    return redirect(url_for("index"))

@app.route("/nota/<int:tarea_id>", methods=["POST"])
def nota(tarea_id):
    if "usuario" not in session:
        return redirect(url_for("login"))
    nota = request.form.get("nota", "").strip()
    db.actualizar_nota(tarea_id, nota)
    return redirect(url_for("index"))

@app.route("/mover/<int:tarea_id>/<nuevo_estado>")
def mover(tarea_id, nuevo_estado):
    if "usuario" not in session:
        return redirect(url_for("login"))
    db.cambiar_estado(tarea_id, nuevo_estado)
    return redirect(url_for("index"))

@app.route("/fecha/<int:tarea_id>", methods=["POST"])
def fecha(tarea_id):
    if "usuario" not in session:
        return redirect(url_for("login"))
    fecha_limite = request.form.get("fecha_limite", "").strip()
    try:
        datetime.strptime(fecha_limite, "%Y-%m-%d")
    except:
        fecha_limite = None
    db.actualizar_fecha_limite(tarea_id, fecha_limite)
    return redirect(url_for("index"))

@app.route("/crear_backup", methods=["POST"])
def crear_backup():
    if "usuario" not in session:
        return redirect(url_for("login"))
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_name = f"backuptareas_{timestamp}.db"
    shutil.copy2(os.path.join(db.DATA_DIR, 'tareas.db'), os.path.join(BACKUP_DIR, backup_name))
    backups = sorted(os.listdir(BACKUP_DIR))
    while len(backups) > 3:
        os.remove(os.path.join(BACKUP_DIR, backups[0]))
        backups.pop(0)
    return redirect(url_for("index"))

@app.route("/descargar_backup/<nombre_backup>")
def descargar_backup(nombre_backup):
    if "usuario" not in session:
        return redirect(url_for("login"))
    return send_from_directory(BACKUP_DIR, nombre_backup, as_attachment=True)

@app.route("/calendario")
def calendario():
    if "usuario" not in session:
        return redirect(url_for("login"))
    tareas = db.obtener_tareas()
    hoy = datetime.now()
    anio = request.args.get("anio", hoy.year, type=int)
    mes = request.args.get("mes", hoy.month, type=int)

    if mes < 1:
        mes = 12
        anio -= 1
    elif mes > 12:
        mes = 1
        anio += 1

    fecha_hoy = hoy.date()
    nombre_mes = calendar.month_name[mes].capitalize()
    dias_semana = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]
    cal = Calendar(firstweekday=0)
    semanas = cal.monthdatescalendar(anio, mes)

    eventos_por_dia = {}
    for t in tareas:
        if t["fecha_limite"]:
            try:
                fecha = datetime.strptime(t["fecha_limite"], "%Y-%m-%d").date()
                if fecha.year == anio and fecha.month == mes:
                    eventos_por_dia.setdefault(fecha.isoformat(), []).append(t["texto"])
            except:
                continue

    return render_template("calendario.html", nombre_mes=nombre_mes, anio=anio, dias_semana=dias_semana,
        calendario=semanas, eventos_por_dia=eventos_por_dia, mes=mes, fecha_hoy=fecha_hoy,
        mes_anterior=mes-1 if mes > 1 else 12, anio_anterior=anio if mes > 1 else anio-1,
        mes_siguiente=mes+1 if mes < 12 else 1, anio_siguiente=anio if mes < 12 else anio+1,
        usuario=session["usuario"])

@app.route("/etiqueta/<int:tarea_id>", methods=["POST"])
def etiqueta(tarea_id):
    if "usuario" not in session:
        return redirect(url_for("login"))
    nueva_etiqueta = request.form.get("nueva_etiqueta", "").strip()
    if nueva_etiqueta:
        db.actualizar_etiqueta(tarea_id, nueva_etiqueta)
    return redirect(url_for("index"))

@app.route("/register", methods=["GET", "POST"])
def register():
    error = None
    if request.method == "POST":
        usuario = request.form["username"].strip()
        contrasena = request.form["password"].strip()
        contrasena_confirm = request.form["password_confirm"].strip()

        if not usuario or not contrasena or not contrasena_confirm:
            error = "Todos los campos son obligatorios."
        elif contrasena != contrasena_confirm:
            error = "Las contraseñas no coinciden."
        else:
            exito = db.crear_usuario(usuario, contrasena)
            if exito:
                return redirect(url_for("login"))
            else:
                error = "El usuario ya existe."

    return render_template("register.html", error=error)

@app.route("/usuarios")
def ver_usuarios():
    # Quitar chequeos de sesión para pruebas, o comentalos si quieres seguridad:
    # if "usuario" not in session:
    #     return redirect(url_for("login"))
    #
    # if session["usuario"] != "admin":
    #     return "No tienes permisos para ver esta página", 403

    usuarios = []
    try:
        usuarios = db.obtener_usuarios_con_pass()  # Obtiene lista de dicts {username, password}
        print("Usuarios en DB:", usuarios)
    except Exception as e:
        print(f"Error accediendo a la base de datos: {e}")
        return f"Error accediendo a la base de datos: {e}"

    return render_template("usuarios.html", usuarios=usuarios)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
