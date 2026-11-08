import 'package:flutter/material.dart';

import '../overlay/palette.dart';
import '../services/protection_reports.dart';
import '../services/stores.dart';
import '../theme/app_palette.dart';
import '../widgets/drone_widget.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.onOpenFamily});
  final VoidCallback onOpenFamily;
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with WidgetsBindingObserver {
  List<ProtectionReport> _reports = [];
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ProtectionReportStore.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ProtectionReportStore.revision.removeListener(_load);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final reports = await ProtectionReportStore.load();
      if (mounted) {
        setState(() {
          _reports = reports;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load saved reports. Pull down to retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.palette.background,
    appBar: AppBar(
      title: const Text('Protection reports'),
      backgroundColor: context.palette.panel,
      actions: const [ThemeToggleButton()],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Your findings, ready when you need them',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Reports you open from the overlay stay on this phone. Only redacted findings are saved. The latest ${ProtectionReportStore.limit} are kept.',
            style: TextStyle(color: context.palette.secondaryText),
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Text(_error!)
          else if (_reports.isEmpty) ...[
            const SizedBox(height: 28),
            const Icon(
              Icons.fact_check_outlined,
              size: 56,
              color: Color(0xFFE20074),
            ),
            const SizedBox(height: 16),
            Text(
              'No saved reports yet',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'When a drone flags a message in Google Messages or Gmail, open its report and tap “Open in Swat”.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.secondaryText),
            ),
          ] else
            for (final report in _reports)
              Card(
                color: context.palette.panel,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Icon(
                    report.channel == 'email'
                        ? Icons.mail_outline
                        : Icons.message_outlined,
                    color: const Color(0xFFE20074),
                  ),
                  title: Text(
                    '${verdictWord(report.verdict)} · ${report.riskScore}/100',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${report.source} · ${_time(report.savedAt)}\n${report.summary}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProtectionReportScreen(
                        report: report,
                        onOpenFamily: widget.onOpenFamily,
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    ),
  );
}

String _time(DateTime date) {
  final local = date.toLocal();
  return '${local.month}/${local.day} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class ProtectionReportScreen extends StatelessWidget {
  const ProtectionReportScreen({
    super.key,
    required this.report,
    required this.onOpenFamily,
  });
  final ProtectionReport report;
  final VoidCallback onOpenFamily;

  Future<void> _delete(BuildContext context) async {
    try {
      await ProtectionReportStore.delete(report.id);
      if (context.mounted) Navigator.of(context).pop();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete this report. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = verdictColor(report.verdict);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('Protection report'),
        backgroundColor: palette.panel,
        actions: [
          IconButton(
            tooltip: 'Delete saved report',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${report.source} · ${_time(report.savedAt)}',
            style: TextStyle(color: palette.secondaryText),
          ),
          const SizedBox(height: 12),
          Text(
            verdictWord(report.verdict),
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: color),
          ),
          const SizedBox(height: 8),
          Text(
            'Risk ${report.riskScore}/100 · ${confidenceLabel(report.confidence)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          Text(report.summary),
          const SizedBox(height: 24),
          Text(
            'What the drones found',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          for (final finding in report.findings)
            Builder(
              builder: (context) {
                final style = styleFor(finding.drone);
                return Card(
                  color: palette.panel,
                  child: ExpansionTile(
                    key: ValueKey('finding:${finding.drone}'),
                    initiallyExpanded:
                        report.focusDrone == null ||
                        report.focusDrone == finding.drone,
                    leading: DroneArtwork(
                      color: style.color,
                      icon: style.icon,
                      size: 40,
                    ),
                    title: Text(
                      style.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(finding.title),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(finding.explanation),
                      if (finding.uncertainty != null) ...[
                        const SizedBox(height: 14),
                        const Text(
                          'What would change my mind',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(finding.uncertainty!),
                      ],
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 24),
          Text(
            'A calm next step',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            report.verdict == 'safe'
                ? 'Stay cautious if the message changes or asks for a code. A scan is a check, not a guarantee.'
                : 'Pause before replying, paying or sharing a code. Reach the organization through its official app or a number you already trust.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.family_restroom_outlined),
            label: const Text('Add to Family chat'),
            onPressed: () {
              FamilyStore.shareProtectionReport(report);
              onOpenFamily();
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.arrow_back),
            label: Text('Return to ${report.source}'),
            onPressed: () async {
              if (!await ReportHandoff.returnToSource(report.channel) &&
                  context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Could not open ${report.source} on this device.',
                    ),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Saved only on this phone'),
            subtitle: const Text(
              'This is a redacted snapshot from the time of the scan. The original conversation is not saved here. You can delete this report using the trash button.',
            ),
          ),
        ],
      ),
    );
  }
}
