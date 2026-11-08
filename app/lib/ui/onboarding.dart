import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hive_logo.dart';
import 'native.dart';
import 'prefs.dart';
import 'protected_screen.dart';
import 'theme.dart';

const kReceiptSample =
    'From: +1 555 0100\n'
    '"Hi CONTACT, your T-Mobile bill is overdue. Pay now: http://t-mob1le-pay.example\n'
    'Code <CODE:6> expires in 10 min. Card <CARD>"';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow>
    with WidgetsBindingObserver {
  static const _steps = 5; // 3 cards, permission, guardian
  final _pc = PageController();
  int _i = 0;
  bool? _enabled;
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pc.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) async {
    if (s == AppLifecycleState.resumed) {
      final e = await Native.isAccessibilityEnabled();
      if (mounted) setState(() => _enabled = e);
    }
  }

  void _next() => _pc.nextPage(
    duration: const Duration(milliseconds: 400),
    curve: Curves.easeOutCubic,
  );

  Future<void> _finish({bool skipGuardian = false}) async {
    final p = await SharedPreferences.getInstance();
    if (!skipGuardian) {
      await p.setString(Prefs.guardianName, _name.text.trim());
      await p.setString(Prefs.guardianPhone, _phone.text.trim());
    }
    await p.setBool(Prefs.onboarded, true);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final last = _i == _steps - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pc,
                onPageChanged: (i) => setState(() => _i = i),
                children: [
                  const _InfoPage(
                    icon: HiveLogo(size: 110),
                    title: 'A swarm that\nwatches for scams',
                    body: 'Tiny guards read a suspicious text, check it from every angle, and tell you plainly if it’s safe. All in a few seconds.',
                  ),
                  const _InfoPage(
                    icon: Icon(
                      Icons.chat_bubble_outline,
                      size: 72,
                      color: swarmGreen,
                    ),
                    title: 'Reads only\nGoogle Messages',
                    body: 'Signal Swarm is limited to the Google Messages app. It never sees your other apps, and the visible conversation is held in memory only.',
                  ),
                  const _InfoPage(
                    icon: Icon(
                      Icons.receipt_long_outlined,
                      size: 72,
                      color: swarmGreen,
                    ),
                    title: 'Only redacted\ntext leaves',
                    body: 'Names, card numbers and codes are scrubbed on your phone first. You can always see exactly what was sent:',
                    extra: _Receipt(),
                  ),
                  _InfoPage(
                    icon: const Icon(
                      Icons.accessibility_new,
                      size: 72,
                      color: swarmGreen,
                    ),
                    title: 'Turn on\nAccessibility',
                    body: 'Android needs your OK for Signal Swarm to read Google Messages. In Settings, choose Signal Swarm, then switch it on.',
                    extra: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed: Native.openAccessibilitySettings,
                          child: const Text('Open Accessibility settings'),
                        ),
                        const SizedBox(height: 14),
                        AccessStatus(enabled: _enabled),
                      ],
                    ),
                  ),
                  _InfoPage(
                    icon: const Icon(
                      Icons.favorite_border,
                      size: 72,
                      color: swarmGreen,
                    ),
                    title: 'Add a guardian',
                    body: 'Someone you trust who can be alerted about a high-risk scam. They get the category only, never your messages.',
                    extra: Column(
                      children: [
                        TextField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Guardian name',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Guardian phone',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var k = 0; k < _steps; k++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.all(4),
                          width: k == _i ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: k == _i
                                ? swarmGreen
                                : Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: .2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: last ? _finish : _next,
                    child: Text(
                      last ? 'Finish' : (_i == 3 ? 'Continue' : 'Next'),
                    ),
                  ),
                  if (last)
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => _finish(skipGuardian: true),
                      child: const Text('Skip for now'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPage extends StatelessWidget {
  const _InfoPage({
    required this.icon,
    required this.title,
    required this.body,
    this.extra,
  });
  final Widget icon;
  final String title, body;
  final Widget? extra;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: icon),
          const SizedBox(height: 32),
          Semantics(header: true, child: Text(title, style: t.headlineMedium)),
          const SizedBox(height: 14),
          Text(body, style: t.bodyLarge),
          if (extra != null) ...[const SizedBox(height: 20), extra!],
        ],
      ),
    );
  }
}

class _Receipt extends StatelessWidget {
  const _Receipt();
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Sample privacy receipt: $kReceiptSample',
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const ExcludeSemantics(
        child: Text(
          kReceiptSample,
          style: TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
        ),
      ),
    ),
  );
}
