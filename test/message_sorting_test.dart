import 'package:flutter_test/flutter_test.dart';
import 'package:signal_swarm/models/message.dart';
import 'package:signal_swarm/services/message_sorting.dart';

void main() {
  const messages = [
    ChatMessage(
      id: 'new-zed',
      sender: 'Zed',
      body: 'new',
      timeLabel: '9:00 PM',
    ),
    ChatMessage(
      id: 'mid-amy',
      sender: 'amy',
      body: 'mid',
      timeLabel: '5:00 PM',
    ),
    ChatMessage(
      id: 'old-bob',
      sender: 'Bob',
      body: 'old',
      timeLabel: '1:00 PM',
    ),
  ];

  int risk(ChatMessage message) => switch (message.id) {
    'new-zed' => 10,
    'mid-amy' => 90,
    'old-bob' => 90,
    _ => 0,
  };

  List<String> ids(List<ChatMessage> sorted) => [
    for (final message in sorted) message.id,
  ];

  test('newest first preserves the inbox source order', () {
    expect(
      ids(sortChatMessages(messages, MessageSort.newestFirst, riskScore: risk)),
      ['new-zed', 'mid-amy', 'old-bob'],
    );
  });

  test('oldest first reverses the inbox source order', () {
    expect(
      ids(sortChatMessages(messages, MessageSort.oldestFirst, riskScore: risk)),
      ['old-bob', 'mid-amy', 'new-zed'],
    );
  });

  test('sender sort is case-insensitive', () {
    expect(
      ids(sortChatMessages(messages, MessageSort.senderAZ, riskScore: risk)),
      ['mid-amy', 'old-bob', 'new-zed'],
    );
  });

  test('risk sort is descending and keeps the source order for ties', () {
    expect(
      ids(
        sortChatMessages(
          messages,
          MessageSort.highestRiskFirst,
          riskScore: risk,
        ),
      ),
      ['mid-amy', 'old-bob', 'new-zed'],
    );
  });

  test('sorting does not mutate the source list', () {
    sortChatMessages(messages, MessageSort.oldestFirst, riskScore: risk);
    expect(ids(messages), ['new-zed', 'mid-amy', 'old-bob']);
  });
}
