import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_swarm/contracts.dart' as c;
import 'package:signal_swarm/overlay/fake_state.dart';
import 'package:signal_swarm/overlay/fixtures.dart';
import 'package:signal_swarm/overlay/painters.dart';
import 'package:signal_swarm/overlay/palette.dart';
import 'package:signal_swarm/overlay/swarm_overlay.dart';

Widget host(WidgetTester t, FakeSwarmState s, {bool reduce = false}) {
  t.view.physicalSize = const Size(390, 820);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  return _host(s, reduce);
}

Widget _host(FakeSwarmState s, bool reduce) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(390, 820), disableAnimations: reduce),
        child: Scaffold(body: SizedBox(width: 390, height: 820, child: SwarmOverlay(state: s))),
      ),
    );

Future<void> run(WidgetTester t, int ms) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

final droneFinder = find.byWidgetPredicate((w) => w.key is ValueKey && (w.key as ValueKey).value.toString().startsWith('drone:'));

void main() {
  test('embedded fixtures match contracts/fixtures', () {
    kFixtureFiles.forEach((k, f) {
      final disk = jsonDecode(File('contracts/fixtures/$f').readAsStringSync());
      expect(jsonDecode(kFixtures[k]!), disk, reason: f);
    });
  });

  test('anchor resolution and confidence words', () {
    final scr = FakeSwarmState.mockScreen();
    final link = resolveAnchor(const c.Anchor('m1', 'link'), scr, 2.75)!;
    final body = resolveAnchor(const c.Anchor('m1', 'body'), scr, 2.75)!;
    expect(link.top, greaterThan(body.top));
    expect(link.bottom, lessThanOrEqualTo(body.bottom));
    expect(resolveAnchor(const c.Anchor('header', 'sender'), scr, 2.75)!.top, 24);
    expect(resolveAnchor(const c.Anchor('draft', 'compose'), scr, 2.75)!.top, 750);
    expect(resolveAnchor(const c.Anchor('zzz', 'body'), scr, 2.75), isNull);
    expect(confidenceLabel(0.92), 'Likely · 92%');
    expect(confidenceLabel(0.52), 'Not sure · 52%');
  });

  testWidgets('hero: 4 drones land, hit targets reported, panel opens and closes', (t) async {
    final s = FakeSwarmState()..load('hero');
    await t.pumpWidget(host(t, s));
    await run(t, 2500);
    expect(droneFinder, findsNWidgets(4));
    final last = s.reported.last;
    expect(last.keys, containsAll(['hive', 'drone:angler', 'drone:link', 'drone:pressure', 'drone:impersonator']));
    // drones hover in a row just above the bubble, never over its text (px -> dp)
    final body = resolveAnchor(const c.Anchor('m1', 'body'), s.screen!, 2.75)!;
    final lr = last['drone:link']!;
    expect((lr.y + lr.h) / 2.75, closeTo(body.top - 4, 2));
    expect(s.panelOpen, isFalse);
    expect(find.text('Scam · 92%'), findsOneWidget);

    await t.tap(find.bySemanticsLabel(RegExp('Signal Swarm')));
    await run(t, 400);
    expect(s.panelOpen, isTrue);
    expect(find.text('Swat protection report'), findsOneWidget);
    expect(find.text('Account-Suspension Smishing'), findsOneWidget);

    await t.tap(find.text('Link').first);
    await run(t, 100);
    expect(find.text('Lookalike domain'), findsOneWidget);
    expect(find.text('Likely · 95%'), findsOneWidget);

    await t.tap(find.text('Report to 7726'));
    expect(s.performed, ['report_7726']);
    await run(t, 100);
    expect(s.panelOpen, isFalse); // external intent: sheet closes so the target app is not dimmed
    s.setPanelOpen(true);
    await run(t, 400);

    await t.ensureVisible(find.text('Privacy receipt'));
    await run(t, 300);
    await t.tap(find.text('Privacy receipt'));
    await run(t, 100);
    expect(find.text('Retained by server: no'), findsOneWidget);
    expect(find.textContaining('"targetMessageId"'), findsOneWidget);

    await t.tapAt(const Offset(195, 20)); // dim
    await run(t, 400);
    expect(s.panelOpen, isFalse);
    expect(find.text('Swat protection report'), findsNothing);
  });

  testWidgets('native tap on a drone opens its tab', (t) async {
    final s = FakeSwarmState()..load('hero');
    await t.pumpWidget(host(t, s));
    await run(t, 300);
    s.tapController.add('drone:pressure');
    await run(t, 400);
    expect(s.panelOpen, isTrue);
    expect(find.text('Deadline pressure'), findsOneWidget);
  });

  testWidgets('unsure finding shows Not sure and what would change my mind', (t) async {
    final s = FakeSwarmState()..load('unsure');
    await t.pumpWidget(host(t, s));
    await run(t, 1500);
    s.tapController.add('drone:link');
    await run(t, 400);
    expect(find.text('Not sure · 50%'), findsOneWidget);
  });

  testWidgets('safe and local-safe show no drones', (t) async {
    final s = FakeSwarmState()..load('safe');
    await t.pumpWidget(host(t, s));
    await run(t, 1000);
    expect(droneFinder, findsNothing);
    expect(find.text('Safe · 95%'), findsOneWidget);
    s.localSafe();
    await run(t, 500);
    expect(droneFinder, findsNothing);
    expect(find.text('Checked on-device'), findsOneWidget);
  });

  testWidgets('hidden screen renders nothing', (t) async {
    final s = FakeSwarmState()..load('hero');
    await t.pumpWidget(host(t, s));
    await run(t, 500);
    s.setScreen(const c.ScreenModel(visible: false));
    await run(t, 300);
    expect(droneFinder, findsNothing);
    expect(find.bySemanticsLabel(RegExp('Signal Swarm')), findsNothing);
    expect(s.reported.last, isEmpty);
  });

  testWidgets('warden card appears and Dont send performs the action', (t) async {
    final s = FakeSwarmState()..load('warden');
    await t.pumpWidget(host(t, s));
    await run(t, 1500);
    expect(find.text('Hold up'), findsOneWidget);
    expect(droneFinder, findsOneWidget);
    expect(s.reported.last.keys, contains('drone:warden'));
    await t.tap(find.text('Don\'t send'));
    await run(t, 200);
    expect(s.performed, ['dont_send']);
    expect(find.text('Hold up'), findsNothing);
  });

  testWidgets('offscreen anchor docks at the top edge; scroll back re-anchors', (t) async {
    final s = FakeSwarmState()..load('hero');
    await t.pumpWidget(host(t, s));
    await run(t, 2000);
    s.scrollTo(260);
    await run(t, 2000);
    final top = s.reported.last['drone:link']!;
    expect(top.y / 2.75, lessThan(150));
    expect(find.bySemanticsLabel(RegExp('scroll up')), findsWidgets);
    s.scrollTo(0);
    await run(t, 2000);
    expect(s.reported.last['drone:link']!.y / 2.75, greaterThan(130));
  });

  testWidgets('reduced motion snaps drones into place', (t) async {
    final s = FakeSwarmState()..load('hero');
    await t.pumpWidget(host(t, s, reduce: true));
    await run(t, 100);
    expect(droneFinder, findsNWidgets(4));
    expect(s.reported.last.keys, contains('drone:angler'));
  });

  testWidgets('drift shows sparkline label', (t) async {
    final s = FakeSwarmState()..load('drift');
    await t.pumpWidget(host(t, s));
    await run(t, 1500);
    s.tapController.add('drone:drift');
    await run(t, 400);
    expect(find.text('Risk across this conversation'), findsOneWidget);
  });

  testWidgets('hero drone hit rects never overlap each other', (t) async {
    final s = FakeSwarmState()..load('hero');
    await t.pumpWidget(host(t, s));
    await run(t, 2500);
    final r = [for (final e in s.reported.last.entries) if (e.key.startsWith('drone:')) Rect.fromLTWH(e.value.x, e.value.y, e.value.w, e.value.h)];
    expect(r.length, 4);
    for (var i = 0; i < r.length; i++) {
      for (var j = i + 1; j < r.length; j++) {
        expect(r[i].deflate(0.5).overlaps(r[j]), isFalse, reason: '$i vs $j');
      }
    }
  });

  testWidgets('missing bubble hides its drones; header drone sits below header, right side', (t) async {
    final s = FakeSwarmState()..load('hero');
    await t.pumpWidget(host(t, s));
    await run(t, 2000);
    final a = s.reported.last['drone:angler']!;
    expect(a.y / 2.75, greaterThanOrEqualTo(79)); // header bottom is 80dp
    expect((a.x + a.w / 2) / 2.75, greaterThan(195));
    final m = FakeSwarmState.mockScreen();
    s.setScreen(c.ScreenModel(header: m.header, compose: m.compose, send: m.send, bubbles: [m.bubbles.first]));
    await run(t, 300);
    expect(droneFinder, findsOneWidget); // only the header-anchored Angler remains
    expect(s.reported.last.keys, isNot(contains('drone:link')));
  });

  testWidgets('send_guard is reported only with a draft risk; tapping it re-shows the card', (t) async {
    final s = FakeSwarmState()..load('hero');
    await t.pumpWidget(host(t, s));
    await run(t, 1500);
    expect(s.reported.last.keys, isNot(contains('send_guard')));
    s.load('warden');
    await run(t, 1500);
    expect(s.reported.last['send_guard']!.x, s.screen!.send!.x);
    final dr = s.draftRisk;
    await t.tap(find.text('Send anyway'));
    await run(t, 200);
    expect(find.text('Hold up'), findsNothing);
    s.draftRisk = dr; // fake clears it on action; keep the draft pending to model a controller that does not
    s.setPanelOpen(false);
    await run(t, 100);
    expect(find.text('Hold up'), findsNothing); // same draft stays dismissed
    s.tapController.add('send_guard');
    await run(t, 200);
    expect(find.text('Hold up'), findsOneWidget);
  });

  test('embedded email request matches contracts/fixtures', () {
    final disk = jsonDecode(File('contracts/fixtures/scan_request_email_phish.json').readAsStringSync());
    expect(jsonDecode(kEmailRequest), disk);
  });

  test('email anchors: sender->header, link span->link rect, carrier->attachment, fallback->body', () {
    final scr = FakeSwarmState.mockEmailScreen();
    final em = scr.email!;
    ui.Rect dp(c.Rect r) => ui.Rect.fromLTWH(r.x / 2.75, r.y / 2.75, r.w / 2.75, r.h / 2.75);
    expect(resolveAnchor(const c.Anchor('header', 'sender'), scr, 2.75), dp(scr.header!));
    expect(resolveAnchor(const c.Anchor('e1', 'body'), scr, 2.75), dp(scr.bubbles.first.rect));
    expect(resolveAnchor(const c.Anchor('e1', 'link', [0, 0]), scr, 2.75), dp(em.links[0].rect!));
    expect(resolveAnchor(const c.Anchor('e1', 'body'), scr, 2.75, drone: 'carrier'), dp(em.attachments[0].rect!));
    // out-of-range span or missing rects fall back to the body
    expect(resolveAnchor(const c.Anchor('e1', 'link', [5, 5]), scr, 2.75), dp(scr.bubbles.first.rect));
    final bare = c.ScreenModel(channel: 'email', header: scr.header, bubbles: scr.bubbles, email: const c.EmailInfo(links: [c.EmailLink(text: 'a', href: 'b')], attachments: [c.EmailAttachment(name: 'x')]));
    expect(resolveAnchor(const c.Anchor('e1', 'link', [0, 0]), bare, 2.75), dp(scr.bubbles.first.rect));
    expect(resolveAnchor(const c.Anchor('e1', 'body'), bare, 2.75, drone: 'carrier'), dp(scr.bubbles.first.rect));
  });

  testWidgets('email hero: 5 drones in one row between header and body, none overlapping', (t) async {
    final s = FakeSwarmState()..loadEmail();
    await t.pumpWidget(host(t, s));
    await run(t, 2500);
    expect(droneFinder, findsNWidgets(5));
    final m = s.reported.last;
    expect(m.keys, containsAll(['hive', 'drone:angler', 'drone:link', 'drone:pressure', 'drone:impersonator', 'drone:carrier']));
    final r = [for (final e in m.entries) if (e.key.startsWith('drone:')) ui.Rect.fromLTWH(e.value.x, e.value.y, e.value.w, e.value.h)];
    final hdrBottom = s.screen!.header!.y + s.screen!.header!.h, bodyTop = s.screen!.bubbles.first.rect.y;
    for (var i = 0; i < r.length; i++) {
      expect(r[i].top, greaterThanOrEqualTo(hdrBottom - 1)); // never over the sender row
      expect(r[i].bottom, lessThanOrEqualTo(bodyTop)); // never over the body text
      for (var j = i + 1; j < r.length; j++) {
        expect(r[i].deflate(0.5).overlaps(r[j]), isFalse, reason: '$i vs $j');
      }
    }
  });

  testWidgets('email panel: summary context line, link tab shows both texts, carrier tab lists the file', (t) async {
    final s = FakeSwarmState()..loadEmail();
    await t.pumpWidget(host(t, s));
    await run(t, 300);
    s.tapController.add('hive');
    await run(t, 400);
    expect(find.textContaining('PayPal Support <security@paypa1-support.com>'), findsOneWidget);
    expect(find.textContaining('Your account is limited'), findsOneWidget);
    expect(find.textContaining('Reply-to  help@mailbox-relay.biz'), findsOneWidget);
    expect(find.text('Block sender'), findsOneWidget); // labels come from the backend

    s.tapController.add('drone:link');
    await run(t, 400);
    expect(find.text('Shown as'), findsOneWidget);
    expect(find.text('Actually goes to'), findsOneWidget);
    expect(find.text('https://www.paypal.com/verify'), findsOneWidget);
    expect(find.text('https://paypa1-support.com/login?id=88a'), findsOneWidget);

    s.tapController.add('drone:carrier');
    await run(t, 400);
    expect(find.text('invoice_4491.html'), findsOneWidget);
  });

  testWidgets('email with missing rects: drones fall back to the body or hide, never crash', (t) async {
    final s = FakeSwarmState()..loadEmail();
    await t.pumpWidget(host(t, s));
    await run(t, 1500);
    final m = FakeSwarmState.mockEmailScreen();
    s.setScreen(c.ScreenModel(channel: 'email', header: m.header, bubbles: m.bubbles, email: const c.EmailInfo(links: [c.EmailLink(text: 'a', href: 'b')], attachments: [c.EmailAttachment(name: 'x')])));
    await run(t, 1500);
    expect(droneFinder, findsNWidgets(5)); // link/carrier fall back to the body outline
    s.setScreen(c.ScreenModel(channel: 'email', header: m.header, email: m.email));
    await run(t, 500);
    expect(droneFinder, findsOneWidget); // no body bubble: only the header-anchored Angler remains
    expect(s.reported.last.keys, isNot(contains('drone:link')));
  });

  OutlinesPainter outlines(WidgetTester t) => t.widgetList<CustomPaint>(find.byType(CustomPaint)).map((w) => w.painter).whereType<OutlinesPainter>().single;

  testWidgets('email link drone: outline and leader land on the link rect, not the body', (t) async {
    final s = FakeSwarmState()..loadEmail();
    await t.pumpWidget(host(t, s));
    await run(t, 2500);
    final p = outlines(t);
    final lr = s.screen!.email!.links[0].rect!;
    final want = ui.Rect.fromLTWH(lr.x / 2.75, lr.y / 2.75, lr.w / 2.75, lr.h / 2.75);
    expect(p.items.any((o) => o.rect == want && o.color == styleFor('link').color), isTrue);
    final linkLeaders = p.leaders.where((l) => l.color == styleFor('link').color).toList();
    expect(linkLeaders.length, 1);
    final to = linkLeaders.single.to;
    expect(to.dy, closeTo(want.top, 0.01));
    expect(to.dx, inInclusiveRange(want.left, want.right));
  });

  testWidgets('email with a tall expanded header: angler docks below the header, leader ends at its bottom, row left-aligned', (t) async {
    final s = FakeSwarmState()..loadEmail();
    await t.pumpWidget(host(t, s));
    await run(t, 500);
    final m = FakeSwarmState.mockEmailScreen();
    c.Rect r(double x, double y, double w, double h) => c.Rect(x * 2.75, y * 2.75, w * 2.75, h * 2.75);
    // header spans the whole details card (120..260dp); body starts right under it
    s.setScreen(c.ScreenModel(channel: 'email', email: m.email, header: r(0, 120, 390, 140), bubbles: [c.Bubble(messageId: 'e1', direction: 'in', text: 'x', rect: r(0, 268, 390, 300))]));
    await run(t, 2500);
    final hit = s.reported.last;
    final a = hit['drone:angler']!;
    expect(a.y / 2.75, greaterThanOrEqualTo(260 - 0.5));
    for (final k in hit.keys.where((k) => k.startsWith('drone:'))) {
      expect(hit[k]!.x, greaterThanOrEqualTo(a.x - 0.5), reason: 'angler is the leftmost'); // same row, left-aligned
      expect((hit[k]!.y - a.y).abs(), lessThan(1));
    }
    final to = outlines(t).leaders.map((l) => l.to).where((o) => (o.dy - 260).abs() < 0.01);
    expect(to, isNotEmpty); // a leader ends exactly on the header's bottom edge
  });

  testWidgets('email privacy receipt says subject and body are redacted', (t) async {
    final s = FakeSwarmState()..loadEmail();
    await t.pumpWidget(host(t, s));
    await run(t, 300);
    s.tapController.add('hive');
    await run(t, 400);
    await t.ensureVisible(find.text('Privacy receipt'));
    await t.tap(find.text('Privacy receipt'));
    await run(t, 100);
    expect(find.textContaining('Subject and body text are redacted on-device'), findsOneWidget);
  });
}
