# Use the official Nginx image as base
FROM nginx:alpine

# Copy the HTML files to the nginx html directory
COPY index.html /usr/share/nginx/html/
COPY enhanced-survey.html /usr/share/nginx/html/
COPY enhanced-index.html /usr/share/nginx/html/

# Copy nginx configuration if needed (optional)
# COPY nginx.conf /etc/nginx/nginx.conf

# Expose port 80
EXPOSE 80

# Add labels for better container management
LABEL maintainer="anthony@vendfinder.com"
LABEL description="VendFinder Global Translation Chat Polling Application"
LABEL version="1.0"

# Start nginx
CMD ["nginx", "-g", "daemon off;"]