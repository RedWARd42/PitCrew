import '../models/message.dart';

/// ElevenLabs streaming voice configuration.
///
/// Each drone speaks with its own ElevenLabs voice (streaming TTS,
/// `eleven_flash_v2_5` — the low-latency model Squeek uses). The API
/// key is supplied at run time and never committed:
///
///   flutter run --dart-define=ELEVENLABS_API_KEY=sk_...
///
/// Empty key = not configured: drone conversations fall back to the
/// device text-to-speech engine. (A production build should proxy
/// ElevenLabs through a small server, the way Squeek does, so the key
/// never ships inside the app — for a hackathon demo the define is the
/// pragmatic route, and the README says so.)
const String kElevenLabsApiKey = String.fromEnvironment('ELEVENLABS_API_KEY');

bool get elevenLabsConfigured => kElevenLabsApiKey.isNotEmpty;

/// The streaming model: lowest-latency ElevenLabs model (Squeek's
/// choice), with streaming latency optimization on the request URL.
const String kElevenLabsModelId = 'eleven_flash_v2_5';

/// One distinct premade voice per drone, so the fleet sounds like six
/// specialists, not one narrator. Voice IDs are ElevenLabs' public
/// premade voices; swap any of them for a cloned/designed voice in
/// the ElevenLabs dashboard without touching call sites.
const Map<DroneId, String> kElevenLabsVoices = {
  DroneId.angler: 'VR6AewLTigWG4xSOukaG', // Arnold — deep, no-nonsense
  DroneId.link: 'TxGEqnHWrfWFTfGW9XjX', // Josh — calm explainer
  DroneId.scanner: 'MF3mGyEYCl7XYWbV9V6O', // Elli — bright, precise
  DroneId.pressure: 'pNInz6obpgDQGcFmaJgB', // Adam — firm, urgent
  DroneId.impersonator: '21m00Tcm4TlvDq8ikWAM', // Rachel — composed
  DroneId.swap: 'EXAVITQu4vr4xnSDxMaL', // Bella — warm, steady
};

String elevenLabsVoiceFor(DroneId drone) => kElevenLabsVoices[drone]!;
