import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../contracts.dart';
import '../core/state_api.dart';
import 'fixtures.dart';

/// Hand-written SwarmState for the harness and tests. Phone frame is 390x820dp at density 2.75.
class FakeSwarmState extends ChangeNotifier implements SwarmState {
  static const frameW = 390.0, frameH = 820.0;

  @override
  ScreenModel? screen = mockScreen();
  @override
  double density = 2.75;
  @override
  ScanPhase phase = ScanPhase.idle;
  @override
  String? targetMessageId, localSafeReason;
  @override
  ScanResult? result, draftRisk;
  @override
  ScanRequest? lastRequest;
  @override
  bool panelOpen = false;

  final reported = <Map<String, Rect>>[];
  final performed = <String>[];
  final tapController = StreamController<String>.broadcast();
  @override
  Stream<String> get taps => tapController.stream;

  @override
  void setPanelOpen(bool open) {
    panelOpen = open;
    notifyListeners();
  }

  @override
  void reportHitTargets(Map<String, Rect> targets) => reported.add(targets);

  @override
  Future<void> performAction(String id, {Map<String, String>? payload}) async {
    performed.add(id);
    if (id == 'dont_send' || id == 'send_anyway') {
      draftRisk = null;
      screen = _mock();
      notifyListeners();
    }
  }

  double _scroll = 0;
  bool _email = false;

  ScreenModel _mock({String? draft}) => _email ? mockEmailScreen(scrollDp: _scroll) : mockScreen(scrollDp: _scroll, draft: draft);

  void setScreen(ScreenModel? s) {
    screen = s;
    notifyListeners();
  }

  void scrollTo(double dp) {
    _scroll = dp;
    screen = _mock(draft: screen?.draftText);
    notifyListeners();
  }

  void clear() {
    phase = ScanPhase.idle;
    result = draftRisk = lastRequest = null;
    panelOpen = false;
    _email = false;
    screen = _mock();
    notifyListeners();
  }

  /// Loads one of the embedded fixtures (hero, safe, unsure, drift, warden) straight into `done`.
  void load(String name) {
    clear();
    final r = ScanResult.fromJson(jsonDecode(kFixtures[name]!) as Map);
    targetMessageId = 'm1';
    if (name == 'warden') {
      screen = mockScreen(scrollDp: _scroll, draft: '482913');
      draftRisk = r;
    } else {
      result = r;
      phase = ScanPhase.done;
      lastRequest = _request();
    }
    notifyListeners();
  }

  /// Gmail phishing email: the mock Gmail screen, the inline hand-written result and the matching request.
  void loadEmail() {
    clear();
    _email = true;
    screen = _mock();
    result = ScanResult.fromJson(jsonDecode(kFixtures['email']!) as Map);
    lastRequest = ScanRequest.fromJson(jsonDecode(kEmailRequest) as Map);
    targetMessageId = 'e1';
    phase = ScanPhase.done;
    notifyListeners();
  }

  /// hero-style playback: scanning beam, then results.
  Future<void> play(String name) async {
    clear();
    phase = ScanPhase.scanning;
    targetMessageId = 'm1';
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    load(name);
  }

  void localSafe() {
    clear();
    phase = ScanPhase.localSafe;
    localSafeReason = 'Known bank short code, no links.';
    notifyListeners();
  }

  ScanRequest _request() => const ScanRequest(
        requestId: '11111111-1111-4111-8111-111111111111',
        mode: 'incoming',
        sender: Sender(raw: '<PHONE>', kind: 'long_code'),
        messages: [MessageIn(id: 'm1', direction: 'in', text: 'T-Mobile: your line will be suspended in 2 hrs. Verify: <URL>')],
        targetMessageId: 'm1',
        redactions: [
          {'type': 'url', 'count': 1}
        ],
      );

  static const emailBody = 'Dear customer,\n\nWe noticed unusual activity on your account. To keep your account active you must confirm your details within 24 hours, or it will be permanently limited.\n\nVerify your account:\nhttps://www.paypal.com/verify\n\nIf you do not act, you will lose access to your balance and any pending payments.\n\nThank you,\nPayPal Support';

  /// Gmail-like open email in screen px: subject, sender row (header), one long body bubble, attachment card. No compose box.
  static ScreenModel mockEmailScreen({double scrollDp = 0}) {
    const d = 2.75;
    Rect r(double x, double y, double w, double h) => Rect(x * d, y * d, w * d, h * d);
    final em = EmailInfo(
      subject: 'Your account is limited - verify within 24 hours',
      fromName: 'PayPal Support',
      fromAddress: 'security@paypa1-support.com',
      replyTo: 'help@mailbox-relay.biz',
      links: [EmailLink(text: 'https://www.paypal.com/verify', href: 'https://paypa1-support.com/login?id=88a', rect: r(16, 392 - scrollDp, 230, 22))],
      attachments: [EmailAttachment(name: 'invoice_4491.html', rect: r(16, 560 - scrollDp, 200, 56))],
    );
    return ScreenModel(
      channel: 'email',
      email: em,
      threadKey: 'e1',
      senderRaw: 'PayPal Support',
      header: r(0, 128 - scrollDp, frameW, 56),
      bubbles: [Bubble(messageId: 'e1', direction: 'in', text: emailBody, rect: r(0, 244 - scrollDp, frameW, 304))],
    );
  }

  static const bubbleText = 'T-Mobile: your line will be suspended in 2 hrs. Verify: t-mobi1e-acct-verify.co/x';

  /// Messages-like screen in screen px (density 2.75). `scrollDp` moves bubbles up.
  static ScreenModel mockScreen({double scrollDp = 0, String? draft}) {
    const d = 2.75;
    Rect r(double x, double y, double w, double h) => Rect(x * d, y * d, w * d, h * d);
    return ScreenModel(
      threadKey: 't1',
      senderRaw: '+1 469 555 0142',
      draftText: draft,
      header: r(0, 24, frameW, 56),
      compose: r(12, 750, 300, 48),
      send: r(324, 750, 48, 48),
      bubbles: [
        Bubble(messageId: 'm0', direction: 'in', text: 'Hi', rect: r(16, 110 - scrollDp, 240, 52)),
        Bubble(messageId: 'm1', direction: 'in', text: bubbleText, rect: r(16, 200 - scrollDp, 300, 130), linkRects: [r(28, 292 - scrollDp, 200, 22)]),
      ],
    );
  }
}
