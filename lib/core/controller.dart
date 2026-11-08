import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../contracts.dart';
import 'action_executor.dart';
import 'bridge.dart';
import 'draft_guard.dart';
import 'prefilter.dart';
import 'redactor.dart';
import 'scan_client.dart';
import 'state_api.dart';
import 'thread_buffer.dart';

class _Entry {
  final String text;
  String id; // current on-screen bubble id
  String anchorId; // id the result's anchors currently point at
  ScanPhase phase = ScanPhase.scanning;
  ScanResult? result;
  ScanRequest? request;
  String? reason;
  final EmailInfo? email; // email channel only
  _Entry(this.text, this.id, [this.email]) : anchorId = id;
}

ScanResult _reanchor(ScanResult r, String from, String to) {
  if (from == to) return r;
  Anchor a(Anchor x) => x.messageId == from ? Anchor(to, x.field, x.span) : x;
  return ScanResult(
    requestId: r.requestId,
    verdict: r.verdict,
    riskScore: r.riskScore,
    confidence: r.confidence,
    category: r.category,
    summary: r.summary,
    findings: [
      for (final f in r.findings)
        Finding(
          drone: f.drone,
          severity: f.severity,
          confidence: f.confidence,
          title: f.title,
          explanation: f.explanation,
          evidence: f.evidence,
          anchor: a(f.anchor),
          whatWouldChangeMyMind: f.whatWouldChangeMyMind,
        ),
    ],
    actions: r.actions,
    riskSeries: r.riskSeries,
    privacy: r.privacy,
    latencyMs: r.latencyMs,
    modelVersion: r.modelVersion,
  );
}

/// Glue: bridge events -> prefilter -> redact -> scan -> SwarmState for the overlay.
class SwarmController extends ChangeNotifier implements SwarmState {
  final SwarmBridge bridge;
  final ScanClient client;
  final Prefilter prefilter;
  final Redactor redactor;
  final ThreadBuffer buffer;
  final ActionExecutor executor;
  late final DraftGuard _guard;
  final _taps = StreamController<String>.broadcast();
  final _subs = <StreamSubscription>[];
  final _entries = <String, _Entry>{}; // '<thread>|<text>' -> scan state; ids shift on scroll, text does not
  String? _curKey;

  ScreenModel? _screen;
  double _density = 1;
  ScanPhase _phase = ScanPhase.idle;
  String? _target,
      _localSafeReason,
      _threadKey,
      _lastDraft; // _target = target bubble id in the CURRENT screen
  ScanResult? _result, _draftRisk;
  ScanRequest? _lastRequest;
  bool _panelOpen = false;
  Sender? _sender;

  /// Short status of the last action (for a toast); not part of SwarmState.
  String? actionStatus;

  SwarmController._(
    this.bridge,
    this.client,
    this.prefilter,
    this.redactor,
    this.buffer,
    this.executor,
    Duration debounce,
  ) {
    _guard = DraftGuard(
      onRisk: (r) {
        _draftRisk = r;
        notifyListeners();
      },
      debounce: debounce,
      enrichClient: client,
    );
  }

  factory SwarmController({
    required SwarmBridge bridge,
    http.Client? httpClient,
    ScanClient? client,
    Prefilter? prefilter,
    Redactor? redactor,
    ThreadBuffer? buffer,
    ActionExecutor? executor,
    UriLauncher? launch,
    Duration draftDebounce = const Duration(milliseconds: 300),
  }) {
    final c = client ?? ScanClient(client: httpClient);
    return SwarmController._(
      bridge,
      c,
      prefilter ?? Prefilter(),
      redactor ?? Redactor(),
      buffer ?? ThreadBuffer(),
      executor ?? ActionExecutor(bridge: bridge, client: c, launch: launch),
      draftDebounce,
    );
  }

  /// Subscribes to the bridge and tells native we are ready.
  Future<void> start() async {
    _subs
      ..add(
        bridge.init.listen((i) {
          if (i.density > 0) _density = i.density;
          notifyListeners();
        }),
      )
      ..add(bridge.screen.listen(_onScreen))
      ..add(
        bridge.hide.listen((_) => _onScreen(const ScreenModel(visible: false))),
      )
      ..add(bridge.tap.listen(_taps.add));
    await _loadPrefs();
    await bridge.ready();
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload(); // the overlay engine may hold a stale copy of what the app UI saved
      final u = p.getString('backend_url'), k = p.getString('api_key');
      client.baseUrl = (u == null || u.isEmpty) ? 'http://127.0.0.1:8000' : u;
      client.apiKey = (k == null || k.isEmpty) ? 'dev-key' : k;
    } catch (_) {
      /* keep current settings */
    }
  }

  /// Heuristic: Google Messages shows numbers for non-contacts and names for contacts.
  static Sender senderFrom(String? raw) {
    final r = (raw ?? '').trim();
    final digits = r.replaceAll(RegExp(r'\D'), '');
    if (r.isEmpty) return const Sender(raw: '', kind: 'unknown');
    if (r.contains('@')) return Sender(raw: r, kind: 'email');
    if (RegExp(r'^[\d\s()+.-]+$').hasMatch(r)) {
      if (digits.length <= 6) return Sender(raw: r, kind: 'short_code');
      final n = digits.length == 11 && digits.startsWith('1')
          ? digits.substring(1)
          : digits;
      if (RegExp(r'^8(00|33|44|55|66|77|88)').hasMatch(n)) {
        return Sender(raw: r, kind: 'toll_free', e164: '+1$n');
      }
      return Sender(
        raw: r,
        kind: 'long_code',
        e164: r.startsWith('+') ? '+$digits' : '+1$n',
      );
    }
    if (RegExp(r'^[A-Z0-9]{3,11}$').hasMatch(r) &&
        r.contains(RegExp(r'[A-Z]'))) {
      return Sender(raw: r, kind: 'alphanumeric');
    }
    return Sender(raw: r, kind: 'unknown', isContact: true);
  }

  void _onScreen(ScreenModel s) {
    final key = s.threadKey;
    if (s.visible && key != _threadKey) {
      _threadKey = key;
      _phase = ScanPhase.idle;
      _result = _draftRisk = _lastRequest = null;
      _target = _localSafeReason = _curKey = null;
      _lastDraft = null;
    }
    _screen = s;
    if (!s.visible) {
      _draftRisk = null;
      _lastDraft = null;
      notifyListeners();
      return;
    }
    final isEmail = s.channel == 'email' && s.email != null;
    _sender = isEmail
        ? Sender(raw: s.email!.fromAddress, kind: 'email')
        : senderFrom(s.senderRaw); // fromAddress is never redacted
    final k = key ?? '';
    for (final b in s.bubbles) {
      // shortcut: identical text+direction counts as the same message (ids are ordinal-based and shift on scroll).
      if (b.text.isNotEmpty &&
          !buffer
              .thread(k)
              .any((m) => m.direction == b.direction && m.text == b.text)) {
        buffer.add(
          k,
          MessageIn(id: b.messageId, direction: b.direction, text: b.text),
        );
      }
    }

    final draft = s.draftText ?? '';
    if (draft != _lastDraft) {
      _lastDraft = draft;
      final thread = buffer.thread(k);
      _guard.onDraft(
        draft,
        threadKey: k,
        sender: _sender!,
        thread: thread,
        recentIncoming: buffer.recentIncoming().where(
          (m) => !thread.any((t) => t.id == m.id),
        ),
      );
    }
    _resolveTarget(s, k);
    notifyListeners();
  }

  /// Keeps the current target while its bubble is on screen (match by id, else by text);
  /// otherwise shows the cached result of the newest visible incoming bubble, scanning it if new.
  void _resolveTarget(ScreenModel s, String k) {
    Bubble? find(_Entry e) {
      for (final b in s.bubbles) {
        if (b.direction == 'in' && b.messageId == e.id && b.text == e.text) {
          return b;
        }
      }
      for (final b in s.bubbles.reversed) {
        if (b.direction == 'in' && b.text == e.text) return b;
      }
      return null;
    }

    final cur = _curKey == null ? null : _entries[_curKey];
    final kept = cur == null ? null : find(cur);
    if (cur != null && kept != null) return _publish(cur, kept.messageId);

    final incoming = s.bubbles.where(
      (b) => b.direction == 'in' && b.text.isNotEmpty,
    );
    if (incoming.isEmpty) return;
    final b = incoming.last;
    final em = s.channel == 'email' ? s.email : null;
    final ek = em != null
        ? '$k|email:${b.messageId}'
        : '$k|${b.text}'; // email ids are stable per email
    final known = _entries[ek];
    if (known != null) {
      _curKey = ek;
      return _publish(known, b.messageId);
    }
    final e = _entries[ek] = _Entry(b.text, b.messageId, em);
    _curKey = ek;
    _publish(e, b.messageId);
    unawaited(_scan(e, ek, b, k));
  }

  void _publish(_Entry e, String id) {
    e.id = id;
    if (e.result != null) {
      e.result = _reanchor(e.result!, e.anchorId, id);
      e.anchorId = id;
    }
    _target = id;
    _phase = e.phase;
    _result = e.result;
    _lastRequest = e.request;
    _localSafeReason = e.reason;
  }

  Future<void> _scan(_Entry e, String ek, Bubble b, String key) async {
    void done(ScanPhase p, {String? reason}) {
      e.phase = p;
      e.reason = reason;
      if (_curKey == ek) _publish(e, e.id);
      notifyListeners();
    }

    try {
      final sender = _sender!;
      if (await executor.isMarkedSafe(sender.raw)) {
        return done(
          ScanPhase.localSafe,
          reason: 'You marked this sender as safe.',
        );
      }
      final em = e.email;
      final pre = em == null
          ? prefilter.check(sender, b.text)
          : prefilter.checkEmail(
              sender,
              em.subject,
              b.text,
              links: em.links.length,
              attachments: em.attachments.length,
            );
      if (pre.isLocalSafe) return done(ScanPhase.localSafe, reason: pre.reason);
      await _loadPrefs();
      final red = redactor.redact(b.text);
      final subj = em == null ? null : redactor.redact(em.subject);
      final thread = buffer.thread(key);
      final recent = thread.length > 10
          ? thread.sublist(thread.length - 10)
          : thread;
      final sentId = e.id;
      final req = ScanRequest(
        requestId: 'req-${DateTime.now().microsecondsSinceEpoch}',
        mode: 'incoming',
        sender: sender,
        channel: em == null ? 'sms' : 'email',
        email: em == null
            ? null
            : EmailInfo(
                subject: subj!.text,
                fromName: em.fromName,
                fromAddress: em.fromAddress,
                replyTo: em.replyTo,
                links: em.links,
                attachments: em.attachments,
              ),
        messages: em != null
            ? [MessageIn(id: sentId, direction: 'in', text: red.text)]
            : [
                for (final m in recent)
                  if (m.direction == 'in' && m.text == b.text)
                    MessageIn(id: sentId, direction: 'in', text: red.text)
                  else
                    MessageIn(
                      id: m.id,
                      direction: m.direction,
                      text: redactor.redact(m.text).text,
                    ),
              ],
        targetMessageId: sentId,
        redactions: _merge(red, subj),
      );
      e.request = req;
      if (_curKey == ek) _publish(e, e.id);
      notifyListeners();
      final res = await client.scan(req, threadKey: key);
      if (res == null) {
        _entries.remove(ek); // superseded: scan again when it is next shown
        if (_curKey == ek) _curKey = null;
        return;
      }
      e.result = res;
      e.anchorId = sentId; // the id the server anchored to; _publish re-points it at the current bubble
      unawaited(bridge.log('scan_done'));
      done(ScanPhase.done);
    } on ScanException catch (e) {
      unawaited(
        bridge.log('scan_error reason=${e.reason}'),
      ); // reason is a type/status name, never message text
      done(ScanPhase.error);
    } catch (error) {
      unawaited(bridge.log('scan_error reason=${error.runtimeType}'));
      done(ScanPhase.error);
    }
  }

  static List<Map<String, dynamic>> _merge(RedactResult a, RedactResult? b) {
    final c = {...a.counts};
    b?.counts.forEach((k, v) => c[k] = (c[k] ?? 0) + v);
    return [
      for (final e in c.entries) {'type': e.key, 'count': e.value},
    ];
  }

  @override
  Future<void> performAction(String id, {Map<String, String>? payload}) async {
    try {
      final isDraft = id == 'dont_send' || id == 'send_anyway';
      final r = isDraft ? _draftRisk : _result;
      final cur = _curKey == null ? null : _entries[_curKey];
      final ctx = ActionContext(
        requestId: r?.requestId ?? '',
        senderRaw: _sender?.raw ?? '',
        originalText: cur?.text ?? '', // only ever leaves the device through the user's own SMS app (report_7726)
        categoryId: (r?.category?['label'] ?? r?.category?['id'] ?? 'unknown')
            .toString(),
        riskScore: r?.riskScore ?? 0,
      );
      actionStatus = await executor.run(id, ctx, payload: payload);
      if (isDraft) {
        _draftRisk = null;
      } else if (id == 'mark_safe' && cur != null) {
        cur.result = null;
        cur.phase = ScanPhase.localSafe;
        cur.reason = 'You marked this sender as safe.';
        _publish(cur, cur.id);
      }
    } catch (_) {
      actionStatus = 'Something went wrong. Please try again.';
    }
    notifyListeners();
  }

  @override
  void setPanelOpen(bool open) {
    _panelOpen = open;
    unawaited(bridge.panel(open));
    notifyListeners();
  }

  @override
  void reportHitTargets(Map<String, Rect> targets) =>
      unawaited(bridge.hitTargets(targets));

  @override
  ScreenModel? get screen => _screen;
  @override
  double get density => _density;
  @override
  ScanPhase get phase => _phase;
  @override
  String? get targetMessageId => _target;
  @override
  ScanResult? get result => _result;
  @override
  String? get localSafeReason => _localSafeReason;
  @override
  ScanResult? get draftRisk => _draftRisk;
  @override
  ScanRequest? get lastRequest => _lastRequest;
  @override
  bool get panelOpen => _panelOpen;
  @override
  Stream<String> get taps => _taps.stream;

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _guard.dispose();
    _taps.close();
    super.dispose();
  }
}
