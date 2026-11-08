// Smoke test for the Swat app shell: the Messages screen loads, falls back
// to the synthetic demo inbox when no SMS platform channel answers, and
// offers the Release the Fleet action.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:signal_swarm/main.dart';

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

  testWidgets('Messages screen loads with the drone bay', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SwatApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Messages'), findsWidgets);
    expect(find.text('Release the Fleet'), findsOneWidget);
    // Shell tabs for the blocked list and the trusted contact.
    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
    // The headline synthetic smishing scenario is in the demo inbox.
    expect(find.textContaining('872-555-0147'), findsWidgets);
  });
}
