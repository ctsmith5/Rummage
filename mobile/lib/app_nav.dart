import 'package:flutter/material.dart';

/// App-wide navigation/scaffold keys.
///
/// Using these avoids calling Navigator/ScaffoldMessenger on a context that may be
/// mid-dispose during destructive flows (e.g. account deletion), which can cause
/// Overlay/GlobalKey teardown assertions.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

