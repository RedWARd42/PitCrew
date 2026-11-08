import 'package:flutter_test/flutter_test.dart';
import 'package:signal_swarm/data/demo_inbox.dart';
import 'package:signal_swarm/services/gemini_service.dart';
import 'package:signal_swarm/services/scam_analyzer.dart';

void main() {
  const analyzer = ScamAnalyzer();
  final smish = analyzer.analyze(
    demoInbox.firstWhere((m) => m.id == 'smish-tmobile'),
  );

  test('prompt is grounded in the scan: sender, body, score, findings', () {
    final p = buildGeminiPrompt(smish);
    expect(p, contains(smish.message.sender));
    expect(p, contains('t-mobile-verify-secure.com'));
    expect(p, contains('${smish.riskScore}/100'));
    expect(p, contains('Lookalike'));
    expect(p, contains('60 words'));
  });

  test('request body targets the flash model input shape', () {
    final body = geminiRequestBody(smish);
    final contents = body['contents'] as List;
    expect(contents, hasLength(1));
    expect(geminiUri().path, contains('gemini-2.5-flash'));
  });

  test('parser extracts reply text from a well-formed response', () {
    final text = parseGeminiResponse({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': '  I agree — the domain is fake. Delete it.  '},
            ],
          },
        },
      ],
    });
    expect(text, 'I agree — the domain is fake. Delete it.');
  });

  test('parser returns null for blocked or malformed payloads', () {
    expect(parseGeminiResponse({}), isNull);
    expect(parseGeminiResponse({'candidates': []}), isNull);
    expect(
      parseGeminiResponse({
        'candidates': [
          {
            'content': {'parts': []},
          },
        ],
      }),
      isNull,
    );
  });

  test('unconfigured without a dart-define key (tests run keyless)', () {
    expect(geminiConfigured, isFalse);
  });
}
