// Tests for conversation grouping and ordering: the Messages tab is a
// contacts list (one row per sender / phone number), sorted by phone
// number on request, and each conversation keeps its messages in inbox
// order for the thread view.

import 'package:flutter_test/flutter_test.dart';
import 'package:signal_swarm/models/message.dart';
import 'package:signal_swarm/services/conversations.dart';

void main() {
  // Source order is newest-first, as the SMS provider returns it.
  const inbox = [
    ChatMessage(
      id: 'a2',
      sender: '+1 214-555-0176',
      body: 'newer A',
      timeLabel: '9:00 PM',
    ),
    ChatMessage(id: 'b1', sender: '456', body: 'only B', timeLabel: '6:00 PM'),
    ChatMessage(
      id: 'a1',
      sender: '+1 214-555-0176',
      body: 'older A',
      timeLabel: '5:00 PM',
    ),
    ChatMessage(id: 'c1', sender: 'Mom', body: 'only C', timeLabel: '11:30 AM'),
  ];

  int risk(ChatMessage m) => switch (m.id) {
    'a2' => 20,
    'b1' => 95,
    'a1' => 40,
    _ => 0,
  };

  test('grouping keeps one conversation per sender, messages newest-first', () {
    final convs = buildConversations(inbox);
    expect(convs.map((c) => c.sender), ['+1 214-555-0176', '456', 'Mom']);
    final a = convs.first;
    expect(a.count, 2);
    expect(a.messages.map((m) => m.id), ['a2', 'a1']);
    expect(a.latest.id, 'a2');
    expect(a.firstIndex, 0);
    expect(a.lastIndex, 2);
  });

  test('phone ordering: short codes, then full numbers, then names', () {
    expect(compareByPhoneNumber('456', '+1 214-555-0176'), lessThan(0));
    expect(
      compareByPhoneNumber('+1 214-555-0176', '+1 872-555-0147'),
      lessThan(0),
    );
    expect(compareByPhoneNumber('Mom', '456'), greaterThan(0));
    expect(compareByPhoneNumber('Mom', 'Zoe'), lessThan(0));
  });

  test('sort by phone number orders the demo-style contact list', () {
    final sorted = sortConversations(
      buildConversations(inbox),
      MessageSort.phoneNumber,
      riskScore: risk,
    );
    expect(sorted.map((c) => c.sender), ['456', '+1 214-555-0176', 'Mom']);
  });

  test('newest first follows first appearance; oldest first follows the oldest message', () {
    final convs = buildConversations(inbox);
    expect(
      sortConversations(
        convs,
        MessageSort.newestFirst,
        riskScore: risk,
      ).map((c) => c.sender),
      ['+1 214-555-0176', '456', 'Mom'],
    );
    // A owns the oldest message overall (index 2)... C's only message is
    // at index 3, which is older still — source indexes grow older, so
    // oldest-first is by lastIndex descending: C (3), A (2), B (1).
    expect(
      sortConversations(
        convs,
        MessageSort.oldestFirst,
        riskScore: risk,
      ).map((c) => c.sender),
      ['Mom', '+1 214-555-0176', '456'],
    );
  });

  test('highest risk first uses each conversation\'s worst message', () {
    final sorted = sortConversations(
      buildConversations(inbox),
      MessageSort.highestRiskFirst,
      riskScore: risk,
    );
    expect(sorted.map((c) => c.sender), ['456', '+1 214-555-0176', 'Mom']);
  });
}
