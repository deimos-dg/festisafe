#!/bin/bash
# Actualiza un valor en Secrets Manager sin recrear el secret.
# Uso: ./deploy/update-secret.sh SECRET_KEY "nuevo-valor"

set -euo pipefail

AWS_REGION="us-east-1"
APP_NAME="festisafe"
KEY="$1"
VALUE="$2"

CURRENT=$(aws secretsmanager get-secret-value \
  --secret-id "${APP_NAME}/env" \
  --region "$AWS_REGION" \
  --query "SecretString" --output text)

UPDATED=$(echo "$CURRENT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
d['$KEY'] = '$VALUE'
print(json.dumps(d))
")

aws secretsmanager update-secret \
  --secret-id "${APP_NAME}/env" \
  --region "$AWS_REGION" \
  --secret-string "$UPDATED"

echo "Secreto '$KEY' actualizado correctamente"
