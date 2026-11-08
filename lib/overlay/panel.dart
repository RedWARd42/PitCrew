import 'dart:convert';

import 'package:flutter/material.dart';

import '../contracts.dart' as c;
import '../core/state_api.dart';
import '../services/protection_reports.dart';
import 'painters.dart';
import 'palette.dart';

/// Tap target with a restrained press scale. Always at least 48dp tall.
class Pressable extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final String? label;
  final double minHeight;
  const Pressable({
    super.key,
    required this.onTap,
    required this.child,
    this.label,
    this.minHeight = 48,
  });
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    excludeSemantics: widget.label != null,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: widget.minHeight, minWidth: 48),
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 90),
          child: Center(widthFactor: 1, child: widget.child),
        ),
      ),
    ),
  );
}

/// Bottom sheet content. Caller positions it and supplies the dim.
class SwarmPanel extends StatelessWidget {
  final SwarmState state;
  final String tab;
  final ValueChanged<String> onTab;
  final VoidCallback onClose;
  final double maxHeight;
  final Pal pal;
  const SwarmPanel({
    super.key,
    required this.state,
    required this.tab,
    required this.onTab,
    required this.onClose,
    required this.maxHeight,
    required this.pal,
  });

  /// Findings with one tab per drone (first finding wins).
  static List<c.Finding> findingsOf(SwarmState s) {
    final seen = <String>{};
    return [
      for (final f in [...?s.result?.findings, ...?s.draftRisk?.findings])
        if (seen.add(f.drone)) f,
    ];
  }

  static List<String> tabIds(SwarmState s) {
    final fs = findingsOf(s);
    return [
      'summary',
      for (final f in fs) f.drone,
      if (s.result?.riskSeries != null && !fs.any((f) => f.drone == 'drift'))
        'drift',
      'privacy',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ids = tabIds(state);
    final cur = ids.contains(tab) ? tab : 'summary';
    final bottom = MediaQuery.maybeOf(context)?.padding.bottom ?? 0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 40,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: pal.hairline,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Swat protection report',
                        style: ts(20, FontWeight.w700, pal.text, spacing: -0.3),
                      ),
                    ),
                  ),
                  Pressable(
                    label: 'Close report',
                    onTap: onClose,
                    child: SizedBox(
                      width: 48,
                      child: Icon(Icons.close_rounded, color: pal.dim),
                    ),
                  ),
                ],
              ),
            ),
            if (state.result != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: _OpenInSwat(state: state, tab: cur, pal: pal),
              ),
            SizedBox(
              height: 48,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final id in ids)
                      _TabChip(
                        id: id,
                        selected: id == cur,
                        pal: pal,
                        onTap: () => onTab(id),
                      ),
                  ],
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
                child: KeyedSubtree(key: ValueKey(cur), child: _content(cur)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(String id) {
    if (id == 'summary') return _Summary(state: state, pal: pal, onTab: onTab);
    if (id == 'privacy') return _Privacy(state: state, pal: pal);
    if (id == 'drift') return _DriftOnly(state: state, pal: pal);
    final f = findingsOf(state).firstWhere((f) => f.drone == id);
    return _FindingView(state: state, f: f, pal: pal);
  }
}

class _OpenInSwat extends StatefulWidget {
  const _OpenInSwat({
    required this.state,
    required this.tab,
    required this.pal,
  });
  final SwarmState state;
  final String tab;
  final Pal pal;
  @override
  State<_OpenInSwat> createState() => _OpenInSwatState();
}

class _OpenInSwatState extends State<_OpenInSwat> {
  bool _opening = false;
  String? _error;

  Future<void> _open() async {
    if (_opening) return;
    final result = widget.state.result;
    if (result == null) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final report = ProtectionReport.fromScan(
        result,
        widget.state.lastRequest,
        focusDrone: droneStyles.containsKey(widget.tab) ? widget.tab : null,
      );
      final opened = await ReportHandoff.openInApp(report);
      if (opened) {
        widget.state.setPanelOpen(false);
      } else if (mounted) {
        setState(
          () => _error =
              'Report saved on this phone. Open Swat → Reports to find it.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save this report. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed: _opening ? null : _open,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFE20074),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
        ),
        icon: _opening
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.open_in_new),
        label: Text(
          _opening ? 'Opening Swat…' : 'Open in Swat',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_error!, style: ts(15, FontWeight.w500, widget.pal.text)),
        ),
    ],
  );
}

class _TabChip extends StatelessWidget {
  final String id;
  final bool selected;
  final Pal pal;
  final VoidCallback onTap;
  const _TabChip({
    required this.id,
    required this.selected,
    required this.pal,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final label = switch (id) {
      'summary' => 'Summary',
      'privacy' => 'Privacy receipt',
      _ => styleFor(id).name,
    };
    final dot = droneStyles.containsKey(id) || id == 'drift'
        ? styleFor(id).color
        : null;
    return Semantics(
      selected: selected,
      button: true,
      label: '$label tab',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Container(
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? pal.text : pal.tonal,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dot != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  style: ts(
                    14,
                    FontWeight.w600,
                    selected ? pal.surface : pal.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final SwarmState state;
  final Pal pal;
  final ValueChanged<String> onTab;
  const _Summary({required this.state, required this.pal, required this.onTab});
  @override
  Widget build(BuildContext context) {
    final r = state.result ?? state.draftRisk;
    if (r == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          state.phase == ScanPhase.localSafe
              ? 'Checked on-device. Nothing left your phone.'
              : 'No report yet. The Swarm is watching this chat.',
          style: ts(16, FontWeight.w400, pal.dim, height: 1.4),
        ),
      );
    }
    final col = verdictColor(r.verdict);
    final cat = r.category?['label'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    verdictWord(r.verdict),
                    style: ts(
                      30,
                      FontWeight.w700,
                      col,
                      spacing: -0.6,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${confidenceLabel(r.confidence)} confident',
                    style: ts(14, FontWeight.w500, pal.dim),
                  ),
                ],
              ),
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${r.riskScore}',
                    style: ts(34, FontWeight.w700, pal.text, spacing: -1),
                  ),
                  TextSpan(
                    text: ' /100',
                    style: ts(14, FontWeight.w500, pal.dim),
                  ),
                ],
              ),
              semanticsLabel: 'Risk ${r.riskScore} out of 100',
            ),
          ],
        ),
        const SizedBox(height: 14),
        Semantics(
          label: 'Risk meter, ${r.riskScore} out of 100',
          child: SizedBox(
            height: 10,
            child: CustomPaint(
              painter: RiskMeterPainter(r.riskScore, col, pal.tonal),
              size: Size.infinite,
            ),
          ),
        ),
        if (cat != null) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: _Chip(cat, pal, bg: col.withValues(alpha: 0.14), fg: col),
          ),
        ],
        const SizedBox(height: 14),
        Text(r.summary, style: ts(16, FontWeight.w400, pal.text, height: 1.4)),
        if (_emailOf(state) case final em?) _EmailContext(em: em, pal: pal),
        if (findingsOf(state).isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'What the drones found',
            style: ts(13, FontWeight.w600, pal.dim, spacing: 0.2),
          ),
          const SizedBox(height: 4),
          for (final f in findingsOf(state))
            Pressable(
              label: '${styleFor(f.drone).name}: ${f.title}',
              onTap: () => onTab(f.drone),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: styleFor(f.drone).color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      f.title,
                      style: ts(16, FontWeight.w500, pal.text),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: pal.dim, size: 22),
                ],
              ),
            ),
        ],
        _Actions(state: state, actions: r.actions, pal: pal),
      ],
    );
  }
}

List<c.Finding> findingsOf(SwarmState s) => SwarmPanel.findingsOf(s);

/// What left the device is the source of truth; fall back to the parsed screen.
c.EmailInfo? _emailOf(SwarmState s) {
  final e =
      s.lastRequest?.email ??
      (s.screen?.channel == 'email' ? s.screen?.email : null);
  return e == null || (e.fromAddress.isEmpty && e.subject.isEmpty) ? null : e;
}

class _EmailContext extends StatelessWidget {
  final c.EmailInfo em;
  final Pal pal;
  const _EmailContext({required this.em, required this.pal});
  @override
  Widget build(BuildContext context) {
    final from = em.fromName.isEmpty
        ? em.fromAddress
        : '${em.fromName} <${em.fromAddress}>';
    final reply =
        em.replyTo != null &&
            em.replyTo!.isNotEmpty &&
            em.replyTo != em.fromAddress
        ? em.replyTo
        : null;
    Widget line(String k, String v, {bool warn = false}) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$k  ', style: ts(13, FontWeight.w600, pal.dim)),
            TextSpan(
              text: v,
              style: ts(
                14,
                warn ? FontWeight.w600 : FontWeight.w400,
                warn ? kRed : pal.text,
              ),
            ),
          ],
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pal.tonal,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line('From', from),
          if (em.subject.isNotEmpty) line('Subject', em.subject),
          if (reply != null) line('Reply-to', reply, warn: true),
        ],
      ),
    );
  }
}

/// Link tab for email: what the reader sees vs where the href really goes.
class _LinkCompare extends StatelessWidget {
  final c.EmailLink l;
  final Pal pal;
  const _LinkCompare({required this.l, required this.pal});
  @override
  Widget build(BuildContext context) {
    Widget box(String label, String v, Color accent) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: pal.tonal,
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: ts(12, FontWeight.w700, pal.dim, spacing: 0.3)),
            const SizedBox(height: 4),
            Text(
              v,
              style: ts(
                12.5,
                FontWeight.w500,
                pal.text,
                height: 1.35,
                mono: true,
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            box('Shown as', l.text, kGreen),
            const SizedBox(width: 8),
            box('Actually goes to', l.href, kRed),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Pal pal;
  final Color? bg, fg;
  const _Chip(this.text, this.pal, {this.bg, this.fg});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: bg ?? pal.tonal,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(text, style: ts(13, FontWeight.w600, fg ?? pal.text)),
  );
}

class _FindingView extends StatelessWidget {
  final SwarmState state;
  final c.Finding f;
  final Pal pal;
  const _FindingView({required this.state, required this.f, required this.pal});
  @override
  Widget build(BuildContext context) {
    final st = styleFor(f.drone);
    final unsure = f.confidence < 0.6;
    final actions = f.drone == 'warden'
        ? (state.draftRisk?.actions ?? const <c.Action>[])
        : (state.result?.actions ?? const <c.Action>[]);
    final series = f.drone == 'drift' ? state.result?.riskSeries : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: st.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${st.name} · ${st.watches}'.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ts(12, FontWeight.w700, pal.dim, spacing: 0.8),
              ),
            ),
            const SizedBox(width: 8),
            // Under 0.6: muted, outlined, never green/red certainty.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: unsure
                    ? Colors.transparent
                    : st.color.withValues(alpha: 0.16),
                border: unsure
                    ? Border.all(
                        color: pal.dim.withValues(alpha: 0.6),
                        width: 1.2,
                      )
                    : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                confidenceLabel(f.confidence),
                style: ts(
                  13,
                  unsure ? FontWeight.w500 : FontWeight.w700,
                  unsure ? pal.dim : pal.text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          header: true,
          child: Text(
            f.title,
            style: ts(
              22,
              FontWeight.w700,
              pal.text,
              spacing: -0.4,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          f.explanation,
          style: ts(16, FontWeight.w400, pal.text, height: 1.4),
        ),
        if (f.drone == 'link')
          if (_linkFor(state, f) case final l?) _LinkCompare(l: l, pal: pal),
        if (f.drone == 'carrier')
          for (final a
              in _emailOf(state)?.attachments ?? const <c.EmailAttachment>[])
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(Icons.attach_file_rounded, size: 18, color: pal.dim),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      a.name,
                      style: ts(14, FontWeight.w600, pal.text, mono: true),
                    ),
                  ),
                ],
              ),
            ),
        if (f.evidence.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in f.evidence)
                _Chip('${e.kind.replaceAll('_', ' ')}: ${e.value}', pal),
            ],
          ),
        ],
        if (f.whatWouldChangeMyMind != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: pal.tonal,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What would change my mind',
                  style: ts(13, FontWeight.w700, pal.dim, spacing: 0.2),
                ),
                const SizedBox(height: 4),
                Text(
                  f.whatWouldChangeMyMind!,
                  style: ts(15, FontWeight.w400, pal.text, height: 1.4),
                ),
              ],
            ),
          ),
        ],
        if (series != null) ...[
          const SizedBox(height: 16),
          _Drift(series: series, pal: pal),
        ],
        _Actions(state: state, actions: actions, pal: pal),
      ],
    );
  }
}

/// The email link a link finding is about: span [i,i] index, else the first whose text differs from its href.
c.EmailLink? _linkFor(SwarmState s, c.Finding f) {
  final ls = _emailOf(s)?.links ?? const <c.EmailLink>[];
  if (ls.isEmpty) return null;
  final i = f.anchor.span?.firstOrNull;
  if (f.anchor.field == 'link' && i != null && i >= 0 && i < ls.length) {
    return ls[i];
  }
  return ls.where((l) => l.text != l.href).firstOrNull ?? ls.first;
}

class _Drift extends StatelessWidget {
  final List<double> series;
  final Pal pal;
  const _Drift({required this.series, required this.pal});
  @override
  Widget build(BuildContext context) {
    final last = series.isEmpty ? 0.0 : series.last;
    final col = last > 0.66 ? kRed : (last > 0.33 ? kAmber : kGreen);
    return Semantics(
      label:
          'Risk over this conversation, from ${(series.first * 100).round()} to ${(last * 100).round()} out of 100 across ${series.length} messages',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Risk across this conversation',
            style: ts(13, FontWeight.w700, pal.dim, spacing: 0.2),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 84,
            child: CustomPaint(
              painter: SparklinePainter(series, col, pal.hairline),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('Message 1', style: ts(12, FontWeight.w500, pal.dim)),
              const Spacer(),
              Text(
                'Message ${series.length}',
                style: ts(12, FontWeight.w500, pal.dim),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DriftOnly extends StatelessWidget {
  final SwarmState state;
  final Pal pal;
  const _DriftOnly({required this.state, required this.pal});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: _Drift(series: state.result!.riskSeries!, pal: pal),
  );
}

class _Privacy extends StatelessWidget {
  final SwarmState state;
  final Pal pal;
  const _Privacy({required this.state, required this.pal});
  @override
  Widget build(BuildContext context) {
    final req = state.lastRequest;
    final p = (state.result ?? state.draftRisk)?.privacy ?? const {};
    final retained = p['retained'] == true ? 'yes' : 'no';
    final body = req == null
        ? 'Nothing was sent. ${state.localSafeReason ?? 'This message was checked on-device.'}'
        : const JsonEncoder.withIndent('  ').convert(req.toJson());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Text(
          req == null ? 'Stayed on your phone' : 'Exactly what left your phone',
          style: ts(20, FontWeight.w700, pal.text, spacing: -0.3),
        ),
        const SizedBox(height: 6),
        Text(
          state.lastRequest?.channel == 'email'
              ? 'Subject and body text are redacted on-device before they are sent.'
              : 'Text is redacted on-device before it is sent.',
          style: ts(15, FontWeight.w400, pal.dim, height: 1.35),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: pal.tonal,
            borderRadius: BorderRadius.circular(16),
          ),
          child: SelectableText(
            body,
            style: ts(12, FontWeight.w400, pal.text, height: 1.45, mono: true),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Retained by server: $retained',
          style: ts(16, FontWeight.w700, pal.text),
        ),
        const SizedBox(height: 2),
        Text(
          'AI model used: ${p['llmUsed'] == true ? 'yes' : 'no'}',
          style: ts(14, FontWeight.w500, pal.dim),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  final SwarmState state;
  final List<c.Action> actions;
  final Pal pal;
  const _Actions({
    required this.state,
    required this.actions,
    required this.pal,
  });
  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final sorted = [
      ...actions.where((a) => a.primary),
      ...actions.where((a) => !a.primary),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in sorted)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Pressable(
                label: a.label,
                onTap: () async {
                  await state.performAction(a.id, payload: a.payload);
                  // External intents hand off to another app: don't leave it dimmed behind our sheet.
                  if (const {'report_7726', 'call_official'}.contains(a.id)) {
                    state.setPanelOpen(false);
                  }
                },
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: a.primary ? pal.text : pal.tonal,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    a.label,
                    style: ts(
                      16,
                      FontWeight.w600,
                      a.primary ? pal.surface : pal.text,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
