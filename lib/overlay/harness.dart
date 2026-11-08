// Dev harness: `flutter run -d chrome -t lib/overlay/harness.dart` (or an emulator).
import 'package:flutter/material.dart';
import '../contracts.dart' as c;
import 'fake_state.dart';
import 'swarm_overlay.dart';

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Harness()));

class Harness extends StatefulWidget {
  const Harness({super.key});
  @override
  State<Harness> createState() => _HarnessState();
}

class _HarnessState extends State<Harness> {
  final s = FakeSwarmState();
  bool dark = false, scrolled = false;

  @override
  void dispose() {
    s.dispose();
    super.dispose();
  }

  Widget _btn(String label, VoidCallback f) => Padding(padding: const EdgeInsets.all(3), child: FilledButton.tonal(onPressed: f, child: Text(label)));

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF2B2B2F),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Center(
              child: FittedBox(
                child: SizedBox(
                  width: FakeSwarmState.frameW,
                  height: FakeSwarmState.frameH,
                  child: MediaQuery(
                    data: mq.copyWith(platformBrightness: dark ? Brightness.dark : Brightness.light, size: const Size(FakeSwarmState.frameW, FakeSwarmState.frameH)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Stack(children: [
                        ListenableBuilder(listenable: s, builder: (_, _) => _MockMessages(s: s, dark: dark)),
                        SwarmOverlay(state: s),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Wrap(alignment: WrapAlignment.center, children: [
            _btn('Hero (play)', () => s.play('hero')),
            _btn('Hero (instant)', () => s.load('hero')),
            _btn('Email phish', s.loadEmail),
            _btn('Unsure', () => s.load('unsure')),
            _btn('Safe bank', () => s.load('safe')),
            _btn('On-device safe', s.localSafe),
            _btn('Warden', () => s.load('warden')),
            _btn('Drift', () => s.load('drift')),
            _btn('Scroll', () {
              scrolled = !scrolled;
              s.scrollTo(scrolled ? 260 : 0);
            }),
            _btn(dark ? 'Light' : 'Dark', () => setState(() => dark = !dark)),
            _btn('Clear', s.clear),
          ]),
        ]),
      ),
    );
  }
}

/// Messages-like background drawn from the same ScreenModel the overlay consumes.
class _MockMessages extends StatelessWidget {
  final FakeSwarmState s;
  final bool dark;
  const _MockMessages({required this.s, required this.dark});

  @override
  Widget build(BuildContext context) {
    final scr = s.screen!;
    if (scr.channel == 'email') return _MockGmail(scr: scr, d: s.density, dark: dark);
    final d = s.density;
    final bg = dark ? const Color(0xFF121316) : const Color(0xFFFAFAFB);
    final bubble = dark ? const Color(0xFF2A2C31) : const Color(0xFFE9EAEE);
    final fg = dark ? Colors.white : const Color(0xFF1B1B1F);
    Widget at(c, Widget child) => Positioned(left: c.x / d, top: c.y / d, width: c.w / d, height: c.h / d, child: child);
    return Container(color: bg, child: Stack(children: [
      for (final b in scr.bubbles)
        at(b.rect, Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: bubble, borderRadius: BorderRadius.circular(20)),
          child: DefaultTextStyle(style: TextStyle(fontSize: 15, height: 1.35, color: fg, decoration: TextDecoration.none), child: Text(b.text)),
        )),
      at(scr.header!, Container(color: bg, alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 60), child: Text(scr.senderRaw ?? '', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: fg, decoration: TextDecoration.none)))),
      if (scr.compose != null) at(scr.compose!, Container(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 18), decoration: BoxDecoration(color: bubble, borderRadius: BorderRadius.circular(24)), child: Text(scr.draftText ?? 'Text message', style: TextStyle(fontSize: 15, color: fg.withValues(alpha: scr.draftText == null ? 0.5 : 1), decoration: TextDecoration.none)))),
      if (scr.send != null) at(scr.send!, Container(decoration: const BoxDecoration(color: Color(0xFF1A73E8), shape: BoxShape.circle), child: const Icon(Icons.send_rounded, color: Colors.white, size: 20))),
    ]));
  }
}

/// Gmail-like open email: top bar, subject, sender row, long body, attachment card.
class _MockGmail extends StatelessWidget {
  final c.ScreenModel scr;
  final double d;
  final bool dark;
  const _MockGmail({required this.scr, required this.d, required this.dark});

  @override
  Widget build(BuildContext context) {
    final bg = dark ? const Color(0xFF121316) : Colors.white;
    final fg = dark ? Colors.white : const Color(0xFF1B1B1F);
    final dim = fg.withValues(alpha: 0.6);
    TextStyle t(double s, [Color? c, FontWeight w = FontWeight.w400]) => TextStyle(fontSize: s, color: c ?? fg, fontWeight: w, height: 1.4, decoration: TextDecoration.none);
    Widget at(c.Rect r, Widget child) => Positioned(left: r.x / d, top: r.y / d, width: r.w / d, height: r.h / d, child: child);
    final em = scr.email!, body = scr.bubbles.first, h = scr.header!;
    final dy = (h.y / d) - 128; // scroll offset in dp (negative when scrolled)
    return Container(color: bg, child: Stack(children: [
      Positioned(left: 16, top: 84 + dy, right: 16, child: Text(em.subject, style: t(20, null, FontWeight.w500))),
      at(h, Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
        const CircleAvatar(radius: 20, backgroundColor: Color(0xFF8E24AA), child: Text('P', style: TextStyle(color: Colors.white, decoration: TextDecoration.none))),
        const SizedBox(width: 12),
        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(em.fromName, style: t(15, null, FontWeight.w600)),
          Text('to me', style: t(13, dim)),
        ])),
      ]))),
      at(body.rect, Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(body.text, style: t(15)))),
      for (final l in em.links) if (l.rect != null) at(l.rect!, Container(alignment: Alignment.centerLeft, color: bg, child: Text(l.text, style: t(15, const Color(0xFF1A73E8))))),
      for (final a in em.attachments) if (a.rect != null) at(a.rect!, Container(
        margin: const EdgeInsets.only(left: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(border: Border.all(color: dim.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [const Icon(Icons.insert_drive_file_outlined, size: 20, color: Color(0xFFE8710A)), const SizedBox(width: 8), Expanded(child: Text(a.name, style: t(13), overflow: TextOverflow.ellipsis))]),
      )),
    ]));
  }
}
