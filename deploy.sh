#!/bin/bash

# EKS Deployment Script for VendFinder Polling App
# Prerequisites: kubectl configured for your EKS cluster, AWS CLI configured

set -e

# Configuration
CLUSTER_NAME="ridiculous-lofi-ant"
REGION="us-east-1"
ECR_REGISTRY="897297238258.dkr.ecr.us-east-1.amazonaws.com"
FRONTEND_IMAGE="vendfinder-polling-frontend"
BACKEND_IMAGE="vendfinder-polling-backend"
NAMESPACE="vendfinder"
ALERT_EMAIL="anthony@vendfinder.com" # Update with your actual email

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Starting VendFinder Polling App EKS Deployment${NC}"

# Function to check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}❌ $1 is not installed. Please install it first.${NC}"
        exit 1
    fi
}

# Check prerequisites
echo -e "${YELLOW}📋 Checking prerequisites...${NC}"
check_command kubectl
check_command aws
check_command docker

# Verify kubectl is configured for the correct cluster
echo -e "${YELLOW}🔍 Verifying kubectl configuration...${NC}"
CURRENT_CONTEXT=$(kubectl config current-context)
if [[ $CURRENT_CONTEXT != *"$CLUSTER_NAME"* ]]; then
    echo -e "${RED}❌ kubectl is not configured for cluster $CLUSTER_NAME${NC}"
    echo "Current context: $CURRENT_CONTEXT"
    echo "Please run: aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME"
    exit 1
fi

# Build and push Docker images
echo -e "${YELLOW}🏗️  Building and pushing Docker images...${NC}"

# Build frontend image
echo "Building frontend image..."
docker build -t $FRONTEND_IMAGE:latest .

# Build backend image (if backend directory exists)
if [ -d "backend" ]; then
    echo "Building backend image..."
    cd backend
    docker build -t $BACKEND_IMAGE:latest .
    cd ..
fi

# Login to ECR
echo "Logging into ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# Create ECR repositories if they don't exist
echo "Creating ECR repositories..."
aws ecr describe-repositories --repository-names $FRONTEND_IMAGE --region $REGION 2>/dev/null || \
    aws ecr create-repository --repository-name $FRONTEND_IMAGE --region $REGION

if [ -d "backend" ]; then
    aws ecr describe-repositories --repository-names $BACKEND_IMAGE --region $REGION 2>/dev/null || \
        aws ecr create-repository --repository-name $BACKEND_IMAGE --region $REGION
fi

# Tag and push images
echo "Tagging and pushing images..."
docker tag $FRONTEND_IMAGE:latest $ECR_REGISTRY/$FRONTEND_IMAGE:latest
docker push $ECR_REGISTRY/$FRONTEND_IMAGE:latest

if [ -d "backend" ]; then
    docker tag $BACKEND_IMAGE:latest $ECR_REGISTRY/$BACKEND_IMAGE:latest
    docker push $ECR_REGISTRY/$BACKEND_IMAGE:latest
fi

# Update image references in deployment files
echo -e "${YELLOW}📝 Updating deployment manifests...${NC}"
sed -i.bak "s|your-ecr-repo|$ECR_REGISTRY|g" k8s/frontend-deployment.yaml
if [ -d "backend" ]; then
    sed -i.bak "s|your-ecr-repo|$ECR_REGISTRY|g" k8s/backend-deployment.yaml
fi

# Deploy to Kubernetes
echo -e "${YELLOW}☸️  Deploying to Kubernetes...${NC}"

# Create namespace
kubectl apply -f k8s/namespace.yaml

# Apply ConfigMaps
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/monitoring.yaml

# Deploy applications
kubectl apply -f k8s/frontend-deployment.yaml

if [ -d "backend" ]; then
    # Update database and Redis connection strings
    echo -e "${YELLOW}🗄️  Please update database and Redis connection strings in k8s/backend-deployment.yaml${NC}"
    read -p "Press enter when ready to continue..."
    kubectl apply -f k8s/backend-deployment.yaml
fi

# Apply ingress
kubectl apply -f k8s/ingress.yaml

# Wait for deployments to be ready
echo -e "${YELLOW}⏳ Waiting for deployments to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/polling-frontend -n $NAMESPACE

if [ -d "backend" ]; then
    kubectl wait --for=condition=available --timeout=300s deployment/polling-backend -n $NAMESPACE
fi

# Get ingress information
echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
echo ""
echo -e "${GREEN}📊 Deployment Information:${NC}"
kubectl get all -n $NAMESPACE

echo ""
echo -e "${GREEN}🔗 Ingress Information:${NC}"
kubectl get ingress -n $NAMESPACE

echo ""
echo -e "${GREEN}📈 Access your application:${NC}"
INGRESS_HOST=$(kubectl get ingress polling-app-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
if [ ! -z "$INGRESS_HOST" ]; then
    echo "Frontend: https://$INGRESS_HOST"
    if [ -d "backend" ]; then
        echo "API: https://$INGRESS_HOST/api"
    fi
else
    echo "Ingress is still provisioning. Check back in a few minutes."
fi

echo ""
echo -e "${GREEN}🎯 Useful Commands:${NC}"
echo "View pods: kubectl get pods -n $NAMESPACE"
echo "View logs: kubectl logs -f deployment/polling-frontend -n $NAMESPACE"
if [ -d "backend" ]; then
    echo "View API logs: kubectl logs -f deployment/polling-backend -n $NAMESPACE"
fi
echo "Scale frontend: kubectl scale deployment polling-frontend --replicas=5 -n $NAMESPACE"
echo "Delete deployment: kubectl delete namespace $NAMESPACE"

echo ""
echo -e "${YELLOW}📊 Monitoring Setup:${NC}"
echo "1. Install Prometheus Operator if not already installed:"
echo "   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts"
echo "   helm install prometheus prometheus-community/kube-prometheus-stack"
echo ""
echo "2. Import the Grafana dashboard from grafana/dashboard.json"
echo ""
echo -e "${GREEN}🎉 Deployment completed! Your polling app is now running on EKS.${NC}"
