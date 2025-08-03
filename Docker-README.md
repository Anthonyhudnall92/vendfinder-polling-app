# VendFinder Translation Chat Poll - Docker Setup

This directory contains the Docker configuration for the VendFinder Translation Chat polling application.

## 🚀 Quick Start

### Prerequisites
- Docker installed on your system
- Docker Compose installed

### Option 1: Using the Build Script (Recommended)
```bash
# Make the script executable
chmod +x build-and-run.sh

# Run the script
./build-and-run.sh
```

### Option 2: Manual Docker Commands
```bash
# Build the image
docker build -t vendfinder-translation-poll:latest .

# Run with docker-compose
docker-compose up -d

# Or run directly with Docker
docker run -d -p 8080:80 --name vendfinder-poll vendfinder-translation-poll:latest
```

## 📁 File Structure
```
vendfinder-poll/
├── index.html              # Main poll application
├── Dockerfile              # Docker container definition
├── docker-compose.yml      # Docker Compose configuration
├── build-and-run.sh       # Automated build script
├── Docker-README.md        # This file
└── logs/                   # Nginx logs directory (created automatically)
```

## 🌐 Access
Once running, access the poll at:
- **Local**: http://localhost:8080
- **Production**: Configure your domain in docker-compose.yml

## 🔧 Configuration

### Environment Variables
The following environment variables can be configured in `docker-compose.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `NGINX_HOST` | `poll.vendfinder.com` | Domain name for the service |
| `NGINX_PORT` | `80` | Internal nginx port |

### Port Configuration
- **Host Port**: 8080 (configurable in docker-compose.yml)
- **Container Port**: 80 (nginx default)

### SSL/TLS Setup
The docker-compose.yml includes basic Traefik labels for SSL setup. To enable:

1. Ensure you have Traefik running
2. Update the domain name in the labels
3. Configure your DNS to point to your server

## 📊 Monitoring & Logs

### View Logs
```bash
# View recent logs
docker-compose logs

# Follow logs in real-time
docker-compose logs -f

# View nginx access logs
tail -f logs/access.log

# View nginx error logs
tail -f logs/error.log
```

### Container Management
```bash
# Check container status
docker-compose ps

# Restart the service
docker-compose restart

# Stop the service
docker-compose down

# Update and restart
docker-compose up -d --build
```

## 🔄 Updating the Poll

1. Update the `index.html` file with your changes
2. Rebuild and restart:
   ```bash
   docker-compose down
   docker-compose up -d --build
   ```

## 🎯 Production Deployment

### For Production Use:
1. Update the domain in `docker-compose.yml`
2. Configure SSL certificates
3. Set up proper monitoring
4. Configure log rotation
5. Set up automated backups if using Redis

### Scaling Options:
To handle more traffic, you can:
- Run multiple container instances
- Use a load balancer (nginx proxy, Traefik, etc.)
- Add Redis for session storage and analytics

## 📈 Data Collection

Currently, poll responses are stored in browser localStorage. For production, consider:

1. **Add a backend service** to collect responses
2. **Enable Redis** (uncomment Redis service in docker-compose.yml)
3. **Add analytics** integration
4. **Set up database** for persistent storage

## 🛠️ Troubleshooting

### Common Issues:

**Port already in use:**
```bash
# Change the port in docker-compose.yml or stop conflicting services
sudo lsof -i :8080
```

**Permission denied:**
```bash
# Make script executable
chmod +x build-and-run.sh
```

**Container won't start:**
```bash
# Check logs for errors
docker-compose logs
```

### Health Checks
Test if the service is running:
```bash
curl http://localhost:8080
```

## 📞 Support

For issues with the Docker setup:
1. Check the logs: `docker-compose logs`
2. Verify Docker and Docker Compose are installed
3. Ensure port 8080 is available
4. Check file permissions

---

**Built for VendFinder by Anthony** 🚀