# Quick Reference Cheatsheet

## Pre-deployment
```bash
# 1. Verificar credenciales AWS
aws sts get-caller-identity

# 2. Crear backend remoto (S3 + DynamoDB)
./scripts/backend-setup.sh

# 3. Listar backends existentes
./scripts/backend-list.sh
```

## Terraform
```bash
cd terraform/environments/dev

# Inicializar con backend remoto
terragrunt init

# Validar configuración
terragrunt fmt -check && terragrunt validate

# Ver costos ANTES de apply
infracost breakdown --path . --format table

# Plan sin aplicar
terragrunt plan -out=tfplan

# Aplicar infraestructura
terragrunt apply tfplan

# Destruir todo
terragrunt destroy -auto-approve
```

## Kubernetes / ArgoCD
```bash
# Actualizar kubeconfig
aws eks update-kubeconfig --name devops-lab-main --region us-east-1

# Ver nodos
kubectl get nodes

# Ver todos los recursos
kubectl get all -A

# Ver ArgoCD
kubectl get pods -n argocd

# Obtener contraseña ArgoCD
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Obtener URL de ArgoCD
kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Ver aplicaciones ArgoCD
kubectl get applications -n argocd

# Agregar app (plug-and-play): crear k8s/apps/mi-app/kustomization.yaml
# ArgoCD sincroniza automáticamente
```

## Auditoría y Validación
```bash
# Detectar drift + huérfanos
python3 scripts/audit.py

# Fallar si hay cambios no autorizados (para CI/CD)
./scripts/validate-no-drift.sh

# Ver reporte último audit
cat /tmp/audit-report-*.json | jq .
```

## Cleanup
```bash
# Destruir TODO en orden correcto
# (K8s -> ArgoCD -> Terraform -> Esperar liberación)
./scripts/cleanup.sh

# (Opcional) Eliminar S3 + DynamoDB después de cleanup
./scripts/backend-cleanup.sh
```

## Troubleshooting
```bash
# Ver logs de EKS
kubectl logs -n kube-system -f deployment/coredns

# Ver eventos del cluster
kubectl get events -A --sort-by='.lastTimestamp'

# Describir nodo para problemas
kubectl describe node $(kubectl get nodes -o name | head -1)

# Ver estado de Terraform (remoto en S3)
aws s3 ls s3://devops-lab-tfstate-$(aws sts get-caller-identity --query Account -o text)/

# Ver locks de Terraform
aws dynamodb scan --table-name devops-lab-tfstate-lock

# Monitorear costos en tiempo real
aws ce get-cost-and-usage \
  --time-period Start=2026-04-28,End=2026-04-29 \
  --granularity HOURLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

## Variables Útiles
```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account -o text)
export CLUSTER_NAME=devops-lab-main
export TF_LOG=DEBUG          # Para debug Terraform
export TF_LOG_PATH=/tmp/tf.log
```

## GitHub Actions (Local Testing)
```bash
# Act: ejecutar workflows localmente
brew install act
cd devops-lab
act push --job terraform

# Ver logs
act push --job terraform -v
```

## Secretos & Credentials
```bash
# NO guardes en código:
# ✗ AWS keys en variables.tf
# ✗ Passwords en deployment.yaml
# ✗ Tokens en scripts

# SÍ usa:
# ✓ GitHub Secrets (AWS_ROLE_ARN, INFRACOST_API_KEY)
# ✓ AWS Secrets Manager (para apps en K8s)
# ✓ IRSA (IAM Roles for Service Accounts)
```

## Monitoreo
```bash
# CloudWatch Logs de EKS
aws logs tail /aws/eks/devops-lab-main/cluster --follow

# Métricas de nodo
kubectl top nodes

# Métricas de pods
kubectl top pods -A

# Ver uso de recursos en cluster
kubectl describe nodes
```

## Estimado de Costos
```bash
# Mostrar costo por hora
infracost breakdown --path terraform/environments/dev --format table | grep TOTAL

# Desglose por recurso
infracost breakdown --path terraform/environments/dev --format json | \
  jq '.projects[0].breakdown.resources[] | {address, monthly_cost}'

# Generar PDF report
infracost report --path /tmp/infracost.json --format pdf
```

---

**Guía rápida**: Sigue `runbook.md` para instrucciones paso-a-paso completas.
