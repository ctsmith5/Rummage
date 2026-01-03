import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/sales_service.dart';
import 'services/location_service.dart';
import 'services/favorite_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Add crash protection
    FlutterError.onError = (FlutterErrorDetails details) {
      print('Flutter Error: ${details.exception}');
      print('Stack trace: ${details.stack}');
    };
    
    runApp(const RummageApp());
  } catch (e, stackTrace) {
    print('Main initialization error: $e');
    print('Stack trace: $stackTrace');
    // Still try to run the app
    runApp(const RummageApp());
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

