import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signal_swarm/contracts.dart';
import 'package:signal_swarm/main.dart';
import 'package:signal_swarm/models/account.dart';
import 'package:signal_swarm/services/account_store.dart';
import 'package:signal_swarm/screens/reports_screen.dart';
import 'package:signal_swarm/services/protection_reports.dart';
import 'package:signal_swarm/services/stores.dart';

ProtectionReport makeReport(String id) => ProtectionReport.fromScan(
  ScanResult(
    requestId: id,
    verdict: 'scam',
    riskScore: 93,
    confidence: .97,
    summary: 'A fake account warning asks you to act urgently.',
    findings: [
      Finding(
        drone: 'pressure',
        severity: 'high',
        confidence: .97,
        title: 'An artificial deadline',
        explanation: 'A short deadline is being used to rush you.',
        anchor: const Anchor('m1', 'body'),
      ),
    ],
  ),
  null,
  focusDrone: 'pressure',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReportHandoff.pending.value = null;
    messenger.setMockMethodCallHandler(
      const MethodChannel('swat/account'),
      (_) async => {'name': 'Demo User', 'email': 'demo@example.com'},
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('swat/sms'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('swat/overlay'),
      (call) async => call.method == 'getNativeBlocks' ? [] : false,
    );
    messenger.setMockMethodCallHandler(
      ReportHandoff.channel,
      (_) async => null,
    );
  });
  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
  }

  testWidgets('pending report survives the account gate until sign-in', (
    t,
  ) async {
    phone(t);
    await AccountStore.signOut();
    messenger.setMockMethodCallHandler(
      const MethodChannel('swat/account'),
      (_) async => null,
    );
    final report = makeReport('login');
    await ProtectionReportStore.save(report);
    ReportHandoff.pending.value = report.id;
    await t.pumpWidget(const SwatApp());
    await t.pumpAndSettle();
    expect(find.text('Welcome to Swat'), findsOneWidget);
    expect(ReportHandoff.pending.value, report.id);
    await AccountStore.signIn(
      const UserAccount(name: 'Synthetic User', email: 'synthetic@example.com'),
    );
    await t.pumpAndSettle();
    expect(
      t
          .widget<ProtectionReportScreen>(find.byType(ProtectionReportScreen))
          .report
          .id,
      report.id,
    );
  });

  testWidgets('pending report opens exact findings and back leads to Reports', (
    t,
  ) async {
    phone(t);
    final report = makeReport('cold');
    await ProtectionReportStore.save(report);
    ReportHandoff.pending.value = report.id;
    await t.pumpWidget(const SwatApp());
    await t.pumpAndSettle();
    expect(find.byType(ProtectionReportScreen), findsOneWidget);
    expect(find.text('An artificial deadline'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Protection reports'), findsOneWidget);
    expect(find.text('Likely scam · 93/100'), findsOneWidget);
  });

  testWidgets(
    'running app handles another report and a missing report gracefully',
    (t) async {
      phone(t);
      await t.pumpWidget(const SwatApp());
      await t.pumpAndSettle();
      final report = makeReport('warm');
      await ProtectionReportStore.save(report);
      ReportHandoff.pending.value = report.id;
      await t.pumpAndSettle();
      expect(
        t
            .widget<ProtectionReportScreen>(find.byType(ProtectionReportScreen))
            .report
            .id,
        report.id,
      );
      ReportHandoff.pending.value = makeReport('deleted').id;
      await t.pumpAndSettle();
      expect(find.byType(ProtectionReportScreen), findsNothing);
      expect(
        find.text(
          'This report is no longer saved. Your other reports are below.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Family action shares a redacted scan card into the existing tab',
    (t) async {
      phone(t);
      final report = makeReport('family');
      await ProtectionReportStore.save(report);
      ReportHandoff.pending.value = report.id;
      await t.pumpWidget(const SwatApp());
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Add to Family chat'));
      await t.tap(find.text('Add to Family chat'));
      await t.pumpAndSettle();
      expect(FamilyStore.messages.last.scanDetail, contains(report.summary));
      expect(
        t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );
      expect(find.byType(ProtectionReportScreen), findsNothing);
    },
  );
}
