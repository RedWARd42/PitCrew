import '../contracts.dart';

/// RAM only. Last [cap] messages per thread, deduped by message id.
class ThreadBuffer {
  final int cap;
  ThreadBuffer({this.cap = 20});
  final Map<String, List<MessageIn>> _threads = {};

  void add(String threadKey, MessageIn m) {
    final l = _threads.putIfAbsent(threadKey, () => []);
    if (l.any((e) => e.id == m.id)) return;
    l.add(m);
    if (l.length > cap) l.removeRange(0, l.length - cap);
  }

  List<MessageIn> thread(String threadKey) => List.unmodifiable(_threads[threadKey] ?? const []);

  /// Incoming messages from every thread (for "a recent thread asked for a code").
  Iterable<MessageIn> recentIncoming() => _threads.values.expand((l) => l).where((m) => m.direction == 'in');

  void clear() => _threads.clear();
}
