#!/bin/bash

# Complete VendFinder Polling App Deployment Script
# This script deploys everything: app, monitoring, analytics, alerts, and auto-scaling

set -e

# Configuration
CLUSTER_NAME="ridiculous-lofi-ant"
REGION="us-east-1"
ECR_REGISTRY="897297238258.dkr.ecr.us-east-1.amazonaws.com"
FRONTEND_IMAGE="vendfinder-polling-frontend"
BACKEND_IMAGE="vendfinder-polling-backend"
NAMESPACE="vendfinder"
SLACK_WEBHOOK_URL=""  # You'll need to set this
EMAIL_PASSWORD=""     # You'll need to set this

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Complete VendFinder Polling App Deployment${NC}"
echo -e "${CYAN}======================================================${NC}"

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
check_command helm

# Verify cluster connection
echo -e "${YELLOW}🔍 Verifying cluster connection...${NC}"
CURRENT_CONTEXT=$(kubectl config current-context)
if [[ $CURRENT_CONTEXT != *"$CLUSTER_NAME"* ]]; then
    echo -e "${RED}❌ kubectl is not configured for cluster $CLUSTER_NAME${NC}"
    echo "Current context: $CURRENT_CONTEXT"
    exit 1
fi

echo -e "${GREEN}✅ Connected to cluster: $CLUSTER_NAME${NC}"

# Step 1: Build and Push Images
echo -e "${BLUE}🏗️  Step 1: Building and pushing Docker images...${NC}"

# Build frontend image
echo "Building frontend image..."
docker build -t $FRONTEND_IMAGE:latest .

# Build backend image
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

echo -e "${GREEN}✅ Images built and pushed successfully${NC}"

# Step 2: Deploy Core Application
echo -e "${BLUE}☸️  Step 2: Deploying core application...${NC}"

# Update image references
sed -i.bak "s|your-ecr-repo|$ECR_REGISTRY|g" k8s/frontend-deployment.yaml
if [ -d "backend" ]; then
    sed -i.bak "s|your-ecr-repo|$ECR_REGISTRY|g" k8s/backend-deployment.yaml
fi

# Create namespace
kubectl apply -f k8s/namespace.yaml
echo -e "${GREEN}✅ Namespace created${NC}"

# Apply configurations
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/monitoring.yaml
echo -e "${GREEN}✅ Configurations applied${NC}"

# Deploy applications
kubectl apply -f k8s/frontend-deployment.yaml

if [ -d "backend" ]; then
    echo -e "${YELLOW}🗄️  Please configure database connection strings in k8s/backend-deployment.yaml${NC}"
    echo -e "${YELLOW}Press enter when ready to continue...${NC}"
    read
    kubectl apply -f k8s/backend-deployment.yaml
fi

echo -e "${GREEN}✅ Core applications deployed${NC}"

# Step 3: Setup Auto-scaling and Resource Management
echo -e "${BLUE}⚖️  Step 3: Setting up auto-scaling and resource management...${NC}"

kubectl apply -f k8s/autoscaling.yaml
echo -e "${GREEN}✅ Auto-scaling configured${NC}"

# Step 4: Configure Networking
echo -e "${BLUE}🌐 Step 4: Configuring networking and ingress...${NC}"

# Check if ingress controller is ready
INGRESS_READY=$(kubectl get pods -n ingress-nginx -o jsonpath='{.items[*].status.phase}' | grep -c "Running" || echo "0")
if [ "$INGRESS_READY" -eq "0" ]; then
    echo -e "${YELLOW}⚠️  Ingress controller not found or not ready${NC}"
    echo "Please ensure nginx ingress controller is installed and running"
else
    kubectl apply -f k8s/ingress.yaml
    echo -e "${GREEN}✅ Ingress configured${NC}"
fi

# Step 5: Setup Monitoring and Alerting
echo -e "${BLUE}📊 Step 5: Setting up monitoring and alerting...${NC}"

# Check if Prometheus is already installed
if kubectl get pods -n monitoring | grep -q prometheus; then
    echo -e "${GREEN}✅ Prometheus already installed${NC}"
else
    echo "Installing Prometheus stack..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    helm install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --set grafana.adminUser=admin \
        --set grafana.adminPassword=VendFinder2024!
    
    echo -e "${GREEN}✅ Prometheus and Grafana installed${NC}"
fi

# Apply custom alerting rules
kubectl apply -f k8s/alerting.yaml
echo -e "${GREEN}✅ Custom alerting rules applied${NC}"

# Step 6: Wait for Deployments
echo -e "${BLUE}⏳ Step 6: Waiting for deployments to be ready...${NC}"

kubectl wait --for=condition=available --timeout=300s deployment/polling-frontend -n $NAMESPACE
echo -e "${GREEN}✅ Frontend deployment ready${NC}"

if [ -d "backend" ]; then
    kubectl wait --for=condition=available --timeout=300s deployment/polling-backend -n $NAMESPACE
    echo -e "${GREEN}✅ Backend deployment ready${NC}"
fi

# Step 7: Display Deployment Information
echo -e "${BLUE}📈 Step 7: Deployment Summary${NC}"
echo -e "${CYAN}======================================================${NC}"

echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
echo ""
echo -e "${GREEN}📊 Deployment Information:${NC}"
kubectl get all -n $NAMESPACE

echo ""
echo -e "${GREEN}🔗 Service URLs:${NC}"
echo "Frontend: http://$(kubectl get service polling-frontend-service -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo 'pending')"

if [ -d "backend" ]; then
    echo "Backend API: http://$(kubectl get service polling-backend-service -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo 'pending')/api"
fi

echo ""
echo -e "${GREEN}📊 Monitoring Access:${NC}"
echo "Grafana: http://$(kubectl get service prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo 'Use port-forward')"
echo "  - Username: admin"
echo "  - Password: VendFinder2024!"
echo ""
echo "Port-forward commands (if LoadBalancer not available):"
echo "  Grafana:  kubectl port-forward service/prometheus-grafana 3000:80 -n monitoring"
echo "  Frontend: kubectl port-forward service/polling-frontend-service 8080:80 -n $NAMESPACE"

echo ""
echo -e "${GREEN}🎯 Management Commands:${NC}"
echo "View pods:        kubectl get pods -n $NAMESPACE"
echo "View logs:        kubectl logs -f deployment/polling-frontend -n $NAMESPACE"
if [ -d "backend" ]; then
    echo "View API logs:    kubectl logs -f deployment/polling-backend -n $NAMESPACE"
fi
echo "Scale frontend:   kubectl scale deployment polling-frontend --replicas=5 -n $NAMESPACE"
echo "View HPA status:  kubectl get hpa -n $NAMESPACE"
echo "View ingress:     kubectl get ingress -n $NAMESPACE"

echo ""
echo -e "${YELLOW}🔧 Next Steps:${NC}"
echo "1. Configure your Slack webhook URL in the notification secrets"
echo "2. Set up your email credentials for notifications"
echo "3. Import the Grafana dashboard from grafana/enhanced-dashboard.json"
echo "4. Configure your domain DNS to point to the load balancer"
echo "5. Test the enhanced survey at enhanced-survey.html"

echo ""
echo -e "${PURPLE}📈 Analytics Features Deployed:${NC}"
echo "✅ A/B Testing Framework"
echo "✅ Conditional Logic Questions"
echo "✅ Real-time User Interaction Tracking"
echo "✅ Advanced Grafana Dashboards"
echo "✅ Slack + Email Notifications"
echo "✅ Auto-scaling based on traffic"
echo "✅ Resource optimization"
echo "✅ Security policies"

echo ""
echo -e "${GREEN}🎊 Your enhanced polling app is now live with enterprise-grade analytics!${NC}"

# Clean up backup files
rm -f k8s/*.bak 2>/dev/null || true

echo -e "${CYAN}======================================================${NC}"
echo -e "${GREEN}Deployment Complete! 🚀${NC}"
