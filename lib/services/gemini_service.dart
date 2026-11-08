import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/message.dart';

/// Gemini API "second opinion" — the [MLH] Best Use of Gemini API
/// integration.
///
/// The fleet's verdict is computed on-device and never changes. As an
/// optional extra, the verdict panel can ask Google's Gemini for a
/// plain-language second opinion on the same findings — clearly
/// labeled in the UI as cloud AI, not the verdict. Key supplied at
/// run time (free from Google AI Studio), never committed:
///
///   flutter run --dart-define=GEMINI_API_KEY=...
const String kGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

bool get geminiConfigured => kGeminiApiKey.isNotEmpty;

const String kGeminiModel = 'gemini-2.5-flash';

Uri geminiUri() => Uri.parse(
  'https://generativelanguage.googleapis.com/v1beta/models/'
  '$kGeminiModel:generateContent',
);

/// The prompt: grounded in the fleet's actual findings, capped hard —
/// plain language, one convincing sign, one action, no formatting.
String buildGeminiPrompt(MessageAnalysis a) {
  final flags = [
    for (final d in a.flaggingDrones)
      for (final f in a.findingsFor(d).where((f) => f.isFlag))
        '${d.label}: ${f.title} (+${f.points})',
  ];
  return 'You are a scam-safety explainer for older adults. An '
      'on-device security fleet scanned this text message.\n'
      'Sender: ${a.message.sender}\n'
      'Message: """${a.message.body}"""\n'
      'Fleet verdict: ${a.verdict.label}, risk ${a.riskScore}/100, '
      'confidence ${a.confidence}%.\n'
      'Findings: ${flags.isEmpty ? 'none' : flags.join('; ')}.\n'
      'In at most 60 words of plain language: do you agree with the '
      'fleet? Name the single most convincing sign, and end with '
      'exactly one action the reader should take. No formatting, '
      'no lists.';
}

Map<String, dynamic> geminiRequestBody(MessageAnalysis a) => {
  'contents': [
    {
      'parts': [
        {'text': buildGeminiPrompt(a)},
      ],
    },
  ],
  'generationConfig': {'maxOutputTokens': 160, 'temperature': 0.3},
};

/// Extracts the reply text from a generateContent response; null when
/// the shape is anything unexpected (blocked, empty, error payload).
String? parseGeminiResponse(Map<String, dynamic> json) {
  try {
    final candidates = json['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return null;
    final content = (candidates.first as Map)['content'] as Map?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) return null;
    final text = (parts.first as Map)['text'];
    return (text is String && text.trim().isNotEmpty) ? text.trim() : null;
  } catch (_) {
    return null;
  }
}

class GeminiService {
  /// One second opinion, or null on any failure (no key, offline,
  /// quota, unexpected payload) — the caller degrades gracefully.
  static Future<String?> secondOpinion(
    MessageAnalysis analysis, {
    http.Client? client,
  }) async {
    if (!geminiConfigured) return null;
    final c = client ?? http.Client();
    try {
      final res = await c
          .post(
            geminiUri(),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': kGeminiApiKey,
            },
            body: jsonEncode(geminiRequestBody(analysis)),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      return parseGeminiResponse(
        jsonDecode(res.body) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }
}
