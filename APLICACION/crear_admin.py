import db

if __name__ == "__main__":
    exito = db.crear_usuario("admin", "pass1234")
    if exito:
        print("Usuario admin creado")
    else:
        print("Usuario admin ya existe")
