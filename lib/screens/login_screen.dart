import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../models/account.dart';
import '../services/account_store.dart';

/// The front door.
///
/// Whoever logs in becomes the person Swat protects — their name comes
/// from the account info and follows them through the app (greeting,
/// reports, blocks they file). The email is the account key; the name
/// field is optional because the app can make a name from the email,
/// the way mail apps do.
///
/// Built to the elderly-first rules (this app's audience): 18sp+ text,
/// one primary action, a 56dp button, plain words, and no password to
/// forget in the demo build — stated openly on the screen.
///
/// Demo honesty: the account is stored on this device only
/// (SharedPreferences via the platform channel). No server, no sync.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final email = _email.text.trim();
    if (!email.contains('@') || email.startsWith('@') || email.endsWith('@')) {
      setState(
        () => _error =
            'That email doesn\'t look complete — '
            'it should look like name@example.com.',
      );
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    await AccountStore.signIn(
      UserAccount(name: _name.text.trim(), email: email),
    );
    // The account gate in main.dart hears the change and swaps this
    // screen for the shell — nothing to navigate here.
  }

  @override
  Widget build(BuildContext context) {
    const magenta = Color(0xFFE20074);
    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [Spacer(), ThemeToggleButton()]),
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: magenta,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  'S',
                  style: TextStyle(
                    color: context.palette.primaryText,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Welcome to Swat',
                style: TextStyle(
                  color: context.palette.primaryText,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A fleet of drones that watches your texts and email for '
                'scams — and explains what it finds in plain words.',
                style: TextStyle(
                  color: context.palette.secondaryText,
                  fontSize: 18,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 34),
              Text(
                'Your email',
                style: TextStyle(
                  color: context.palette.primaryText,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                style: TextStyle(
                  color: context.palette.primaryText,
                  fontSize: 20,
                ),
                decoration: _fieldDecoration('name@example.com'),
              ),
              const SizedBox(height: 22),
              Text(
                'Your name (optional)',
                style: TextStyle(
                  color: context.palette.primaryText,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                keyboardType: TextInputType.name,
                autofillHints: const [AutofillHints.name],
                style: TextStyle(
                  color: context.palette.primaryText,
                  fontSize: 20,
                ),
                decoration: _fieldDecoration('e.g. Maya Reyes'),
              ),
              const SizedBox(height: 8),
              Text(
                'Leave it blank and Swat will make your name from your '
                'email — maya.reyes@… becomes "Maya Reyes".',
                style: TextStyle(
                  color: context.palette.tertiaryText,
                  fontSize: 17,
                  height: 1.4,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFF87171),
                    fontSize: 17.5,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: magenta,
                    textStyle: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _busy ? null : _continue,
                  child: Text(_busy ? 'One moment…' : 'Start protecting me'),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Demo build: your account stays on this phone. No '
                'password, and nothing you type here leaves the device.',
                style: TextStyle(
                  color: context.palette.tertiaryText,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: context.palette.faintText, fontSize: 18),
      filled: true,
      fillColor: const Color(0xFF17171F),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: context.palette.overlayBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE20074), width: 2),
      ),
    );
  }
}
