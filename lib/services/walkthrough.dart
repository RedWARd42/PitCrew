/// Click-to-explain walkthroughs.
///
/// The Clicky mechanic, applied to scam defense: each drone is a character
/// the user can tap. Tapping one opens its walkthrough — the drone steps
/// through its own findings one at a time, highlighting the exact words in
/// the message as its caption "speaks" them, so the user learns the tell
/// instead of just being told a score.
///
/// Pure Dart: the UI plays these steps; a text-to-speech engine can read
/// [WalkthroughStep.narration] verbatim without changing this logic.
library;

import '../models/message.dart';

class WalkthroughStep {
  const WalkthroughStep({
    required this.drone,
    required this.headline,
    required this.narration,
    required this.finding,
  });

  final DroneId drone;
  final String headline;

  /// What the drone says for this step (also shown as the caption).
  final String narration;

  /// The finding being explained — its span is what the UI highlights
  /// while this step is active.
  final Finding finding;
}

/// Build the walkthrough for one drone out of a completed analysis.
/// Flagged findings become steps; a drone that found nothing wrong gets a
/// single "all clear" step so tapping it still teaches something.
List<WalkthroughStep> buildWalkthrough(
  MessageAnalysis analysis,
  DroneId drone,
) {
  final mine = analysis.findingsFor(drone);
  final flagged = mine.where((f) => f.isFlag).toList()
    ..sort((a, b) => b.points.compareTo(a.points));

  if (flagged.isEmpty) {
    final clean = mine.isNotEmpty
        ? mine.first
        : Finding(
            drone: drone,
            title: 'All clear',
            detail:
                'I checked this message for ${drone.specialty.toLowerCase()} '
                'and found nothing wrong.',
            points: 0,
          );
    return [
      WalkthroughStep(
        drone: drone,
        headline: '${drone.label}: all clear',
        narration:
            'I\'m ${drone.label} — I check for '
            '${drone.specialty.toLowerCase()}. ${clean.detail}',
        finding: clean,
      ),
    ];
  }

  return [
    for (var i = 0; i < flagged.length; i++)
      WalkthroughStep(
        drone: drone,
        headline: '${drone.label} — ${flagged[i].title}',
        narration: i == 0
            ? 'I\'m ${drone.label} — I check for '
                  '${drone.specialty.toLowerCase()}. Here\'s what I found: '
                  '${flagged[i].detail}'
            : 'Also: ${flagged[i].detail}',
        finding: flagged[i],
      ),
  ];
}

/// The auto-written protection report: assembled as a byproduct of the
/// analysis, no extra user effort. This is what "Block & Report" files.
class ProtectionReport {
  const ProtectionReport({
    required this.incidentId,
    required this.message,
    required this.analysis,
    required this.lines,
  });

  final String incidentId;
  final ChatMessage message;
  final MessageAnalysis analysis;
  final List<String> lines;
}

ProtectionReport buildReport(MessageAnalysis analysis) {
  final m = analysis.message;
  final lines = <String>[
    'Sender: ${m.sender}',
    'Risk score: ${analysis.riskScore}/100 '
        '(confidence ${analysis.confidence}%) — ${analysis.verdict.label}',
    for (final drone in DroneId.values)
      if (analysis.pointsFor(drone) > 0)
        '${drone.label} (+${analysis.pointsFor(drone)}): '
            '${analysis.findingsFor(drone).where((f) => f.isFlag).map((f) => f.title).join('; ')}',
  ];
  return ProtectionReport(
    incidentId: 'INC-2026-${m.id.hashCode.abs() % 9000 + 1000}',
    message: m,
    analysis: analysis,
    lines: lines,
  );
}
