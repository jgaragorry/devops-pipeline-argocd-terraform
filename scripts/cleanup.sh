#!/bin/bash
echo "▶ Iniciando Cleanup total..."
cd terraform/environments/dev
terragrunt destroy --auto-approve

echo "▶ Eliminando recursos huérfanos (ALBs)..."
ALB_ARNS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[*].LoadBalancerArn' --output text)
for arn in $ALB_ARNS; do
    echo "Eliminando ALB: $arn"
    aws elbv2 delete-load-balancer --load-balancer-arn $arn
done
echo "✓ Cleanup finalizado."
