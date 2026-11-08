import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _f(String drone, String title, String why, String mid, String field) => {
      'drone': drone,
      'severity': 'high',
      'confidence': 0.9,
      'title': title,
      'explanation': why,
      'evidence': <Map<String, String>>[],
      'anchor': {'messageId': mid, 'field': field},
    };

Map<String, dynamic> _result(String id, String verdict, int risk, String summary, List<Map<String, dynamic>> findings, List<Map<String, dynamic>> actions, [String? cat]) => {
      'requestId': id,
      'verdict': verdict,
      'riskScore': risk,
      'confidence': 0.9,
      'category': cat == null ? null : {'id': cat, 'label': cat, 'source': 'fallback'},
      'summary': summary,
      'findings': findings,
      'actions': actions,
      'privacy': {'fieldsReceived': ['sender', 'messages[].text'], 'retained': false, 'llmUsed': false},
      'latencyMs': 40,
      'modelVersion': 'demo-1',
    };

/// Offline stand-in for the backend (same keyword routing as backend/mock_server.py).
http.Client demoHttpClient() => MockClient((req) async {
      Map<String, dynamic> out;
      if (req.url.path.endsWith('/v1/guardian/alert')) {
        out = {'sent': true};
      } else {
        final j = jsonDecode(req.body) as Map<String, dynamic>;
        final id = j['requestId'] as String, target = j['targetMessageId'] as String;
        final t = [for (final m in j['messages'] as List) (m as Map)['text']].join(' ').toLowerCase();
        if (t.contains('t-mobile') || t.contains('t-mobi')) {
          out = _result(id, 'scam', 94, 'This text pretends to be T-Mobile and pushes you to a fake website with a deadline.', [
            _f('link', 'Lookalike domain', "The link imitates T-Mobile's website.", target, 'link'),
            _f('pressure', 'Deadline pressure', 'A short deadline is meant to make you act before you think.', target, 'body'),
          ], [
            {'id': 'report_7726', 'label': 'Report to 7726', 'primary': true},
            {'id': 'call_official', 'label': 'Call real T-Mobile', 'payload': {'number': '611'}},
            {'id': 'alert_guardian', 'label': 'Alert my guardian'},
            {'id': 'mark_safe', 'label': 'Mark safe'},
          ], 'Account-Suspension Smishing');
        } else if (t.contains('code')) {
          out = _result(id, 'suspicious', 80, 'A code is being requested. Never share login codes.', [
            _f('warden', 'Code request', 'Real companies never ask for login codes by text.', target, 'body'),
          ], [
            {'id': 'report_7726', 'label': 'Report to 7726', 'primary': true},
            {'id': 'mark_safe', 'label': 'Mark safe'},
          ], 'OTP Harvesting');
        } else {
          out = _result(id, 'safe', 6, 'Looks like a normal message.', [], []);
        }
      }
      return http.Response(jsonEncode(out), 200, headers: {'content-type': 'application/json'});
    });
