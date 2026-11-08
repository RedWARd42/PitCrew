import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../contracts.dart';

class InitInfo {
  final double density, screenW, screenH;
  final Map<String, dynamic> insets;
  const InitInfo({this.density = 1, this.screenW = 0, this.screenH = 0, this.insets = const {}});
}

/// Native <-> Dart bridge (contracts/BRIDGE.md). Event names only in `log`; never message text.
abstract class SwarmBridge {
  // Kotlin -> Dart
  Stream<InitInfo> get init;
  Stream<ScreenModel> get screen;
  Stream<void> get hide;
  Stream<String> get tap;
  Stream<String> get draftText;
  Stream<Map<String, dynamic>> get actionResults;
  // Dart -> Kotlin
  Future<void> ready();
  Future<void> hitTargets(Map<String, Rect> targets);
  Future<void> panel(bool open);
  Future<void> action(String id, Map<String, String>? payload, String requestId);
  Future<void> log(String event);
}

Object? _decode(Object? a) {
  if (a is String) {
    try {
      return jsonDecode(a);
    } catch (_) {
      return a;
    }
  }
  return a;
}

class MethodChannelBridge implements SwarmBridge {
  final MethodChannel _ch;
  final _init = StreamController<InitInfo>.broadcast();
  final _screen = StreamController<ScreenModel>.broadcast();
  final _hide = StreamController<void>.broadcast();
  final _tap = StreamController<String>.broadcast();
  final _draft = StreamController<String>.broadcast();
  final _results = StreamController<Map<String, dynamic>>.broadcast();

  MethodChannelBridge([MethodChannel? channel]) : _ch = channel ?? const MethodChannel('swarm/bridge') {
    _ch.setMethodCallHandler(_onCall);
  }

  Future<dynamic> _onCall(MethodCall c) async {
    final a = _decode(c.arguments);
    final m = a is Map ? a : const {};
    switch (c.method) {
      case 'init':
        _init.add(InitInfo(
            density: (m['density'] as num?)?.toDouble() ?? 1,
            screenW: (m['screenW'] as num?)?.toDouble() ?? 0,
            screenH: (m['screenH'] as num?)?.toDouble() ?? 0,
            insets: Map<String, dynamic>.from(m['insets'] is Map ? m['insets'] as Map : const {})));
      case 'screen':
        _screen.add(ScreenModel.fromJson(m));
      case 'hide':
        _hide.add(null);
      case 'tap':
        if (m['id'] is String) _tap.add(m['id'] as String);
      case 'draftText':
        _draft.add(m['text'] is String ? m['text'] as String : (a is String ? a : ''));
      case 'actionResult':
        _results.add(Map<String, dynamic>.from(m));
    }
    return null;
  }

  Future<void> _send(String method, Object payload) async {
    try {
      await _ch.invokeMethod(method, jsonEncode(payload));
    } on MissingPluginException {/* no native side (desktop/tests) */}
  }

  @override
  Stream<InitInfo> get init => _init.stream;
  @override
  Stream<ScreenModel> get screen => _screen.stream;
  @override
  Stream<void> get hide => _hide.stream;
  @override
  Stream<String> get tap => _tap.stream;
  @override
  Stream<String> get draftText => _draft.stream;
  @override
  Stream<Map<String, dynamic>> get actionResults => _results.stream;

  @override
  Future<void> ready() => _send('ready', {});
  @override
  Future<void> hitTargets(Map<String, Rect> t) => _send('hitTargets', {
        'targets': [for (final e in t.entries) {'id': e.key, 'rect': e.value.toJson()}]
      });
  @override
  Future<void> panel(bool open) => _send('panel', {'open': open});
  @override
  Future<void> action(String id, Map<String, String>? payload, String requestId) => _send('action', {'id': id, 'payload': payload ?? {}, 'requestId': requestId});
  @override
  Future<void> log(String event) => _send('log', {'event': event});
}

/// Test/desktop harness: replays screens by hand and records everything Dart sends to "native".
class FakeBridge implements SwarmBridge {
  final _init = StreamController<InitInfo>.broadcast();
  final _screen = StreamController<ScreenModel>.broadcast();
  final _hide = StreamController<void>.broadcast();
  final _tap = StreamController<String>.broadcast();
  final _draft = StreamController<String>.broadcast();
  final _results = StreamController<Map<String, dynamic>>.broadcast();

  /// Everything sent Dart -> "native", as {method, ...args}.
  final List<Map<String, dynamic>> sent = [];

  void emitInit(InitInfo i) => _init.add(i);
  void emitScreen(ScreenModel s) => _screen.add(s);
  void emitScreenJson(Map<String, dynamic> j) => _screen.add(ScreenModel.fromJson(j));
  void emitHide() => _hide.add(null);
  void emitTap(String id) => _tap.add(id);
  void emitDraft(String t) => _draft.add(t);
  void emitActionResult(Map<String, dynamic> r) => _results.add(r);
  Iterable<Map<String, dynamic>> sentOf(String method) => sent.where((e) => e['method'] == method);

  @override
  Stream<InitInfo> get init => _init.stream;
  @override
  Stream<ScreenModel> get screen => _screen.stream;
  @override
  Stream<void> get hide => _hide.stream;
  @override
  Stream<String> get tap => _tap.stream;
  @override
  Stream<String> get draftText => _draft.stream;
  @override
  Stream<Map<String, dynamic>> get actionResults => _results.stream;

  @override
  Future<void> ready() async => sent.add({'method': 'ready'});
  @override
  Future<void> hitTargets(Map<String, Rect> t) async => sent.add({'method': 'hitTargets', 'targets': {for (final e in t.entries) e.key: e.value.toJson()}});
  @override
  Future<void> panel(bool open) async => sent.add({'method': 'panel', 'open': open});
  @override
  Future<void> action(String id, Map<String, String>? payload, String requestId) async => sent.add({'method': 'action', 'id': id, 'payload': payload, 'requestId': requestId});
  @override
  Future<void> log(String event) async => sent.add({'method': 'log', 'event': event});
}
