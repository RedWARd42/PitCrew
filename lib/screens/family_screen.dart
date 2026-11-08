import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../models/family_and_blocked.dart';
import '../services/device_services.dart';
import '../services/stores.dart';

const Color _kMagenta = Color(0xFFE20074);

/// The Family thread — talk to your trusted person from inside Swat.
///
/// The point is the moment *during* a scam: the user is being pressured
/// and alone. Here they can, without leaving the app or hunting through
/// contacts:
///  * share the fleet's scan card straight into the thread ("look at what
///    the drones found before I do anything"),
///  * hit one-tap quick actions — "I'm being pressured", "Ask for the
///    safe word" — designed for shaky hands, not typing,
///  * escalate to a real call or a real SMS to the trusted contact
///    (dialer / composer hand-off on Android).
///
/// Safe word, stated plainly on the contact card: any "family emergency"
/// that can't produce it isn't family.
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  StreamSubscription<void>? _sub;
  bool _awaitingReply = false;

  TrustedContact get contact => FamilyStore.contact;

  @override
  void initState() {
    super.initState();
    _sub = FamilyStore.changes.listen((_) {
      if (!mounted) return;
      setState(() {});
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _nowLabel() {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${now.minute.toString().padLeft(2, '0')} $ampm';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scheduleReply({bool wasScanShare = false, bool wasSos = false}) {
    if (_awaitingReply) return;
    _awaitingReply = true;
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      _awaitingReply = false;
      if (!mounted) return;
      FamilyStore.receive(
        FamilyStore.cannedReply(wasScanShare: wasScanShare, wasSos: wasSos),
        _nowLabel(),
      );
    });
  }

  void _sendTyped() {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    FamilyStore.send(text, _nowLabel());
    _scheduleReply();
  }

  void _quickSos() {
    FamilyStore.send(
      '🚨 I\'m being pressured by someone right now and I don\'t trust it. '
      'Please help me check before I do anything.',
      _nowLabel(),
    );
    _scheduleReply(wasSos: true);
  }

  void _quickSafeWord() {
    FamilyStore.send(
      'Quick check — what\'s our family safe word? Asking because someone '
      'is claiming there\'s a family emergency.',
      _nowLabel(),
    );
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      FamilyStore.receive(
        'It\'s ${contact.safeWord}. And love — if the person pressuring '
        'you can\'t say it instantly, it is NOT family, whatever they '
        'claim. Hang up and call me on my saved number.',
        _nowLabel(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = FamilyStore.messages;
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        backgroundColor: context.palette.panel,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: _kMagenta,
              child: Text(
                contact.name.substring(0, 1),
                style: TextStyle(
                  color: context.palette.primaryText,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: const TextStyle(
                    fontSize: 17.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  contact.relation,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: context.palette.tertiaryText,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Call ${contact.name} (real call)',
            icon: const Icon(Icons.call, color: Color(0xFF34D399)),
            onPressed: () async {
              final ok = await CommsService.openDialer(contact.phone);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Calling hand-off is Android-only in this build — '
                      'on the demo device this dials Alex directly.',
                    ),
                  ),
                );
              }
            },
          ),
          IconButton(
            tooltip: 'Text ${contact.name} in your SMS app',
            icon: Icon(
              Icons.sms_outlined,
              color: context.palette.secondaryText,
            ),
            onPressed: () => CommsService.openSmsComposer(
              contact.phone,
              'Hi ${contact.name}, checking in from Swat — ',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.palette.sheet,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kMagenta.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.key, color: _kMagenta, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Family safe word: ${contact.safeWord}\n'
                    'Anyone claiming a family emergency who can\'t say it '
                    'isn\'t family. Set in person — never sent by text '
                    'first.',
                    style: TextStyle(
                      color: context.palette.secondaryText,
                      fontSize: 14.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              itemCount: messages.length,
              itemBuilder: (context, i) => _bubble(messages[i]),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.emergency_share, size: 16),
                    label: const Text('I\'m being pressured'),
                    onPressed: _quickSos,
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.key, size: 16),
                    label: const Text('Ask for the safe word'),
                    onPressed: _quickSafeWord,
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.radar, size: 16),
                    label: const Text('How scan-sharing works'),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'After the fleet scans a message, tap '
                            '"Share with Alex" on the verdict — the full '
                            'report card lands in this thread.',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _composer,
                    style: TextStyle(color: context.palette.primaryText),
                    decoration: InputDecoration(
                      hintText: 'Message ${contact.name}…',
                      hintStyle: TextStyle(color: context.palette.tertiaryText),
                      filled: true,
                      fillColor: context.palette.bubble,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _sendTyped(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: _kMagenta),
                  onPressed: _sendTyped,
                  icon: const Icon(Icons.send, size: 19),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(FamilyChatMessage msg) {
    final align = msg.fromMe ? Alignment.centerRight : Alignment.centerLeft;
    final color = msg.fromMe ? _kMagenta : context.palette.bubble;
    // Text sitting on the magenta (mine) bubbles stays white in both
    // modes; on the neutral (theirs) bubbles it follows the palette.
    final onColor = msg.fromMe ? Colors.white : context.palette.primaryText;
    final onColorSoft = msg.fromMe
        ? Colors.white70
        : context.palette.secondaryText;
    final onColorFaint = msg.fromMe
        ? Colors.white60
        : context.palette.tertiaryText;
    return Align(
      alignment: align,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: msg.isScanCard
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.radar, size: 15, color: onColor),
                      SizedBox(width: 6),
                      Text(
                        'Shared fleet scan',
                        style: TextStyle(
                          color: onColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    msg.scanTitle,
                    style: TextStyle(
                      color: onColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    msg.scanDetail,
                    style: TextStyle(
                      color: onColorSoft,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    msg.timeLabel,
                    style: TextStyle(color: onColorFaint, fontSize: 12.5),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    msg.text,
                    style: TextStyle(color: onColor, height: 1.35),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    msg.timeLabel,
                    style: TextStyle(color: onColorFaint, fontSize: 12.5),
                  ),
                ],
              ),
      ),
    );
  }
}
