import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/message.dart';
import '../services/drone_brain.dart';
import '../services/elevenlabs_config.dart';
import '../services/elevenlabs_tts.dart';
import '../widgets/drone_widget.dart';

const Color _kMagenta = Color(0xFFE20074);

class _Turn {
  const _Turn({required this.fromDrone, required this.text});
  final bool fromDrone;
  final String text;
}

/// A voice conversation with one specialist drone about the message it
/// just scanned.
///
/// The user can type, or tap the microphone and dictate a question
/// (speech-to-text via the platform recognizer); the drone answers out
/// loud as well as in text. When an ElevenLabs API key is supplied at
/// run time (--dart-define=ELEVENLABS_API_KEY=...), answers stream in
/// this drone's own ElevenLabs voice (eleven_flash_v2_5, the pattern
/// borrowed from Squeek); otherwise — or if ElevenLabs is unreachable —
/// the device text-to-speech engine speaks them. Answers come from
/// [DroneBrain] — composed on-device from this drone's actual findings
/// plus its built-in specialty knowledge, never from a cloud chatbot, so
/// everything it says can be checked against the scan.
///
/// Speech is best-effort: on a device/emulator without a recognizer or a
/// microphone, dictation calmly reports itself unavailable and typing
/// still works.
class DroneChatScreen extends StatefulWidget {
  const DroneChatScreen({
    super.key,
    required this.drone,
    required this.analysis,
  });

  final DroneId drone;
  final MessageAnalysis analysis;

  @override
  State<DroneChatScreen> createState() => _DroneChatScreenState();
}

class _DroneChatScreenState extends State<DroneChatScreen> {
  static const DroneBrain _brain = DroneBrain();

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final ElevenLabsTts _eleven = ElevenLabsTts();

  final List<_Turn> _turns = [];
  bool _listening = false;
  bool _voiceOn = true;
  bool _speaking = false;

  DroneId get _drone => widget.drone;
  Color get _droneColor => Color(_drone.colorValue);

  @override
  void initState() {
    super.initState();
    final greeting = _brain.greeting(_drone, widget.analysis);
    _turns.add(_Turn(fromDrone: true, text: greeting));
    _initTts(greeting);
  }

  Future<void> _initTts(String greeting) async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setVolume(1.0);
      // This drone's own device-TTS personality (used whenever the
      // ElevenLabs voice isn't) — distinct pitch and rate per drone.
      final profile = kDroneVoiceProfiles[_drone]!;
      await _tts.setSpeechRate(profile.rate);
      await _tts.setPitch(profile.pitch);
      _tts.setCompletionHandler(() => _setSpeaking(false));
      _tts.setCancelHandler(() => _setSpeaking(false));
      if (_voiceOn) await _speak(greeting);
    } catch (_) {
      // No TTS engine (tests, some emulators): text answers still work.
    }
  }

  void _setSpeaking(bool value) {
    if (mounted && _speaking != value) setState(() => _speaking = value);
  }

  Future<void> _stopSpeaking() async {
    await _eleven.stop();
    try {
      await _tts.stop();
    } catch (_) {}
    _setSpeaking(false);
  }

  Future<void> _speak(String text) async {
    if (!_voiceOn) return;
    // ElevenLabs first when configured: this drone's own voice. Any
    // failure (bad key, no quota, offline) falls back to the device
    // engine so the answer is still spoken.
    if (_eleven.isConfigured) {
      await _tts.stop();
      _setSpeaking(true);
      final ok = await _eleven.speak(text, _drone);
      _setSpeaking(false);
      if (ok || !_voiceOn) return;
    }
    try {
      await _tts.stop();
      _setSpeaking(true);
      await _tts.speak(text);
      // The completion handler clears _speaking when it finishes.
    } catch (_) {
      _setSpeaking(false);
      // Speaking is an enhancement, never a blocker.
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    _eleven.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    // Never compete with the drone's own voice: on the emulator the
    // recognizer errors out (or hears the TTS) if playback is live.
    await _stopSpeaking();
    try {
      final ready = await _speech.initialize(
        onStatus: (status) {
          if (mounted && (status == 'done' || status == 'notListening')) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (!ready) {
        _showMicUnavailable();
        return;
      }
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _input.text = result.recognizedWords;
            _input.selection = TextSelection.fromPosition(
              TextPosition(offset: _input.text.length),
            );
          });
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
        ),
      );
      if (mounted) setState(() => _listening = true);
    } catch (_) {
      _showMicUnavailable();
    }
  }

  void _showMicUnavailable() {
    // Deliberately NOT latching a disabled state: the usual causes
    // (permission not yet granted, emulator mic passthrough off) are
    // fixable mid-session, and a permanently dead button strands the
    // user. Explain, and let the button be tapped again to retry.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 8),
        content: Text(
          'The microphone did not start. On the emulator, turn on '
          'Extended Controls → Microphone → "Virtual microphone uses '
          'host audio input", and allow Swat microphone permission '
          '(Settings → Apps → Swat → Permissions). Then tap Voice '
          'again — typing always works too.',
        ),
      ),
    );
  }

  void _send(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;
    if (_listening) {
      _speech.stop();
      _listening = false;
    }
    _input.clear();
    final reply = _brain.answer(
      drone: _drone,
      analysis: widget.analysis,
      question: text,
    );
    setState(() {
      _turns.add(_Turn(fromDrone: false, text: text));
      _turns.add(_Turn(fromDrone: true, text: reply));
    });
    _scrollToBottom();
    _speak(reply);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        backgroundColor: context.palette.panel,
        title: Row(
          children: [
            DroneWidget(drone: _drone, size: 36, showLabel: false),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Talk to ${_drone.label}',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    elevenLabsConfigured
                        ? '${_drone.specialty} · ElevenLabs voice'
                        : _drone.specialty,
                    style: TextStyle(fontSize: 14, color: _droneColor),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _voiceOn
                ? 'Turn spoken answers off'
                : 'Turn spoken answers on',
            icon: Icon(
              _voiceOn ? Icons.volume_up : Icons.volume_off,
              color: _voiceOn ? _kMagenta : context.palette.secondaryText,
            ),
            onPressed: () {
              setState(() => _voiceOn = !_voiceOn);
              if (!_voiceOn) _stopSpeaking();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              itemCount: _turns.length,
              itemBuilder: (context, i) => _buildTurn(_turns[i]),
            ),
          ),
          _buildSuggestions(),
          if (_listening) _buildListeningStrip(),
          if (_speaking) _buildSpeakingStrip(),
          _buildVoiceBar(),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildTurn(_Turn turn) {
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.82,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: turn.fromDrone
            ? context.palette.bubble
            : _kMagenta.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: turn.fromDrone
            ? Border.all(color: _droneColor.withValues(alpha: 0.55))
            : null,
      ),
      child: Text(
        turn.text,
        style: TextStyle(
          // The user's bubble is magenta in both modes — its text stays
          // white; the drone's neutral bubble follows the palette.
          color: turn.fromDrone ? context.palette.primaryText : Colors.white,
          fontSize: 16.5,
          height: 1.4,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: turn.fromDrone
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        children: [
          if (turn.fromDrone) ...[
            DroneWidget(drone: _drone, size: 30, showLabel: false),
            const SizedBox(width: 8),
          ],
          Flexible(child: bubble),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    final suggestions = _brain.suggestions(_drone, widget.analysis);
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final s in suggestions)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: const Icon(Icons.help_outline, size: 18),
                label: Text(s),
                onPressed: () => _send(s),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildListeningStrip() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: const Color(0xFF3B0A24),
      child: Row(
        children: [
          Icon(Icons.mic, color: Color(0xFFF472B6), size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Listening… speak now. Tap the voice button to stop.',
              style: TextStyle(
                color: context.palette.primaryText,
                fontSize: 15.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Squeek-style speaking status: while the drone talks, a status
  /// strip with a progress shimmer says so — and offers a stop.
  Widget _buildSpeakingStrip() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      color: _droneColor.withValues(alpha: 0.16),
      child: Row(
        children: [
          Icon(Icons.volume_up, color: _droneColor, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_drone.label} is speaking…',
                  style: TextStyle(
                    color: context.palette.primaryText,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  minHeight: 4,
                  color: _droneColor,
                  backgroundColor: _droneColor.withValues(alpha: 0.25),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Stop speaking',
            icon: Icon(Icons.stop_circle, color: _droneColor, size: 30),
            onPressed: _stopSpeaking,
          ),
        ],
      ),
    );
  }

  /// The communication choice, Squeek-style: one big voice button —
  /// or type in the box below it. Tapping starts dictation; your
  /// words land in the text box so you can check them before sending.
  Widget _buildVoiceBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: SizedBox(
        height: 60,
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _toggleMic,
          icon: Icon(_listening ? Icons.stop : Icons.mic, size: 28),
          label: Text(
            _listening
                ? 'Listening… tap to stop'
                : 'Ask ${_drone.label} by voice',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _listening
                ? const Color(0xFFDC2626)
                : _droneColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: context.palette.bubble,
            disabledForegroundColor: context.palette.faintText,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                style: TextStyle(
                  color: context.palette.primaryText,
                  fontSize: 17,
                ),
                decoration: InputDecoration(
                  hintText: 'Type a question for ${_drone.label}…',
                  hintStyle: TextStyle(
                    color: context.palette.faintText,
                    fontSize: 16,
                  ),
                  filled: true,
                  fillColor: context.palette.bubble,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _roundButton(
              icon: Icons.send,
              color: _kMagenta,
              tooltip: 'Send question',
              onPressed: () => _send(_input.text),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}
