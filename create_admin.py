import sys
import os

# Añadir el directorio actual al path
sys.path.append(os.getcwd())

# IMPORTANTE: Importar todos los modelos para evitar errores de relación
from app.db.models.company import Company
from app.db.models.user import User, UserRole
from app.db.models.geofence import Geofence
from app.db.models.broadcast import BroadcastMessage
from app.db.models.user_location_history import UserLocationHistory

from app.db.session import SessionLocal
from app.core.security import hash_password

def create_super_admin():
    db = SessionLocal()
    try:
        email = "admin@festisafe.com"
        password = "AdminSecretPassword123!"

        exists = db.query(User).filter(User.email == email).first()
        if exists:
            print(f"El admin {email} ya existe.")
            return

        new_admin = User(
            email=email,
            hashed_password=hash_password(password),
            full_name="Super Admin FestiSafe",
            role=UserRole.admin,
            is_active=True,
            is_verified=True
        )

        db.add(new_admin)
        db.commit()
        print(f"✅ ¡Super Admin creado con éxito!")
        print(f"📧 Email: {email}")
        print(f"🔑 Password: {password}")

    except Exception as e:
        print(f"❌ Error: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    create_super_admin()
