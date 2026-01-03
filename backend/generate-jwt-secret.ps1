# PowerShell script to generate a secure random JWT secret key

Write-Host "Generating JWT secret key..." -ForegroundColor Green
Write-Host ""

# Generate a secure random 32-byte key and convert to Base64
$bytes = New-Object byte[] 32
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)
$secret = [Convert]::ToBase64String($bytes)

Write-Host "Your JWT Secret Key:" -ForegroundColor Yellow
Write-Host $secret -ForegroundColor White
Write-Host ""
Write-Host "Copy this key and use it when deploying:" -ForegroundColor Cyan
Write-Host "  gcloud run deploy rummage-backend --set-env-vars JWT_SECRET=`"$secret`"" -ForegroundColor White
Write-Host ""
Write-Host "Or set it as an environment variable:" -ForegroundColor Cyan
Write-Host "  `$env:JWT_SECRET=`"$secret`"" -ForegroundColor White




