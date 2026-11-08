// Smoke test for the Swat app shell: the Messages screen loads, falls back
// to the synthetic demo inbox when no SMS platform channel answers, and
// offers the Release the Fleet action.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:signal_swarm/data/demo_inbox.dart';
import 'package:signal_swarm/main.dart';
import 'package:signal_swarm/models/message.dart';
import 'package:signal_swarm/screens/drone_chat_screen.dart';
import 'package:signal_swarm/services/scam_analyzer.dart';
import 'package:signal_swarm/services/theme_store.dart';

/// A phone-tall surface (1080x2400 at the emulator's density), so the
/// whole conversation list is built — the default 800x600 test surface
/// only fits about three rows.
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // No native side in a widget test: answer the SMS channel with null so
    // SmsService takes its documented demo-inbox fallback right away, and
    // answer the account channel with a stored account so the gate opens
    // straight into the shell (no stored account would mean the login
    // screen — an unmocked channel reads as "no account" here).
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('swat/sms'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('swat/account'),
      (call) async => {'name': 'Test User', 'email': 'test@example.com'},
    );
  });

  testWidgets('Messages opens on the conversation list', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(const SwatApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Messages'), findsWidgets);
    // Shell tabs for the blocked list and the trusted contact.
    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
    // One row per contact: the smish number, the real short code, Mom.
    expect(find.text('+1 872-555-0147'), findsOneWidget);
    expect(find.text('456'), findsOneWidget);
    expect(find.text('Mom'), findsOneWidget);
    // The fleet waits inside a thread — no Drone Bay on the list itself.
    expect(find.text('Release the Fleet'), findsNothing);
  });

  testWidgets('Conversations can be sorted by phone number', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(const SwatApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Sort messages'), findsOneWidget);
    expect(find.text('Newest first'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Newest first'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('By phone number'), findsWidgets);
    final phoneTile = find.ancestor(
      of: find.text('By phone number').last,
      matching: find.byType(ListTile),
    );
    tester.widget<ListTile>(phoneTile).onTap!();
    await tester.pump(const Duration(milliseconds: 300));

    // Phone order: the 456 short code first, then full numbers in
    // ascending order, and named contacts (Mom) after the numbers.
    expect(
      find.widgetWithText(OutlinedButton, 'By phone number'),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('456')).dy,
      lessThan(tester.getTopLeft(find.text('+1 214-555-0176')).dy),
    );
    // Mom sorts last (named contacts after numbers) — scroll her row in
    // and check she sits below the last number (the smish sender).
    await tester.scrollUntilVisible(find.text('Mom'), 150);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.getTopLeft(find.text('+1 872-555-0147')).dy,
      lessThan(tester.getTopLeft(find.text('Mom')).dy),
    );
  });

  testWidgets('Tapping a conversation opens its thread with the Drone Bay', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(const SwatApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final row = find.ancestor(
      of: find.text('+1 872-555-0147'),
      matching: find.byType(InkWell),
    );
    tester.widget<InkWell>(row).onTap!();
    await tester.pump(const Duration(milliseconds: 300));

    // Inside the thread: back button, the fleet, and only this contact.
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.text('Release the Fleet'), findsOneWidget);
    expect(find.textContaining('URGENT'), findsWidgets);
    expect(find.text('Mom'), findsNothing);
  });

  testWidgets('Light/dark toggle flips the app theme', (
    WidgetTester tester,
  ) async {
    usePhoneSurface(tester);
    addTearDown(() => ThemeStore.mode.value = ThemeMode.dark);
    await tester.pumpWidget(const SwatApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Dark by default: the app bar offers the sun (switch to light).
    expect(ThemeStore.mode.value, ThemeMode.dark);
    expect(find.byIcon(Icons.light_mode), findsOneWidget);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);

    await tester.tap(find.byIcon(Icons.light_mode));
    // The theme cross-fades (AnimatedTheme) — give it several frames.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Light now: the same screens render, and the button offers the moon.
    expect(ThemeStore.mode.value, ThemeMode.light);
    expect(find.byIcon(Icons.dark_mode), findsOneWidget);
    expect(find.text('+1 872-555-0147'), findsOneWidget);
    final scaffolds = tester.widgetList<Scaffold>(find.byType(Scaffold));
    expect(
      scaffolds.any((s) => s.backgroundColor == const Color(0xFFF7F4FA)),
      isTrue,
      reason: 'a screen scaffold should use the light background',
    );
  });

  testWidgets('Drone chat greets, then answers from the scan', (
    WidgetTester tester,
  ) async {
    const analyzer = ScamAnalyzer();
    final smish = analyzer.analyze(
      demoInbox.firstWhere((m) => m.id == 'smish-tmobile'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DroneChatScreen(drone: DroneId.link, analysis: smish),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // The drone introduces itself with the verdict up front, and offers
    // tappable starter questions plus a dictation mic.
    expect(find.textContaining("I'm Link"), findsOneWidget);
    expect(find.text('Why did you flag this?'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Why did you flag this?');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump(const Duration(milliseconds: 300));

    // The answer quotes the drone's actual evidence from the message.
    expect(find.textContaining('t-mobile-verify-secure.com'), findsWidgets);
  });
}
