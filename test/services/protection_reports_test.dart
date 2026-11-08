import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signal_swarm/contracts.dart';
import 'package:signal_swarm/services/protection_reports.dart';

ScanResult scan(
  String id, {
  String summary = 'A suspicious request for payment.',
}) => ScanResult(
  requestId: id,
  verdict: 'scam',
  riskScore: 92,
  confidence: .95,
  summary: summary,
  findings: [
    Finding(
      drone: 'link',
      severity: 'high',
      confidence: .95,
      title: 'Lookalike domain',
      explanation: 'Do not share code 482913 or email jane@example.com.',
      anchor: const Anchor('m1', 'body'),
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReportHandoff.pending.value = null;
  });

  test(
    'saved records contain redacted findings without conversation metadata',
    () async {
      const request = ScanRequest(
        requestId: 'r1',
        mode: 'incoming',
        sender: Sender(raw: '+15550182', kind: 'long_code'),
        messages: [MessageIn(id: 'm1', direction: 'in', text: 'ORIGINAL BODY')],
        targetMessageId: 'm1',
        channel: 'email',
        email: EmailInfo(
          subject: 'PRIVATE SUBJECT',
          fromAddress: 'sender@example.com',
        ),
      );
      final report = ProtectionReport.fromScan(
        scan('r1'),
        request,
        focusDrone: 'link',
      );
      await ProtectionReportStore.save(report);
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs
          .getStringList(ProtectionReportStore.storageKey)!
          .single;
      expect(saved, isNot(contains('ORIGINAL BODY')));
      expect(saved, isNot(contains('PRIVATE SUBJECT')));
      expect(saved, isNot(contains('+15550182')));
      expect(saved, isNot(contains('jane@example.com')));
      expect(saved, isNot(contains('482913')));
      final restored = (await ProtectionReportStore.load()).single;
      expect(restored.source, 'Gmail');
      expect(restored.focusDrone, 'link');
      expect(restored.riskScore, 92);
      expect(restored.findings.single.explanation, contains('<EMAIL>'));
      expect(ReportHandoff.validId(restored.id), isTrue);
    },
  );

  test(
    'history deduplicates, caps retention, and deletes saved reports',
    () async {
      for (var i = 0; i < 22; i++) {
        await ProtectionReportStore.save(
          ProtectionReport.fromScan(scan('r$i'), null),
        );
      }
      var reports = await ProtectionReportStore.load();
      expect(reports, hasLength(20));
      final latest = reports.first;
      await ProtectionReportStore.save(latest);
      expect(await ProtectionReportStore.load(), hasLength(20));
      await ProtectionReportStore.delete(latest.id);
      reports = await ProtectionReportStore.load();
      expect(reports, hasLength(19));
      expect(reports.any((report) => report.id == latest.id), isFalse);
    },
  );

  test('one malformed record does not hide healthy records', () async {
    final good = ProtectionReport.fromScan(scan('r1'), null);
    SharedPreferences.setMockInitialValues({
      ProtectionReportStore.storageKey: ['bad json', jsonEncode(good.toJson())],
    });
    expect((await ProtectionReportStore.load()).single.id, good.id);
  });

  test('handoff saves before launching and sends only an opaque ID', () async {
    final report = ProtectionReport.fromScan(scan('r1'), null);
    messenger.setMockMethodCallHandler(ReportHandoff.channel, (call) async {
      expect(call.method, 'openReport');
      expect(call.arguments, {'reportId': report.id});
      expect((await ProtectionReportStore.load()).single.id, report.id);
      return true;
    });
    expect(await ReportHandoff.openInApp(report), isTrue);
  });

  test('failed launch keeps the saved report available in history', () async {
    messenger.setMockMethodCallHandler(
      ReportHandoff.channel,
      (_) async => throw PlatformException(code: 'not_available'),
    );
    final report = ProtectionReport.fromScan(scan('r1'), null);
    expect(await ReportHandoff.openInApp(report), isFalse);
    expect((await ProtectionReportStore.load()).single.id, report.id);
  });

  test(
    'cold-start intent is consumed and untrusted IDs are rejected',
    () async {
      final report = ProtectionReport.fromScan(scan('r1'), null);
      messenger.setMockMethodCallHandler(
        ReportHandoff.channel,
        (_) async => report.id,
      );
      await ReportHandoff.start();
      expect(ReportHandoff.pending.value, report.id);
      expect(ReportHandoff.validId('https://example.com/private'), isFalse);
    },
  );
}
