import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../contracts.dart' as c;
import '../core/state_api.dart';
import 'painters.dart';
import 'palette.dart';
import 'panel.dart';

const double _kDrone = 48; // drone hit box (48dp touch target); the art is drawn at 40
const double _kHive = 56;
const double _kStride = 50; // horizontal spacing of a drone row

/// The bubble a finding anchors to. An email has exactly one body bubble, whatever id the backend echoes.
c.Bubble? bubbleFor(c.Anchor a, c.ScreenModel s) {
  if (s.channel == 'email') return s.bubbles.where((b) => b.direction == 'in').firstOrNull ?? s.bubbles.firstOrNull;
  for (final b in s.bubbles) {
    if (b.messageId == a.messageId) return b;
  }
  return null;
}

/// Resolves a finding anchor to a logical-px rect (screen px / density), or null when the
/// target is not in the parsed screen (e.g. scrolled out of the accessibility tree).
/// [drone] lets the email channel route carrier findings to the attachment card.
ui.Rect? resolveAnchor(c.Anchor a, c.ScreenModel s, double density, {String? drone}) {
  c.Rect? r;
  if (a.field == 'compose' || a.messageId == 'draft') {
    r = s.compose;
  } else if (a.field == 'sender' || a.messageId == 'header') {
    r = s.header;
  } else {
    final b = bubbleFor(a, s);
    if (b != null) {
      r = b.rect;
      final em = s.channel == 'email' ? s.email : null;
      if (em != null) {
        // Email: link span [i,i] is the link index; carrier points at the first attachment. Missing rect -> body.
        final i = a.field == 'link' && (a.span?.isNotEmpty ?? false) ? a.span!.first : -1;
        final er = i >= 0 && i < em.links.length ? em.links[i].rect : (drone == 'carrier' && em.attachments.isNotEmpty ? em.attachments.first.rect : null);
        if (er != null) r = er;
      } else if (a.field == 'link' && b.linkRects.isNotEmpty) {
        // Clamp to the bubble so a sloppy link rect never outlines outside it.
        final l = b.linkRects.first;
        final x0 = math.max(l.x, b.rect.x), y0 = math.max(l.y, b.rect.y);
        final x1 = math.min(l.x + l.w, b.rect.x + b.rect.w), y1 = math.min(l.y + l.h, b.rect.y + b.rect.h);
        if (x1 > x0 && y1 > y0) r = c.Rect(x0, y0, x1 - x0, y1 - y0);
      }
    }
  }
  return r == null ? null : ui.Rect.fromLTWH(r.x / density, r.y / density, r.w / density, r.h / density);
}

class _Drone {
  final String key;
  final c.Finding f;
  ui.Offset pos, target = ui.Offset.zero, vel = ui.Offset.zero;
  ui.Rect? anchor;
  ui.Offset? edge; // point on the bubble/header/compose edge the leader line ends at
  int arrow = 0;
  final double delay;
  double age = 0, land = 0;
  bool settled = false, hidden = false; // hidden: anchor not in the parsed screen
  _Drone(this.key, this.f, this.pos, this.delay);
}

/// Transparent overlay drawn over Google Messages. Consumes [SwarmState] only.
class SwarmOverlay extends StatefulWidget {
  final SwarmState state;
  const SwarmOverlay({super.key, required this.state});
  @override
  State<SwarmOverlay> createState() => _SwarmOverlayState();
}

class _SwarmOverlayState extends State<SwarmOverlay> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _drones = <String, _Drone>{};
  final _rootKey = GlobalKey(), _dockKey = GlobalKey(), _cardKey = GlobalKey();
  StreamSubscription<String>? _tapSub;
  Size _size = Size.zero;
  double _time = 0, _lastReportT = -1;
  bool _reduce = false;
  String _tab = 'summary';
  Object? _wardenDismissed;
  Map<String, c.Rect> _lastReported = const {};

  SwarmState get _s => widget.state;
  double get _d => _s.density <= 0 ? 1.0 : _s.density;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _listenTaps();
  }

  @override
  void didUpdateWidget(SwarmOverlay old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      _drones.clear();
      _listenTaps();
    }
  }

  void _listenTaps() {
    _tapSub?.cancel();
    _tapSub = _s.taps.listen((id) {
      if (id == 'hive') {
        _open('summary');
      } else if (id == 'send_guard') {
        // User tried to send while the Warden is active: (re)show the card, send nothing.
        if (_s.draftRisk != null) setState(() => _wardenDismissed = null);
      } else if (id.startsWith('drone:')) {
        _open(id.substring(6));
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tapSub?.cancel();
    super.dispose();
  }

  void _open(String tab) {
    setState(() => _tab = tab);
    _s.setPanelOpen(true);
  }

  double _dockBottom() {
    final cp = _s.screen?.compose;
    return cp == null ? 96 : math.max(12, _size.height - cp.y / _d + 12);
  }

  ui.Offset _hiveCenter() => ui.Offset(_size.width - 12 - _kHive / 2, _size.height - _dockBottom() - _kHive / 2);

  // ---- simulation -------------------------------------------------------------------------

  void _onTick(Duration el) {
    final t = el.inMicroseconds / 1e6;
    final dt = (t - _time).clamp(0.0, 0.05);
    _time = t;
    _retarget();
    _step(dt);
    _report();
    if (mounted) setState(() {});
  }

  void _retarget() {
    final scr = _s.screen;
    if (scr == null || !scr.visible || _size.isEmpty) {
      _drones.clear();
      return;
    }
    final items = <String, c.Finding>{};
    final seen = <String>{};
    final r = _s.result;
    if (_s.phase == ScanPhase.done && r != null) {
      for (final f in r.findings) {
        if (seen.add(f.drone)) items['r${r.requestId}|${f.drone}'] = f;
      }
    }
    final dr = _s.draftRisk;
    if (dr != null) {
      for (final f in dr.findings) {
        if (seen.add(f.drone)) items['d${identityHashCode(dr)}|${f.drone}'] = f;
      }
    }
    _drones.removeWhere((k, _) => !items.containsKey(k));
    var i = 0;
    for (final e in items.entries) {
      if (!_drones.containsKey(e.key)) {
        final warden = e.value.drone == 'warden';
        final origin = warden ? ui.Offset((scr.compose?.x ?? 0) / _d + 40, -30) : _hiveCenter();
        _drones[e.key] = _Drone(e.key, e.value, origin, _reduce ? 0 : 0.1 + i * 0.05);
      }
      i++;
    }
    final top = scr.header == null ? 0.0 : (scr.header!.y + scr.header!.h) / _d;
    final bottom = scr.compose == null ? _size.height : scr.compose!.y / _d;
    var kTop = 0, kBot = 0;
    final emailEdge = <_Drone>{}; // email drones whose leader ends on their own rect, not the row's anchor edge
    final groups = <String, int>{};
    for (final dn in _drones.values) {
      final a = dn.f.anchor;
      final rect = resolveAnchor(a, scr, _d, drone: dn.f.drone);
      final email = scr.channel == 'email';
      final isHeader = a.field == 'sender' || a.messageId == 'header';
      final isCompose = a.field == 'compose' || a.messageId == 'draft';
      dn.anchor = rect;
      dn.hidden = rect == null;
      dn.edge = null;
      if (rect == null) continue;
      if ((!isHeader && !isCompose && rect.bottom <= top)) {
        dn.arrow = -1;
        dn.target = ui.Offset(40.0 + 60 * kTop++, top + 34);
      } else if (!isHeader && !isCompose && rect.top >= bottom) {
        dn.arrow = 1;
        dn.target = ui.Offset(40.0 + 60 * kBot++, bottom - 34);
      } else {
        dn.arrow = 0;
        // Tidy row hugging the target's outer edge: above a bubble/compose, below the header.
        ui.Rect base = rect;
        final b = isHeader && !email || isCompose ? null : bubbleFor(a, scr);
        if (b != null) base = ui.Rect.fromLTWH(b.rect.x / _d, b.rect.y / _d, b.rect.w / _d, b.rect.h / _d);
        final emailHeader = email && isHeader && b != null;
        if (email && b != null && (emailHeader || rect != base)) emailEdge.add(dn); // email: one tidy row for every drone, header's included
        final k = groups.update('${base.left.round()},${base.top.round()}', (v) => v + 1, ifAbsent: () => 0);
        final x = (isHeader && !emailHeader ? _size.width - 12 - _kDrone / 2 - k * _kStride : base.left + 10 + _kDrone / 2 + k * _kStride).clamp(_kDrone / 2, math.max(_kDrone / 2, _size.width - _kDrone / 2)).toDouble();
        if (emailHeader) {
          dn.target = ui.Offset(x, math.max(base.top - 4 - _kDrone / 2, top + _kDrone / 2));
          dn.edge = ui.Offset(x, rect.bottom);
        } else if (isHeader) {
          dn.target = ui.Offset(x, base.bottom + 4 + _kDrone / 2);
          dn.edge = ui.Offset(x, base.bottom);
        } else {
          dn.target = ui.Offset(x, math.max(base.top - 4 - _kDrone / 2, top + _kDrone / 2));
          dn.edge = ui.Offset(x, base.top);
        }
      }
    }
    // Keep drones from overlapping each other: slide right, then wrap one row up.
    final placed = <ui.Offset>[];
    for (final dn in _drones.values.where((d) => !d.hidden)) {
      var t = dn.target;
      for (var n = 0; n < 12 && placed.any((p) => (p.dx - t.dx).abs() < _kStride - 1 && (p.dy - t.dy).abs() < _kStride - 1); n++) {
        t = t.dx + _kStride > _size.width - _kDrone / 2 ? ui.Offset(_kDrone / 2 + 6, t.dy - _kStride) : ui.Offset(t.dx + _kStride, t.dy);
      }
      dn.target = t;
      placed.add(t);
      // Email leaders end on the sender row's bottom edge / the link or attachment rect itself (x follows the final slot).
      final r = dn.anchor;
      if (r != null && emailEdge.contains(dn)) {
        final ex = t.dx.clamp(r.left, math.max(r.left, r.right)).toDouble();
        dn.edge = ui.Offset(ex, dn.f.anchor.field == 'sender' || dn.f.anchor.messageId == 'header' ? r.bottom : r.top);
      }
    }
  }

  void _step(double dt) {
    for (final dn in _drones.values.where((d) => !d.hidden)) {
      dn.age += dt;
      if (dn.age < dn.delay) continue;
      if (_reduce) {
        dn.pos = dn.target;
        dn.vel = ui.Offset.zero;
      } else {
        // Slightly underdamped spring (zeta ~0.8): quick launch, one soft settle.
        const k = 200.0, cd = 2 * 0.84 * 14.14;
        final n = (dt / (1 / 120)).ceil().clamp(1, 12);
        final h = dt / n;
        for (var i = 0; i < n; i++) {
          dn.vel += ((dn.target - dn.pos) * k - dn.vel * cd) * h;
          dn.pos += dn.vel * h;
        }
      }
      dn.settled = (dn.pos - dn.target).distance < 1.5 && dn.vel.distance < 8;
      final goal = dn.settled && dn.arrow == 0 && dn.anchor != null ? 1.0 : 0.0;
      dn.land = _reduce ? goal : dn.land + (goal - dn.land) * (1 - math.exp(-dt * 9));
    }
  }

  double _opacity(_Drone d) => _reduce ? (d.age >= d.delay ? 1 : 0) : ((d.age - d.delay) / 0.18).clamp(0.0, 1.0);

  c.Rect _px(ui.Rect r) => c.Rect(r.left * _d, r.top * _d, r.width * _d, r.height * _d);

  ui.Rect? _boxRect(GlobalKey k) {
    final ro = k.currentContext?.findRenderObject();
    final root = _rootKey.currentContext?.findRenderObject();
    if (ro is! RenderBox || root is! RenderBox || !ro.attached || !root.attached || !ro.hasSize) return null;
    return ro.localToGlobal(ui.Offset.zero, ancestor: root) & ro.size;
  }

  void _report() {
    final m = <String, c.Rect>{};
    if (_s.screen?.visible ?? false) {
      final hr = _boxRect(_dockKey);
      if (hr != null) m['hive'] = _px(hr);
      for (final dn in _drones.values.where((d) => !d.hidden)) {
        if (dn.settled && _opacity(dn) > 0.9) {
          m['drone:${dn.f.drone}'] = _px(ui.Rect.fromCenter(center: dn.pos, width: _kDrone, height: _kDrone));
        }
      }
      // Invisible guard over Send while a risky draft is pending, so the tap is intercepted.
      final send = _s.screen?.send;
      if (_s.draftRisk != null && send != null) m['send_guard'] = send;
      final cr = _boxRect(_cardKey);
      if (cr != null) m['card:warden'] = _px(cr);
    }
    var changed = m.length != _lastReported.length;
    if (!changed) {
      for (final e in m.entries) {
        final o = _lastReported[e.key];
        if (o == null || (o.x - e.value.x).abs() > 1.5 || (o.y - e.value.y).abs() > 1.5 || (o.w - e.value.w).abs() > 1.5 || (o.h - e.value.h).abs() > 1.5) {
          changed = true;
          break;
        }
      }
    }
    if (changed && (_time - _lastReportT > 0.1 || _lastReportT < 0)) {
      _lastReported = m;
      _lastReportT = _time;
      _s.reportHitTargets(m);
    }
  }

  // ---- build -------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    _reduce = mq?.disableAnimations ?? false;
    Widget body = ListenableBuilder(listenable: _s, builder: (_, _) => LayoutBuilder(builder: (ctx, cons) => _layer(ctx, cons.biggest)));
    if (mq == null) body = MediaQuery(data: MediaQueryData.fromView(View.of(context)), child: body);
    return Directionality(textDirection: TextDirection.ltr, child: Material(type: MaterialType.transparency, child: body));
  }

  (Color, String?) _status() {
    if (_s.draftRisk != null) return (kRed, 'Check your reply');
    final r = _s.result;
    return switch (_s.phase) {
      ScanPhase.scanning => (kNeutral, 'Scanning…'),
      ScanPhase.localSafe => (kGreen, 'Checked on-device'),
      ScanPhase.error => (kNeutral, 'Couldn\'t scan'),
      ScanPhase.done when r != null => (verdictColor(r.verdict), '${_short(r.verdict)} · ${(r.confidence * 100).round()}%'),
      _ => (kGreen, null),
    };
  }

  Widget _layer(BuildContext context, Size size) {
    _size = size;
    _retarget(); // anchors always follow the latest screen model (no one-frame stale outlines)
    final scr = _s.screen;
    if (scr == null || !scr.visible) return const SizedBox.shrink();
    final pal = Pal.of(MediaQuery.maybeOf(context)?.platformBrightness ?? Brightness.light);
    final (ring, chip) = _status();
    final scanning = _s.phase == ScanPhase.scanning;

    final leaders = [for (final d in _drones.values) if (!d.hidden && d.land > 0.01 && d.edge != null) Leader(d.pos, d.edge!, styleFor(d.f.drone).color, d.land)];
    final outlines = [for (final d in _drones.values) if (!d.hidden && d.land > 0.01 && d.anchor != null) Outline(d.anchor!, styleFor(d.f.drone).color, d.land)];
    ui.Rect? beam;
    if (scanning) {
      c.Bubble? b;
      for (final x in scr.bubbles) {
        if (x.messageId == _s.targetMessageId) b = x;
      }
      b ??= scr.bubbles.where((x) => x.direction == 'in').lastOrNull;
      if (b != null) beam = ui.Rect.fromLTWH(b.rect.x / _d, b.rect.y / _d, b.rect.w / _d, b.rect.h / _d);
    }
    final open = _s.panelOpen;
    final dur = _reduce ? Duration.zero : const Duration(milliseconds: 300);
    final dr = _s.draftRisk;

    return Stack(key: _rootKey, fit: StackFit.expand, clipBehavior: Clip.none, children: [
      if (outlines.isNotEmpty) IgnorePointer(child: CustomPaint(painter: OutlinesPainter(outlines, leaders, _band(scr)))),
      if (beam != null) IgnorePointer(child: CustomPaint(painter: ScanBeamPainter(beam, _reduce ? 0.5 : (_time / 1.6) % 1, const Color(0xFF5AC8FA)))),
      for (final (i, d) in _drones.values.indexed) if (!d.hidden) _droneWidget(i, d),
      _dock(ring, chip, scanning, pal),
      // After the dock so the status chip never sits on top of the card's buttons.
      if (dr != null && !identical(_wardenDismissed, dr)) _wardenCard(dr, scr, pal),
      IgnorePointer(ignoring: !open, child: AnimatedSwitcher(duration: dur, child: open ? GestureDetector(key: const ValueKey('dim'), behavior: HitTestBehavior.opaque, onTap: () => _s.setPanelOpen(false), child: ColoredBox(color: pal.scrim, child: const SizedBox.expand())) : const SizedBox.shrink())),
      Align(
        alignment: Alignment.bottomCenter,
        child: AnimatedSwitcher(
          duration: dur,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (w, a) => SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(a), child: w),
          child: open
              ? SwarmPanel(key: const ValueKey('panel'), state: _s, tab: _tab, pal: pal, maxHeight: size.height * 0.7, onTab: (t) => setState(() => _tab = t), onClose: () => _s.setPanelOpen(false))
              : const SizedBox.shrink(key: ValueKey('nopanel')),
        ),
      ),
    ]);
  }

  /// Visible area for highlights: between the header's bottom and the compose box's top.
  ui.Rect _band(c.ScreenModel scr) => ui.Rect.fromLTRB(0, scr.header == null ? 0 : (scr.header!.y + scr.header!.h) / _d, _size.width, scr.compose == null ? _size.height : scr.compose!.y / _d);

  Widget _droneWidget(int i, _Drone d) {
    final st = styleFor(d.f.drone);
    final bob = _reduce ? 0.0 : math.sin(_time * 2 * math.pi / 1.8 + i) * 1.2 * d.land;
    final where = d.arrow < 0 ? ' Its target is above, scroll up.' : (d.arrow > 0 ? ' Its target is below, scroll down.' : '');
    return Positioned(
      key: ValueKey('drone:${d.f.drone}'),
      left: d.pos.dx - _kDrone / 2,
      top: d.pos.dy - _kDrone / 2 + bob,
      width: _kDrone,
      height: _kDrone,
      child: Opacity(
        opacity: _opacity(d),
        child: Semantics(
          button: true,
          label: '${st.name} drone: ${d.f.title}.$where Double tap for details.',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _open(d.f.drone),
            child: Center(child: SizedBox(width: 40, height: 40, child: FittedBox(child: SizedBox(width: 56, height: 56, child: CustomPaint(painter: DronePainter(st.color, _reduce ? 0 : _time * 38 + i, shadow: d.land, arrow: d.arrow)))))),
          ),
        ),
      ),
    );
  }

  Widget _dock(Color ring, String? chip, bool scanning, Pal pal) {
    final pulse = _s.phase == ScanPhase.localSafe && !_reduce ? (_time / 2.4) % 1 : -1.0;
    final bob = _reduce ? 0.0 : math.sin(_time * 2 * math.pi / 3.2) * 2.5;
    return AnimatedPositioned(
      duration: _reduce ? Duration.zero : const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      right: 12,
      bottom: _dockBottom(),
      child: Semantics(
        button: true,
        label: 'Signal Swarm, ${chip ?? 'protected'}. Double tap to open the report.',
        excludeSemantics: true,
        child: GestureDetector(
          key: _dockKey,
          behavior: HitTestBehavior.opaque,
          onTap: () => _s.panelOpen ? _s.setPanelOpen(false) : _open('summary'),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            AnimatedSwitcher(
              duration: _reduce ? Duration.zero : const Duration(milliseconds: 200),
              transitionBuilder: (w, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(a), alignment: Alignment.bottomRight, child: w)),
              child: chip == null
                  ? const SizedBox.shrink(key: ValueKey('nochip'))
                  : Padding(
                      key: ValueKey(chip),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(color: pal.surface.withValues(alpha: 0.82), borderRadius: BorderRadius.circular(16), border: Border.all(color: pal.hairline, width: 0.5)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Container(width: 7, height: 7, decoration: BoxDecoration(color: ring, shape: BoxShape.circle)),
                              const SizedBox(width: 7),
                              Text(chip, style: ts(13, FontWeight.w600, pal.text, spacing: -0.1)),
                            ]),
                          ),
                        ),
                      ),
                    ),
            ),
            Transform.translate(
              offset: Offset(0, bob),
              child: SizedBox(width: _kHive, height: _kHive, child: CustomPaint(painter: HivePainter(ring, _time, scanning: scanning, pulse: pulse))),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _wardenCard(c.ScanResult dr, c.ScreenModel scr, Pal pal) {
    final f = dr.findings.isEmpty ? null : dr.findings.first;
    final composeTop = scr.compose == null ? _size.height - 96 : scr.compose!.y / _d;
    final actions = dr.actions.isNotEmpty ? dr.actions : const [c.Action('dont_send', 'Don\'t send', primary: true), c.Action('send_anyway', 'Send anyway')];
    final sorted = [...actions.where((a) => a.primary), ...actions.where((a) => !a.primary)];
    const amber = Color(0xFFFBBF24);
    return Positioned(
      left: 12,
      right: 12,
      bottom: _size.height - composeTop + 8 + _kDrone + 8,
      child: Semantics(
        liveRegion: true,
        container: true,
        label: 'Hold up. ${f?.title ?? ''}. ${f?.explanation ?? ''}',
        child: Container(
          key: _cardKey,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: pal.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: amber.withValues(alpha: 0.7), width: 1.5),
            boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 32, offset: Offset(0, 10))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(width: 10, height: 10, decoration: const BoxDecoration(color: amber, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('WARDEN', style: ts(12, FontWeight.w700, pal.dim, spacing: 0.8)),
            ]),
            const SizedBox(height: 8),
            Text('Hold up', style: ts(26, FontWeight.w700, pal.text, spacing: -0.5)),
            if (f != null) ...[
              const SizedBox(height: 6),
              Text(f.title, style: ts(16, FontWeight.w600, pal.text)),
              const SizedBox(height: 4),
              Text(f.explanation, style: ts(15, FontWeight.w400, pal.dim, height: 1.4)),
            ],
            const SizedBox(height: 14),
            for (final a in sorted)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Pressable(
                  label: a.label,
                  onTap: () {
                    _s.performAction(a.id, payload: a.payload);
                    setState(() => _wardenDismissed = dr);
                  },
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: a.primary ? amber : Colors.transparent, borderRadius: BorderRadius.circular(14)),
                    child: Text(a.label, style: ts(16, FontWeight.w600, a.primary ? const Color(0xFF1C1C1E) : pal.dim)),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

String _short(String v) => switch (v) { 'scam' => 'Scam', 'suspicious' => 'Suspicious', 'safe' => 'Safe', _ => 'Not sure' };
