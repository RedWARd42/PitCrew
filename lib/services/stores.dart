/// In-app stores for the blocked list and the trusted-contact chat.
///
/// Deliberately tiny and framework-free (a list + a change stream), so the
/// logic is unit-testable and the three screens (Messages, Blocked,
/// Family) stay in sync. In Squeek this state synced through Supabase;
/// here it lives on-device for the demo, behind the same shape of API —
/// a `share` from either side lands in the same lists.
library;

import 'dart:async';

import '../models/family_and_blocked.dart';
import '../models/message.dart';
import 'scam_analyzer.dart';
import 'walkthrough.dart';

class BlocklistStore {
  BlocklistStore._();

  static final List<BlockedEntry> _entries = [
    // Earlier synthetic incidents, so the Blocked view opens with the
    // story of a protected week — including one the trusted contact
    // blocked and shared to this phone (family-shared block list).
    const BlockedEntry(
      id: 'seed-1',
      sender: '+1 469-555-0119',
      snippet: '"IRS: a warrant has been issued…" — demanded gift cards',
      whenLabel: 'Yesterday',
      riskScore: 96,
      categories: [DroneId.impersonator, DroneId.pressure],
      status: BlockStatus.reported,
      blockedBy: 'You',
      incidentId: 'INC-2026-0917',
    ),
    const BlockedEntry(
      id: 'seed-2',
      sender: '+1 888-555-0163',
      snippet: '"Your Netflix payment failed" — fake billing link',
      whenLabel: 'Tue',
      riskScore: 81,
      categories: [DroneId.link, DroneId.angler],
      status: BlockStatus.blocked,
      blockedBy: 'Alex',
      incidentId: 'INC-2026-0742',
    ),
    const BlockedEntry(
      id: 'seed-3',
      sender: '+1 737-555-0108',
      snippet: '"Grandma, it\'s me — I need bail money, don\'t tell Mom"',
      whenLabel: 'Mon',
      riskScore: 93,
      categories: [DroneId.impersonator, DroneId.swap],
      status: BlockStatus.reported,
      blockedBy: 'Alex',
      incidentId: 'INC-2026-0588',
    ),
  ];

  static final StreamController<void> _changes =
      StreamController<void>.broadcast();
  static Stream<void> get changes => _changes.stream;

  static List<BlockedEntry> get entries => List.unmodifiable(_entries);

  static int get count => _entries.length;
  static int get reportedCount =>
      _entries.where((e) => e.status == BlockStatus.reported).length;
  static int get sharedCount =>
      _entries.where((e) => e.blockedBy != 'You').length;

  static bool isBlocked(String messageId) =>
      _entries.any((e) => e.id == messageId);

  /// File a Block & Report from a completed analysis. Idempotent per
  /// message — blocking the same text twice files one incident.
  static BlockedEntry blockFromAnalysis(MessageAnalysis analysis) {
    for (final e in _entries) {
      if (e.id == analysis.message.id) return e;
    }
    final report = buildReport(analysis);
    final body = analysis.message.body;
    final entry = BlockedEntry(
      id: analysis.message.id,
      sender: analysis.message.sender,
      snippet: body.length <= 90 ? body : '${body.substring(0, 90)}…',
      whenLabel: 'Just now',
      riskScore: analysis.riskScore,
      categories: analysis.flaggingDrones,
      status: BlockStatus.reported,
      blockedBy: 'You',
      incidentId: report.incidentId,
    );
    _entries.insert(0, entry);
    _changes.add(null);
    return entry;
  }

  /// Merge in senders blocked from the Android overlay panel (written
  /// natively to SharedPreferences). Categories are recovered by running
  /// the analyzer over the stored snippet; the risk score is the one the
  /// overlay computed over the full message.
  static void mergeNativeBlocks(List<Map<String, String>> blocks) {
    var added = false;
    for (final b in blocks) {
      final sender = b['sender'] ?? '';
      final at = b['at'] ?? '0';
      if (sender.isEmpty) continue;
      final id = 'native-$at-$sender';
      if (_entries.any((e) => e.id == id)) continue;
      final snippet = b['snippet'] ?? '';
      final analysis = const ScamAnalyzer().analyze(
        ChatMessage(id: id, sender: sender, body: snippet, timeLabel: ''),
      );
      _entries.insert(
        0,
        BlockedEntry(
          id: id,
          sender: sender,
          snippet: snippet.length <= 90
              ? snippet
              : '${snippet.substring(0, 90)}…',
          whenLabel: 'Via overlay',
          riskScore: int.tryParse(b['risk'] ?? '') ?? analysis.riskScore,
          categories: analysis.flaggingDrones,
          status: BlockStatus.reported,
          blockedBy: 'You (overlay)',
          incidentId: buildReport(analysis).incidentId,
        ),
      );
      added = true;
    }
    if (added) _changes.add(null);
  }

  /// Undo a block (false positives happen; a block list you can't correct
  /// is one people stop trusting).
  static void unblock(String entryId) {
    _entries.removeWhere((e) => e.id == entryId);
    _changes.add(null);
  }
}

class FamilyStore {
  FamilyStore._();

  static const TrustedContact contact = demoTrustedContact;

  static final List<FamilyChatMessage> _messages = [
    const FamilyChatMessage(
      fromMe: false,
      text:
          'Morning! Swat blocked a fake IRS text on your phone yesterday '
          '— I got the report here too. You did nothing wrong, it never '
          'reached your inbox as a live message.',
      timeLabel: '9:02 AM',
    ),
    const FamilyChatMessage(
      fromMe: true,
      text: 'Saw that, thank you love. This drone thing is growing on me.',
      timeLabel: '9:15 AM',
    ),
    const FamilyChatMessage(
      fromMe: false,
      text:
          'Remember — if anyone ever calls saying it\'s me in trouble, '
          'ask for the safe word first. Real me knows it. 💙',
      timeLabel: '9:16 AM',
    ),
  ];

  static final StreamController<void> _changes =
      StreamController<void>.broadcast();
  static Stream<void> get changes => _changes.stream;

  static List<FamilyChatMessage> get messages => List.unmodifiable(_messages);

  static void send(String text, String timeLabel) {
    _messages.add(
      FamilyChatMessage(fromMe: true, text: text, timeLabel: timeLabel),
    );
    _changes.add(null);
  }

  static void receive(String text, String timeLabel) {
    _messages.add(
      FamilyChatMessage(fromMe: false, text: text, timeLabel: timeLabel),
    );
    _changes.add(null);
  }

  /// Share a completed fleet scan into the chat as a report card — the
  /// "don't face it alone" move: the trusted contact sees exactly what
  /// the drones found, in the user's own thread with them.
  static void shareScan(MessageAnalysis analysis, String timeLabel) {
    final report = buildReport(analysis);
    _messages.add(
      FamilyChatMessage(
        fromMe: true,
        text: '',
        timeLabel: timeLabel,
        isScanCard: true,
        scanTitle:
            '${report.incidentId} — ${analysis.verdict.label} '
            '(${analysis.riskScore}/100)',
        scanDetail: report.lines.skip(1).join('\n'),
      ),
    );
    _changes.add(null);
  }

  /// The trusted contact's canned replies for the demo. In the real
  /// product these are genuine messages from the contact's own phone —
  /// the point being demonstrated is the *shape*: ask, share the scan,
  /// get a calm human verdict back in the same thread.
  static String cannedReply({
    required bool wasScanShare,
    required bool wasSos,
  }) {
    if (wasSos) {
      return 'I\'m here. Stop talking to them right now — hang up / don\'t '
          'reply. Nothing real is ever that urgent. I\'m calling you in '
          'one minute from my number, the one in your contacts.';
    }
    if (wasScanShare) {
      return 'Got the scan — good catch sending it to me first. That is '
          'NOT really them: look at what Link and Swap found. Don\'t tap '
          'anything in it. I\'ve added the sender to our shared block '
          'list too.';
    }
    return 'Got it. If anything about it feels off, send me the scan '
        'before you tap a thing — that\'s what the fleet is for.';
  }
}
