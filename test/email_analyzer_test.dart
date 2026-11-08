// The fleet over email: same convictions, email-only tells included.
// Sending-domain spoofing, Reply-To mismatch, and the genuine article
// acquitted — the email analyzer reuses the SMS engine plus its own
// Angler/Scanner checks.

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_swarm/data/demo_emails.dart';
import 'package:signal_swarm/models/message.dart';
import 'package:signal_swarm/services/email_analyzer.dart';
import 'package:signal_swarm/services/walkthrough.dart';

void main() {
  const analyzer = EmailAnalyzer();

  byId(String id) => demoEmails.firstWhere((e) => e.id == id);

  test('fake T-Mobile billing email is dangerous', () {
    final a = analyzer.analyze(byId('phish-tmobile-billing'));
    expect(a.verdict, Verdict.dangerous);
    expect(
      a
          .findingsFor(DroneId.angler)
          .any((f) => f.title.contains('sending domain')),
      isTrue,
    );
    expect(a.pointsFor(DroneId.link), greaterThan(0));
  });

  test('payroll QR phish is caught: Reply-To trick + credential ask', () {
    final a = analyzer.analyze(byId('phish-payroll-qr'));
    expect(a.riskScore, greaterThanOrEqualTo(50));
    expect(
      a.findingsFor(DroneId.angler).any((f) => f.title.contains('Reply-To')),
      isTrue,
    );
    expect(a.pointsFor(DroneId.impersonator), greaterThan(0));
    expect(a.pointsFor(DroneId.scanner), greaterThan(0));
  });

  test('CEO gift-card email is flagged without any link at all', () {
    final a = analyzer.analyze(byId('phish-ceo-giftcards'));
    expect(a.verdict, isNot(Verdict.safe));
    expect(a.pointsFor(DroneId.impersonator), greaterThan(0));
    expect(a.pointsFor(DroneId.link), 0);
  });

  test('genuine T-Mobile email from the official domain is safe', () {
    final a = analyzer.analyze(byId('real-tmobile-bill'));
    expect(a.verdict, Verdict.safe);
    expect(
      a
          .findingsFor(DroneId.angler)
          .any((f) => f.title == 'Verified sending domain'),
      isTrue,
    );
  });

  test('ordinary newsletter is safe', () {
    final a = analyzer.analyze(byId('school-newsletter'));
    expect(a.verdict, Verdict.safe);
  });

  test('findings spans land inside the email display text', () {
    for (final email in demoEmails) {
      final a = analyzer.analyze(email);
      for (final f in a.findings.where((f) => f.hasSpan)) {
        expect(f.spanEnd, lessThanOrEqualTo(email.displayText.length));
      }
    }
  });

  test('walkthrough teaches from an email analysis', () {
    final a = analyzer.analyze(byId('phish-tmobile-billing'));
    final steps = buildWalkthrough(a, DroneId.angler);
    expect(steps, isNotEmpty);
    expect(steps.first.narration, contains('Angler'));
  });
}
