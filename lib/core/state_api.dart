// Interface between dart-core (implements) and overlay-ui / app-shell (consume). Orchestrator-owned.
// dart-core: `class SwarmController extends ChangeNotifier implements SwarmState` in controller.dart.
// overlay-ui: build widgets against SwarmState only; test with a hand-written fake that fills these fields.
import 'package:flutter/foundation.dart';

import '../contracts.dart';

enum ScanPhase { idle, scanning, done, localSafe, error }

abstract class SwarmState implements Listenable {
  /// Latest parsed Google Messages screen (screen px). null/!visible => overlay hides everything.
  ScreenModel? get screen;
  double get density; // devicePixelRatio of the display (screen px / density = logical px)

  ScanPhase get phase;

  /// Message currently being scanned/explained, and its result (null until done).
  String? get targetMessageId;
  ScanResult? get result;

  /// Why the on-device prefilter skipped the network (phase == localSafe).
  String? get localSafeReason;

  /// Warden: outgoing draft risk (compose box) or null.
  ScanResult? get draftRisk;

  /// Exactly what left the device for the current result (Privacy receipt tab).
  ScanRequest? get lastRequest;

  bool get panelOpen;
  void setPanelOpen(bool open); // tells native to toggle window touchability
  /// Overlay-ui reports tappable things (screen px, ids: `hive`, `drone:<id>`).
  void reportHitTargets(Map<String, Rect> targets);

  /// Execute an action id from ScanResult.actions (report_7726, call_official, ...).
  Future<void> performAction(String id, {Map<String, String>? payload});

  /// Native hit-window tap forwarded to Dart (`hive` or `drone:<id>`).
  Stream<String> get taps;
}
