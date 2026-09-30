import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/services/pairing_service.dart';
import 'core/theme/agy_theme.dart';
import 'core/theme/antigravity_logo.dart';
import 'views/desktop/windows_fleet_station.dart';
import 'views/home_scaffold.dart';
import 'views/pairing/station_pairing_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }
  runApp(
    const ProviderScope(
      child: AntigravityApp(),
    ),
  );
}

class AntigravityApp extends ConsumerWidget {
  const AntigravityApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final pairing = ref.watch(pairingProvider);

    final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

    Widget homeWidget;
    if (isDesktop) {
      // Windows Desktop App: 15-Account Control Station with 1-Button Login & QR
      homeWidget = const WindowsFleetStation();
    } else {
      // Mobile Android/iOS APK:
      if (pairing.isLoading) {
        homeWidget = const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: AntigravityLogo(size: 40),
          ),
        );
      } else if (!pairing.isPaired) {
        // First time launch: Prompt to scan QR code
        homeWidget = const StationPairingScreen();
      } else {
        // Permanently bound: Direct access
        homeWidget = const HomeScaffold();
      }
    }

    return MaterialApp(
      title: isDesktop ? 'Antigravity Fleet Command Station' : 'Antigravity Mobile Command',
      debugShowCheckedModeBanner: false,
      theme: AgyTheme.lightTheme,
      darkTheme: AgyTheme.darkTheme,
      themeMode: themeMode,
      home: homeWidget,
    );
  }
}
