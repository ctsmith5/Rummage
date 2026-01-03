#!/bin/bash
# Generate a secure random JWT secret key

echo "Generating JWT secret key..."
SECRET=$(openssl rand -base64 32)
echo ""
echo "Your JWT Secret Key:"
echo "$SECRET"
echo ""
echo "Copy this key and use it when deploying:"
echo "  gcloud run deploy rummage-backend --set-env-vars JWT_SECRET=\"$SECRET\""
echo ""
echo "Or set it as an environment variable:"
echo "  export JWT_SECRET=\"$SECRET\""



