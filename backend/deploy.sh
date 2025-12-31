#!/bin/bash
# Quick deployment script for Google Cloud Run

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Deploying Rummage Backend to Google Cloud Run${NC}"

# Get project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo -e "${YELLOW}No project ID found. Please set it with:${NC}"
    echo "  gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

echo -e "${GREEN}Project: ${PROJECT_ID}${NC}"

# Check if JWT_SECRET is set
if [ -z "$JWT_SECRET" ]; then
    echo -e "${YELLOW}Warning: JWT_SECRET not set. Using default (change in production!)${NC}"
    JWT_SECRET="your-secret-key-change-in-production"
fi

# Deploy
gcloud run deploy rummage-backend \
  --source . \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars "JWT_SECRET=${JWT_SECRET}" \
  --memory 512Mi \
  --cpu 1 \
  --max-instances 10 \
  --project "$PROJECT_ID"

echo -e "${GREEN}✅ Deployment complete!${NC}"
echo ""
echo "Get your service URL with:"
echo "  gcloud run services describe rummage-backend --region us-central1 --format 'value(status.url)'"

