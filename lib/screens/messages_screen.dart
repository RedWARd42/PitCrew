import 'package:flutter/material.dart';

import '../models/message.dart';
import '../services/account_store.dart';
import '../services/device_services.dart';
import '../services/message_sorting.dart';
import '../services/scam_analyzer.dart';
import '../services/stores.dart';
import '../services/walkthrough.dart';
import '../widgets/drone_widget.dart';

const Color kMagenta = Color(0xFFE20074);
const Color kBackground = Color(0xFF0B0B12);
const Color kBubble = Color(0xFF1C1C26);
const Color kBubbleSelected = Color(0xFF26202E);

enum FleetPhase { idle, scanning, revealed, protected }

/// Avatar letter for a sender: first alphanumeric character, so a phone
/// number like +1 872-… shows "1" instead of a bare "+".
String _avatarInitial(String sender) {
  final cleaned = sender.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  return cleaned.isEmpty ? '?' : cleaned.substring(0, 1).toUpperCase();
}

/// The Messages screen: an Android-Messages-style inbox with the drone
/// fleet living on top of it.
///
/// Flow (the Clicky mechanic, as a protection flow):
///  1. The fleet sits docked in the Drone Bay at the bottom.
///  2. "Release the Fleet" sends all six drones out at once — each flies
///     to the part of the message its specialty is about and scan-highlights
///     the exact words it found.
///  3. Tapping any drone opens its findings and a step-by-step walkthrough
///     that highlights each tell as it is explained.
///  4. "Block & Report" files the auto-written protection report and shows
///     the after-checklist (SIM lock, account PIN, family safe word).
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, this.onOpenFamily});

  /// Switches the shell to the Family tab (scan sharing / trusted contact).
  final VoidCallback? onOpenFamily;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final ScamAnalyzer _analyzer = const ScamAnalyzer();
  final GlobalKey _stackKey = GlobalKey();
  final Map<String, GlobalKey> _bubbleKeys = {};

  List<ChatMessage> _messages = const [];
  bool _fromRealStore = false;
  bool _loading = true;
  MessageSort _sort = MessageSort.newestFirst;

  String? _selectedId;
  FleetPhase _phase = FleetPhase.idle;
  int _revealedCount = 0;
  int _scanningIdx = -1;
  bool _overlayOn = false;

  // Walkthrough state
  List<WalkthroughStep>? _walkSteps;
  int _walkIndex = 0;

  // After-checklist state
  bool _simLock = false;
  bool _pinSet = false;
  bool _safeWord = false;

  final Map<String, MessageAnalysis> _analysisCache = {};

  @override
  void initState() {
    super.initState();
    _loadInbox();
  }

  Future<void> _loadInbox() async {
    final (messages, fromReal) = await SmsService.loadInbox();
    if (!mounted) return;
    setState(() {
      _messages = messages;
      _fromRealStore = fromReal;
      _loading = false;
      _selectedId = messages.isNotEmpty ? messages.first.id : null;
      _phase = FleetPhase.idle;
    });
  }

  String _nowLabel() {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${now.minute.toString().padLeft(2, '0')} $ampm';
  }

  ChatMessage? get _selected {
    for (final m in _messages) {
      if (m.id == _selectedId) return m;
    }
    return null;
  }

  MessageAnalysis? get _analysis {
    final m = _selected;
    if (m == null) return null;
    return _analysisCache.putIfAbsent(m.id, () => _analyzer.analyze(m));
  }

  int _riskFor(ChatMessage message) => _analysisCache
      .putIfAbsent(message.id, () => _analyzer.analyze(message))
      .riskScore;

  List<ChatMessage> _visibleMessages() =>
      sortChatMessages(_messages, _sort, riskScore: _riskFor);

  void _showSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF15151F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'Sort messages',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final option in MessageSort.values)
                  ListTile(
                    minTileHeight: 64,
                    leading: Icon(
                      _sortIcon(option),
                      color: option == _sort ? kMagenta : Colors.white70,
                    ),
                    title: Text(
                      option.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      option.description,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 14.5,
                      ),
                    ),
                    trailing: Icon(
                      option == _sort
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: option == _sort ? kMagenta : Colors.white38,
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      setState(() => _sort = option);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _sortIcon(MessageSort sort) => switch (sort) {
    MessageSort.newestFirst => Icons.schedule,
    MessageSort.oldestFirst => Icons.history,
    MessageSort.highestRiskFirst => Icons.warning_amber,
    MessageSort.senderAZ => Icons.sort_by_alpha,
  };

  Widget _buildSortBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: const BoxDecoration(
        color: Color(0xFF10101A),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          const Icon(Icons.sort, color: Colors.white70, size: 22),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              'Sort messages',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _loading || _messages.isEmpty ? null : _showSortSheet,
            icon: const Icon(Icons.expand_more, size: 21),
            label: Text(_sort.label),
          ),
        ],
      ),
    );
  }

  void _selectMessage(String id) {
    if (id == _selectedId) return;
    setState(() {
      _selectedId = id;
      _phase = FleetPhase.idle;
      _revealedCount = 0;
      _scanningIdx = -1;
      _walkSteps = null;
    });
  }

  Future<void> _releaseFleet() async {
    final analysis = _analysis;
    if (analysis == null || _phase == FleetPhase.scanning) return;
    setState(() {
      _phase = FleetPhase.scanning;
      _revealedCount = 0;
      _walkSteps = null;
    });
    // All drones launch at once; each "lands" in turn as its scan finishes.
    // Reduce-motion (elderly skill): if the system asks for no animation,
    // the fleet lands instantly — same result, no flight to follow.
    final stepMs = MediaQuery.of(context).disableAnimations ? 0 : 260;
    for (var i = 0; i < DroneId.values.length; i++) {
      if (!mounted || _phase != FleetPhase.scanning) return;
      setState(() => _scanningIdx = i);
      await Future<void>.delayed(Duration(milliseconds: stepMs));
      if (!mounted || _phase != FleetPhase.scanning) return;
      setState(() {
        _revealedCount = i + 1;
        _scanningIdx = -1;
      });
    }
    if (!mounted) return;
    setState(() => _phase = FleetPhase.revealed);
  }

  void _startWalkthrough(DroneId drone) {
    final analysis = _analysis;
    if (analysis == null) return;
    setState(() {
      _walkSteps = buildWalkthrough(analysis, drone);
      _walkIndex = 0;
    });
  }

  void _openDronePanel(DroneId drone) {
    final analysis = _analysis;
    if (analysis == null) return;
    final findings = analysis.findingsFor(drone);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF15151F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DroneWidget(drone: drone, size: 44, showLabel: false),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      drone.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      drone.specialty,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 14.5,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  analysis.pointsFor(drone) > 0
                      ? '+${analysis.pointsFor(drone)} risk'
                      : 'all clear',
                  style: TextStyle(
                    color: analysis.pointsFor(drone) > 0
                        ? const Color(0xFFF87171)
                        : const Color(0xFF34D399),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final f in findings)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.title,
                      style: TextStyle(
                        color: f.isFlag
                            ? const Color(0xFFFCA5A5)
                            : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      f.detail,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _startWalkthrough(drone);
                },
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Walk me through it'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAccountSheet() {
    final account = AccountStore.account;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF15151F),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account?.displayName ?? 'Signed in',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                account?.email ?? '',
                style: const TextStyle(color: Colors.white54, fontSize: 17),
              ),
              const SizedBox(height: 8),
              const Text(
                'Swat protects this account on this phone. Reports and '
                'blocks are filed under this name.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  onPressed: () async {
                    Navigator.of(sheetContext).pop();
                    await AccountStore.signOut();
                  },
                  child: const Text('Sign out', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleOverlay() async {
    if (_overlayOn) {
      await OverlayService.stopOverlay();
      setState(() => _overlayOn = false);
      return;
    }
    if (!await OverlayService.canDrawOverlays()) {
      await OverlayService.openPermissionSettings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Allow "Display over other apps" for Swat, then tap the drone '
            'button again. The floating drone hovers over Google Messages.',
          ),
        ),
      );
      return;
    }
    // The patrol needs RECEIVE_SMS to wake on incoming texts and
    // READ_SMS for badge-tap scans — ask once, up front.
    await OverlayService.requestSmsPermissions();
    final started = await OverlayService.startOverlay();
    if (!mounted) return;
    setState(() => _overlayOn = started);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          started
              ? 'Fleet on patrol over your apps — open Messages: new texts '
                    'get scanned right on top of it. Tap the badge to scan '
                    'your latest text.'
              : 'Overlay is only available on Android.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final analysis = _analysis;
    final visibleMessages = _loading
        ? const <ChatMessage>[]
        : _visibleMessages();
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121C),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Messages',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              'Protecting ${AccountStore.firstName}',
              style: const TextStyle(fontSize: 13.5, color: kMagenta),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Account',
            icon: const Icon(
              Icons.account_circle_outlined,
              color: Colors.white70,
            ),
            onPressed: _showAccountSheet,
          ),
          IconButton(
            tooltip: _overlayOn
                ? 'Stop the floating drone'
                : 'Float a drone over the real Messages app (Android)',
            icon: Icon(
              _overlayOn ? Icons.layers : Icons.layers_outlined,
              color: _overlayOn ? kMagenta : Colors.white70,
            ),
            onPressed: _toggleOverlay,
          ),
          IconButton(
            tooltip: 'Reload inbox',
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadInbox,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            color: const Color(0xFF15151F),
            child: Text(
              _fromRealStore
                  ? 'Reading the real SMS inbox on this device — analysis '
                        'happens on-device.'
                  : 'Demo inbox — synthetic messages only. On Android, grant '
                        'SMS permission and the fleet reads your real inbox.',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
          _buildSortBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      key: _stackKey,
                      children: [
                        ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 96, 90),
                          itemCount: visibleMessages.length,
                          itemBuilder: (context, i) =>
                              _buildBubble(visibleMessages[i]),
                        ),
                        ..._buildFlyingDrones(constraints, analysis),
                      ],
                    ),
                  ),
          ),
          _buildBottomPanel(analysis),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- bubbles
  Widget _buildBubble(ChatMessage m) {
    final key = _bubbleKeys.putIfAbsent(m.id, () => GlobalKey());
    final selected = m.id == _selectedId;
    final analysis = selected ? _analysis : null;
    final showHighlights =
        selected &&
        analysis != null &&
        (_walkSteps != null ||
            _phase == FleetPhase.revealed ||
            _phase == FleetPhase.protected ||
            _phase == FleetPhase.scanning);
    var activeFindings = <Finding>[];
    if (showHighlights) {
      if (_walkSteps != null) {
        activeFindings = [_walkSteps![_walkIndex].finding];
      } else {
        // Only show spans for drones that have landed so far.
        final landed = DroneId.values
            .take(
              _phase == FleetPhase.scanning
                  ? _revealedCount
                  : DroneId.values.length,
            )
            .toSet();
        activeFindings = analysis.findings
            .where((f) => f.hasSpan && landed.contains(f.drone))
            .toList();
      }
    }

    return GestureDetector(
      key: key,
      onTap: () => _selectMessage(m.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: const Color(0xFF2A2A3A),
              child: Text(
                _avatarInitial(m.sender),
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        m.sender,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        m.timeLabel,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13.5,
                        ),
                      ),
                      if (m.hasQr) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.qr_code_2,
                          size: 14,
                          color: Color(0xFFA78BFA),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? kBubbleSelected : kBubble,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? kMagenta : Colors.white10,
                        width: selected ? 1.4 : 1,
                      ),
                    ),
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          height: 1.4,
                        ),
                        children: _highlightedSpans(m.body, activeFindings),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<TextSpan> _highlightedSpans(String body, List<Finding> findings) {
    if (findings.isEmpty) return [TextSpan(text: body)];
    final spans = findings.where((f) => f.hasSpan).toList()
      ..sort((a, b) => a.spanStart.compareTo(b.spanStart));
    final children = <TextSpan>[];
    var cursor = 0;
    for (final f in spans) {
      final start = f.spanStart.clamp(0, body.length);
      final end = f.spanEnd.clamp(0, body.length);
      if (start < cursor || end <= start) continue;
      if (start > cursor) {
        children.add(TextSpan(text: body.substring(cursor, start)));
      }
      children.add(
        TextSpan(
          text: body.substring(start, end),
          style: TextStyle(
            backgroundColor: Color(f.drone.colorValue).withValues(alpha: 0.45),
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      cursor = end;
    }
    if (cursor < body.length) {
      children.add(TextSpan(text: body.substring(cursor)));
    }
    return children;
  }

  // -------------------------------------------------------------- drones
  List<Widget> _buildFlyingDrones(
    BoxConstraints constraints,
    MessageAnalysis? analysis,
  ) {
    if (analysis == null) return const [];
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final widgets = <Widget>[];
    for (var i = 0; i < DroneId.values.length; i++) {
      final drone = DroneId.values[i];
      final landed =
          _phase == FleetPhase.revealed ||
          _phase == FleetPhase.protected ||
          (_phase == FleetPhase.scanning && i < _revealedCount);
      final scanningThis = _phase == FleetPhase.scanning && i == _scanningIdx;
      // Docked: spread along the bottom edge-to-edge. Landed: spread down
      // the right side of the message area, in fleet order. Sizes shrink
      // a touch so six drones fit a phone-width screen without clipping.
      final dockLeft = 8.0 + i * ((width - 68) / (DroneId.values.length - 1));
      final dockTop = height - 78;
      final landLeft = width - 70;
      final landTop = 8.0 + i * ((height - 88) / DroneId.values.length);
      widgets.add(
        AnimatedPositioned(
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          left: landed ? landLeft : dockLeft,
          top: landed ? landTop : dockTop,
          child: DroneWidget(
            drone: drone,
            size: landed ? 56 : 52,
            scanning: scanningThis,
            badgePoints:
                (_phase == FleetPhase.revealed ||
                    _phase == FleetPhase.protected)
                ? analysis.pointsFor(drone)
                : null,
            onTap: () => _openDronePanel(drone),
          ),
        ),
      );
      // Scan beam from the scanning drone toward the message.
      if (scanningThis) {
        widgets.add(
          Positioned(
            left: 16,
            top: landTop + 26,
            child: Container(
              width: landLeft - 8,
              height: 2.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(drone.colorValue).withValues(alpha: 0),
                    Color(drone.colorValue),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  // -------------------------------------------------------- bottom panel
  Widget _buildBottomPanel(MessageAnalysis? analysis) {
    if (_walkSteps != null && analysis != null) {
      return _buildWalkthroughCard();
    }
    switch (_phase) {
      case FleetPhase.idle:
        return _panelShell(
          // Stacked, not side-by-side: at senior type sizes the button
          // needs the full width (a Row here overflowed by 33px).
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Drone Bay',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _selected == null
                    ? 'Pick a message above, then release the fleet.'
                    : '6 specialists ready — tap a message, then '
                          'release the fleet.',
                style: const TextStyle(color: Colors.white54, fontSize: 14.5),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kMagenta),
                  onPressed: _selected == null ? null : _releaseFleet,
                  icon: const Icon(Icons.radar),
                  label: const Text('Release the Fleet'),
                ),
              ),
            ],
          ),
        );
      case FleetPhase.scanning:
        return _panelShell(
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 12),
              Text(
                _scanningIdx >= 0
                    ? '${DroneId.values[_scanningIdx].label} scanning…'
                    : 'Fleet airborne…',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        );
      case FleetPhase.revealed:
        return _buildVerdictPanel(analysis!);
      case FleetPhase.protected:
        return _buildProtectedPanel(analysis!);
    }
  }

  Widget _panelShell({required Widget child}) {
    // Material (not a bare DecoratedBox) so the checklist's SwitchListTiles
    // have a proper ink ancestor, and a capped, scrollable height so the
    // tall PROTECTED panel never squeezes the message list away.
    return Material(
      color: const Color(0xFF12121C),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white10)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 430),
          child: SingleChildScrollView(child: child),
        ),
      ),
    );
  }

  Widget _buildVerdictPanel(MessageAnalysis analysis) {
    final verdict = analysis.verdict;
    final color = switch (verdict) {
      Verdict.dangerous => const Color(0xFFEF4444),
      Verdict.caution => const Color(0xFFF59E0B),
      Verdict.safe => const Color(0xFF22C55E),
    };
    return _panelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: analysis.riskScore),
                duration: const Duration(milliseconds: 900),
                builder: (context, value, child) => Text(
                  '$value',
                  style: TextStyle(
                    color: color,
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Text('/100 risk', style: TextStyle(color: Colors.white54)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      verdict.label,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      'Confidence ${analysis.confidence}% · '
                      '${analysis.flaggingDrones.length} of 6 drones flagged '
                      'something. Tap a drone to hear its case.',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 14.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (verdict != Verdict.safe)
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: kMagenta),
                    onPressed: () {
                      // Filing the report also lands the message in the
                      // Blocked tab's incident list (shared with family).
                      BlocklistStore.blockFromAnalysis(analysis);
                      setState(() => _phase = FleetPhase.protected);
                    },
                    icon: const Icon(Icons.shield),
                    label: const Text('Block & Report'),
                  ),
                )
              else
                const Expanded(
                  child: Text(
                    'No action needed — the fleet checked this one and it '
                    'holds up.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => setState(() {
                  _phase = FleetPhase.idle;
                  _revealedCount = 0;
                }),
                child: const Text('Reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProtectedPanel(MessageAnalysis analysis) {
    final report = buildReport(analysis, accountName: AccountStore.displayName);
    return _panelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_user, color: Color(0xFF22C55E)),
              SizedBox(width: 8),
              Text(
                'PROTECTED',
                style: TextStyle(
                  color: Color(0xFF22C55E),
                  fontWeight: FontWeight.w900,
                  fontSize: 17.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Sender blocked. Report ${report.incidentId} filed with '
            'T-Mobile — written automatically from the fleet\'s findings:',
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0B12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: Text(
              report.lines.join('\n'),
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Finish the job (the "after" checklist):',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          _checklistTile(
            'Turn on SIM-swap / port-out lock',
            _simLock,
            (v) => setState(() => _simLock = v),
          ),
          _checklistTile(
            'Set an account PIN you never reuse',
            _pinSet,
            (v) => setState(() => _pinSet = v),
          ),
          _checklistTile(
            'Agree a family safe word for "emergency" calls',
            _safeWord,
            (v) => setState(() => _safeWord = v),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kMagenta),
              onPressed: () {
                // Don't face it alone: the scan card lands in the Family
                // thread, and we jump straight there.
                FamilyStore.shareScan(analysis, _nowLabel());
                widget.onOpenFamily?.call();
              },
              icon: const Icon(Icons.family_restroom),
              label: Text('Share this scan with ${FamilyStore.contact.name}'),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: () => setState(() {
                _phase = FleetPhase.idle;
                _revealedCount = 0;
              }),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checklistTile(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 15.5),
      ),
      value: value,
      onChanged: onChanged,
      activeThumbColor: kMagenta,
    );
  }

  Widget _buildWalkthroughCard() {
    final steps = _walkSteps!;
    final step = steps[_walkIndex];
    final color = Color(step.drone.colorValue);
    return _panelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.record_voice_over, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  step.headline,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                'Step ${_walkIndex + 1} of ${steps.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 13.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            step.narration,
            style: const TextStyle(color: Colors.white, height: 1.4),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _walkIndex == 0
                    ? null
                    : () => setState(() => _walkIndex--),
                child: const Text('Back'),
              ),
              if (_walkIndex < steps.length - 1)
                FilledButton(
                  onPressed: () => setState(() => _walkIndex++),
                  child: const Text('Next tell'),
                )
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kMagenta),
                  onPressed: () => setState(() => _walkSteps = null),
                  icon: const Icon(Icons.check),
                  label: const Text('Got it'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
