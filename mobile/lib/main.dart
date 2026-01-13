import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/sales_service.dart';
import 'services/location_service.dart';
import 'services/favorite_service.dart';
import 'screens/splash_screen.dart';

void main() async {
    WidgetsFlutterBinding.ensureInitialized();
    
  // Add crash protection (still useful in profile on-device)
  FlutterError.onError = (FlutterErrorDetails details) {
    print('Flutter Error: ${details.exception}');
    print('Stack trace: ${details.stack}');
  };

  try {
    // Initialize Firebase with generated options
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    runApp(const RummageApp());
  } catch (e, stackTrace) {
    // If Firebase isn't configured correctly (common on iOS without GoogleService-Info.plist),
    // the app should NOT continue into runtime and then fail with opaque Auth errors.
    print('Firebase initialization error: $e');
    print('Stack trace: $stackTrace');
    runApp(FirebaseInitErrorApp(error: e.toString()));
  }
}

class RummageApp extends StatelessWidget {
  const RummageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => SalesService()),
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => FavoriteService()),
      ],
      child: MaterialApp(
        title: 'Rummage',
        debugShowCheckedModeBanner: false,
        // Automatically follow system theme setting
        themeMode: ThemeMode.system,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const SplashScreen(),
      ),
    );
  }
}

class FirebaseInitErrorApp extends StatelessWidget {
  final String error;

  const FirebaseInitErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('Firebase not configured')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Firebase failed to initialize.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'On iOS this is often caused by a missing GoogleService-Info.plist. '
                'Add it to mobile/ios/Runner/ and ensure it is included in the Runner target, then rebuild.',
              ),
              const SizedBox(height: 16),
              const Text('Error details:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SelectableText(error),
            ],
          ),
        ),
      ),
    );
  }
}

