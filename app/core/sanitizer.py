"""
Sanitización de inputs de texto libre.
Previene XSS, inyección de caracteres de control y payloads maliciosos.
"""
import re
import unicodedata

# Caracteres de control Unicode (excepto tab, newline, carriage return)
_CONTROL_CHARS = re.compile(
    r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f"   # ASCII control
    r"\u200b-\u200f\u202a-\u202e\u2060-\u2064\ufeff]"  # Unicode invisible
)

# Patrones de inyección comunes
_SQL_PATTERNS = re.compile(
    r"(\b(SELECT|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|EXEC|UNION|SCRIPT)\b)",
    re.IGNORECASE,
)

_HTML_TAGS = re.compile(r"<[^>]+>")

# Longitudes máximas por tipo de campo
MAX_LENGTHS = {
    "name": 100,
    "description": 500,
    "location_name": 255,
    "text": 100,   # chat
    "reaction": 100,
    "phone": 30,
    "email": 255,
}


def sanitize_text(value: str, max_length: int = 255) -> str:
    """
    Limpia un campo de texto libre:
    1. Normaliza Unicode (NFC)
    2. Elimina caracteres de control
    3. Trunca a max_length
    4. Strip de espacios extremos
    """
    if not isinstance(value, str):
        return value

    # Normalizar Unicode para evitar bypass con caracteres homoglifos
    value = unicodedata.normalize("NFC", value)

    # Eliminar caracteres de control
    value = _CONTROL_CHARS.sub("", value)

    # Eliminar tags HTML
    value = _HTML_TAGS.sub("", value)

    # Truncar
    value = value[:max_length]

    # Strip
    return value.strip()


def sanitize_name(value: str) -> str:
    return sanitize_text(value, MAX_LENGTHS["name"])


def sanitize_description(value: str) -> str:
    return sanitize_text(value, MAX_LENGTHS["description"])


def sanitize_location(value: str) -> str:
    return sanitize_text(value, MAX_LENGTHS["location_name"])


def sanitize_chat_text(value: str) -> str:
    return sanitize_text(value, MAX_LENGTHS["text"])
