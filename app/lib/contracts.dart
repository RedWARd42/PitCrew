// Dart mirror of contracts/models.py. Orchestrator-owned. Plain maps in/out so JSON round-trips exactly.
class Rect {
  final double x, y, w, h;
  const Rect(this.x, this.y, this.w, this.h);
  factory Rect.fromJson(Map j) => Rect((j['x'] as num).toDouble(), (j['y'] as num).toDouble(), (j['w'] as num).toDouble(), (j['h'] as num).toDouble());
  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};
}

class Sender {
  final String raw, kind;
  final String? e164;
  final bool isContact;
  const Sender({required this.raw, required this.kind, this.e164, this.isContact = false});
  factory Sender.fromJson(Map j) => Sender(raw: j['raw'], kind: j['kind'], e164: j['e164'], isContact: j['isContact'] ?? false);
  Map<String, dynamic> toJson() => {'raw': raw, 'kind': kind, if (e164 != null) 'e164': e164, 'isContact': isContact};
}

class MessageIn {
  final String id, direction, text;
  final String? ts;
  final bool? hasAttachment;
  const MessageIn({required this.id, required this.direction, required this.text, this.ts, this.hasAttachment});
  factory MessageIn.fromJson(Map j) => MessageIn(id: j['id'], direction: j['direction'], text: j['text'], ts: j['ts'], hasAttachment: j['hasAttachment']);
  Map<String, dynamic> toJson() => {'id': id, 'direction': direction, 'text': text, if (ts != null) 'ts': ts, if (hasAttachment != null) 'hasAttachment': hasAttachment};
}

class ScanRequest {
  final String requestId, client, mode, targetMessageId, locale;
  final Sender sender;
  final List<MessageIn> messages;
  final List<Map<String, dynamic>> redactions; // {type,count}
  const ScanRequest({required this.requestId, this.client = 'android', required this.mode, required this.sender, required this.messages, required this.targetMessageId, this.locale = 'en-US', this.redactions = const []});
  factory ScanRequest.fromJson(Map j) => ScanRequest(
      requestId: j['requestId'], client: j['client'], mode: j['mode'], sender: Sender.fromJson(j['sender']),
      messages: [for (final m in j['messages']) MessageIn.fromJson(m)], targetMessageId: j['targetMessageId'],
      locale: j['locale'] ?? 'en-US', redactions: [for (final r in j['redactions'] ?? []) Map<String, dynamic>.from(r)]);
  Map<String, dynamic> toJson() => {'requestId': requestId, 'client': client, 'mode': mode, 'sender': sender.toJson(), 'messages': [for (final m in messages) m.toJson()], 'targetMessageId': targetMessageId, 'locale': locale, 'redactions': redactions};
}

class Evidence {
  final String kind, value, source;
  const Evidence(this.kind, this.value, this.source);
  factory Evidence.fromJson(Map j) => Evidence(j['kind'], j['value'], j['source']);
}

class Anchor {
  final String messageId, field; // field: sender|body|link|compose
  final List<int>? span;
  const Anchor(this.messageId, this.field, [this.span]);
  factory Anchor.fromJson(Map j) => Anchor(j['messageId'], j['field'], (j['span'] as List?)?.cast<int>());
}

class Finding {
  final String drone, severity, title, explanation; // drone: angler|link|pressure|impersonator|warden|drift|carrier|scanner
  final double confidence;
  final List<Evidence> evidence;
  final Anchor anchor;
  final String? whatWouldChangeMyMind;
  const Finding({required this.drone, required this.severity, required this.confidence, required this.title, required this.explanation, this.evidence = const [], required this.anchor, this.whatWouldChangeMyMind});
  factory Finding.fromJson(Map j) => Finding(
      drone: j['drone'], severity: j['severity'], confidence: (j['confidence'] as num).toDouble(), title: j['title'], explanation: j['explanation'],
      evidence: [for (final e in j['evidence'] ?? []) Evidence.fromJson(e)], anchor: Anchor.fromJson(j['anchor']), whatWouldChangeMyMind: j['whatWouldChangeMyMind']);
}

class Action {
  final String id, label; // id: report_7726|call_official|alert_guardian|block_sender|delete|mark_safe|dont_send|send_anyway
  final Map<String, String>? payload;
  final bool primary;
  const Action(this.id, this.label, {this.payload, this.primary = false});
  factory Action.fromJson(Map j) => Action(j['id'], j['label'], payload: (j['payload'] as Map?)?.cast<String, String>(), primary: j['primary'] ?? false);
}

class ScanResult {
  final String requestId, verdict, summary, modelVersion; // verdict: scam|suspicious|unsure|safe
  final int riskScore, latencyMs;
  final double confidence;
  final Map<String, dynamic>? category; // {id,label,source}
  final List<Finding> findings;
  final List<Action> actions;
  final List<double>? riskSeries;
  final Map<String, dynamic> privacy;
  const ScanResult({required this.requestId, required this.verdict, required this.riskScore, required this.confidence, this.category, required this.summary, this.findings = const [], this.actions = const [], this.riskSeries, this.privacy = const {}, this.latencyMs = 0, this.modelVersion = ''});
  factory ScanResult.fromJson(Map j) => ScanResult(
      requestId: j['requestId'], verdict: j['verdict'], riskScore: j['riskScore'], confidence: (j['confidence'] as num).toDouble(),
      category: (j['category'] as Map?)?.cast<String, dynamic>(), summary: j['summary'],
      findings: [for (final f in j['findings'] ?? []) Finding.fromJson(f)], actions: [for (final a in j['actions'] ?? []) Action.fromJson(a)],
      riskSeries: (j['riskSeries'] as List?)?.map((e) => (e as num).toDouble()).toList(), privacy: Map<String, dynamic>.from(j['privacy'] ?? {}),
      latencyMs: j['latencyMs'] ?? 0, modelVersion: j['modelVersion'] ?? '');
}

/// Parsed Google Messages screen (Kotlin -> Dart). Rects are screen px.
class Bubble {
  final String messageId, direction; // in|out
  final String text;
  final Rect rect;
  final List<Rect> linkRects;
  const Bubble({required this.messageId, required this.direction, this.text = '', required this.rect, this.linkRects = const []});
  factory Bubble.fromJson(Map j) => Bubble(messageId: j['messageId'], direction: j['direction'], text: j['text'] ?? '', rect: Rect.fromJson(j['rect']), linkRects: [for (final r in j['linkRects'] ?? []) Rect.fromJson(r)]);
}

class ScreenModel {
  final bool visible;
  final String? threadKey, senderRaw, draftText;
  final Rect? header, compose, send;
  final List<Bubble> bubbles;
  const ScreenModel({this.visible = true, this.threadKey, this.senderRaw, this.draftText, this.header, this.compose, this.send, this.bubbles = const []});
  factory ScreenModel.fromJson(Map j) => ScreenModel(
      visible: j['visible'] ?? true, threadKey: j['threadKey'], senderRaw: j['senderRaw'], draftText: j['draftText'],
      header: j['header'] == null ? null : Rect.fromJson(j['header']), compose: j['compose'] == null ? null : Rect.fromJson(j['compose']),
      send: j['send'] == null ? null : Rect.fromJson(j['send']), bubbles: [for (final b in j['bubbles'] ?? []) Bubble.fromJson(b)]);
}
