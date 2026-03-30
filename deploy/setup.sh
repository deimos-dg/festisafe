#!/bin/bash
# =============================================================================
# FestiSafe — Setup inicial de infraestructura AWS
# Ejecutar UNA SOLA VEZ antes del primer deploy.
#
# Crea: VPC, subnets, security groups, RDS, ALB, ECS cluster, roles IAM,
#       Secrets Manager, CloudWatch log group.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# CONFIGURACIÓN — edita antes de ejecutar
# ---------------------------------------------------------------------------
AWS_REGION="us-east-1"
APP_NAME="festisafe"
DB_PASSWORD="CambiarEsto!2024"          # Cambia esto
SECRET_KEY="festisafe-secret-key-produccion-minimo-32-chars"  # Cambia esto
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=== FestiSafe Infrastructure Setup ==="
echo "Account: $AWS_ACCOUNT_ID | Region: $AWS_REGION"
echo ""

# ---------------------------------------------------------------------------
# 1. VPC y networking
# ---------------------------------------------------------------------------
echo "[1/9] Creando VPC..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --region "$AWS_REGION" \
  --query "Vpc.VpcId" --output text)
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value="${APP_NAME}-vpc"

# Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway --region "$AWS_REGION" --query "InternetGateway.InternetGatewayId" --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"

# Subnets públicas (ALB) en 2 AZs
SUBNET_PUB_A=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.1.0/24 \
  --availability-zone "${AWS_REGION}a" --query "Subnet.SubnetId" --output text)
SUBNET_PUB_B=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.2.0/24 \
  --availability-zone "${AWS_REGION}b" --query "Subnet.SubnetId" --output text)

# Subnets privadas (ECS + RDS)
SUBNET_PRIV_A=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.10.0/24 \
  --availability-zone "${AWS_REGION}a" --query "Subnet.SubnetId" --output text)
SUBNET_PRIV_B=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.11.0/24 \
  --availability-zone "${AWS_REGION}b" --query "Subnet.SubnetId" --output text)

# Route table pública
RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query "RouteTable.RouteTableId" --output text)
aws ec2 create-route --route-table-id "$RT_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" > /dev/null
aws ec2 associate-route-table --route-table-id "$RT_ID" --subnet-id "$SUBNET_PUB_A" > /dev/null
aws ec2 associate-route-table --route-table-id "$RT_ID" --subnet-id "$SUBNET_PUB_B" > /dev/null

echo "  VPC: $VPC_ID | Subnets pub: $SUBNET_PUB_A, $SUBNET_PUB_B"

# ---------------------------------------------------------------------------
# 2. Security Groups
# ---------------------------------------------------------------------------
echo "[2/9] Creando Security Groups..."

# ALB: acepta 80 y 443 desde internet
SG_ALB=$(aws ec2 create-security-group --group-name "${APP_NAME}-alb-sg" \
  --description "ALB FestiSafe" --vpc-id "$VPC_ID" --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_ALB" --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id "$SG_ALB" --protocol tcp --port 443 --cidr 0.0.0.0/0

# ECS: acepta 8000 solo desde el ALB
SG_ECS=$(aws ec2 create-security-group --group-name "${APP_NAME}-ecs-sg" \
  --description "ECS FestiSafe" --vpc-id "$VPC_ID" --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_ECS" --protocol tcp --port 8000 \
  --source-group "$SG_ALB"

# RDS: acepta 5432 solo desde ECS
SG_RDS=$(aws ec2 create-security-group --group-name "${APP_NAME}-rds-sg" \
  --description "RDS FestiSafe" --vpc-id "$VPC_ID" --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_RDS" --protocol tcp --port 5432 \
  --source-group "$SG_ECS"

echo "  SG ALB: $SG_ALB | ECS: $SG_ECS | RDS: $SG_RDS"

# ---------------------------------------------------------------------------
# 3. RDS PostgreSQL
# ---------------------------------------------------------------------------
echo "[3/9] Creando RDS PostgreSQL (puede tardar ~5 min)..."

# Subnet group para RDS
aws rds create-db-subnet-group \
  --db-subnet-group-name "${APP_NAME}-db-subnet" \
  --db-subnet-group-description "FestiSafe DB subnet" \
  --subnet-ids "$SUBNET_PRIV_A" "$SUBNET_PRIV_B" > /dev/null

aws rds create-db-instance \
  --db-instance-identifier "${APP_NAME}-db" \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version "16.3" \
  --master-username festisafe \
  --master-user-password "$DB_PASSWORD" \
  --db-name festisafe \
  --allocated-storage 20 \
  --storage-type gp3 \
  --no-publicly-accessible \
  --vpc-security-group-ids "$SG_RDS" \
  --db-subnet-group-name "${APP_NAME}-db-subnet" \
  --backup-retention-period 7 \
  --deletion-protection \
  --region "$AWS_REGION" > /dev/null

echo "  RDS creándose en background..."

# ---------------------------------------------------------------------------
# 4. Roles IAM
# ---------------------------------------------------------------------------
echo "[4/9] Creando roles IAM..."

# Execution role (para que ECS pueda leer ECR y Secrets Manager)
aws iam create-role \
  --role-name "${APP_NAME}-ecs-execution-role" \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' > /dev/null

aws iam attach-role-policy \
  --role-name "${APP_NAME}-ecs-execution-role" \
  --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"

aws iam attach-role-policy \
  --role-name "${APP_NAME}-ecs-execution-role" \
  --policy-arn "arn:aws:iam::aws:policy/SecretsManagerReadWrite"

# Task role (permisos de la app en runtime — mínimos por ahora)
aws iam create-role \
  --role-name "${APP_NAME}-ecs-task-role" \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' > /dev/null

echo "  Roles creados"

# ---------------------------------------------------------------------------
# 5. Secrets Manager
# ---------------------------------------------------------------------------
echo "[5/9] Guardando secretos en Secrets Manager..."

# Esperar a que RDS esté disponible para obtener el endpoint
echo "  Esperando RDS disponible..."
aws rds wait db-instance-available --db-instance-identifier "${APP_NAME}-db" --region "$AWS_REGION"

DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "${APP_NAME}-db" \
  --region "$AWS_REGION" \
  --query "DBInstances[0].Endpoint.Address" --output text)

DATABASE_URL="postgresql://festisafe:${DB_PASSWORD}@${DB_ENDPOINT}:5432/festisafe"

aws secretsmanager create-secret \
  --name "${APP_NAME}/env" \
  --region "$AWS_REGION" \
  --secret-string "{
    \"SECRET_KEY\": \"${SECRET_KEY}\",
    \"DATABASE_URL\": \"${DATABASE_URL}\",
    \"DEBUG\": \"False\"
  }" > /dev/null

echo "  Secretos guardados | DB: $DB_ENDPOINT"

# ---------------------------------------------------------------------------
# 6. CloudWatch Log Group
# ---------------------------------------------------------------------------
echo "[6/9] Creando log group..."
aws logs create-log-group --log-group-name "/ecs/${APP_NAME}" --region "$AWS_REGION" 2>/dev/null || true
aws logs put-retention-policy --log-group-name "/ecs/${APP_NAME}" --retention-in-days 30 --region "$AWS_REGION"

# ---------------------------------------------------------------------------
# 7. ECS Cluster
# ---------------------------------------------------------------------------
echo "[7/9] Creando ECS Cluster..."
aws ecs create-cluster \
  --cluster-name "${APP_NAME}-cluster" \
  --capacity-providers FARGATE \
  --region "$AWS_REGION" > /dev/null

# ---------------------------------------------------------------------------
# 8. Application Load Balancer
# ---------------------------------------------------------------------------
echo "[8/9] Creando ALB..."

ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "${APP_NAME}-alb" \
  --subnets "$SUBNET_PUB_A" "$SUBNET_PUB_B" \
  --security-groups "$SG_ALB" \
  --region "$AWS_REGION" \
  --query "LoadBalancers[0].LoadBalancerArn" --output text)

TG_ARN=$(aws elbv2 create-target-group \
  --name "${APP_NAME}-tg" \
  --protocol HTTP \
  --port 8000 \
  --vpc-id "$VPC_ID" \
  --target-type ip \
  --health-check-path "/health/" \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --region "$AWS_REGION" \
  --query "TargetGroups[0].TargetGroupArn" --output text)

# Listener HTTP (redirige a HTTPS si tienes certificado, o sirve directo para MVP)
aws elbv2 create-listener \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn="$TG_ARN" \
  --region "$AWS_REGION" > /dev/null

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$ALB_ARN" \
  --region "$AWS_REGION" \
  --query "LoadBalancers[0].DNSName" --output text)

echo "  ALB DNS: $ALB_DNS"

# ---------------------------------------------------------------------------
# 9. ECS Service
# ---------------------------------------------------------------------------
echo "[9/9] Creando ECS Service..."

aws ecs create-service \
  --cluster "${APP_NAME}-cluster" \
  --service-name "${APP_NAME}-service" \
  --task-definition "${APP_NAME}-task" \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_PRIV_A},${SUBNET_PRIV_B}],securityGroups=[${SG_ECS}],assignPublicIp=DISABLED}" \
  --load-balancers "targetGroupArn=${TG_ARN},containerName=${APP_NAME},containerPort=8000" \
  --health-check-grace-period-seconds 60 \
  --region "$AWS_REGION" > /dev/null

# ---------------------------------------------------------------------------
# Resumen
# ---------------------------------------------------------------------------
echo ""
echo "=== Setup completado ==="
echo "API URL  : http://${ALB_DNS}"
echo "Docs     : http://${ALB_DNS}/docs"
echo "Health   : http://${ALB_DNS}/health/"
echo ""
echo "Próximo paso: ejecuta ./deploy/deploy.sh para subir la imagen"
echo ""
echo "IMPORTANTE: Guarda estos valores para el frontend:"
echo "  API_BASE_URL=http://${ALB_DNS}/api/v1"
echo "  WS_URL=ws://${ALB_DNS}/ws"
