#!/bin/sh
# Entrypoint script to set API_BASE from environment variable
# This allows the COBOL program to use the correct API endpoint

# Read API_BASE from environment (set by Kubernetes ConfigMap)
# If not set, use default
API_BASE="${API_BASE:-http://php-api-service:9000}"

# Export for the COBOL program (though COBOL reads it differently)
export API_BASE

# For now, the COBOL program uses the hardcoded default
# which matches the Kubernetes service name
# In a production setup, you'd modify the COBOL program to read env vars
# or use a config file

exec /app/server

