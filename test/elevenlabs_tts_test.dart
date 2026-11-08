import 'package:flutter_test/flutter_test.dart';
import 'package:signal_swarm/models/message.dart';
import 'package:signal_swarm/services/elevenlabs_config.dart';
import 'package:signal_swarm/services/elevenlabs_tts.dart';

void main() {
  group('splitForSpeech', () {
    test('splits on sentence boundaries and merges short fragments', () {
      final chunks = splitForSpeech(
        'I flagged this link. The domain is t-mobile-verify-secure.com, '
        'which T-Mobile does not own. Do not tap it!',
      );
      expect(chunks.length, 1); // all short enough to ride together
      expect(chunks.single, contains('Do not tap it!'));
    });

    test('breaks long answers into multiple chunks under the cap', () {
      final sentence = 'This is one finding about the message. ';
      final text = sentence * 30; // ~1170 chars
      final chunks = splitForSpeech(text);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(240));
      }
      expect(chunks.join(' '), contains('finding'));
    });

    test('hard-splits a single over-long sentence', () {
      final text = '${List.filled(80, 'word').join(' ')}.';
      final chunks = splitForSpeech(text);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(240));
      }
    });

    test('empty text yields no chunks', () {
      expect(splitForSpeech(''), isEmpty);
      expect(splitForSpeech('   '), isEmpty);
    });
  });

  group('request shape (mirrors the Squeek proxy)', () {
    test('stream URL carries the voice id and latency flag', () {
      final uri = elevenLabsStreamUri('abc123');
      expect(uri.host, 'api.elevenlabs.io');
      expect(uri.path, '/v1/text-to-speech/abc123/stream');
      expect(uri.queryParameters['optimize_streaming_latency'], '3');
    });

    test('body uses the flash model and Squeek voice settings', () {
      final body = elevenLabsBody('Hello');
      expect(body['text'], 'Hello');
      expect(body['model_id'], 'eleven_flash_v2_5');
      final settings = body['voice_settings'] as Map<String, dynamic>;
      expect(settings['stability'], 0.5);
      expect(settings['similarity_boost'], 0.8);
      expect(settings['use_speaker_boost'], true);
    });
  });

  group('voice assignment', () {
    test('every drone has a distinct ElevenLabs voice', () {
      expect(kElevenLabsVoices.length, DroneId.values.length);
      expect(kElevenLabsVoices.values.toSet().length, DroneId.values.length);
      for (final drone in DroneId.values) {
        expect(elevenLabsVoiceFor(drone), isNotEmpty);
      }
    });

    test('unconfigured without a dart-define key (tests run keyless)', () {
      expect(kElevenLabsApiKey, isEmpty);
      expect(elevenLabsConfigured, isFalse);
    });
  });
}
