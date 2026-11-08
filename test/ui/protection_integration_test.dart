import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signal_swarm/main.dart';
import 'package:signal_swarm/services/stores.dart';
import 'package:signal_swarm/ui/prefs.dart';
import 'package:signal_swarm/ui/protected_screen.dart';
import 'package:signal_swarm/widgets/drone_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var access = false;
  var openedSettings = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    access = false;
    openedSettings = false;
    messenger.setMockMethodCallHandler(const MethodChannel('swarm/native'), (
      call,
    ) async {
      if (call.method == 'isAccessibilityEnabled') return access;
      if (call.method == 'openAccessibilitySettings') openedSettings = true;
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('swat/account'),
      (_) async => {'name': 'Test User', 'email': 'test@example.com'},
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('swat/sms'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('swat/overlay'),
      (call) async => call.method == 'getNativeBlocks' ? <dynamic>[] : access,
    );
  });

  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
  }

  testWidgets(
    'Swat opens accessibility protection from its existing overlay control',
    (t) async {
      phone(t);
      await t.pumpWidget(const SwatApp());
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.byTooltip('Protect Google Messages and Gmail'));
      await t.pumpAndSettle();
      expect(find.text('Protection outside Swat'), findsOneWidget);
      expect(find.byType(DroneArtwork), findsNWidgets(6));
      expect(find.text('Accessibility access is off'), findsOneWidget);
      await t.tap(find.text('Enable protection'));
      await t.pump();
      expect(openedSettings, isTrue);
    },
  );

  testWidgets('protection reports actual access and saves backend settings', (
    t,
  ) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    access = true;
    await t.pumpWidget(const MaterialApp(home: ProtectedScreen()));
    await t.pumpAndSettle();
    expect(find.text('The fleet is on patrol'), findsOneWidget);
    expect(find.text('Accessibility access is on'), findsOneWidget);
    await t.tap(find.text('Scan connection'));
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextField, 'Backend URL'),
      'https://scan.example.com',
    );
    await t.enterText(
      find.widgetWithText(TextField, 'API key'),
      'synthetic-key',
    );
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(Prefs.backendUrl), 'https://scan.example.com');
    expect(prefs.getString(Prefs.apiKey), 'synthetic-key');
  });

  testWidgets(
    'guardian alert action uses the Family contact only after opt-in',
    (t) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: ProtectedScreen()));
      await t.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(Prefs.guardianPhone), isNull);
      await t.tap(find.byType(SwitchListTile));
      await t.pumpAndSettle();
      expect(prefs.getString(Prefs.guardianPhone), FamilyStore.contact.phone);
      expect(prefs.getString(Prefs.guardianName), FamilyStore.contact.name);
      await t.tap(find.byType(SwitchListTile));
      await t.pumpAndSettle();
      expect(prefs.getString(Prefs.guardianPhone), isNull);
    },
  );
}
