import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../services/stores.dart';
import '../services/protection_reports.dart';
import 'blocked_screen.dart';
import 'emails_screen.dart';
import 'family_screen.dart';
import 'messages_screen.dart';
import 'reports_screen.dart';

/// App shell: three tabs, one protection loop.
///
///  * Messages — the inbox and the fleet.
///  * Blocked — what Swat stopped (incidents + shared block list).
///  * Family — the trusted contact: scan-sharing, safe word, real
///    call/text hand-offs.
class SwatShell extends StatefulWidget {
  const SwatShell({super.key});

  @override
  State<SwatShell> createState() => _SwatShellState();
}

class _SwatShellState extends State<SwatShell> {
  int _index = 0;
  StreamSubscription<void>? _sub;
  bool _openingReport = false;

  @override
  void initState() {
    super.initState();
    _sub = BlocklistStore.changes.listen((_) {
      if (mounted) setState(() {});
    });
    ReportHandoff.pending.addListener(_openPendingReport);
    unawaited(ReportHandoff.start());
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingReport());
  }

  void _showFamily() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _index = 3);
  }

  Future<void> _openPendingReport() async {
    if (!mounted || _openingReport || ReportHandoff.pending.value == null) {
      return;
    }
    _openingReport = true;
    final id = ReportHandoff.pending.value!;
    ReportHandoff.pending.value = null;
    try {
      final reports = await ProtectionReportStore.load();
      if (!mounted) return;
      setState(() => _index = 4);
      Navigator.of(context).popUntil((route) => route.isFirst);
      final matches = reports.where((report) => report.id == id);
      if (matches.isNotEmpty) {
        unawaited(
          Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => ProtectionReportScreen(
                report: matches.first,
                onOpenFamily: _showFamily,
              ),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This report is no longer saved. Your other reports are below.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open the report. Please try the Reports tab.',
            ),
          ),
        );
      }
    } finally {
      _openingReport = false;
      if (mounted && ReportHandoff.pending.value != null) {
        unawaited(_openPendingReport());
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    ReportHandoff.pending.removeListener(_openPendingReport);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          MessagesScreen(onOpenFamily: () => setState(() => _index = 3)),
          const EmailsScreen(),
          const BlockedScreen(),
          const FamilyScreen(),
          ReportsScreen(onOpenFamily: _showFamily),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: context.palette.panel,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.message_outlined),
            selectedIcon: Icon(Icons.message),
            label: 'Messages',
          ),
          const NavigationDestination(
            icon: Icon(Icons.mail_outline),
            selectedIcon: Icon(Icons.mail),
            label: 'Emails',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: BlocklistStore.count > 0,
              label: Text('${BlocklistStore.count}'),
              child: const Icon(Icons.block_outlined),
            ),
            selectedIcon: const Icon(Icons.block),
            label: 'Blocked',
          ),
          const NavigationDestination(
            icon: Icon(Icons.family_restroom_outlined),
            selectedIcon: Icon(Icons.family_restroom),
            label: 'Family',
          ),
          const NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'Reports',
          ),
        ],
      ),
    );
  }
}
