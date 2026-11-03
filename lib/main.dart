import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/app_shell.dart';
import 'services/backend_connector.dart';
import 'state/guard_state.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  final state = GuardState();
  // Links the app to the user's ThreatGuard server (see server/). It
  // restores the last connection, or follows a pairing link in the page URL.
  final connector = BackendConnector(state)..start();
  // Coming back to the app: re-check the SMS permission and catch up.
  AppLifecycleListener(onResume: connector.onAppResumed);
  runApp(
    ChangeNotifierProvider.value(value: state, child: const ThreatGuardApp()),
  );
}

class ThreatGuardApp extends StatelessWidget {
  const ThreatGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ThreatGuard AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark().copyWith(
        pageTransitionsTheme: PageTransitionsTheme(
          builders: {
            for (final p in TargetPlatform.values)
              p: const CupertinoPageTransitionsBuilder(),
          },
        ),
      ),

      builder: (context, child) {
        final mq = MediaQuery.of(context);
        // Design width 390. The app column is capped at 520.
        final width = math.min(mq.size.width, 520.0);
        final layoutScale = (width / 390).clamp(0.95, 1.1).toDouble();
        // Respect the user's font setting, but cap it so layouts don't break.
        final userScale = mq.textScaler.scale(1).clamp(0.9, 1.2).toDouble();
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(layoutScale * userScale),
          ),
          child: child!,
        );
      },

      home: const AppShell(),
    );
  }
}
