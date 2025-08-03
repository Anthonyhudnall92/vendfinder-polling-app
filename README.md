# VendFinder Polling App - EKS Deployment Guide

## 🎯 Overview

This repository contains a comprehensive polling application with advanced data capture capabilities, designed for deployment on Amazon EKS with full observability using Prometheus and Grafana.

## 📊 Data Capture Capabilities

### Real-time Interaction Tracking
- **Individual field interactions**: Every click, focus, and value change
- **Question-level analytics**: Track engagement per survey section
- **User journey mapping**: Complete funnel analysis from start to finish
- **Time-based metrics**: Time spent on each question, completion rates
- **Device and browser analytics**: User agent, viewport, and device type

### Advanced Analytics
- **Response patterns**: Identify which questions cause drop-offs
- **Geographic distribution**: Track responses by location
- **Completion funnels**: See where users abandon the survey
- **A/B testing ready**: Framework for testing different question formats

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Frontend      │    │   Backend API   │    │   Database      │
│   (nginx)       │────│   (Node.js)     │────│   (PostgreSQL)  │
│   Static HTML   │    │   Express       │    │   + Redis Cache │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │              ┌─────────────────┐              │
         │              │   Monitoring    │              │
         └──────────────│   Prometheus    │──────────────┘
                        │   + Grafana     │
                        └─────────────────┘
```

## 🚀 EKS Deployment Strategy

### 1. **Infrastructure Components**

#### Frontend (Static Serving)
- **nginx** with custom configuration for analytics
- **Fluent Bit** sidecar for log aggregation
- **3 replicas** for high availability
- **Health checks** and readiness probes

#### Backend API (Data Processing)
- **Node.js/Express** API server
- **PostgreSQL** for persistent data storage
- **Redis** for caching and real-time analytics
- **Prometheus metrics** built-in
- **Rate limiting** and security headers

#### Monitoring Stack
- **Prometheus** for metrics collection
- **Grafana** for visualization and alerting
- **CloudWatch** integration for AWS native monitoring
- **Custom dashboards** for poll-specific analytics

### 2. **Data Flow Architecture**

```mermaid
graph TD
    A[User Interaction] --> B[Frontend JavaScript]
    B --> C[Real-time API Call]
    C --> D[Backend API]
    D --> E[PostgreSQL Database]
    D --> F[Redis Cache]
    D --> G[Prometheus Metrics]
    G --> H[Grafana Dashboard]
    E --> I[Analytics Queries]
    F --> J[Real-time Stats]
```

## 📈 Prometheus & Grafana Integration

### Why This Stack is Perfect for Your Use Case:

#### **Prometheus Benefits:**
1. **Real-time Metrics**: Track poll submissions, interaction rates, and completion funnels in real-time
2. **Custom Metrics**: Built-in counters for each poll question and interaction type
3. **Alerting**: Get notified when submission rates drop or errors spike
4. **High Performance**: Handle thousands of concurrent poll submissions

#### **Grafana Benefits:**
1. **Rich Visualizations**: 
   - Pie charts for interest level distribution
   - Heat maps for response time analysis
   - Geographic maps for user distribution
   - Funnel analysis for conversion tracking

2. **Business Intelligence**:
   - Track which features users want most
   - Monitor price sensitivity trends
   - Identify optimal survey length
   - A/B test question formats

3. **Operational Monitoring**:
   - Application performance metrics
   - Error rate tracking
   - User engagement analytics
   - Real-time completion rates

## 🛠️ Deployment Instructions

### Prerequisites
- AWS CLI configured
- kubectl configured for your EKS cluster
- Docker installed
- Helm (for monitoring stack)

### Quick Deploy
```bash
# 1. Clone and prepare
git clone <your-repo>
cd polling-app

# 2. Update configuration
# Edit deploy.sh with your ECR registry and cluster details

# 3. Deploy everything
./deploy.sh
```

### Manual Steps

#### 1. **Build and Push Images**
```bash
# Frontend
docker build -t vendfinder-polling-frontend .
docker tag vendfinder-polling-frontend:latest $ECR_REGISTRY/vendfinder-polling-frontend:latest
docker push $ECR_REGISTRY/vendfinder-polling-frontend:latest

# Backend
cd backend
docker build -t vendfinder-polling-backend .
docker tag vendfinder-polling-backend:latest $ECR_REGISTRY/vendfinder-polling-backend:latest
docker push $ECR_REGISTRY/vendfinder-polling-backend:latest
```

#### 2. **Deploy to Kubernetes**
```bash
# Create namespace and deploy
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/monitoring.yaml
```

#### 3. **Setup AWS Resources**
```bash
# Create RDS PostgreSQL instance
aws rds create-db-instance \
  --db-name polling_db \
  --db-instance-identifier vendfinder-polling-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username admin \
  --master-user-password <secure-password>

# Create ElastiCache Redis instance
aws elasticache create-replication-group \
  --replication-group-id vendfinder-polling-redis \
  --description "Redis for polling app" \
  --node-type cache.t3.micro
```

#### 4. **Install Monitoring Stack**
```bash
# Add Prometheus Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus + Grafana
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminUser=admin \
  --set grafana.adminPassword=<secure-password>
```

## 📊 Analytics & Monitoring Features

### Key Metrics to Track:

#### **User Engagement**
- Page views and unique sessions
- Time spent on each question
- Interaction rates per field
- Drop-off points in the survey

#### **Conversion Funnel**
- Question 1 → Question 2 progression
- Complete survey submissions
- Email capture rate
- Feature preference patterns

#### **Performance Metrics**
- API response times
- Database query performance
- Error rates and types
- Infrastructure resource usage

#### **Business Intelligence**
- Most popular use cases
- Price sensitivity analysis
- Feature demand prioritization
- Geographic distribution insights

### Grafana Dashboard Panels:

1. **📈 Submissions Over Time** - Track poll completion trends
2. **🥧 Interest Level Distribution** - See user enthusiasm levels
3. **🌍 Geographic Heat Map** - Where your users are located
4. **⏱️ Completion Time Analysis** - Optimize survey length
5. **📱 Device Type Breakdown** - Mobile vs desktop usage
6. **🔄 User Journey Funnel** - Identify drop-off points
7. **💰 Price Sensitivity Chart** - Understand willingness to pay
8. **⚠️ Error Rate Monitoring** - Operational health tracking

## 🚦 Deployment Checklist

- [ ] ECR repositories created
- [ ] RDS PostgreSQL instance running
- [ ] ElastiCache Redis instance running
- [ ] EKS cluster configured
- [ ] AWS Load Balancer Controller installed
- [ ] SSL certificate configured in ACM
- [ ] Domain DNS pointing to load balancer
- [ ] Prometheus operator installed
- [ ] Grafana dashboard imported
- [ ] Alerting rules configured

## 🔧 Configuration

### Environment Variables
```bash
# Backend API
DATABASE_URL=postgresql://user:pass@rds-endpoint:5432/polling_db
REDIS_URL=redis://elasticache-endpoint:6379
NODE_ENV=production
PORT=3000

# Frontend
API_ENDPOINT=/api
```

### Scaling Configuration
```bash
# Scale frontend for high traffic
kubectl scale deployment polling-frontend --replicas=10 -n polling-app

# Auto-scaling based on CPU
kubectl autoscale deployment polling-frontend --cpu-percent=70 --min=3 --max=20 -n polling-app
```

## 📞 Support & Monitoring

### Useful Commands
```bash
# Check deployment status
kubectl get all -n polling-app

# View logs
kubectl logs -f deployment/polling-frontend -n polling-app
kubectl logs -f deployment/polling-backend -n polling-app

# Port forward for local testing
kubectl port-forward service/polling-frontend-service 8080:80 -n polling-app

# Access Grafana
kubectl port-forward service/prometheus-grafana 3000:80 -n monitoring
```

### Health Checks
- Frontend: `https://your-domain.com/health`
- Backend API: `https://your-domain.com/api/health`
- Metrics: `https://your-domain.com/api/metrics`

## 🎉 Expected Results

Once deployed, you'll have:

1. **📊 Real-time Analytics**: See poll responses as they come in
2. **🔍 Deep Insights**: Understand user behavior at every step
3. **⚡ High Performance**: Handle thousands of concurrent users
4. **🛡️ Production Ready**: Security, monitoring, and scaling built-in
5. **📈 Business Intelligence**: Data-driven product decisions

Your polling app will capture **every user interaction** and provide **actionable insights** for building the perfect translation chat product! 🚀
