# rummage

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## CI: Build + Upload to TestFlight / Google Play

This repo ships app store artifacts via **GitHub Actions** when changes land in `main`.

### What happens on `main`

- **Android**: builds an `.aab` and uploads it to a Google Play track.
- **iOS**: builds an `.ipa` and uploads it to TestFlight.
- Both workflows also upload the built artifacts as GitHub Actions artifacts for debugging.

Workflows:
- `.github/workflows/release-android.yml`
- `.github/workflows/release-ios.yml`

### Required GitHub Secrets

Set these in **GitHub → Settings → Secrets and variables → Actions**.

#### Android (Google Play)

- `ANDROID_KEYSTORE_BASE64`: base64 of your upload keystore (CI writes it to `mobile/android/app/upload-keystore.jks`)
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `PLAY_SERVICE_ACCOUNT_JSON`: the full Google Play service account JSON (used by Fastlane `supply`)

Notes:
- CI writes `mobile/android/key.properties` at runtime (do not commit it).
- Package name is `com.rummageapps.rummage`.

#### iOS (TestFlight)

- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_P8`: contents of the `.p8` key (not a file path)
- `MATCH_GIT_URL`: git repo used by Fastlane `match` to store certs/profiles
- `MATCH_PASSWORD`: password used by `match` to encrypt/decrypt the repo
- `MATCH_SSH_PRIVATE_KEY`: SSH private key with access to `MATCH_GIT_URL`

Notes:
- iOS bundle identifier is `com.RummageApp.Rummage`.

### How to run releases

- **Automatic**: merge `develop` → `main` (workflows run on `push` to `main`).
- **Manual**: run from GitHub Actions tab via `workflow_dispatch`.
  - Android workflow exposes a `track` input (`internal`, `closed`, `open`, `production`).

