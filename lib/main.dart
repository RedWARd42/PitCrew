import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/swat_shell.dart';
import 'services/account_store.dart';

void main() {
  runApp(const SwatApp());
}

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
    return MaterialApp(
      title: 'Swat — Signal Swarm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE20074),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AccountGate(),
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
      return const Scaffold(
        backgroundColor: Color(0xFF0B0B12),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return AccountStore.account == null
        ? const LoginScreen()
        : const SwatShell();
  }
}
