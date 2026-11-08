import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hive_logo.dart';
import 'native.dart';
import 'prefs.dart';
import 'theme.dart';

class AccessStatus extends StatelessWidget {
  const AccessStatus({super.key, required this.enabled});
  final bool? enabled; // null = unknown
  @override
  Widget build(BuildContext context) {
    final on = enabled == true;
    final text = enabled == null
        ? 'Status unknown'
        : on
        ? 'Accessibility access is on'
        : 'Accessibility access is off';
    final color = on ? swarmGreen : Theme.of(context).colorScheme.error;
    return Semantics(
      label: text,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            on ? Icons.check_circle : Icons.error_outline,
            color: enabled == null ? Colors.grey : color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: ExcludeSemantics(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProtectedScreen extends StatefulWidget {
  const ProtectedScreen({super.key});
  @override
  State<ProtectedScreen> createState() => _ProtectedScreenState();
}

class _ProtectedScreenState extends State<ProtectedScreen>
    with WidgetsBindingObserver {
  bool? _enabled;
  String _guardian = '';
  final _url = TextEditingController(text: Prefs.defaultUrl);
  final _key = TextEditingController(text: Prefs.defaultKey);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final e = await Native.isAccessibilityEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = e;
      _guardian = p.getString(Prefs.guardianName) ?? '';
      _url.text = p.getString(Prefs.backendUrl) ?? Prefs.defaultUrl;
      _key.text = p.getString(Prefs.apiKey) ?? Prefs.defaultKey;
    });
  }

  Future<void> _saveDebug() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(Prefs.backendUrl, _url.text.trim());
    await p.setString(Prefs.apiKey, _key.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          children: [
            const Center(child: HiveLogo(size: 120)),
            const SizedBox(height: 28),
            Text(
              'You’re protected',
              textAlign: TextAlign.center,
              style: t.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(
              'Open Google Messages. Signal Swarm watches for scams and stays quiet otherwise.',
              textAlign: TextAlign.center,
              style: t.bodyLarge,
            ),
            const SizedBox(height: 20),
            Center(child: AccessStatus(enabled: _enabled)),
            if (_enabled != true) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: Native.openAccessibilitySettings,
                child: const Text('Open Accessibility settings'),
              ),
            ],
            const SizedBox(height: 28),
            if (_guardian.isNotEmpty)
              ListTile(
                tileColor: cardColor(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: const Icon(Icons.shield_outlined),
                title: Text('Guardian: $_guardian'),
                minVerticalPadding: 12,
              ),
            const SizedBox(height: 12),
            ExpansionTile(
              title: const Text('Developer'),
              shape: const Border(),
              collapsedShape: const Border(),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                TextField(
                  controller: _url,
                  decoration: const InputDecoration(labelText: 'Backend URL'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _key,
                  decoration: const InputDecoration(labelText: 'API key'),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _saveDebug, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
