
import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../services/stores.dart';

import 'blocked_screen.dart';
import 'call_screen.dart';
import 'emails_screen.dart';
import 'family_screen.dart';
import 'messages_screen.dart';

class SwatShell extends StatefulWidget {
  const SwatShell({super.key});

  @override
  State<SwatShell> createState() => _SwatShellState();
}

class _SwatShellState extends State<SwatShell> {
  int _index = 0;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();

    _sub = BlocklistStore.changes.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const CallScreen(),
          MessagesScreen(
            onOpenFamily: () => setState(() => _index = 4),
          ),
          const EmailsScreen(),
          const BlockedScreen(),
          const FamilyScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
        },
        backgroundColor: context.palette.panel,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.phone_outlined),
            selectedIcon: Icon(Icons.phone),
            label: 'Calls',
          ),
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
        ],
      ),
    );
  }
}
