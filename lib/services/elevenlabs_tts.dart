import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import '../models/message.dart';
import 'elevenlabs_config.dart';

/// The streaming request URL for one chunk of speech — mirrors the
/// Squeek implementation (a POST to the `/stream` endpoint with
/// maximum streaming-latency optimization, MP3 back).
Uri elevenLabsStreamUri(String voiceId) => Uri.parse(
  'https://api.elevenlabs.io/v1/text-to-speech/$voiceId/stream'
  '?optimize_streaming_latency=3',
);

/// The JSON body for one chunk — same shape and voice settings as
/// Squeek's proxy sends.
Map<String, dynamic> elevenLabsBody(String text) => {
  'text': text,
  'model_id': kElevenLabsModelId,
  'voice_settings': {
    'stability': 0.5,
    'similarity_boost': 0.8,
    'use_speaker_boost': true,
  },
};

/// Split a drone answer into speakable chunks on sentence boundaries,
/// so the first sentence starts playing while the rest is still being
/// synthesized — this is what keeps a long forensic answer from
/// feeling like a long wait. Chunks are capped so no single request
/// runs away; fragments shorter than a breath are merged forward.
List<String> splitForSpeech(String text, {int maxChars = 240}) {
  final sentences = <String>[];
  final pattern = RegExp(r'[^.!?]+[.!?]+["”)]*\s*|[^.!?]+$');
  for (final m in pattern.allMatches(text)) {
    final s = m.group(0)!.trim();
    if (s.isNotEmpty) sentences.add(s);
  }
  final chunks = <String>[];
  var current = '';
  void flush() {
    if (current.trim().isNotEmpty) chunks.add(current.trim());
    current = '';
  }

  for (final s in sentences) {
    if (s.length > maxChars) {
      flush();
      // Hard-split an over-long sentence on commas, then spaces.
      var rest = s;
      while (rest.length > maxChars) {
        var cut = rest.lastIndexOf(', ', maxChars);
        if (cut < maxChars ~/ 2) cut = rest.lastIndexOf(' ', maxChars);
        if (cut <= 0) cut = maxChars;
        chunks.add(rest.substring(0, cut).trim());
        rest = rest.substring(cut).trim();
      }
      if (rest.isNotEmpty) current = rest;
      continue;
    }
    if (current.isEmpty) {
      current = s;
    } else if ('$current $s'.length <= maxChars) {
      current = '$current $s';
    } else {
      flush();
      current = s;
    }
  }
  flush();
  return chunks;
}

/// ElevenLabs speech for the drone conversations.
///
/// Answers are chunked by sentence (see [splitForSpeech]); each chunk
/// is fetched from the streaming endpoint as one MP3 and played in
/// sequence through just_audio. The flash model renders a sentence
/// fast, so the first words land quickly — and serving the player a
/// complete, known-length file per chunk is deliberate: the first
/// version fed it the raw live stream, the player kept re-requesting
/// it, every re-request restarted the MP3 from byte zero, and the
/// answer replayed itself. Buffering the chunk kills that loop.
/// [speak] returns false when ElevenLabs is unreachable or rejects the
/// request (bad/expired key, no quota) so the caller can fall back to
/// the device TTS for that answer instead of going silent.
class ElevenLabsTts {
  factory ElevenLabsTts({AudioPlayer? player}) {
    final loudness = AndroidLoudnessEnhancer();
    return ElevenLabsTts._(
      player:
          player ??
          AudioPlayer(
            audioPipeline: AudioPipeline(androidAudioEffects: [loudness]),
          ),
      loudness: loudness,
    );
  }

  ElevenLabsTts._({required this._player, required this._loudness});

  final AudioPlayer _player;

  /// Playback level for the drone voices (Ryan tuned this by ear:
  /// +8 dB at full volume was too hot once the emulator volume came
  /// up; now a mild +2 dB enhancer lift at 0.7 player volume).
  final AndroidLoudnessEnhancer _loudness;
  bool _boostApplied = false;

  http.Client? _client;
  int _session = 0;

  bool get isConfigured => elevenLabsConfigured;

  Future<bool> speak(String text, DroneId drone) async {
    if (!isConfigured) return false;
    final session = ++_session;
    _client?.close();
    final client = http.Client();
    _client = client;
    if (!_boostApplied) {
      _boostApplied = true;
      try {
        await _loudness.setEnabled(true);
        await _loudness.setTargetGain(2); // mild +2 dB lift
        await _player.setVolume(0.7);
      } catch (_) {
        // Non-Android or effect unavailable: plain full volume.
      }
    }
    try {
      await _player.stop();
    } catch (_) {}
    final chunks = splitForSpeech(text);
    for (var i = 0; i < chunks.length; i++) {
      if (session != _session) return true; // superseded/stopped
      try {
        await _player.setAudioSource(
          _ElevenLabsSource(
            text: chunks[i],
            voiceId: elevenLabsVoiceFor(drone),
            client: client,
          ),
        );
        await _player.play();
      } catch (_) {
        // First chunk failing means the service/key is bad — let the
        // caller fall back. A later chunk failing just ends the answer.
        return i > 0;
      }
    }
    return true;
  }

  Future<void> stop() async {
    _session++;
    _client?.close();
    _client = null;
    try {
      await _player.stop();
    } catch (_) {}
  }

  void dispose() {
    _session++;
    _client?.close();
    _player.dispose();
  }
}

/// A just_audio source that POSTs to ElevenLabs for one chunk, buffers
/// the MP3, then serves it with correct lengths and range offsets.
///
/// The player may call [request] more than once (preroll, buffering,
/// seek); every call must serve the SAME bytes at the requested
/// offset. The first version streamed the live response and ignored
/// offsets, so a re-request restarted the chunk — the replay loop.
/// Buffering once and slicing by offset makes re-requests harmless.
///
/// (just_audio still marks its stream-source API "experimental"; it
//  is the package's supported route for custom audio sources and
//  has been stable across the 0.9/0.10 lines.)
// ignore: experimental_member_use
class _ElevenLabsSource extends StreamAudioSource {
  _ElevenLabsSource({
    required this.text,
    required this.voiceId,
    required this.client,
  });

  final String text;
  final String voiceId;
  final http.Client client;
  List<int>? _bytes;

  Future<List<int>> _load() async {
    final cached = _bytes;
    if (cached != null) return cached;
    final request = http.Request('POST', elevenLabsStreamUri(voiceId))
      ..headers['xi-api-key'] = kElevenLabsApiKey
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'audio/mpeg'
      ..body = jsonEncode(elevenLabsBody(text));
    final response = await client.send(request);
    if (response.statusCode != 200) {
      // Drain and surface as an error so speak() can fall back.
      await response.stream.drain<void>().catchError((_) {});
      throw Exception('ElevenLabs TTS failed: ${response.statusCode}');
    }
    final bytes = await response.stream.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    _bytes = bytes;
    return bytes;
  }

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final bytes = await _load();
    final s = start ?? 0;
    final e = end ?? bytes.length;
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: e - s,
      offset: s,
      stream: Stream<List<int>>.value(bytes.sublist(s, e)),
      contentType: 'audio/mpeg',
    );
  }
}
