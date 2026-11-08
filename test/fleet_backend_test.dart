import 'package:flutter_test/flutter_test.dart';
import 'package:signal_swarm/data/demo_inbox.dart';
import 'package:signal_swarm/models/message.dart';
import 'package:signal_swarm/services/fleet_backend.dart';
import 'package:signal_swarm/services/scam_analyzer.dart';

void main() {
  const analyzer = ScamAnalyzer();
  final smish = analyzer.analyze(
    demoInbox.firstWhere((m) => m.id == 'smish-tmobile'),
  );

  test('report payload matches the backend document contract', () {
    final p = reportPayload(smish, accountName: 'Ryan');
    expect(p['incidentId'], startsWith('INC-2026-'));
    expect(p['sender'], '+1 872-555-0147');
    expect(p['riskScore'], 100);
    expect(p['verdict'], smish.verdict.label);
    expect(p['account'], 'Ryan');
    final flags = p['topFlags'] as List;
    expect(flags, isNotEmpty);
    expect(flags.any((f) => '$f'.contains('Angler')), isTrue);
  });

  test('unconfigured without a dart-define URL (tests run local-only)', () {
    expect(fleetBackendConfigured, isFalse);
  });
}
