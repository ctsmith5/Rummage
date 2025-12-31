# Rummage

A mobile app for discovering and advertising garage sales in your local area.

## Overview

Rummage helps users find nearby garage sales and allows sellers to advertise their sales to the local community. Built with Flutter for the mobile frontend and Go for the backend API.

## Features

- **User Authentication**: Email/password registration and login
- **GPS-Based Discovery**: Find garage sales near your current location
- **Map View**: Interactive map showing all nearby sales with pins
- **Create Sales**: Post your own garage sales with details and items
- **Item Management**: Add items with photos, descriptions, and prices
- **Live Status**: Start and end sales to show customers when you're active
- **Favorites**: Save sales you're interested in
- **Dark Mode**: Automatic theme switching based on system settings

## Tech Stack

- **Mobile App**: Flutter (Dart)
- **Backend**: Go with Chi router
- **Authentication**: JWT tokens
- **Database**: TBD (currently using in-memory storage)

## Project Structure

```
Rummage/
├── mobile/                 # Flutter mobile app
│   ├── lib/
│   │   ├── main.dart       # App entry point
│   │   ├── theme/          # Light and dark theme definitions
│   │   ├── models/         # Data models
│   │   ├── screens/        # UI screens
│   │   ├── services/       # API clients and state management
│   │   └── widgets/        # Reusable UI components
│   └── pubspec.yaml        # Flutter dependencies
├── backend/                # Go backend API
│   ├── cmd/server/         # Server entry point
│   ├── internal/
│   │   ├── handlers/       # HTTP request handlers
│   │   ├── models/         # Data models
│   │   ├── services/       # Business logic
│   │   ├── middleware/     # Auth middleware
│   │   └── config/         # Configuration
│   └── go.mod              # Go dependencies
└── README.md
```

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.0+)
- [Go](https://golang.org/dl/) (1.21+)
- Android Studio / Xcode for mobile development
- Google Maps API key (for map functionality)

### Backend Setup

1. Navigate to the backend directory:
   ```bash
   cd backend
   ```

2. Install dependencies:
   ```bash
   go mod download
   ```

3. Create a `.env` file (optional):
   ```env
   SERVER_ADDRESS=:8080
   JWT_SECRET=your-secret-key-here
   UPLOAD_DIR=./uploads
   ```

4. Run the server:
   ```bash
   go run cmd/server/main.go
   ```

The API will be available at `http://localhost:8080`

### Mobile App Setup

1. Navigate to the mobile directory:
   ```bash
   cd mobile
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Configure Google Maps:
   - Get an API key from [Google Cloud Console](https://console.cloud.google.com/)
   - Android: Add key to `android/app/src/main/AndroidManifest.xml`
   - iOS: Add key to `ios/Runner/AppDelegate.swift`

4. Update the API base URL in `lib/services/api_client.dart` if needed

5. Run the app:
   ```bash
   flutter run
   ```

## API Endpoints

### Authentication
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth/register` | Register new user |
| POST | `/api/auth/login` | Login user |
| GET | `/api/auth/profile` | Get current user profile |

### Garage Sales
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/sales` | List nearby sales (query: lat, lng, radius) |
| POST | `/api/sales` | Create new sale |
| GET | `/api/sales/:id` | Get sale details |
| PUT | `/api/sales/:id` | Update sale |
| DELETE | `/api/sales/:id` | Delete sale |
| POST | `/api/sales/:id/start` | Start sale (set active) |
| POST | `/api/sales/:id/end` | End sale (set inactive) |

### Items
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/sales/:id/items` | Add item to sale |
| DELETE | `/api/sales/:id/items/:itemId` | Remove item |

### Favorites
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/favorites` | List user's favorites |
| POST | `/api/sales/:id/favorite` | Add to favorites |
| DELETE | `/api/sales/:id/favorite` | Remove from favorites |

### Images
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/upload` | Upload image |
| DELETE | `/api/upload/:imageId` | Delete image |

## Theming

The app supports both light and dark themes, automatically switching based on the user's system preference.

### Light Theme
- Primary: Blue (#2196F3)
- Background: White (#FFFFFF)
- Surface: Light Gray (#F5F5F5)

### Dark Theme
- Primary: Blue (#2196F3)
- Background: Charcoal (#1E1E1E)
- Surface: Dark Gray (#2D2D2D)

## Future Enhancements

- [ ] Database integration (PostgreSQL/SQLite)
- [ ] Push notifications for new sales in area
- [ ] Messaging between buyers and sellers
- [ ] Search and filter by category/keyword
- [ ] Social authentication (Google, Apple)
- [ ] Sale ratings and reviews

## License

MIT License - see LICENSE file for details

