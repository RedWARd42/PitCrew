import 'dart:async';
import '../contracts.dart';
import 'redactor.dart';
import 'scan_client.dart';

class DraftHit {
  final String kind, title, explanation, evidence;
  const DraftHit(this.kind, this.title, this.explanation, this.evidence);
}

/// Warden: watches the compose box for things that should not be sent.
class DraftGuard {
  final Duration debounce;
  final void Function(ScanResult? risk) onRisk;
  final ScanClient? enrichClient; // null => local only
  Timer? _t;
  int _gen = 0;

  DraftGuard({required this.onRisk, this.debounce = const Duration(milliseconds: 300), this.enrichClient});

  static final _codeAsk = RegExp(r'\b(?:code|otp|passcode|pin|verification|verify)\b', caseSensitive: false);
  static final _gift = RegExp(r'\b(?:gift\s?card|itunes|google\s?play|steam|apple\s?card|amazon\s?card|vanilla|razer|target\s?card)\b', caseSensitive: false);
  static final _giftCode = RegExp(r'\b(?=[A-Z0-9-]*\d)[A-Z0-9]{4}(?:-[A-Z0-9]{4}){2,}\b|\b(?=[A-Z0-9]*\d)[A-Z0-9]{10,}\b', caseSensitive: false);
  static final _ssn = RegExp(r'(?<![\d-])\d{3}-\d{2}-\d{4}(?![\d-])');
  static final _card = RegExp(r'(?<![\d-])\d(?:[ -]?\d){12,18}(?![\d-])');
  static final _otp = RegExp(r'(?<![\d\-.$,/:+])\d{4,8}(?![\d\-.,/:%])');
  static final _password = RegExp(r'\bpassword\b', caseSensitive: false);

  /// Does any incoming message (this thread or a recent one) ask for / carry a code?
  static bool codeRequested(Iterable<MessageIn> incoming) => incoming.any((m) => _codeAsk.hasMatch(m.text));

  static List<DraftHit> detect(String draft, {required bool codeRequested}) {
    final hits = <DraftHit>[];
    final cards = _card.allMatches(draft).where((m) => luhnValid(m[0]!.replaceAll(RegExp(r'\D'), '')));
    if (cards.isNotEmpty) {
      hits.add(const DraftHit('card_in_draft', 'This looks like a card number', 'Card numbers sent by text can be used to charge you. Only share one with a business you contacted yourself.', '<CARD>'));
    }
    if (_ssn.hasMatch(draft)) {
      hits.add(const DraftHit('ssn_in_draft', 'This looks like a Social Security number', 'Legitimate companies do not ask for your SSN by text.', '<SSN>'));
    }
    if (_gift.hasMatch(draft) && _giftCode.hasMatch(draft)) {
      hits.add(const DraftHit('gift_card_in_draft', 'This looks like a gift card code', 'Gift card codes are spent like cash and cannot be reversed. Scammers ask for them on purpose.', '<GIFTCARD>'));
    }
    if (_password.hasMatch(draft)) {
      hits.add(const DraftHit('password_in_draft', 'You may be sending a password', 'Never share a password by text, even with someone who seems official.', 'password'));
    }
    if (codeRequested) {
      final rest = draft.replaceAll(_card, ' ').replaceAll(_ssn, ' ');
      final m = _otp.firstMatch(rest);
      if (m != null) {
        hits.add(DraftHit('otp_in_draft', 'This code unlocks your account',
            'A text asked for a code and you are typing one. Real companies never ask for login codes by text. Sending it lets someone take over your account.', '<CODE:${m[0]!.length}>'));
      }
    }
    return hits;
  }

  static ScanResult buildLocalResult(List<DraftHit> hits, {String? requestId}) {
    final h = hits.first;
    return ScanResult(
      requestId: requestId ?? 'draft-${DateTime.now().microsecondsSinceEpoch}',
      verdict: 'suspicious',
      riskScore: 88,
      confidence: 0.9,
      category: const {'id': 'outgoing_sensitive', 'label': 'Sensitive info in draft', 'source': 'heuristic'},
      summary: h.kind == 'otp_in_draft' ? "You're about to send a login code." : h.title,
      findings: [
        for (final x in hits)
          Finding(
            drone: 'warden',
            severity: 'high',
            confidence: 0.9,
            title: x.title,
            explanation: x.explanation,
            evidence: [Evidence(x.kind, x.evidence, 'heuristic')],
            anchor: const Anchor('draft', 'compose'),
          ),
      ],
      actions: const [Action('dont_send', "Don't send", primary: true), Action('send_anyway', 'Send anyway')],
      privacy: const {'fieldsReceived': <String>[], 'retained': false, 'llmUsed': false},
      modelVersion: 'local-warden-1',
    );
  }

  /// Call on every draft change. Debounced; an empty draft clears at once.
  /// [thread] = this thread's messages; [recentIncoming] = incoming messages from other recent threads.
  void onDraft(String draft, {required String threadKey, required Sender sender, required List<MessageIn> thread, Iterable<MessageIn> recentIncoming = const []}) {
    _t?.cancel();
    final g = ++_gen;
    if (draft.trim().isEmpty) {
      onRisk(null);
      return;
    }
    _t = Timer(debounce, () async {
      final incoming = [...thread.where((m) => m.direction == 'in'), ...recentIncoming];
      final hits = detect(draft, codeRequested: codeRequested(incoming));
      if (g != _gen) return;
      if (hits.isEmpty) {
        onRisk(null);
        return;
      }
      final local = buildLocalResult(hits);
      onRisk(local);
      final c = enrichClient;
      if (c == null) return;
      try {
        final red = Redactor().redact(draft);
        final req = ScanRequest(
          requestId: local.requestId,
          mode: 'outgoing_draft',
          sender: sender,
          messages: [
            for (final m in thread) MessageIn(id: m.id, direction: m.direction, text: Redactor().redact(m.text).text),
            MessageIn(id: 'draft', direction: 'out', text: red.text),
          ],
          targetMessageId: 'draft',
          redactions: red.toRedactions(),
        );
        final remote = await c.scan(req, threadKey: 'draft:$threadKey');
        if (remote == null || g != _gen) return;
        onRisk(ScanResult(
          requestId: local.requestId,
          verdict: remote.verdict,
          riskScore: remote.riskScore < local.riskScore ? local.riskScore : remote.riskScore,
          confidence: remote.confidence,
          category: remote.category,
          summary: remote.summary,
          findings: remote.findings.any((f) => f.drone == 'warden') ? remote.findings : local.findings,
          actions: remote.actions.any((a) => a.id == 'dont_send') ? remote.actions : local.actions,
          privacy: remote.privacy,
          latencyMs: remote.latencyMs,
          modelVersion: remote.modelVersion,
        ));
      } catch (_) {/* local result stays */}
    });
  }

  void dispose() => _t?.cancel();
}
