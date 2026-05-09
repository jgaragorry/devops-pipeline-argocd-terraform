#!/bin/bash
set -e
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
BUCKET_NAME="devops-lab-tfstate-$ACCOUNT_ID"
TABLE_NAME="devops-lab-tfstate-lock"

echo "Creating S3 bucket: $BUCKET_NAME..."
aws s3 mb s3://$BUCKET_NAME --region $REGION

echo "Enabling versioning..."
aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled

echo "Creating DynamoDB table: $TABLE_NAME..."
aws dynamodb create-table \
    --table-name $TABLE_NAME \
    --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 --region $REGION

echo "✓ Backend setup completed."
