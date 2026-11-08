import '../models/message.dart';

/// Ways the Messages inbox can be ordered.
///
/// "Newest" follows the order supplied by the inbox source: Android's SMS
/// provider is queried newest-first, and the synthetic demo inbox is written
/// in that same order. Keeping that source order as the canonical order also
/// gives the other sorts a stable, predictable tie-breaker.
enum MessageSort { newestFirst, oldestFirst, highestRiskFirst, senderAZ }

extension MessageSortInfo on MessageSort {
  String get label => switch (this) {
    MessageSort.newestFirst => 'Newest first',
    MessageSort.oldestFirst => 'Oldest first',
    MessageSort.highestRiskFirst => 'Highest risk first',
    MessageSort.senderAZ => 'Sender A–Z',
  };

  String get description => switch (this) {
    MessageSort.newestFirst => 'Show the most recent messages at the top.',
    MessageSort.oldestFirst => 'Show the oldest messages at the top.',
    MessageSort.highestRiskFirst =>
      'Put the messages the fleet scores as most dangerous first.',
    MessageSort.senderAZ => 'Group the list alphabetically by sender.',
  };
}

/// Returns a newly sorted copy of [messages]; the input order is not changed.
///
/// [riskScore] is only called for [MessageSort.highestRiskFirst], so merely
/// opening the sort menu does not force an analysis of the whole inbox.
List<ChatMessage> sortChatMessages(
  Iterable<ChatMessage> messages,
  MessageSort sort, {
  required int Function(ChatMessage message) riskScore,
}) {
  final indexed = messages.indexed.toList();

  switch (sort) {
    case MessageSort.newestFirst:
      return [for (final entry in indexed) entry.$2];
    case MessageSort.oldestFirst:
      return [for (final entry in indexed.reversed) entry.$2];
    case MessageSort.senderAZ:
      indexed.sort((a, b) {
        final bySender = a.$2.sender.toLowerCase().compareTo(
          b.$2.sender.toLowerCase(),
        );
        return bySender != 0 ? bySender : a.$1.compareTo(b.$1);
      });
      return [for (final entry in indexed) entry.$2];
    case MessageSort.highestRiskFirst:
      final scored =
          [
            for (final entry in indexed)
              (entry.$1, entry.$2, riskScore(entry.$2)),
          ]..sort((a, b) {
            final byRisk = b.$3.compareTo(a.$3);
            return byRisk != 0 ? byRisk : a.$1.compareTo(b.$1);
          });
      return [for (final entry in scored) entry.$2];
  }
}
