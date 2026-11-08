import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/message.dart';
import '../services/stores.dart';
import '../theme/app_palette.dart';
import '../widgets/drone_widget.dart';
import 'native.dart';
import 'prefs.dart';

/// Swat's setup surface for the fleet running outside its own inbox.
class ProtectedScreen extends StatefulWidget {
  const ProtectedScreen({super.key});
  @override
  State<ProtectedScreen> createState() => _ProtectedScreenState();
}

class _ProtectedScreenState extends State<ProtectedScreen>
    with WidgetsBindingObserver {
  bool? _enabled;
  bool _guardianEnabled = false;
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = await Native.isAccessibilityEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _guardianEnabled =
          prefs.getString(Prefs.guardianPhone) == FamilyStore.contact.phone;
      _url.text = prefs.getString(Prefs.backendUrl) ?? Prefs.defaultUrl;
      _key.text = prefs.getString(Prefs.apiKey) ?? Prefs.defaultKey;
    });
  }

  Future<void> _setGuardian(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      await prefs.setString(Prefs.guardianName, FamilyStore.contact.name);
      await prefs.setString(Prefs.guardianPhone, FamilyStore.contact.phone);
    } else {
      await prefs.remove(Prefs.guardianName);
      await prefs.remove(Prefs.guardianPhone);
    }
    if (mounted) setState(() => _guardianEnabled = enabled);
  }

  Future<void> _save() async {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid backend URL.')),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(Prefs.backendUrl, _url.text.trim());
    await prefs.setString(Prefs.apiKey, _key.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('Protection outside Swat'),
        backgroundColor: palette.panel,
        actions: const [ThemeToggleButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final drone in DroneId.values)
                DroneArtwork(
                  color: Color(drone.colorValue),
                  icon: drone.icon,
                  size: 42,
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            _enabled == true
                ? 'The fleet is on patrol'
                : 'Take the fleet with you',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'The same Swat drones can point at suspicious words in Google Messages and Gmail. Tap a drone to see its evidence.',
            style: TextStyle(color: palette.secondaryText, height: 1.45),
          ),
          const SizedBox(height: 24),
          Card(
            color: palette.panel,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        _enabled == true
                            ? Icons.verified_user
                            : Icons.shield_outlined,
                        color: const Color(0xFFE20074),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _enabled == null
                              ? 'Checking Android access'
                              : _enabled!
                              ? 'Accessibility access is on'
                              : 'Accessibility access is off',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'In Android Accessibility settings, choose Swat and allow access. Only visible conversations in Messages and Gmail are read.',
                    style: TextStyle(color: palette.secondaryText),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: Native.openAccessibilitySettings,
                    icon: const Icon(Icons.settings_accessibility),
                    label: Text(
                      _enabled == true
                          ? 'Manage Android access'
                          : 'Enable protection',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: const Icon(
              Icons.privacy_tip_outlined,
              color: Color(0xFFE20074),
            ),
            title: const Text('Private before it leaves your phone'),
            subtitle: const Text(
              'Names, card numbers and codes are redacted before backend scans. Each protection report includes a privacy receipt. Other apps are not read.',
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.all(12),
            value: _guardianEnabled,
            onChanged: _setGuardian,
            title: Text('Use ${FamilyStore.contact.name} from Family'),
            subtitle: const Text(
              'Adds your trusted contact to the alert action. Alerts are sent only when you choose to notify them, without message content.',
            ),
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('Scan connection'),
            subtitle: const Text('Backend settings for this device'),
            childrenPadding: const EdgeInsets.all(12),
            children: [
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Backend URL'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _key,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'API key'),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }
}
