#!/bin/bash

set -e

CLUSTER="cluster-bia"
SERVICE="service-bia"
TASK_FAMILY="task-def-bia"
ECR_IMAGE="961341509182.dkr.ecr.us-east-1.amazonaws.com/bia"
REGION="us-east-1"

usage() {
  cat <<EOF
Uso: $0 <comando> [opções]

Comandos:
  deploy <commit-hash>        Registra nova task definition com a tag do commit e faz deploy
  rollback <task-def-arn>     Faz rollback para uma task definition específica
  list                        Lista as últimas 10 task definitions registradas
  status                      Mostra o status atual do service

Exemplos:
  $0 deploy abc1234
  $0 rollback arn:aws:ecs:us-east-1:961341509182:task-definition/task-def-bia:3
  $0 rollback task-def-bia:3
  $0 list
  $0 status
EOF
  exit 0
}

deploy() {
  local COMMIT_HASH=$1
  [ -z "$COMMIT_HASH" ] && { echo "Erro: informe o commit hash."; usage; }

  local IMAGE_URI="${ECR_IMAGE}:${COMMIT_HASH}"
  echo "→ Registrando task definition com imagem: $IMAGE_URI"

  local CURRENT_TASK_DEF
  CURRENT_TASK_DEF=$(aws ecs describe-task-definition \
    --task-definition "$TASK_FAMILY" \
    --region "$REGION" \
    --query 'taskDefinition' \
    --output json)

  local NEW_TASK_DEF
  NEW_TASK_DEF=$(echo "$CURRENT_TASK_DEF" | python3 -c "
import json, sys
td = json.load(sys.stdin)
td['containerDefinitions'][0]['image'] = '${IMAGE_URI}'
for key in ['taskDefinitionArn','revision','status','requiresAttributes','compatibilities','registeredAt','registeredBy']:
    td.pop(key, None)
print(json.dumps(td))
")

  local NEW_ARN
  NEW_ARN=$(aws ecs register-task-definition \
    --region "$REGION" \
    --cli-input-json "$NEW_TASK_DEF" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

  echo "→ Nova task definition: $NEW_ARN"
  _update_service "$NEW_ARN"
}

rollback() {
  local TASK_DEF=$1
  [ -z "$TASK_DEF" ] && { echo "Erro: informe a task definition ARN ou família:revisão."; usage; }
  echo "→ Fazendo rollback para: $TASK_DEF"
  _update_service "$TASK_DEF"
}

list() {
  echo "→ Últimas 10 task definitions de $TASK_FAMILY:"
  aws ecs list-task-definitions \
    --family-prefix "$TASK_FAMILY" \
    --sort DESC \
    --region "$REGION" \
    --max-items 10 \
    --query 'taskDefinitionArns[]' \
    --output table
}

status() {
  echo "→ Status do service $SERVICE no cluster $CLUSTER:"
  aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --region "$REGION" \
    --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,TaskDefinition:taskDefinition,LastEvent:events[0].message}' \
    --output table
}

_update_service() {
  local TASK_DEF_ARN=$1
  echo "→ Atualizando service $SERVICE..."
  aws ecs update-service \
    --cluster "$CLUSTER" \
    --service "$SERVICE" \
    --task-definition "$TASK_DEF_ARN" \
    --region "$REGION" \
    --query 'service.{service:serviceName,taskDefinition:taskDefinition,status:status}' \
    --output table

  echo "→ Aguardando service estabilizar..."
  aws ecs wait services-stable \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --region "$REGION"
  echo "✓ Deploy concluído com sucesso!"
}

case "$1" in
  deploy)   deploy "$2" ;;
  rollback) rollback "$2" ;;
  list)     list ;;
  status)   status ;;
  *)        usage ;;
esac
