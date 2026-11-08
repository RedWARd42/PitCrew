import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signal_swarm/ui/app.dart';
import 'package:signal_swarm/ui/prefs.dart';

void main() {
  testWidgets('onboarding walks 5 steps, stores guardian, lands on Protected', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(const SwarmApp());
    await t.pumpAndSettle();
    expect(find.textContaining('watches for scams'), findsOneWidget);
    for (var i = 0; i < 2; i++) {
      await t.tap(find.text('Next'));
      await t.pumpAndSettle();
    }
    expect(find.textContaining('<CODE:6>'), findsOneWidget); // sample receipt
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(
      find.text('Open Accessibility settings'),
      findsOneWidget,
    ); // channel missing: must not throw
    await t.tap(find.text('Open Accessibility settings'));
    await t.pumpAndSettle();
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Guardian name'), 'Ana');
    await t.enterText(
      find.widgetWithText(TextField, 'Guardian phone'),
      '5550101',
    );
    await t.tap(find.text('Finish'));
    await t.pumpAndSettle();
    expect(find.textContaining('protected'), findsOneWidget);
    final p = await SharedPreferences.getInstance();
    expect(p.getString(Prefs.guardianName), 'Ana');
    expect(p.getString(Prefs.guardianPhone), '5550101');
  });

  testWidgets('Protected screen shows debug defaults and saves them', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({Prefs.onboarded: true});
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const SwarmApp());
    await t.pumpAndSettle();
    await t.tap(find.text('Developer'));
    await t.pumpAndSettle();
    String txt(String l) => t.widget<TextField>(find.widgetWithText(TextField, l)).controller!.text;
    expect(txt('Backend URL'), Prefs.defaultUrl);
    expect(txt('API key'), Prefs.defaultKey);
    await t.enterText(find.widgetWithText(TextField, 'API key'), 'k2');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getString(Prefs.apiKey),
      'k2',
    );
  });
}
