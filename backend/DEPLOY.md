# Deploying Rummage Backend to Google Cloud Run

## Prerequisites

1. **Install Google Cloud SDK**
   ```bash
   # Download from https://cloud.google.com/sdk/docs/install
   # Or on macOS with Homebrew:
   brew install --cask google-cloud-sdk
   ```

2. **Authenticate**
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

## Method 1: Quick Deploy (Recommended for Dev/Testing)

```bash
cd backend

# Set your project ID
export PROJECT_ID=your-project-id

# Build and deploy in one command
gcloud run deploy rummage-backend \
  --source . \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars JWT_SECRET=your-secret-key-change-this \
  --memory 512Mi \
  --cpu 1 \
  --max-instances 10
```

This will:
- Build the Docker image
- Push to Google Container Registry
- Deploy to Cloud Run
- Give you a URL like: `https://rummage-backend-xxxxx.run.app`

## Method 2: Build Docker Image First

```bash
cd backend

# Build the image
docker build -t gcr.io/YOUR_PROJECT_ID/rummage-backend:latest .

# Push to Google Container Registry
docker push gcr.io/YOUR_PROJECT_ID/rummage-backend:latest

# Deploy to Cloud Run
gcloud run deploy rummage-backend \
  --image gcr.io/YOUR_PROJECT_ID/rummage-backend:latest \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars JWT_SECRET=your-secret-key-change-this
```

## Environment Variables

Set secrets via Cloud Run:
```bash
gcloud run services update rummage-backend \
  --set-env-vars JWT_SECRET=your-actual-secret-key \
  --region us-central1
```

Or use Secret Manager (more secure):
```bash
# Create secret
echo -n "your-secret-key" | gcloud secrets create jwt-secret --data-file=-

# Grant Cloud Run access
gcloud secrets add-iam-policy-binding jwt-secret \
  --member="serviceAccount:YOUR_SERVICE_ACCOUNT" \
  --role="roles/secretmanager.secretAccessor"

# Update service to use secret
gcloud run services update rummage-backend \
  --update-secrets JWT_SECRET=jwt-secret:latest \
  --region us-central1
```

## Update API URL in Flutter App

After deployment, update `mobile/lib/services/api_client.dart`:

```dart
static const String baseUrl = 'https://rummage-backend-xxxxx.run.app/api';
```

Replace `xxxxx` with your actual Cloud Run service URL.

## Useful Commands

```bash
# View logs
gcloud run services logs read rummage-backend --region us-central1

# View service details
gcloud run services describe rummage-backend --region us-central1

# Update service
gcloud run services update rummage-backend --region us-central1

# Delete service
gcloud run services delete rummage-backend --region us-central1
```

## Pricing

Cloud Run charges per request and compute time. For dev/testing:
- Free tier: 2 million requests/month
- After free tier: ~$0.40 per million requests
- Compute: $0.00002400 per GB-second
- Typically costs <$1/month for light testing

## Notes

- The service will scale to zero when idle (no cost)
- Files uploaded to `/uploads` are stored in the container (ephemeral - will be lost on restart)
- For production, consider using Cloud Storage for file uploads
- For production, use a database (Cloud SQL, Firestore, etc.) instead of in-memory storage




