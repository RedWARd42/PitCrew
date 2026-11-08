import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../data/demo_emails.dart';
import '../models/email.dart';
import '../models/message.dart';
import 'drone_chat_screen.dart';
import '../services/account_store.dart';
import '../services/email_analyzer.dart';
import '../services/stores.dart';
import '../services/walkthrough.dart';
import '../widgets/drone_widget.dart';

const Color _kMagenta = Color(0xFFE20074);

/// The mailbox beat: the same fleet, over email.
///
/// Email was Signal Swarm's first stage (the corporate inbox), and it is
/// where phishing still lives — with tells texts don't have: sending
/// domains that don't match the display name, Reply-To tricks, and
/// attachments. The flow is identical on purpose: release the fleet,
/// drones highlight their evidence in the open email, tap one and it
/// *teaches* you the tell in a step-by-step walkthrough. Learning the
/// tell is the protection that survives after the demo ends.
class EmailsScreen extends StatelessWidget {
  const EmailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        backgroundColor: context.palette.panel,
        actions: const [ThemeToggleButton()],
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Inbox',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              'protected by Swat',
              style: TextStyle(fontSize: 13.5, color: _kMagenta),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            color: context.palette.sheet,
            child: Text(
              'Same fleet, second beat. Open an email, release the drones, '
              'then tap one — it teaches you the tell right here in the '
              'mail app. Demo mailbox: synthetic mail only.',
              style: TextStyle(
                color: context.palette.tertiaryText,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: demoEmails.length,
              itemBuilder: (context, i) => _emailRow(context, demoEmails[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emailRow(BuildContext context, EmailMessage email) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EmailDetailScreen(email: email),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.palette.divider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: context.palette.avatarBg,
              child: Text(
                email.fromName.substring(0, 1).toUpperCase(),
                style: TextStyle(color: context.palette.secondaryText),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          email.fromName,
                          style: TextStyle(
                            color: context.palette.primaryText,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        email.timeLabel,
                        style: TextStyle(
                          color: context.palette.tertiaryText,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    email.subject,
                    style: TextStyle(
                      color: context.palette.primaryText,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          email.snippet,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.palette.tertiaryText,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (email.hasAttachment)
                        Icon(
                          Icons.attach_file,
                          size: 14,
                          color: context.palette.tertiaryText,
                        ),
                      if (email.qrPayload != null)
                        const Icon(
                          Icons.qr_code_2,
                          size: 14,
                          color: Color(0xFFA78BFA),
                        ),
                    ],
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

/// One open email, with the fleet over it. Same protection loop as the
/// Messages screen: release → scan highlights → tap a drone → walkthrough
/// → Block & Report → share with the trusted contact.
class EmailDetailScreen extends StatefulWidget {
  const EmailDetailScreen({super.key, required this.email});

  final EmailMessage email;

  @override
  State<EmailDetailScreen> createState() => _EmailDetailScreenState();
}

enum _Phase { idle, scanning, revealed, protected }

class _EmailDetailScreenState extends State<EmailDetailScreen> {
  static const EmailAnalyzer _analyzer = EmailAnalyzer();
  late final MessageAnalysis _analysis = _analyzer.analyze(widget.email);

  _Phase _phase = _Phase.idle;
  int _revealed = 0;
  int _scanningIdx = -1;
  List<WalkthroughStep>? _walk;
  int _walkIndex = 0;

  /// Analyzer spans index into displayText (subject + body); the reading
  /// view renders the body separately, so shift spans by the header size.
  int get _spanOffset => widget.email.subject.length + 1;

  Future<void> _release() async {
    if (_phase == _Phase.scanning) return;
    setState(() {
      _phase = _Phase.scanning;
      _revealed = 0;
      _walk = null;
    });
    // Reduce-motion: land instantly when the system asks for no animation.
    final stepMs = MediaQuery.of(context).disableAnimations ? 0 : 260;
    for (var i = 0; i < DroneId.values.length; i++) {
      if (!mounted || _phase != _Phase.scanning) return;
      setState(() => _scanningIdx = i);
      await Future<void>.delayed(Duration(milliseconds: stepMs));
      if (!mounted || _phase != _Phase.scanning) return;
      setState(() {
        _revealed = i + 1;
        _scanningIdx = -1;
      });
    }
    if (!mounted) return;
    setState(() => _phase = _Phase.revealed);
  }

  List<Finding> get _activeFindings {
    if (_phase == _Phase.idle) return const [];
    if (_walk != null) return [_walk![_walkIndex].finding];
    final landed = _phase == _Phase.scanning
        ? DroneId.values.take(_revealed).toSet()
        : DroneId.values.toSet();
    return _analysis.findings
        .where((f) => f.hasSpan && landed.contains(f.drone))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.email;
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        backgroundColor: context.palette.panel,
        title: const Text('Email', style: TextStyle(fontSize: 18)),
        actions: const [ThemeToggleButton()],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 92, 90),
                    child: _emailCard(email),
                  ),
                  ..._drones(constraints),
                ],
              ),
            ),
          ),
          _bottomPanel(),
        ],
      ),
    );
  }

  Widget _emailCard(EmailMessage email) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.sheet,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _phase == _Phase.idle ? context.palette.divider : _kMagenta,
          width: _phase == _Phase.idle ? 1 : 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            email.subject,
            style: TextStyle(
              color: context.palette.primaryText,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: context.palette.avatarBg,
                child: Text(
                  email.fromName.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    color: context.palette.secondaryText,
                    fontSize: 14.5,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      email.fromName,
                      style: TextStyle(
                        color: context.palette.primaryText,
                        fontWeight: FontWeight.w600,
                        fontSize: 15.5,
                      ),
                    ),
                    Text(
                      email.fromAddress,
                      style: TextStyle(
                        color: context.palette.tertiaryText,
                        fontSize: 14.5,
                      ),
                    ),
                    if (email.replyTo != null)
                      Text(
                        'Reply-To: ${email.replyTo}',
                        style: TextStyle(
                          color: context.palette.tertiaryText,
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                email.timeLabel,
                style: TextStyle(
                  color: context.palette.tertiaryText,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
          Divider(color: context.palette.divider, height: 22),
          Text.rich(
            TextSpan(
              style: TextStyle(
                color: context.palette.primaryText,
                fontSize: 16.5,
                height: 1.45,
              ),
              children: _highlightedBody(email.body, _activeFindings),
            ),
          ),
          if (email.hasAttachment) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: context.palette.bubble,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: context.palette.divider),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.attach_file,
                    size: 15,
                    color: context.palette.tertiaryText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    email.attachmentName!,
                    style: TextStyle(
                      color: context.palette.secondaryText,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (email.qrPayload != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: context.palette.bubble,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: const Color(0xFFA78BFA).withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_2, size: 15, color: Color(0xFFA78BFA)),
                  SizedBox(width: 6),
                  Text(
                    'QR code in this email',
                    style: TextStyle(
                      color: context.palette.secondaryText,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<TextSpan> _highlightedBody(String body, List<Finding> findings) {
    final shifted = <Finding>[];
    for (final f in findings) {
      final start = f.spanStart - _spanOffset;
      final end = f.spanEnd - _spanOffset;
      if (end <= 0 || start >= body.length) continue;
      shifted.add(
        Finding(
          drone: f.drone,
          title: f.title,
          detail: f.detail,
          points: f.points,
          spanStart: start.clamp(0, body.length),
          spanEnd: end.clamp(0, body.length),
          evidence: f.evidence,
        ),
      );
    }
    if (shifted.isEmpty) return [TextSpan(text: body)];
    shifted.sort((a, b) => a.spanStart.compareTo(b.spanStart));
    final children = <TextSpan>[];
    var cursor = 0;
    for (final f in shifted) {
      if (f.spanStart < cursor || f.spanEnd <= f.spanStart) continue;
      if (f.spanStart > cursor) {
        children.add(TextSpan(text: body.substring(cursor, f.spanStart)));
      }
      children.add(
        TextSpan(
          text: body.substring(f.spanStart, f.spanEnd),
          style: TextStyle(
            backgroundColor: Color(f.drone.colorValue).withValues(alpha: 0.45),
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      cursor = f.spanEnd;
    }
    if (cursor < body.length) {
      children.add(TextSpan(text: body.substring(cursor)));
    }
    return children;
  }

  List<Widget> _drones(BoxConstraints constraints) {
    if (_phase == _Phase.idle) return const [];
    final widgets = <Widget>[];
    for (var i = 0; i < DroneId.values.length; i++) {
      final drone = DroneId.values[i];
      final landed = _phase != _Phase.scanning || i < _revealed;
      final top =
          8.0 + i * ((constraints.maxHeight - 88) / DroneId.values.length);
      final dockLeft =
          8.0 + i * ((constraints.maxWidth - 68) / (DroneId.values.length - 1));
      widgets.add(
        AnimatedPositioned(
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          left: landed ? constraints.maxWidth - 70 : dockLeft,
          top: landed ? top : constraints.maxHeight - 78,
          child: DroneWidget(
            drone: drone,
            size: landed ? 56 : 52,
            scanning: _phase == _Phase.scanning && i == _scanningIdx,
            badgePoints: _phase == _Phase.revealed || _phase == _Phase.protected
                ? _analysis.pointsFor(drone)
                : null,
            onTap: () => _openDronePanel(drone),
          ),
        ),
      );
    }
    return widgets;
  }

  void _openDronePanel(DroneId drone) {
    final findings = _analysis.findingsFor(drone);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DroneWidget(drone: drone, size: 44, showLabel: false),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      drone.label,
                      style: TextStyle(
                        color: context.palette.primaryText,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      drone.specialty,
                      style: TextStyle(
                        color: context.palette.secondaryText,
                        fontSize: 14.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final f in findings)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.title,
                      style: TextStyle(
                        color: f.isFlag
                            ? const Color(0xFFFCA5A5)
                            : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      f.detail,
                      style: TextStyle(
                        color: context.palette.secondaryText,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  setState(() {
                    _walk = buildWalkthrough(_analysis, drone);
                    _walkIndex = 0;
                  });
                },
                icon: const Icon(Icons.school_outlined),
                label: const Text('Teach me — walk through it'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          DroneChatScreen(drone: drone, analysis: _analysis),
                    ),
                  );
                },
                icon: const Icon(Icons.mic),
                label: Text('Talk to ${drone.label} — ask by voice'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelShell(Widget child) {
    return Material(
      color: context.palette.panel,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.palette.divider)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 430),
          child: SingleChildScrollView(child: child),
        ),
      ),
    );
  }

  Widget _bottomPanel() {
    if (_walk != null) {
      final steps = _walk!;
      final step = steps[_walkIndex];
      final color = Color(step.drone.colorValue);
      return _panelShell(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.school, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    step.headline,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  'Step ${_walkIndex + 1} of ${steps.length}',
                  style: TextStyle(
                    color: context.palette.tertiaryText,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              step.narration,
              style: TextStyle(color: context.palette.primaryText, height: 1.4),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _walkIndex == 0
                      ? null
                      : () => setState(() => _walkIndex--),
                  child: const Text('Back'),
                ),
                if (_walkIndex < steps.length - 1)
                  FilledButton(
                    onPressed: () => setState(() => _walkIndex++),
                    child: const Text('Next tell'),
                  )
                else
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _kMagenta),
                    onPressed: () => setState(() => _walk = null),
                    icon: const Icon(Icons.check),
                    label: const Text('Got it'),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    switch (_phase) {
      case _Phase.idle:
        return _panelShell(
          // Stacked like the Messages bay: full-width action at senior
          // type sizes (a side-by-side Row overflows).
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Drone Bay',
                style: TextStyle(
                  color: context.palette.primaryText,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Six specialists, email edition — domains, Reply-To '
                'tricks, attachments, links, pressure.',
                style: TextStyle(
                  color: context.palette.tertiaryText,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _kMagenta),
                  onPressed: _release,
                  icon: const Icon(Icons.radar),
                  label: const Text('Release the Fleet'),
                ),
              ),
            ],
          ),
        );
      case _Phase.scanning:
        return _panelShell(
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 12),
              Text(
                _scanningIdx >= 0
                    ? '${DroneId.values[_scanningIdx].label} scanning…'
                    : 'Fleet airborne…',
                style: TextStyle(color: context.palette.primaryText),
              ),
            ],
          ),
        );
      case _Phase.revealed:
        final verdict = _analysis.verdict;
        final color = switch (verdict) {
          Verdict.dangerous => const Color(0xFFEF4444),
          Verdict.caution => const Color(0xFFF59E0B),
          Verdict.safe => const Color(0xFF22C55E),
        };
        return _panelShell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  TweenAnimationBuilder<int>(
                    tween: IntTween(begin: 0, end: _analysis.riskScore),
                    duration: const Duration(milliseconds: 900),
                    builder: (context, value, child) => Text(
                      '$value',
                      style: TextStyle(
                        color: color,
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '/100 risk',
                    style: TextStyle(color: context.palette.tertiaryText),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          verdict.label,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          'Tap a drone and choose "Teach me" — that is where '
                          'the learning happens.',
                          style: TextStyle(
                            color: context.palette.tertiaryText,
                            fontSize: 14.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (verdict != Verdict.safe)
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _kMagenta,
                        ),
                        onPressed: () {
                          BlocklistStore.blockFromAnalysis(_analysis);
                          setState(() => _phase = _Phase.protected);
                        },
                        icon: const Icon(Icons.shield),
                        label: const Text('Block & Report'),
                      ),
                    )
                  else
                    Expanded(
                      child: Text(
                        'This one holds up — official domain, '
                        'official link, no pressure.',
                        style: TextStyle(color: context.palette.secondaryText),
                      ),
                    ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _phase = _Phase.idle;
                      _revealed = 0;
                    }),
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ],
          ),
        );
      case _Phase.protected:
        final report = buildReport(
          _analysis,
          accountName: AccountStore.displayName,
        );
        return _panelShell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.verified_user, color: Color(0xFF22C55E)),
                  SizedBox(width: 8),
                  Text(
                    'PROTECTED',
                    style: TextStyle(
                      color: Color(0xFF22C55E),
                      fontWeight: FontWeight.w900,
                      fontSize: 17.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Sender blocked. Report ${report.incidentId} filed — find '
                'it any time in the Blocked tab.',
                style: TextStyle(
                  color: context.palette.secondaryText,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _kMagenta),
                  onPressed: () {
                    final now = DateTime.now();
                    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
                    final label =
                        '$hour:${now.minute.toString().padLeft(2, '0')} '
                        '${now.hour >= 12 ? 'PM' : 'AM'}';
                    FamilyStore.shareScan(_analysis, label);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Scan shared with ${FamilyStore.contact.name} — '
                          'see it in the Family tab.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.family_restroom),
                  label: Text(
                    'Share this scan with ${FamilyStore.contact.name}',
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to inbox'),
                ),
              ),
            ],
          ),
        );
    }
  }
}
