/// Core data types for Swat message detection.
///
/// This file is pure Dart (no Flutter imports) so the detection logic can be
/// unit-tested with a plain Dart SDK and reused outside the UI.
library;

/// The six specialist drones. One drone per scam type — the Clicky idea:
/// instead of one generic "spam score", a fleet of specialists each patrols
/// for a single kind of tell, flies to the exact spot it found, and explains
/// it when tapped.
enum DroneId { angler, link, scanner, pressure, impersonator, swap }

extension DroneIdInfo on DroneId {
  String get label => switch (this) {
    DroneId.angler => 'Angler',
    DroneId.link => 'Link',
    DroneId.scanner => 'Scanner',
    DroneId.pressure => 'Pressure',
    DroneId.impersonator => 'Impersonator',
    DroneId.swap => 'Swap',
  };

  String get specialty => switch (this) {
    DroneId.angler => 'Spoofed senders',
    DroneId.link => 'Fake links',
    DroneId.scanner => 'QR codes',
    DroneId.pressure => 'Urgency & threats',
    DroneId.impersonator => 'Impersonation & credential asks',
    DroneId.swap => 'SIM-swap & code fishing',
  };

  /// ARGB color value (kept as a raw int so this file stays Flutter-free).
  int get colorValue => switch (this) {
    DroneId.angler => 0xFFFF8A3D,
    DroneId.link => 0xFF38BDF8,
    DroneId.scanner => 0xFFA78BFA,
    DroneId.pressure => 0xFFF87171,
    DroneId.impersonator => 0xFFF472B6,
    DroneId.swap => 0xFF34D399,
  };
}

/// One text message, as read from the Android SMS store or from the bundled
/// synthetic demo inbox (hackathon rule: synthetic scam data only — never
/// real customer data).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.timeLabel,
    this.qrPayload,
    this.isFromRealStore = false,
  });

  final String id;

  /// Raw sender: a phone number, an alphanumeric sender ID, or a carrier
  /// short code (e.g. "456" for genuine T-Mobile notices).
  final String sender;

  final String body;
  final String timeLabel;

  /// If the message carried (or linked to) a QR code, the decoded payload —
  /// usually a URL. Scanner analyzes whatever the QR actually points to.
  final String? qrPayload;

  /// True when this came from the device's real SMS provider via the
  /// platform channel; false for the synthetic demo inbox.
  final bool isFromRealStore;

  bool get hasQr => qrPayload != null && qrPayload!.isNotEmpty;
}

/// A single thing one drone found (or cleared) in a message.
class Finding {
  const Finding({
    required this.drone,
    required this.title,
    required this.detail,
    required this.points,
    this.spanStart = -1,
    this.spanEnd = -1,
    this.evidence = '',
  });

  final DroneId drone;

  /// Short headline, e.g. "Lookalike domain".
  final String title;

  /// Plain-English explanation — this is what the drone "says" when tapped
  /// and what the walkthrough steps through.
  final String detail;

  /// Risk contribution, 0–40. 0 means the drone checked and found this
  /// clean; that still gets reported so the verdict is honest about what
  /// was verified, not just what was flagged.
  final int points;

  /// Character offsets into [ChatMessage.body] for the exact text this
  /// finding is about, so the UI can highlight the evidence in place.
  /// -1/-1 means "whole message" (no specific span).
  final int spanStart;
  final int spanEnd;

  /// The matched text itself, when there is a span.
  final String evidence;

  bool get isFlag => points > 0;
  bool get hasSpan => spanStart >= 0 && spanEnd > spanStart;
}

enum Verdict { safe, caution, dangerous }

extension VerdictInfo on Verdict {
  String get label => switch (this) {
    Verdict.safe => 'LOOKS LEGIT',
    Verdict.caution => 'BE CAREFUL',
    Verdict.dangerous => 'SCAM — BLOCK & REPORT',
  };
}

/// The fleet's combined judgment on one message.
class MessageAnalysis {
  const MessageAnalysis({
    required this.message,
    required this.findings,
    required this.riskScore,
    required this.confidence,
  });

  final ChatMessage message;
  final List<Finding> findings;

  /// 0–100.
  final int riskScore;

  /// 0–100, how much evidence backs the verdict. A verdict built on many
  /// independent drone flags is stated with higher confidence than one
  /// built on a single tell — honest confidence, per the prompt.
  final int confidence;

  Verdict get verdict {
    if (riskScore >= 60) return Verdict.dangerous;
    if (riskScore >= 30) return Verdict.caution;
    return Verdict.safe;
  }

  List<Finding> findingsFor(DroneId drone) =>
      findings.where((f) => f.drone == drone).toList();

  /// The drones that flagged something, worst first.
  List<DroneId> get flaggingDrones {
    final byDrone = <DroneId, int>{};
    for (final f in findings) {
      if (f.isFlag) byDrone[f.drone] = (byDrone[f.drone] ?? 0) + f.points;
    }
    final drones = byDrone.keys.toList()
      ..sort((a, b) => byDrone[b]!.compareTo(byDrone[a]!));
    return drones;
  }

  int pointsFor(DroneId drone) =>
      findingsFor(drone).fold(0, (sum, f) => sum + f.points);
}
