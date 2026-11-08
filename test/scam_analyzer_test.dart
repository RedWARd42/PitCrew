// Unit tests for the detection engine. The analyzer is pure Dart, so these
// run anywhere `flutter test` does — and they pin the behavior the demo
// depends on: the fleet must convict the synthetic smish AND acquit the
// genuine short-code message. A detector that flags everything is useless.

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_swarm/data/demo_inbox.dart';
import 'package:signal_swarm/models/message.dart';
import 'package:signal_swarm/services/scam_analyzer.dart';
import 'package:signal_swarm/services/walkthrough.dart';

void main() {
  const analyzer = ScamAnalyzer();

  ChatMessage byId(String id) => demoInbox.firstWhere((m) => m.id == id);

  group('headline smishing scenario', () {
    final analysis = analyzer.analyze(byId('smish-tmobile'));

    test('is judged dangerous', () {
      expect(analysis.verdict, Verdict.dangerous);
      expect(analysis.riskScore, greaterThanOrEqualTo(60));
    });

    test('at least four different drones flag it', () {
      expect(analysis.flaggingDrones.length, greaterThanOrEqualTo(4));
    });

    test('Link names the lookalike domain', () {
      final linkFindings = analysis.findingsFor(DroneId.link);
      expect(linkFindings.any((f) => f.title == 'Lookalike domain'), isTrue);
    });

    test('Swap catches the verification-code fishing', () {
      expect(analysis.pointsFor(DroneId.swap), greaterThan(0));
    });

    test('flagged findings carry highlight spans into the body', () {
      final body = byId('smish-tmobile').body;
      for (final f in analysis.findings.where((f) => f.hasSpan)) {
        expect(f.spanStart, greaterThanOrEqualTo(0));
        expect(f.spanEnd, lessThanOrEqualTo(body.length));
        if (f.evidence.isNotEmpty) {
          expect(
            body.substring(f.spanStart, f.spanEnd),
            contains(f.evidence.substring(0, 4)),
          );
        }
      }
    });
  });

  group('genuine T-Mobile message from short code 456', () {
    final analysis = analyzer.analyze(byId('real-tmobile'));

    test('is judged safe', () {
      expect(analysis.verdict, Verdict.safe);
      expect(analysis.riskScore, lessThan(30));
    });

    test('Angler verifies the sender and Link verifies the domain', () {
      expect(
        analysis
            .findingsFor(DroneId.angler)
            .any((f) => f.title == 'Verified sender'),
        isTrue,
      );
      expect(
        analysis
            .findingsFor(DroneId.link)
            .any((f) => f.title == 'Official domain'),
        isTrue,
      );
    });
  });

  group('other scam shapes', () {
    test('fake Chase alert is dangerous via sender + domain', () {
      final analysis = analyzer.analyze(byId('smish-chase'));
      expect(analysis.riskScore, greaterThanOrEqualTo(50));
      expect(analysis.pointsFor(DroneId.angler), greaterThan(0));
      expect(analysis.pointsFor(DroneId.link), greaterThan(0));
    });

    test('USPS redelivery-fee text is flagged', () {
      final analysis = analyzer.analyze(byId('smish-usps'));
      expect(analysis.verdict, isNot(Verdict.safe));
      expect(analysis.pointsFor(DroneId.link), greaterThan(0));
    });
  });

  group('personal texts', () {
    test('a normal text from Mom is safe', () {
      final analysis = analyzer.analyze(byId('mom'));
      expect(analysis.verdict, Verdict.safe);
      expect(analysis.riskScore, lessThan(15));
    });
  });

  group('walkthrough + report', () {
    test('walkthrough steps cover the flagging drone findings', () {
      final analysis = analyzer.analyze(byId('smish-tmobile'));
      final steps = buildWalkthrough(analysis, DroneId.swap);
      expect(steps, isNotEmpty);
      expect(steps.every((s) => s.drone == DroneId.swap), isTrue);
      expect(steps.first.narration, contains('Swap'));
    });

    test('a clean drone still gets an all-clear step', () {
      final analysis = analyzer.analyze(byId('real-tmobile'));
      final steps = buildWalkthrough(analysis, DroneId.swap);
      expect(steps.length, 1);
      expect(steps.first.headline, contains('all clear'));
    });

    test('report lines summarize score and drone contributions', () {
      final analysis = analyzer.analyze(byId('smish-tmobile'));
      final report = buildReport(analysis);
      expect(report.incidentId, startsWith('INC-2026-'));
      expect(report.lines.join('\n'), contains('Risk score'));
    });
  });
}
