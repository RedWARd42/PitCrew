/// Conversation grouping for the Messages tab, Google-Messages style:
/// the inbox is a list of contacts (one row per sender / phone number),
/// and tapping a contact opens the thread of messages with that contact.
///
/// Pure Dart so the grouping and ordering are unit-testable. "Source
/// order" throughout means the order the inbox arrived in — Android's
/// SMS provider is queried newest-first, and the demo inbox is written
/// the same way — so index 0 is always the newest message.
library;

import '../models/message.dart';

/// Ways the conversation list can be ordered.
enum MessageSort { newestFirst, oldestFirst, highestRiskFirst, phoneNumber }

extension MessageSortInfo on MessageSort {
  String get label => switch (this) {
    MessageSort.newestFirst => 'Newest first',
    MessageSort.oldestFirst => 'Oldest first',
    MessageSort.highestRiskFirst => 'Highest risk first',
    MessageSort.phoneNumber => 'By phone number',
  };

  String get description => switch (this) {
    MessageSort.newestFirst => 'Conversations with new messages first.',
    MessageSort.oldestFirst => 'Conversations with the oldest messages first.',
    MessageSort.highestRiskFirst =>
      'Put the conversations with the most dangerous message first.',
    MessageSort.phoneNumber =>
      'Contacts ordered by phone number; named contacts come after numbers.',
  };
}

/// All messages from one sender, in source order (newest first).
class Conversation {
  const Conversation({
    required this.sender,
    required this.messages,
    required this.firstIndex,
    required this.lastIndex,
  });

  final String sender;
  final List<ChatMessage> messages;

  /// Source index of this conversation's newest message.
  final int firstIndex;

  /// Source index of this conversation's oldest message.
  final int lastIndex;

  ChatMessage get latest => messages.first;
  int get count => messages.length;
}

/// Groups [messages] by sender, preserving source order inside each
/// conversation and first-appearance order across conversations.
List<Conversation> buildConversations(List<ChatMessage> messages) {
  final bySender = <String, List<ChatMessage>>{};
  final firstIndex = <String, int>{};
  final lastIndex = <String, int>{};
  for (var i = 0; i < messages.length; i++) {
    final m = messages[i];
    bySender.putIfAbsent(m.sender, () => []).add(m);
    firstIndex.putIfAbsent(m.sender, () => i);
    lastIndex[m.sender] = i;
  }
  return [
    for (final entry in bySender.entries)
      Conversation(
        sender: entry.key,
        messages: entry.value,
        firstIndex: firstIndex[entry.key]!,
        lastIndex: lastIndex[entry.key]!,
      ),
  ];
}

String _digitsOf(String sender) => sender.replaceAll(RegExp(r'\D'), '');

/// Orders senders the way a person scanning a contacts list expects:
/// phone numbers first, compared as numbers (fewer digits first, then
/// digit-by-digit — so a short code like 456 sorts before full numbers),
/// then named contacts ("Mom") alphabetically.
int compareByPhoneNumber(String a, String b) {
  final da = _digitsOf(a);
  final db = _digitsOf(b);
  if (da.isNotEmpty && db.isNotEmpty) {
    if (da.length != db.length) return da.length.compareTo(db.length);
    final byDigits = da.compareTo(db);
    if (byDigits != 0) return byDigits;
  } else if (da.isNotEmpty) {
    return -1;
  } else if (db.isNotEmpty) {
    return 1;
  }
  return a.toLowerCase().compareTo(b.toLowerCase());
}

/// Returns a newly sorted copy of [conversations].
/// [riskScore] is only consulted for [MessageSort.highestRiskFirst].
List<Conversation> sortConversations(
  List<Conversation> conversations,
  MessageSort sort, {
  required int Function(ChatMessage message) riskScore,
}) {
  final sorted = List<Conversation>.of(conversations);
  int worstRisk(Conversation c) =>
      c.messages.map(riskScore).fold(0, (a, b) => a > b ? a : b);
  switch (sort) {
    case MessageSort.newestFirst:
      sorted.sort((a, b) => a.firstIndex.compareTo(b.firstIndex));
    case MessageSort.oldestFirst:
      sorted.sort((a, b) => b.lastIndex.compareTo(a.lastIndex));
    case MessageSort.highestRiskFirst:
      sorted.sort((a, b) {
        final byRisk = worstRisk(b).compareTo(worstRisk(a));
        return byRisk != 0 ? byRisk : a.firstIndex.compareTo(b.firstIndex);
      });
    case MessageSort.phoneNumber:
      sorted.sort((a, b) {
        final byPhone = compareByPhoneNumber(a.sender, b.sender);
        return byPhone != 0 ? byPhone : a.firstIndex.compareTo(b.firstIndex);
      });
  }
  return sorted;
}
