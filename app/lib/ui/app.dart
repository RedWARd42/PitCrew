import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding.dart';
import 'prefs.dart';
import 'protected_screen.dart';
import 'theme.dart';

class SwarmApp extends StatelessWidget {
  const SwarmApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Signal Swarm',
    debugShowCheckedModeBanner: false,
    theme: swarmTheme(Brightness.light),
    darkTheme: swarmTheme(Brightness.dark),
    home: const _Root(),
  );
}

class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool? _done;
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _done = p.getBool(Prefs.onboarded) ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_done == null) return const Scaffold();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: _done!
          ? const ProtectedScreen()
          : OnboardingFlow(onDone: () => setState(() => _done = true)),
    );
  }
}
