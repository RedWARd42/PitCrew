// Tests for the shared stores behind the Blocked and Family tabs:
// blocking a convicted message files exactly one incident, the family
// scan-share lands as a report card, and undo really unblocks.

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_swarm/models/message.dart';
import 'package:signal_swarm/services/scam_analyzer.dart';
import 'package:signal_swarm/services/stores.dart';

void main() {
  const analyzer = ScamAnalyzer();

  const scam = ChatMessage(
    id: 'test-scam-1',
    sender: '+1 872-555-0147',
    timeLabel: '9:41 PM',
    body:
        'T-Mobile: URGENT — your line will be SUSPENDED within 24 hours. '
        'Verify NOW: t-mobile-verify-secure.com/pay and send us the '
        '6-digit code we texted you.',
  );

  group('BlocklistStore', () {
    test('blockFromAnalysis files one incident per message', () {
      final before = BlocklistStore.count;
      final analysis = analyzer.analyze(scam);
      final entry = BlocklistStore.blockFromAnalysis(analysis);
      expect(BlocklistStore.count, before + 1);
      expect(entry.sender, scam.sender);
      expect(entry.riskScore, analysis.riskScore);
      expect(entry.categories, isNotEmpty);
      expect(BlocklistStore.isBlocked(scam.id), isTrue);

      // Blocking again (double-tap, re-entry) must not duplicate it.
      BlocklistStore.blockFromAnalysis(analysis);
      expect(BlocklistStore.count, before + 1);
    });

    test('unblock removes the entry', () {
      BlocklistStore.unblock(scam.id);
      expect(BlocklistStore.isBlocked(scam.id), isFalse);
    });

    test('seeded family-shared entries are counted', () {
      expect(BlocklistStore.sharedCount, greaterThan(0));
      expect(BlocklistStore.entries.any((e) => e.blockedBy == 'Alex'), isTrue);
    });
  });

  group('FamilyStore', () {
    test('shareScan adds a scan card with the incident id', () {
      final before = FamilyStore.messages.length;
      final analysis = analyzer.analyze(scam);
      FamilyStore.shareScan(analysis, '9:44 PM');
      expect(FamilyStore.messages.length, before + 1);
      final card = FamilyStore.messages.last;
      expect(card.isScanCard, isTrue);
      expect(card.scanTitle, contains('INC-2026-'));
    });

    test('canned replies differ for SOS vs scan share', () {
      final sos = FamilyStore.cannedReply(wasScanShare: false, wasSos: true);
      final scan = FamilyStore.cannedReply(wasScanShare: true, wasSos: false);
      expect(sos, isNot(scan));
      expect(sos.toLowerCase(), contains('stop'));
    });

    test('trusted contact has a safe word', () {
      expect(FamilyStore.contact.safeWord, isNotEmpty);
    });
  });
}
