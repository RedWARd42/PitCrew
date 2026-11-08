import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/message.dart';
import '../services/drone_brain.dart';
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
/// loud (text-to-speech) as well as in text. Answers come from
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

  final List<_Turn> _turns = [];
  bool _listening = false;
  bool _voiceOn = true;
  bool _micUnavailable = false;

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
      await _tts.setSpeechRate(0.52);
      await _tts.setVolume(1.0);
      if (_voiceOn) await _speak(greeting);
    } catch (_) {
      // No TTS engine (tests, some emulators): text answers still work.
    }
  }

  Future<void> _speak(String text) async {
    if (!_voiceOn) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // Speaking is an enhancement, never a blocker.
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
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
    setState(() => _micUnavailable = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Voice dictation is not available on this device — you can '
          'still type your question.',
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
                    _drone.specialty,
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
              if (!_voiceOn) _tts.stop();
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
              'Listening… speak now. Tap the microphone to stop.',
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
                  hintText: _micUnavailable
                      ? 'Type a question for ${_drone.label}…'
                      : 'Ask ${_drone.label}, or tap the mic…',
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
              icon: _listening ? Icons.mic_off : Icons.mic,
              color: _listening ? const Color(0xFFDC2626) : _droneColor,
              tooltip: _listening ? 'Stop dictation' : 'Ask by voice',
              onPressed: _toggleMic,
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
