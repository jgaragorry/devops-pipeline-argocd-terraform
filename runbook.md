# 🏥 Runbook: DevOps Lab Completo

**Objetivo**: Desplegar laboratorio AWS en us-east-1 con Terraform, EKS, ArgoCD e InfraCost.

**Duración esperada**: 45 minutos (depende de velocidad internet y aprobación de AWS)

**Requisitos previos**:
- AWS Account (free tier eligibility)
- `aws-cli` v2.x configurado con credenciales
- `terraform` 1.7+
- `terragrunt` 0.53+
- `kubectl` 1.28+
- `helm` 3.x
- `git`
- `docker` (para build local)
- GitHub account y repo clonado

---

## ▶️ Paso 1: Validar Prerequisitos

```bash
# Verificar versiones
aws --version          # AWS CLI 2.x
terraform --version   # 1.7+
terragrunt --version  # 0.53+
kubectl version --client
helm version
git --version
docker --version

# Validar credenciales AWS
aws sts get-caller-identity
# Output esperado: { "Account": "123456789...", "UserId": "...", "Arn": "..." }

# Crear variable de entorno
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $AWS_ACCOUNT_ID"
```

**Validación**: Debería mostrarse tu Account ID sin errores.

---

## ▶️ Paso 2: Clonar Repositorio e Instalar Dependencias

```bash
# Clonar (ajusta <repo-url>)
git clone <repo-url> devops-lab
cd devops-lab

# Instalar InfraCost (opcional pero recomendado)
curl -s https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | bash
infracost --version

# Crear credencial (si no existe)
mkdir -p ~/.aws
# Asegúrate que ~/.aws/credentials y ~/.aws/config estén configurados
```

**Validación**: `ls -la` debe mostrar README.md, terraform/, scripts/, etc.

---

## ▶️ Paso 3: Crear Backend Remoto (S3 + DynamoDB)

**Por qué**: Evita estado local, habilita CI/CD, previene race conditions.

```bash
# Ir a scripts
cd scripts

# Dar permisos
chmod +x backend-setup.sh backend-list.sh backend-cleanup.sh cleanup.sh audit.py validate-no-drift.sh

# Crear backend
./backend-setup.sh

# Output esperado:
# ✓ S3 bucket creado: devops-lab-tfstate-<account-id>
# ✓ DynamoDB table creado: devops-lab-tfstate-lock
# ✓ Versioning y encryption habilitados
# ✓ Block public access activado
```

**Validación manual**:
```bash
aws s3 ls | grep devops-lab-tfstate
aws dynamodb list-tables | grep devops-lab-tfstate-lock

# Listar backends existentes
./backend-list.sh
```

**Si falla**:
- Verificar permisos IAM (S3, DynamoDB)
- Revisar límites de AWS (buckets, tablas)
- Ejecutar `aws s3 ls` directamente

---

## ▶️ Paso 4: Inicializar Terraform

```bash
cd terraform/environments/dev

# Inicializar con backend remoto
terragrunt init

# Output esperado:
# Initializing the backend...
# Successfully configured the backend "s3"!
# Terraform has been successfully initialized!
```

**Validación**:
```bash
# Verificar state en S3
aws s3 ls devops-lab-tfstate-$AWS_ACCOUNT_ID/

# Verificar lock table
aws dynamodb scan --table-name devops-lab-tfstate-lock
```

---

## ▶️ Paso 5: Validar Terraform

```bash
# Formatear y validar
terragrunt fmt -check
terragrunt validate

# Lint con tflint (opcional)
tflint .
```

**Validación**: Sin errores de formato ni variables indefinidas.

---

## ▶️ Paso 6: Ver Plan Terraform + Costos (InfraCost)

```bash
# Plan sin aplicar
terragrunt plan -out=tfplan

# Output esperado: ~50 recursos a crear

# Mostrar costos por hora y mes (ANTES de apply!)
infracost breakdown --path . --format table

# Output esperado:
# ┌──────────────────────────────────────────┐
# │ Resource                 │ $/month │ $/hr │
# ├──────────────────────────────────────────┤
# │ aws_eks_cluster.main     │ $73     │ $0.1 │
# │ aws_instance (t3.micro)  │ $7      │ ... │
# │ ... (otros recursos)     │         │     │
# ├──────────────────────────────────────────┤
# │ TOTAL                    │ $117    │ $0.16│
# └──────────────────────────────────────────┘

# Exportar reporte JSON
infracost breakdown --path . --format json > /tmp/infracost.json
cat /tmp/infracost.json | jq '.projects[0].breakdown.resources[] | {address, monthly_cost}'
```

**Decisión**: 
- ✓ Continuar si costos son aceptables (~$0.16/hora)
- ✗ Cancelar si superan presupuesto (ejecutar `rm tfplan`)

---

## ▶️ Paso 7: Aplicar Infraestructura Terraform

⚠️ **A partir de aquí incurres costos. Tienes ~45 minutos para revisar y limpiar.**

```bash
# Aplicar usando el plan generado
terragrunt apply tfplan

# Output esperado (toma 12-15 min):
# Creando VPC, subnets, security groups, EKS cluster, node group, ECR repo
# ... (aplicación de ~50 recursos)
# Apply complete! Outputs: ...
```

**Durante la creación, puedes monitorear**:
```bash
# En otra terminal
aws eks describe-cluster --name devops-lab-main --region us-east-1
aws ec2 describe-instances --region us-east-1 | jq '.Reservations[].Instances[] | {InstanceId, State, Type}'
```

**Validación post-apply**:
```bash
# Esperar a que EKS esté ACTIVE (puede tomar 3-5 min después de apply)
aws eks describe-cluster --name devops-lab-main \
  --region us-east-1 --query 'cluster.status' --output text
# Esperado: ACTIVE

# Obtener kubeconfig
aws eks update-kubeconfig --name devops-lab-main --region us-east-1

# Verificar acceso a cluster
kubectl get nodes
# Esperado: 1 nodo en estado Ready

# Esperar a que nodo esté listo (~5-10 min)
kubectl wait --for=condition=Ready nodes --all --timeout=600s
```

---

## ▶️ Paso 8: Instalar ArgoCD

```bash
# Crear namespace
kubectl create namespace argocd

# Instalar ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd \
  --namespace argocd \
  --set server.service.type=LoadBalancer \
  --wait

# Esperar a que se inicialice (~2 min)
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd

# Obtener contraseña inicial
ARGO_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD admin password: $ARGO_PASS"

# Obtener LoadBalancer URL
ARGO_URL=$(kubectl -n argocd get svc argocd-server \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ArgoCD URL: http://$ARGO_URL"

# Esperar a que LoadBalancer esté asignado (puede tomar 2-5 min)
while [ -z "$ARGO_URL" ] || [ "$ARGO_URL" == "None" ]; do
  echo "Esperando LoadBalancer..."
  sleep 10
  ARGO_URL=$(kubectl -n argocd get svc argocd-server \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
done
echo "✓ ArgoCD disponible en: http://$ARGO_URL"
```

**Validación**:
```bash
# Comprobar pods
kubectl get pods -n argocd
# Esperado: argocd-application-controller, argocd-server, etc. en estado Running

# Verificar ALB creado automáticamente por EKS
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?CreatedTime>=`2026-04-28`]' \
  --region us-east-1
# Debería mostrar ALB creado automáticamente (importante para cleanup)
```

---

## ▶️ Paso 9: Configurar App of Apps (ArgoCD)

```bash
# Aplicar AppProject + ApplicationSet (plug-and-play)
kubectl apply -f k8s/argocd-app-of-apps.yaml

# Verificar
kubectl get applications -n argocd
kubectl get appprojects -n argocd

# Sync manual (auto está habilitado pero puedes forzar)
argocd app sync devops-lab-apps --grpc-web
```

**Para AGREGAR una nueva app**:
1. Crear directorio: `k8s/apps/<app-name>/`
2. Crear `kustomization.yaml`
3. ArgoCD sincroniza automáticamente

**Ejemplo agregar nginx**:
```bash
# Ya incluida en el repo, solo verificar
kubectl apply -f k8s/apps/nginx-deploy/
kubectl get deployments -n default
kubectl get services -n default
```

---

## ▶️ Paso 10: Auditoría y Detección de Drift

**Detecta**:
- Recursos en AWS no en tfstate
- Recursos en tfstate no en AWS
- Load Balancers creados automáticamente por EKS
- Drift en configuración

```bash
# Ejecutar auditoría
cd scripts
python3 audit.py

# Output esperado:
# ✓ Conectado a AWS y Terraform
# ✓ 52 recursos en Terraform
# ✓ 52 recursos en AWS (match)
# ⚠ 1 ALB detectado (automático por EKS, esperado, no en tfstate)
# ✓ Sin drift detectado
# ✓ Reporte: /tmp/audit-report-20260428-120000.json

# Ver reporte
cat /tmp/audit-report-*.json | jq .
```

**Validación**: Status debe ser "SUCCESS" o "WARNING" (ALB automático es esperado).

---

## ▶️ Paso 11: Validar Sin Drift

```bash
# Script que falla si hay cambios no autorizados
cd scripts
./validate-no-drift.sh

# Output esperado:
# ✓ Terraform plan sin cambios (no-op)
# ✓ Estado sincronizado
# Exit code: 0
```

---

## ▶️ Paso 12: Simular CI/CD (Opcional)

```bash
# Ver GitHub Actions workflows
cd .github/workflows
ls -la

# Puedes hacer push a repo para disparar:
git add .
git commit -m "Trigger CI/CD pipeline"
git push origin main

# Monitorear en GitHub Actions -> Actions -> Workflows
# Valida: terraform lint, security scan, build, deploy
```

---

## ▶️ Paso 13: Monitorear Costos

```bash
# Ver costos acumulados desde que empezó
aws ce get-cost-and-usage \
  --time-period Start=2026-04-28,End=2026-04-29 \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE

# InfraCost en tiempo real
infracost breakdown --path terraform/environments/dev --format table
```

---

## 🧹 Paso 14: Limpiar TODO (IMPORTANTE)

⚠️ **Ejecuta esto cuando termines pruebas, de lo contrario seguirás incurriendo costos.**

```bash
# Ir a root del proyecto
cd devops-lab

# Ejecutar cleanup
./scripts/cleanup.sh

# Output esperado:
# ▶ Paso 1/6: Eliminar aplicaciones Kubernetes...
# ▶ Paso 2/6: Desinstalar ArgoCD...
# ▶ Paso 3/6: Destruir Load Balancer automático de EKS...
#   └─ Detectado ALB: arn:aws:elasticloadbalancing:...
#   └─ Eliminando... (puede tomar 1-2 min)
#   └─ Esperando liberación de recursos...
#   └─ ✓ ALB eliminado
# ▶ Paso 4/6: Destruir infraestructura Terraform...
#   └─ Liberando EKS resources...
#   └─ Liberando subnets y security groups (reintentos)...
#   └─ ✓ Terraform destroy completado
# ▶ Paso 5/6: Esperar liberación de recursos...
#   └─ Esperando 30 segundos...
#   └─ Verificando VPC...
#   └─ Verificando security groups...
#   └─ ✓ Recursos liberados
# ▶ Paso 6/6: Auditoría post-cleanup...
#   └─ Verificando recursos residuales...
# 
# ✓ Cleanup completado
# ✓ Sin recursos huérfanos detectados
# Exit code: 0
```

**Si cleanup falla**:
```bash
# Debug: ver qué recursos quedan
aws ec2 describe-instances --region us-east-1 | jq '.Reservations[].Instances[] | {InstanceId, State}'
aws elbv2 describe-load-balancers --region us-east-1
aws eks describe-clusters --region us-east-1

# Eliminar manualmente si es necesario
aws ec2 terminate-instances --instance-ids i-xxx --region us-east-1
aws elbv2 delete-load-balancer --load-balancer-arn arn:aws:elasticloadbalancing:... --region us-east-1

# Re-ejecutar cleanup
./scripts/cleanup.sh
```

---

## ▶️ Paso 15: Limpiar Backend (Opcional, si no reutilizarás)

```bash
# Eliminar S3 + DynamoDB (después de cleanup)
cd scripts
./backend-cleanup.sh

# Output esperado:
# ✓ S3 bucket eliminado: devops-lab-tfstate-<account-id>
# ✓ DynamoDB table eliminada: devops-lab-tfstate-lock
```

---

## 🔍 Troubleshooting

### EKS cluster tarda más de 15 minutos
**Causa**: AWS puede tener retrasos en provisioning.
**Solución**: 
```bash
aws eks describe-cluster --name devops-lab-main --region us-east-1
# Ver CreationTime, Status
# Esperar hasta Status=ACTIVE (puede ser 20+ min en horarios pico)
```

### Node no llega a "Ready"
**Causa**: Tiempo de inicialización, issues de networking.
**Solución**:
```bash
kubectl get nodes -w  # Esperar cambio de status
kubectl describe node <node-id>  # Ver eventos
kubectl logs -n kube-system -l component=kubelet --tail=50
```

### ArgoCD Server LoadBalancer no obtiene IP externa
**Causa**: ALB tarda en asignarse.
**Solución**:
```bash
# Esperar 2-5 min
kubectl get svc -n argocd -w
# Cuando LoadBalancer obtenga hostname, continuar
```

### terraform apply falla por timeout en EKS
**Causa**: EKS puede rechazar requests durante provisioning.
**Solución**:
```bash
# Aumentar timeout
export TF_LOG=DEBUG
terragrunt apply -var-file=dev.tfvars --auto-approve
# Esperar 20+ minutos
```

### Cleanup falla: "VPC dependencies"
**Causa**: Recursos aún vinculados (subnets, ENIs, security groups).
**Solución**: cleanup.sh lo maneja con reintentos, pero si persiste:
```bash
# Ver qué bloquea VPC
aws ec2 describe-network-interfaces --region us-east-1 \
  --filters "Name=vpc-id,Values=vpc-xxx" | jq '.NetworkInterfaces[] | {ID, Status}'

# Esperar liberación manual (20-30 seg) y re-ejecutar cleanup
sleep 30
./cleanup.sh
```

### InfraCost no funciona
**Causa**: Token no configurado o formato inválido.
**Solución**:
```bash
# Crear cuenta gratuita en https://dashboard.infracost.io
# Obtener API key y configurar
infracost configure set api_key <key>

# Probar
infracost breakdown --path terraform/environments/dev --format table
```

---

## ✅ Checklist de Validación Final

- [ ] AWS credentials configuradas (`aws sts get-caller-identity` sin errores)
- [ ] Backend S3 + DynamoDB creado (`aws s3 ls` muestra bucket)
- [ ] Terraform init exitoso (sin errores de "backend not configured")
- [ ] Terraform plan genera ~50 recursos
- [ ] InfraCost muestra costos ($117/mes estimado)
- [ ] terraform apply completado (toma 12-15 min)
- [ ] EKS cluster en status ACTIVE
- [ ] Nodo Kubernetes en status Ready
- [ ] ArgoCD instalado y accessible
- [ ] audit.py ejecutado y sin drift
- [ ] cleanup.sh ejecutado exitosamente
- [ ] AWS account sin recursos residuales

---

## 📚 Siguientes Pasos

1. **Customizar variables**: Editar `terraform/environments/dev/terraform.tfvars`
2. **Agregar más apps**: Crear en `k8s/apps/<app>/` y ArgoCD sincroniza
3. **Configurar CI/CD**: Actualizar `.github/workflows` con tu repo
4. **Monitoreo**: Integrar CloudWatch, Prometheus, Loki
5. **Seguridad**: Agregar Network Policies, Pod Security Standards

---

**Versión**: 1.0  
**Última actualización**: 2026-04-28  
**Soporte**: Ver TROUBLESHOOTING.md

