import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/swat_shell.dart';
import 'services/account_store.dart';
import 'services/theme_store.dart';
import 'services/protection_reports.dart';
import 'theme/app_palette.dart';
import 'ui/overlay_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeStore.load();
  await ReportHandoff.start();
  runApp(const SwatApp());
}

/// Flutter surface hosted by Swat's Android accessibility service.
@pragma('vm:entry-point')
void overlayMain() => runApp(buildOverlayApp());

/// Swat — a fleet of specialist drones that patrol your text messages.
///
/// Built for the T-Mobile "Safe Signal" prompt at HackUTD: instead of one
/// opaque spam score, six named drones (one per scam type) fly over the
/// message, highlight the exact words they object to, explain themselves
/// when tapped, and file the protection report for you.
///
/// The app is account-first and general: whoever logs in is the person
/// being protected, and their name — from the account info — is what the
/// greeting, reports, and block list use. No account on this device yet
/// means the login screen; a stored account opens straight into the app.
class SwatApp extends StatelessWidget {
  const SwatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeStore.mode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Swat — Signal Swarm',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        home: const AccountGate(),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFE20074),
        brightness: brightness,
      ),
      useMaterial3: true,
      // Senior-first scale (elderly_mobile_ui skill): body text lives
      // at 17-18sp, nothing meaningful below 14sp, primary actions are
      // at least 56dp tall, and secondary text stays at white70 —
      // gray-on-dark "elegance" is the most common senior-hostile
      // choice in dark UIs.
      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 18, height: 1.45),
        bodyMedium: TextStyle(fontSize: 17, height: 1.45),
        bodySmall: TextStyle(fontSize: 15, height: 1.4),
        labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        labelMedium: TextStyle(fontSize: 14.5),
        labelSmall: TextStyle(fontSize: 13.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 58),
          textStyle: const TextStyle(
            fontSize: 17.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 56),
          textStyle: const TextStyle(fontSize: 17),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(fontSize: 16),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 76,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: const ChipThemeData(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        labelStyle: TextStyle(fontSize: 15.5),
      ),
    );
  }
}

/// Decides between the spinner, the login screen, and the app itself,
/// and keeps deciding when the account changes (sign-in / sign-out).
class AccountGate extends StatefulWidget {
  const AccountGate({super.key});

  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> {
  StreamSubscription<void>? _sub;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _sub = AccountStore.changes.listen((_) {
      if (mounted) setState(() {});
    });
    AccountStore.load().then((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !AccountStore.isLoaded) {
      return Scaffold(
        backgroundColor: context.palette.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return AccountStore.account == null
        ? const LoginScreen()
        : const SwatShell();
  }
}
