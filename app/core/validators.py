"""
Validadores de seguridad para inputs del usuario.
"""
import re


# Contraseñas comunes que no deben permitirse aunque cumplan los requisitos
_COMMON_PASSWORDS = frozenset({
    "Password123!", "Passw0rd!", "Admin1234!", "Qwerty123!",
    "Welcome1!", "Festisafe1!", "Festival123!", "P@ssword1",
    "Contraseña1!", "Contrasena1!",
})


def validate_password(password: str) -> None:
    """
    Valida que la contraseña cumpla la política de seguridad:
    - Mínimo 12 caracteres
    - Al menos una mayúscula
    - Al menos una minúscula
    - Al menos un dígito
    - Al menos un carácter especial
    - Sin secuencias numéricas consecutivas (123, 234…)
    - No es una contraseña conocida/común
    """
    if len(password) < 12:
        raise ValueError("La contraseña debe tener al menos 12 caracteres")

    if not re.search(r"[A-Z]", password):
        raise ValueError("La contraseña debe contener al menos una letra mayúscula")

    if not re.search(r"[a-z]", password):
        raise ValueError("La contraseña debe contener al menos una letra minúscula")

    if not re.search(r"\d", password):
        raise ValueError("La contraseña debe contener al menos un número")

    if not re.search(r'[!@#$%^&*()\-_=+\[\]{};:\'",.<>?/\\|`~]', password):
        raise ValueError("La contraseña debe contener al menos un carácter especial")

    # Secuencias numéricas consecutivas ascendentes o descendentes
    digits = re.findall(r"\d+", password)
    for num in digits:
        for i in range(len(num) - 2):
            a, b, c = int(num[i]), int(num[i + 1]), int(num[i + 2])
            if (b == a + 1 and c == b + 1) or (b == a - 1 and c == b - 1):
                raise ValueError("La contraseña no debe contener secuencias numéricas consecutivas")

    # Contraseñas comunes conocidas
    if password in _COMMON_PASSWORDS:
        raise ValueError("Esta contraseña es demasiado común. Elige una más segura")


def validate_phone(phone: str) -> str:
    """
    Valida y normaliza un número de teléfono.
    Acepta formatos internacionales: +34612345678, 612345678, etc.
    """
    # Eliminar espacios y guiones
    cleaned = re.sub(r"[\s\-\(\)]", "", phone)

    if not re.match(r"^\+?\d{7,15}$", cleaned):
        raise ValueError("Número de teléfono inválido. Usa formato internacional (+34612345678)")

    return cleaned


def validate_uuid(value: str, label: str = "ID") -> str:
    """Valida que un string sea un UUID v4 válido."""
    import uuid
    try:
        uuid.UUID(value, version=4)
        return value
    except (ValueError, AttributeError):
        raise ValueError(f"{label} inválido")
