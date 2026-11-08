import 'package:flutter/material.dart';

import 'screens/swat_shell.dart';

void main() {
  runApp(const SwatApp());
}

/// Swat — a fleet of specialist drones that patrol your text messages.
///
/// Built for the T-Mobile "Safe Signal" prompt at HackUTD: instead of one
/// opaque spam score, six named drones (one per scam type) fly over the
/// message, highlight the exact words they object to, explain themselves
/// when tapped, and file the protection report for you.
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
      home: const SwatShell(),
    );
  }
}
