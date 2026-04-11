FROM python:3.11-slim

# Evitar archivos .pyc y buffering
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Dependencias del sistema (psycopg2-binary las incluye, pero por si acaso)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Instalar dependencias Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar código
COPY . .

# Puerto expuesto dinámico para Railway
EXPOSE ${PORT:-8000}

# Arranque con uvicorn — usando el puerto de la variable de entorno PORT
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers ${UVICORN_WORKERS:-2}
