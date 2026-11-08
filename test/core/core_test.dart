import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signal_swarm/contracts.dart';
import 'package:signal_swarm/core/action_executor.dart';
import 'package:signal_swarm/core/bridge.dart';
import 'package:signal_swarm/core/controller.dart';
import 'package:signal_swarm/core/demo.dart';
import 'package:signal_swarm/core/draft_guard.dart';
import 'package:signal_swarm/core/prefilter.dart';
import 'package:signal_swarm/core/scan_client.dart';
import 'package:signal_swarm/core/state_api.dart';
import 'package:signal_swarm/core/thread_buffer.dart';

MessageIn msg(String id, String text, [String dir = 'in']) =>
    MessageIn(id: id, direction: dir, text: text);
const stranger = Sender(
  raw: '+1 469 555 0182',
  kind: 'long_code',
  isContact: false,
);
const friend = Sender(raw: 'Mom', kind: 'unknown', isContact: true);
ScanRequest req(String id) => ScanRequest(
  requestId: 'r$id',
  mode: 'incoming',
  sender: stranger,
  messages: [msg(id, 'T-Mobile: hi')],
  targetMessageId: id,
);

Bubble bubble(String id, String text, [String dir = 'in']) => Bubble(
  messageId: id,
  direction: dir,
  text: text,
  rect: const Rect(0, 0, 10, 10),
);
ScreenModel screen(
  List<Bubble> b, {
  String sender = '+1 469 555 0182',
  String draft = '',
  String thread = 't1',
}) => ScreenModel(
  threadKey: thread,
  senderRaw: sender,
  draftText: draft,
  bubbles: b,
);

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

class _UnavailablePreferencesExecutor extends ActionExecutor {
  _UnavailablePreferencesExecutor({
    required super.bridge,
    required super.client,
  });
  @override
  Future<bool> isMarkedSafe(String sender) async =>
      throw StateError('preferences unavailable');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'overlay initialization failure leaves scanning with an error',
    () async {
      final bridge = FakeBridge();
      final client = ScanClient(
        client: MockClient((_) async => throw StateError('must not send')),
      );
      final controller = SwarmController(
        bridge: bridge,
        client: client,
        executor: _UnavailablePreferencesExecutor(
          bridge: bridge,
          client: client,
        ),
      );
      addTearDown(controller.dispose);
      await controller.start();
      bridge.emitScreen(screen([bubble('m1', 'Synthetic suspicious message')]));
      await settle();
      expect(controller.phase, ScanPhase.error);
      expect(controller.result, isNull);
    },
  );

  group('Prefilter', () {
    final p = Prefilter();
    test(
      'unknown sender escalates',
      () => expect(p.check(stranger, 'hello').isLocalSafe, isFalse),
    );
    test(
      'known contact plain text is local safe',
      () => expect(
        p.check(friend, 'running late, see you at 6').isLocalSafe,
        isTrue,
      ),
    );
    test(
      'contact with link escalates',
      () => expect(p.check(friend, 'look https://x.co/a').reason, 'has_url'),
    );
    test(
      'contact with bare domain escalates',
      () => expect(p.check(friend, 'see bank-login.com').isLocalSafe, isFalse),
    );
    test(
      'contact with money word escalates',
      () => expect(
        p.check(friend, 'can you send \$50 payment').isLocalSafe,
        isFalse,
      ),
    );
    test(
      'short code otp escalates',
      () => expect(
        p
            .check(
              const Sender(raw: '22000', kind: 'short_code', isContact: true),
              'Your code is 123456',
            )
            .isLocalSafe,
        isFalse,
      ),
    );
  });

  group('ThreadBuffer', () {
    test('dedupes and caps', () {
      final b = ThreadBuffer(cap: 3);
      for (var i = 0; i < 5; i++) {
        b.add('t', msg('m$i', 'x'));
      }
      b.add('t', msg('m4', 'dup'));
      expect(b.thread('t').map((m) => m.id), ['m2', 'm3', 'm4']);
    });
    test('recentIncoming spans threads, in only', () {
      final b = ThreadBuffer()
        ..add('a', msg('1', 'x'))
        ..add('b', msg('2', 'y', 'out'))
        ..add('b', msg('3', 'z'));
      expect(b.recentIncoming().map((m) => m.id), ['1', '3']);
    });
  });

  group('ScanClient', () {
    String ok(String id) => jsonEncode({
      'requestId': id,
      'verdict': 'safe',
      'riskScore': 5,
      'confidence': 0.9,
      'summary': 's',
    });

    test('sends key header, caches by message id', () async {
      var calls = 0;
      late http.BaseRequest seen;
      final c = ScanClient(
        client: MockClient((r) async {
          calls++;
          seen = r;
          return http.Response(ok('ra'), 200);
        }),
      );
      final a = await c.scan(req('a'), threadKey: 't');
      await c.scan(req('a'), threadKey: 't');
      expect(a!.verdict, 'safe');
      expect(calls, 1);
      expect(seen.headers['X-Swarm-Key'], 'dev-key');
      expect(seen.url.toString(), 'http://127.0.0.1:8000/v1/scan');
    });

    test('makes 3 attempts on 500 then throws', () async {
      var calls = 0;
      final c = ScanClient(
        client: MockClient((r) async {
          calls++;
          return http.Response('no', 500);
        }),
      );
      await expectLater(
        c.scan(req('a'), threadKey: 't'),
        throwsA(isA<ScanException>()),
      );
      expect(calls, 3);
    });

    test('fresh client after a non-timeout error', () async {
      var made = 0;
      final c = ScanClient(
        clientFactory: () {
          final n = ++made;
          return MockClient((r) async {
            if (n == 1) throw http.ClientException('stale socket');
            return http.Response(ok('ra'), 200);
          });
        },
      );
      expect((await c.scan(req('a'), threadKey: 't'))!.verdict, 'safe');
      expect(made, 2);
    });

    test('does not retry 4xx', () async {
      var calls = 0;
      final c = ScanClient(
        client: MockClient((r) async {
          calls++;
          return http.Response('no', 422);
        }),
      );
      await expectLater(
        c.scan(req('a'), threadKey: 't'),
        throwsA(isA<ScanException>()),
      );
      expect(calls, 1);
    });

    test('timeout becomes ScanException', () async {
      final c = ScanClient(
        timeout: const Duration(milliseconds: 30),
        client: MockClient((r) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response(ok('ra'), 200);
        }),
      );
      await expectLater(
        c.scan(req('a'), threadKey: 't'),
        throwsA(isA<ScanException>()),
      );
    });

    test('newer scan on the same thread supersedes the older one', () async {
      final c = ScanClient(
        client: MockClient((r) async {
          final id = (jsonDecode(r.body) as Map)['requestId'] as String;
          if (id == 'ra') {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          return http.Response(ok(id), 200);
        }),
      );
      final first = c.scan(req('a'), threadKey: 't');
      final second = c.scan(req('b'), threadKey: 't');
      expect(await first, isNull);
      expect((await second)!.requestId, 'rb');
    });

    test('guardianAlert sends to and no message text', () async {
      late Map body;
      final c = ScanClient(
        client: MockClient((r) async {
          body = jsonDecode(r.body) as Map;
          return http.Response('{"sent":true}', 200);
        }),
      );
      expect(
        await c.guardianAlert(
          requestId: 'r',
          category: 'Smishing',
          riskScore: 90,
          userAlias: 'Gran',
          to: '+15551234567',
        ),
        isTrue,
      );
      expect(body['to'], '+15551234567');
      expect(
        body.keys,
        containsAll(['requestId', 'category', 'riskScore', 'userAlias']),
      );
    });

    test('guardianAlert false on failure', () async {
      final c = ScanClient(
        client: MockClient((r) async => http.Response('x', 500)),
      );
      expect(
        await c.guardianAlert(
          requestId: 'r',
          category: 'c',
          riskScore: 1,
          userAlias: 'a',
        ),
        isFalse,
      );
    });
  });

  group('DraftGuard detectors', () {
    List<String> kinds(String d, {bool code = false}) =>
        DraftGuard.detect(d, codeRequested: code).map((h) => h.kind).toList();
    test(
      'card',
      () => expect(kinds('my card 4111 1111 1111 1111'), ['card_in_draft']),
    );
    test('ssn', () => expect(kinds('123-45-6789'), ['ssn_in_draft']));
    test(
      'gift card code',
      () => expect(kinds('itunes card code A1B2-C3D4-E5F6'), [
        'gift_card_in_draft',
      ]),
    );
    test(
      'password',
      () => expect(kinds('my password is hunter2'), ['password_in_draft']),
    );
    test('otp only when a code was requested', () {
      expect(kinds('482913'), isEmpty);
      expect(kinds('482913', code: true), ['otp_in_draft']);
    });
    test('plain text and phone numbers are clean', () {
      expect(kinds('call me at 469-555-0182 about 5 pm', code: true), isEmpty);
    });
    test('codeRequested sees incoming asks', () {
      expect(
        DraftGuard.codeRequested([msg('1', 'Send me the verification code')]),
        isTrue,
      );
      expect(DraftGuard.codeRequested([msg('1', 'lunch?')]), isFalse);
    });
    test('local result has warden finding and dont_send primary', () {
      final res = DraftGuard.buildLocalResult(
        DraftGuard.detect('123-45-6789', codeRequested: false),
      );
      expect(res.findings.single.drone, 'warden');
      expect(res.findings.single.anchor.field, 'compose');
      expect(res.actions.firstWhere((a) => a.primary).id, 'dont_send');
    });
  });

  group('DraftGuard debounce', () {
    test('fires once after the last edit; empty clears at once', () async {
      final seen = <ScanResult?>[];
      final g = DraftGuard(
        onRisk: seen.add,
        debounce: const Duration(milliseconds: 30),
      );
      void type(String d) => g.onDraft(
        d,
        threadKey: 't',
        sender: stranger,
        thread: [msg('1', 'send me the code', 'in')],
      );
      type('4');
      type('48');
      type('482913');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(seen.length, 1);
      expect(seen.single!.findings.single.drone, 'warden');
      type('');
      expect(seen.last, isNull);
      g.dispose();
    });
  });

  group('Bridge', () {
    test('FakeBridge records sends', () async {
      final b = FakeBridge();
      await b.ready();
      await b.panel(true);
      await b.log('x');
      expect(b.sent.map((e) => e['method']), ['ready', 'panel', 'log']);
    });
  });

  group('ActionExecutor', () {
    ActionExecutor ex(FakeBridge b, List<Uri> launched, {http.Client? h}) =>
        ActionExecutor(
          bridge: b,
          client: ScanClient(client: h ?? demoHttpClient()),
          launch: (u) async {
            launched.add(u);
            return true;
          },
        );

    test('report_7726 opens sms with the original text', () async {
      final l = <Uri>[];
      await ex(
        FakeBridge(),
        l,
      ).run('report_7726', const ActionContext(originalText: 'hi there'));
      expect(l.single.scheme, 'sms');
      expect(l.single.toString(), contains('7726'));
      expect(l.single.toString(), contains('hi%20there'));
    });
    test('call_official only opens the dialer', () async {
      final l = <Uri>[];
      await ex(
        FakeBridge(),
        l,
      ).run('call_official', const ActionContext(), payload: {'number': '611'});
      expect(l.single.toString(), 'tel:611');
    });
    test('mark_safe persists a hash, not the sender', () async {
      final e = ex(FakeBridge(), []);
      expect(await e.isMarkedSafe('Mom'), isFalse);
      await e.run('mark_safe', const ActionContext(senderRaw: 'Mom'));
      expect(await e.isMarkedSafe(' mom '), isTrue);
      final p = await SharedPreferences.getInstance();
      expect(
        p
            .getStringList('swarm.safeSenders')!
            .join()
            .toLowerCase()
            .contains('mom'),
        isFalse,
      );
    });
    test('alert_guardian needs a phone, then posts it as to', () async {
      Map? body;
      final h = MockClient((r) async {
        body = jsonDecode(r.body) as Map;
        return http.Response('{"sent":true}', 200);
      });
      final e = ex(FakeBridge(), [], h: h);
      expect(
        await e.run('alert_guardian', const ActionContext()),
        contains('Set up a guardian'),
      );
      SharedPreferences.setMockInitialValues({
        'guardian_phone': '+15551234567',
        'guardian_name': 'Sam',
      });
      expect(
        await e.run(
          'alert_guardian',
          const ActionContext(
            requestId: 'r',
            categoryId: 'Smishing',
            riskScore: 90,
          ),
        ),
        contains('alerted'),
      );
      expect(body!['to'], '+15551234567');
    });
    test('draft actions go to native', () async {
      final b = FakeBridge();
      await ex(b, []).run('dont_send', const ActionContext(requestId: 'r'));
      expect(b.sentOf('action').single['id'], 'dont_send');
    });
  });

  group('SwarmController', () {
    late FakeBridge bridge;
    late SwarmController c;
    late List<http.Request> reqs;

    Future<void> boot({http.Client? h}) async {
      reqs = [];
      bridge = FakeBridge();
      final demo = demoHttpClient();
      c = SwarmController(
        bridge: bridge,
        httpClient:
            h ??
            MockClient((r) async {
              reqs.add(r);
              return demo.post(r.url, body: r.body);
            }),
        draftDebounce: const Duration(milliseconds: 10),
      );
      await c.start();
    }

    tearDown(() => c.dispose());

    test('start sends ready and adopts init density', () async {
      await boot();
      bridge.emitInit(const InitInfo(density: 2.75));
      await settle();
      expect(bridge.sentOf('ready'), hasLength(1));
      expect(c.density, 2.75);
    });

    test(
      'scam from unknown sender: redacted request leaves, result lands',
      () async {
        SharedPreferences.setMockInitialValues({
          'backend_url': 'http://10.0.2.2:9000',
          'api_key': 'k',
        });
        await boot();
        bridge.emitScreen(
          screen([
            bubble(
              'm1',
              'T-Mobile: your code 482913 expires. Verify t-mobi1e-acct-verify.co/a8f',
            ),
          ]),
        );
        await settle();
        await settle();
        expect(c.phase, ScanPhase.done);
        expect(c.result!.verdict, 'scam');
        expect(c.targetMessageId, 'm1');
        expect(reqs.single.url.toString(), 'http://10.0.2.2:9000/v1/scan');
        expect(reqs.single.headers['X-Swarm-Key'], 'k');
        expect(reqs.single.body.contains('482913'), isFalse);
        expect(reqs.single.body, contains('<CODE:6>'));
        expect(c.lastRequest!.redactions, [
          {'type': 'CODE', 'count': 1},
        ]);
      },
    );

    test('known contact plain text never hits the network', () async {
      await boot();
      bridge.emitScreen(
        screen([bubble('m1', 'running late, see you at 6')], sender: 'Mom'),
      );
      await settle();
      expect(c.phase, ScanPhase.localSafe);
      expect(c.localSafeReason, isNotEmpty);
      expect(reqs, isEmpty);
    });

    test('same message is scanned once across screen updates', () async {
      await boot();
      final s = screen([bubble('m1', 'T-Mobile: pay now')]);
      bridge.emitScreen(s);
      bridge.emitScreen(s);
      await settle();
      await settle();
      expect(reqs, hasLength(1));
    });

    test('backend down gives error phase', () async {
      await boot(h: MockClient((r) async => http.Response('x', 503)));
      bridge.emitScreen(screen([bubble('m1', 'T-Mobile: pay now')]));
      await settle();
      await settle();
      expect(c.phase, ScanPhase.error);
    });

    test('hide hides the screen and clears the draft risk', () async {
      await boot();
      bridge.emitHide();
      await settle();
      expect(c.screen!.visible, isFalse);
    });

    test('draft with sensitive info raises draftRisk; dont_send clears and tells native', () async {
      await boot();
      bridge.emitScreen(
        screen(
          [bubble('m1', 'please send the verification code')],
          sender: 'Mom',
          draft: '482913',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.draftRisk, isNotNull);
      await c.performAction('dont_send');
      expect(c.draftRisk, isNull);
      expect(bridge.sentOf('action').single['id'], 'dont_send');
    });

    test('panel and hit targets go to native, taps come back', () async {
      await boot();
      c.setPanelOpen(true);
      c.reportHitTargets({'hive': const Rect(1, 2, 3, 4)});
      final tap = c.taps.first;
      bridge.emitTap('hive');
      expect(await tap, 'hive');
      expect(c.panelOpen, isTrue);
      expect(bridge.sentOf('panel').single['open'], true);
      expect(bridge.sentOf('hitTargets'), hasLength(1));
    });

    test('mark_safe turns the result into localSafe', () async {
      await boot();
      bridge.emitScreen(screen([bubble('m1', 'T-Mobile: pay now')]));
      await settle();
      await settle();
      await c.performAction('mark_safe');
      expect(c.phase, ScanPhase.localSafe);
      expect(c.result, isNull);
    });

    test('re-opening a scanned thread restores the cached result without a network call', () async {
      await boot();
      bridge.emitScreen(screen([bubble('m1', 'T-Mobile: pay now')]));
      await settle();
      await settle();
      expect(reqs, hasLength(1));
      bridge.emitScreen(
        screen([bubble('x1', 'hi', 'out')], thread: 't2', sender: 'Mom'),
      );
      await settle();
      expect(c.result, isNull);
      bridge.emitScreen(screen([bubble('m1', 'T-Mobile: pay now')]));
      await settle();
      expect(c.phase, ScanPhase.done);
      expect(c.result!.verdict, 'scam');
      expect(reqs, hasLength(1));
    });

    test(
      'ids shifting on scroll: no rescan, anchors follow the current bubble id',
      () async {
        await boot();
        bridge.emitScreen(
          screen([
            bubble('banner', 'Link previews are on'),
            bubble('m1', 'T-Mobile: pay now'),
          ]),
        );
        await settle();
        await settle();
        expect(
          c.result!.findings.every((f) => f.anchor.messageId == 'm1'),
          isTrue,
        );
        bridge.emitScreen(
          screen([bubble('zz9', 'T-Mobile: pay now')]),
        ); // same text, new ordinal-based id
        await settle();
        expect(reqs, hasLength(1));
        expect(c.targetMessageId, 'zz9');
        expect(
          c.result!.findings.every((f) => f.anchor.messageId == 'zz9'),
          isTrue,
        );
      },
    );

    test(
      'target is kept (not switched) while its bubble is on screen',
      () async {
        await boot();
        bridge.emitScreen(screen([bubble('m1', 'T-Mobile: pay now')]));
        await settle();
        await settle();
        bridge.emitScreen(
          screen([
            bubble('m1', 'T-Mobile: pay now'),
            bubble('m2', 'Link previews are on'),
          ]),
        );
        await settle();
        expect(c.targetMessageId, 'm1');
        expect(c.phase, ScanPhase.done);
      },
    );

    test(
      'a throwing launcher gives a friendly status, not an exception',
      () async {
        await boot();
        final cc = SwarmController(
          bridge: bridge,
          httpClient: demoHttpClient(),
          launch: (u) async => throw StateError('boom: secret text'),
        );
        await cc.performAction('report_7726');
        expect(cc.actionStatus, isNotNull);
        expect(cc.actionStatus!.contains('secret'), isFalse);
        cc.dispose();
      },
    );
  });

  test('senderFrom classifies', () {
    expect(SwarmController.senderFrom('22000').kind, 'short_code');
    expect(SwarmController.senderFrom('+1 (800) 555-0100').kind, 'toll_free');
    expect(SwarmController.senderFrom('(469) 555-0182').e164, '+14695550182');
    expect(SwarmController.senderFrom('TMOBILE').kind, 'alphanumeric');
    expect(SwarmController.senderFrom('a@b.com').kind, 'email');
    expect(SwarmController.senderFrom('Mom').isContact, isTrue);
  });

  group('Email channel', () {
    const emailInfo = EmailInfo(
      subject: 'Verify 482913 now',
      fromName: 'PayPal Support',
      fromAddress: 'security@paypa1-support.com',
      replyTo: 'help@mailbox-relay.biz',
      links: [
        EmailLink(
          text: 'https://www.paypal.com/verify',
          href: 'https://paypa1-support.com/login?id=88a',
          rect: Rect(1, 2, 3, 4),
        ),
      ],
      attachments: [
        EmailAttachment(name: 'invoice_4491.html', rect: Rect(1, 2, 3, 4)),
      ],
    );
    const body =
        'Dear customer, your code 482913 and card 4111 1111 1111 1111. Verify https://www.paypal.com/verify';
    ScreenModel emailScreen({String id = 'e1', EmailInfo info = emailInfo}) =>
        ScreenModel(
          channel: 'email',
          email: info,
          threadKey: 'gmail1',
          header: const Rect(0, 0, 10, 10),
          bubbles: [
            Bubble(
              messageId: id,
              direction: 'in',
              text: body,
              rect: const Rect(0, 20, 10, 10),
            ),
          ],
        );

    test('contracts round trip: rects stay on device', () {
      final j = emailScreen().email!.toJson();
      expect(jsonEncode(j).contains('rect'), isFalse);
      final back = ScreenModel.fromJson({
        'channel': 'email',
        'email': {
          'subject': 's',
          'fromName': 'n',
          'fromAddress': 'a@b.co',
          'links': [
            {
              'text': 't',
              'href': 'h',
              'rect': {'x': 1, 'y': 2, 'w': 3, 'h': 4},
            },
          ],
          'attachments': [
            {
              'name': 'x',
              'rect': {'x': 1, 'y': 2, 'w': 3, 'h': 4},
            },
          ],
        },
      });
      expect(back.email!.links.single.rect!.w, 3);
      expect(back.email!.attachments.single.rect!.h, 4);
    });

    test('request is email channel, body and subject redacted, addresses and hrefs kept', () async {
      final seen = <Map>[];
      final bridge = FakeBridge();
      final c = SwarmController(
        bridge: bridge,
        httpClient: MockClient((r) async {
          seen.add(jsonDecode(r.body) as Map);
          return http.Response(
            jsonEncode({
              'requestId': 'r',
              'verdict': 'scam',
              'riskScore': 90,
              'confidence': 0.9,
              'summary': 's',
              'findings': [
                {
                  'drone': 'link',
                  'severity': 'high',
                  'confidence': 0.9,
                  'title': 't',
                  'explanation': 'e',
                  'anchor': {
                    'messageId': 'e1',
                    'field': 'link',
                    'span': [0, 0],
                  },
                },
                {
                  'drone': 'angler',
                  'severity': 'high',
                  'confidence': 0.9,
                  'title': 't',
                  'explanation': 'e',
                  'anchor': {'messageId': 'header', 'field': 'sender'},
                },
              ],
            }),
            200,
          );
        }),
      );
      await c.start();
      bridge.emitScreen(emailScreen());
      await settle();
      await settle();
      final q = seen.single;
      expect(q['channel'], 'email');
      expect(q['sender'], {
        'raw': 'security@paypa1-support.com',
        'kind': 'email',
        'isContact': false,
      });
      expect(q['email']['fromAddress'], 'security@paypa1-support.com');
      expect(q['email']['replyTo'], 'help@mailbox-relay.biz');
      expect(q['email']['subject'], 'Verify <CODE:6> now');
      expect(q['email']['links'], [
        {
          'text': 'https://www.paypal.com/verify',
          'href': 'https://paypa1-support.com/login?id=88a',
        },
      ]);
      expect(q['email']['attachments'], [
        {'name': 'invoice_4491.html'},
      ]);
      final text = (q['messages'] as List).single['text'] as String;
      expect(
        text,
        'Dear customer, your code <CODE:6> and card <CARD>. Verify https://www.paypal.com/verify',
      );
      expect(q['messages'], hasLength(1));
      expect(q['targetMessageId'], 'e1');
      expect(
        q['redactions'],
        containsAll([
          {'type': 'CODE', 'count': 2},
          {'type': 'CARD', 'count': 1},
        ]),
      );
      // anchors pass through; link span is still the link index
      expect(c.phase, ScanPhase.done);
      final f = c.result!.findings;
      expect(f[0].anchor.field, 'link');
      expect(f[0].anchor.span, [0, 0]);
      expect(f[1].anchor.messageId, 'header');
      c.dispose();
    });

    test('email prefilter: contact with links or attachments or risky words escalates', () {
      final p = Prefilter();
      const contact = Sender(raw: 'a@b.co', kind: 'email', isContact: true);
      expect(
        p
            .checkEmail(
              contact,
              'lunch',
              'see you at noon',
              links: 0,
              attachments: 0,
            )
            .isLocalSafe,
        isTrue,
      );
      expect(
        p
            .checkEmail(contact, 'lunch', 'noon', links: 1, attachments: 0)
            .isLocalSafe,
        isFalse,
      );
      expect(
        p
            .checkEmail(contact, 'lunch', 'noon', links: 0, attachments: 1)
            .isLocalSafe,
        isFalse,
      );
      expect(
        p
            .checkEmail(contact, 'Invoice', 'noon', links: 0, attachments: 0)
            .isLocalSafe,
        isFalse,
      );
      expect(
        p
            .checkEmail(stranger, 'lunch', 'noon', links: 0, attachments: 0)
            .isLocalSafe,
        isFalse,
      );
    });
  });
}
