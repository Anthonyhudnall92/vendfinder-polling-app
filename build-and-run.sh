#!/bin/bash

# Build and run script for VendFinder Translation Chat Poll
# Make executable with: chmod +x build-and-run.sh

set -e  # Exit on any error

echo "🚀 Building VendFinder Translation Chat Poll Container..."

# Create logs directory if it doesn't exist
mkdir -p logs

# Build the Docker image
echo "📦 Building Docker image..."
docker build -t vendfinder-translation-poll:latest .

# Stop existing container if running
echo "🛑 Stopping existing containers..."
docker-compose down 2>/dev/null || true

# Start the application
echo "▶️  Starting VendFinder Translation Chat Poll..."
docker-compose up -d

# Show container status
echo "📊 Container Status:"
docker-compose ps

# Show logs
echo "📝 Recent logs:"
docker-compose logs --tail=50

echo ""
echo "✅ VendFinder Translation Chat Poll is now running!"
echo "🌐 Access the poll at: http://localhost:8080"
echo ""
echo "Commands:"
echo "  View logs:     docker-compose logs -f"
echo "  Stop service:  docker-compose down"
echo "  Restart:       docker-compose restart"