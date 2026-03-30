#!/bin/bash
# =============================================================================
# FestiSafe — Deploy a AWS ECS Fargate
# Uso: ./deploy/deploy.sh
#
# Requisitos previos:
#   - AWS CLI instalado y configurado (aws configure)
#   - Docker instalado y corriendo
#   - Permisos IAM: ECR, ECS, RDS, IAM, EC2, SecretsManager
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# CONFIGURACIÓN — edita estos valores antes de ejecutar
# ---------------------------------------------------------------------------
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
APP_NAME="festisafe"
ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}"
ECS_CLUSTER="${APP_NAME}-cluster"
ECS_SERVICE="${APP_NAME}-service"
TASK_FAMILY="${APP_NAME}-task"
IMAGE_TAG=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")

echo "=== FestiSafe Deploy ==="
echo "Account : $AWS_ACCOUNT_ID"
echo "Region  : $AWS_REGION"
echo "Image   : ${ECR_REPO}:${IMAGE_TAG}"
echo ""

# ---------------------------------------------------------------------------
# 1. Crear repositorio ECR (si no existe)
# ---------------------------------------------------------------------------
echo "[1/5] Verificando repositorio ECR..."
aws ecr describe-repositories --repository-names "$APP_NAME" --region "$AWS_REGION" > /dev/null 2>&1 || \
  aws ecr create-repository \
    --repository-name "$APP_NAME" \
    --region "$AWS_REGION" \
    --image-scanning-configuration scanOnPush=true \
    --query "repository.repositoryUri" \
    --output text

# ---------------------------------------------------------------------------
# 2. Build y push de la imagen
# ---------------------------------------------------------------------------
echo "[2/5] Build y push de imagen Docker..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

docker build -t "${APP_NAME}:${IMAGE_TAG}" .
docker tag "${APP_NAME}:${IMAGE_TAG}" "${ECR_REPO}:${IMAGE_TAG}"
docker tag "${APP_NAME}:${IMAGE_TAG}" "${ECR_REPO}:latest"
docker push "${ECR_REPO}:${IMAGE_TAG}"
docker push "${ECR_REPO}:latest"

echo "  Imagen publicada: ${ECR_REPO}:${IMAGE_TAG}"

# ---------------------------------------------------------------------------
# 3. Registrar nueva Task Definition
# ---------------------------------------------------------------------------
echo "[3/5] Registrando Task Definition..."

# Lee el ARN del secret desde SSM (creado en setup.sh)
SECRET_ARN=$(aws secretsmanager describe-secret \
  --secret-id "${APP_NAME}/env" \
  --region "$AWS_REGION" \
  --query "ARN" --output text 2>/dev/null || echo "")

TASK_DEF=$(cat <<EOF
{
  "family": "${TASK_FAMILY}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${APP_NAME}-ecs-execution-role",
  "taskRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${APP_NAME}-ecs-task-role",
  "containerDefinitions": [
    {
      "name": "${APP_NAME}",
      "image": "${ECR_REPO}:${IMAGE_TAG}",
      "portMappings": [{"containerPort": 8000, "protocol": "tcp"}],
      "essential": true,
      "environment": [
        {"name": "UVICORN_WORKERS", "value": "2"}
      ],
      "secrets": [
        {"name": "SECRET_KEY",      "valueFrom": "${SECRET_ARN}:SECRET_KEY::"},
        {"name": "DATABASE_URL",    "valueFrom": "${SECRET_ARN}:DATABASE_URL::"},
        {"name": "DEBUG",           "valueFrom": "${SECRET_ARN}:DEBUG::"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${APP_NAME}",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8000/health/ || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 15
      }
    }
  ]
}
EOF
)

NEW_TASK_ARN=$(aws ecs register-task-definition \
  --cli-input-json "$TASK_DEF" \
  --region "$AWS_REGION" \
  --query "taskDefinition.taskDefinitionArn" \
  --output text)

echo "  Task Definition: $NEW_TASK_ARN"

# ---------------------------------------------------------------------------
# 4. Actualizar servicio ECS
# ---------------------------------------------------------------------------
echo "[4/5] Actualizando servicio ECS..."
aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$ECS_SERVICE" \
  --task-definition "$NEW_TASK_ARN" \
  --force-new-deployment \
  --region "$AWS_REGION" > /dev/null

# ---------------------------------------------------------------------------
# 5. Esperar deployment estable
# ---------------------------------------------------------------------------
echo "[5/5] Esperando que el servicio estabilice (puede tardar ~2 min)..."
aws ecs wait services-stable \
  --cluster "$ECS_CLUSTER" \
  --services "$ECS_SERVICE" \
  --region "$AWS_REGION"

echo ""
echo "=== Deploy completado exitosamente ==="
echo "Imagen: ${ECR_REPO}:${IMAGE_TAG}"
