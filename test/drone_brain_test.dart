// Tests for the drone conversation brain: answers must stay grounded in
// the actual scan (findings, points, verdict) and in each drone's own
// specialty — a drone that invents findings it never made would break
// the app's honest-confidence promise.

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_swarm/data/demo_inbox.dart';
import 'package:signal_swarm/models/message.dart';
import 'package:signal_swarm/services/drone_brain.dart';
import 'package:signal_swarm/services/scam_analyzer.dart';

void main() {
  const brain = DroneBrain();
  const analyzer = ScamAnalyzer();

  ChatMessage byId(String id) => demoInbox.firstWhere((m) => m.id == id);
  final smish = analyzer.analyze(byId('smish-tmobile'));
  final genuine = analyzer.analyze(byId('real-tmobile'));

  String ask(DroneId drone, MessageAnalysis a, String q) =>
      brain.answer(drone: drone, analysis: a, question: q);

  test('greeting names the drone, the verdict, and its own contribution', () {
    final g = brain.greeting(DroneId.link, smish);
    expect(g, contains('Link'));
    expect(g, contains('${smish.riskScore}'));
    expect(g.toLowerCase(), contains('flagged'));
  });

  test('"why did you flag this" quotes the drone\'s real findings', () {
    final a = ask(DroneId.link, smish, 'Why did you flag this?');
    expect(a.toLowerCase(), contains('lookalike'));
    // The exact evidence text from the message is quoted back.
    expect(a, contains('t-mobile-verify-secure.com'));
  });

  test('a drone with no flags honestly says what it checked', () {
    final a = ask(DroneId.scanner, genuine, 'Why did you flag this?');
    expect(a.toLowerCase(), contains('didn\'t flag'));
  });

  test('"what should I do" on a dangerous message gives safe steps', () {
    final a = ask(DroneId.swap, smish, 'What should I do?');
    expect(a.toLowerCase(), contains('do not'));
    expect(a.toLowerCase(), contains('code'));
    // Carrier-specific SIM-swap advice rides along for Swap.
    expect(a.toLowerCase(), contains('sim-swap'));
  });

  test('"is it safe" reflects the verdict and confidence', () {
    final a = ask(DroneId.angler, smish, 'Is this message safe?');
    expect(a.toLowerCase(), contains('scam'));
    expect(a, contains('${smish.confidence}%'));
    final b = ask(DroneId.angler, genuine, 'Is this message safe?');
    expect(b.toLowerCase(), contains('legitimate'));
  });

  test('per-drone lessons stay in their specialty', () {
    final qr = ask(DroneId.scanner, smish, 'How do QR codes trick people?');
    expect(qr.toLowerCase(), contains('qr'));
    final sim = ask(DroneId.swap, smish, 'What is a SIM swap?');
    expect(sim.toLowerCase(), contains('sim-swap'));
    final link = ask(DroneId.link, smish, 'How do I read a link?');
    expect(link, contains('t-mobile.com'));
  });

  test('off-topic questions fall back to the drone\'s real finding', () {
    final a = ask(DroneId.link, smish, 'What is the weather tomorrow?');
    expect(a.toLowerCase(), contains('outside my specialty'));
    expect(a.toLowerCase(), contains('lookalike'));
  });

  test('answers stay short and to the point', () {
    int words(String s) => s.split(RegExp(r'\s+')).length;
    expect(words(brain.greeting(DroneId.link, smish)), lessThanOrEqualTo(30));
    expect(
      words(ask(DroneId.link, smish, 'Why did you flag this?')),
      lessThanOrEqualTo(80),
    );
    expect(
      words(ask(DroneId.swap, smish, 'What should I do?')),
      lessThanOrEqualTo(45),
    );
    expect(
      words(ask(DroneId.angler, smish, 'Is this message safe?')),
      lessThanOrEqualTo(35),
    );
    expect(
      words(ask(DroneId.scanner, smish, 'How do QR codes trick people?')),
      lessThanOrEqualTo(40),
    );
  });

  test('suggestions lead with the finding question when flags exist', () {
    expect(
      brain.suggestions(DroneId.link, smish).first,
      'Why did you flag this?',
    );
    expect(
      brain.suggestions(DroneId.link, genuine).first,
      'What did you check?',
    );
  });
}
