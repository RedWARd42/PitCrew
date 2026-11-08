
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  static const Color pink = Color(0xFFE20074);
  static const Color background = Color(0xFF140F19);
  static const String backendUrl = 'http://10.0.2.2:8000';

  Timer? _pollTimer;
  Room? _liveKitRoom;

  String? _incomingRoom;
  String? _connectedRoom;
  String? _dismissedRoom;
  String? _errorMessage;

  bool _checking = false;
  bool _backendConnected = false;
  bool _connecting = false;
  bool _ending = false;
  bool _microphoneEnabled = false;

  @override
  void initState() {
    super.initState();

    _checkIncomingCalls();

    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
          (_) => _checkIncomingCalls(),
    );
  }

  Future<void> _checkIncomingCalls() async {
    if (_checking || _ending) return;
    _checking = true;

    try {
      final response = await http
          .get(Uri.parse('$backendUrl/incoming'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('Backend returned ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data.containsKey('error')) {
        throw Exception(data['error']);
      }

      final calls = data['calls'] as List<dynamic>? ?? [];

      final activeRooms = calls
          .map(
            (call) =>
        (call as Map<String, dynamic>)['room'] as String,
      )
          .toList();

      if (!mounted) return;

      String? endedRoom;

      setState(() {
        _backendConnected = true;

        if (_dismissedRoom != null &&
            !activeRooms.contains(_dismissedRoom)) {
          _dismissedRoom = null;
        }

        if (_incomingRoom != null &&
            !activeRooms.contains(_incomingRoom)) {
          _incomingRoom = null;
        }

        if (_connectedRoom != null &&
            !activeRooms.contains(_connectedRoom)) {
          endedRoom = _connectedRoom;
        }

        if (_connectedRoom == null &&
            _incomingRoom == null &&
            !_connecting) {
          for (final room in activeRooms) {
            if (room != _dismissedRoom) {
              _incomingRoom = room;
              break;
            }
          }
        }
      });

      if (endedRoom != null) {
        await _endCall();
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _backendConnected = false;
      });

      debugPrint('SWAT backend error: $error');
    } finally {
      _checking = false;
    }
  }

  Future<void> _answerCall() async {
    final roomName = _incomingRoom;

    if (roomName == null || _connecting) return;

    setState(() {
      _connecting = true;
      _errorMessage = null;
    });

    Room? newRoom;

    try {
      final response = await http
          .post(
        Uri.parse('$backendUrl/answer'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'room': roomName,
        }),
      )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception(
          'Could not answer call (${response.statusCode})',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final url = data['url'] as String;
      final token = data['token'] as String;

      newRoom = Room();

      await newRoom.connect(
        url,
        token,
        connectOptions: const ConnectOptions(
          autoSubscribe: true,
        ),
      );

      // Enable the emulator microphone so the cellphone caller
      // can hear the person using SWAT.
      await newRoom.localParticipant?.setMicrophoneEnabled(true);

      if (!mounted) {
        await newRoom.disconnect();
        await newRoom.dispose();
        return;
      }

      _liveKitRoom = newRoom;

      setState(() {
        _connectedRoom = roomName;
        _incomingRoom = null;
        _microphoneEnabled = true;
        _errorMessage = null;
      });
    } catch (error) {
      debugPrint('SWAT answer error: $error');

      if (newRoom != null) {
        try {
          await newRoom.disconnect();
          await newRoom.dispose();
        } catch (_) {}
      }

      if (!mounted) return;

      setState(() {
        _errorMessage =
        'Could not connect the call. Please try again.';
        _microphoneEnabled = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
        });
      }
    }
  }

  void _declineCall() {
    if (_incomingRoom == null) return;

    setState(() {
      _dismissedRoom = _incomingRoom;
      _incomingRoom = null;
      _errorMessage = null;
    });

    // For now this dismisses the call in SWAT.
    // It does not hang up the SIP caller.
  }

  Future<void> _toggleMicrophone() async {
    final room = _liveKitRoom;

    if (room == null) return;

    final newValue = !_microphoneEnabled;

    try {
      await room.localParticipant?.setMicrophoneEnabled(newValue);

      if (!mounted) return;

      setState(() {
        _microphoneEnabled = newValue;
      });
    } catch (error) {
      debugPrint('SWAT microphone error: $error');

      if (!mounted) return;

      setState(() {
        _errorMessage = 'Could not change microphone setting.';
      });
    }
  }

  Future<void> _endCall() async {
    if (_ending) return;
    _ending = true;

    final room = _liveKitRoom;
    final previousRoom = _connectedRoom;

    _liveKitRoom = null;

    if (mounted) {
      setState(() {
        _connectedRoom = null;
        _dismissedRoom = previousRoom;
        _microphoneEnabled = false;
        _errorMessage = null;
      });
    }

    try {
      if (room != null) {
        await room.disconnect();
        await room.dispose();
      }
    } catch (error) {
      debugPrint('SWAT disconnect error: $error');
    } finally {
      _ending = false;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();

    final room = _liveKitRoom;
    if (room != null) {
      unawaited(_disposeRoom(room));
    }

    super.dispose();
  }

  Future<void> _disposeRoom(Room room) async {
    try {
      await room.disconnect();
      await room.dispose();
    } catch (error) {
      debugPrint('SWAT cleanup error: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRinging = _incomingRoom != null;
    final isConnected = _connectedRoom != null;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text('Swat Call Protection'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _backendConnected
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_off_rounded,
                    color: _backendConnected
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _backendConnected
                          ? 'Connected to SWAT protection'
                          : 'Connecting to SWAT backend...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),

              const Spacer(),

              Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: pink.withValues(alpha: 0.13),
                  border: Border.all(
                    color: pink.withValues(alpha: 0.45),
                    width: 2,
                  ),
                ),
                child: Icon(
                  isConnected
                      ? Icons.phone_in_talk_rounded
                      : isRinging
                      ? Icons.phone_callback_rounded
                      : Icons.shield_rounded,
                  color: pink,
                  size: 66,
                ),
              ),

              const SizedBox(height: 30),

              Text(
                _connecting
                    ? 'Connecting Call...'
                    : isConnected
                    ? 'Call Connected'
                    : isRinging
                    ? 'Incoming Call'
                    : 'Call Protection Ready',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 14),

              Text(
                _connecting
                    ? 'Joining the LiveKit call room...'
                    : isConnected
                    ? 'You are connected through LiveKit.\n'
                    'You can now speak with the caller.'
                    : isRinging
                    ? 'Unknown Caller\nIncoming via Photon'
                    : 'Waiting for a Photon phone call...',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),

              if (isConnected) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: pink.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'SWAT call protection active\n'
                        'AI scam analysis will be added next',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 20),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 14,
                  ),
                ),
              ],

              const Spacer(),

              if (_connecting)
                const CircularProgressIndicator(
                  color: pink,
                ),

              if (isRinging && !_connecting)
                Row(
                  children: [
                    Expanded(
                      child: _callAction(
                        icon: Icons.call_end_rounded,
                        label: 'Decline',
                        color: const Color(0xFFD83B43),
                        onPressed: _declineCall,
                      ),
                    ),
                    const SizedBox(width: 22),
                    Expanded(
                      child: _callAction(
                        icon: Icons.call_rounded,
                        label: 'Answer',
                        color: const Color(0xFF259B59),
                        onPressed: _answerCall,
                      ),
                    ),
                  ],
                ),

              if (isConnected)
                Row(
                  children: [
                    Expanded(
                      child: _callAction(
                        icon: _microphoneEnabled
                            ? Icons.mic_rounded
                            : Icons.mic_off_rounded,
                        label: _microphoneEnabled
                            ? 'Mute'
                            : 'Unmute',
                        color: const Color(0xFF393040),
                        onPressed: _toggleMicrophone,
                      ),
                    ),
                    const SizedBox(width: 22),
                    Expanded(
                      child: _callAction(
                        icon: Icons.call_end_rounded,
                        label: 'End Call',
                        color: const Color(0xFFD83B43),
                        onPressed: _endCall,
                      ),
                    ),
                  ],
                ),

              if (!isRinging && !isConnected && !_connecting)
                const Text(
                  'SWAT is monitoring for incoming calls',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                ),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _callAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 74,
          height: 74,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
            ),
            child: Icon(icon, size: 33),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
