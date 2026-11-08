import 'dart:async';

import 'package:flutter/material.dart';

import '../models/family_and_blocked.dart';
import '../models/message.dart';
import '../services/device_services.dart';
import '../services/stores.dart';

/// The Blocked view — "show me what Swat stopped".
///
/// Squeek keeps incidents and a block list, shared with family helpers;
/// this is the same idea for texts: every blocked message stays visible
/// with its risk score, the categories (drones) that convicted it, who
/// blocked it (you, or your trusted contact sharing to your phone), and
/// whether it was also reported. Blocks can be undone — false positives
/// happen, and a list you can't correct is one nobody trusts.
class BlockedScreen extends StatefulWidget {
  const BlockedScreen({super.key});

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = BlocklistStore.changes.listen((_) {
      if (mounted) setState(() {});
    });
    // Pull in anything blocked from the overlay panel over Messages.
    OverlayService.nativeBlocks().then((blocks) {
      if (blocks.isNotEmpty) BlocklistStore.mergeNativeBlocks(blocks);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = BlocklistStore.entries;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121C),
        title: const Text(
          'Blocked & Reported',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Row(
              children: [
                _statCard('${BlocklistStore.count}', 'blocked\nmessages'),
                _statCard(
                  '${BlocklistStore.reportedCount}',
                  'reported to\nT-Mobile',
                ),
                _statCard(
                  '${BlocklistStore.sharedCount}',
                  'shared by\n${FamilyStore.contact.name}',
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Your block list is shared with your trusted contact — '
                'when either of you blocks a scammer, both phones are '
                'protected.',
                style: TextStyle(color: Colors.white54, fontSize: 14.5),
              ),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const Center(
                    child: Text(
                      'Nothing blocked yet.\nWhen the fleet convicts a '
                      'message and you tap Block & Report, it lands here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                    itemCount: entries.length,
                    itemBuilder: (context, i) => _entryCard(entries[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String value, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF15151F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entryCard(BlockedEntry e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF15151F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.block, size: 16, color: Color(0xFFEF4444)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  e.sender,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${e.riskScore}/100',
                  style: const TextStyle(
                    color: Color(0xFFF87171),
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            e.snippet,
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final d in e.categories)
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Color(d.colorValue).withValues(alpha: 0.18),
                  side: BorderSide(
                    color: Color(d.colorValue).withValues(alpha: 0.5),
                  ),
                  label: Text(
                    d.label,
                    style: TextStyle(color: Color(d.colorValue), fontSize: 13.5),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                e.status == BlockStatus.reported
                    ? Icons.outgoing_mail
                    : Icons.shield_outlined,
                size: 13,
                color: Colors.white54,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${e.status == BlockStatus.reported ? 'Blocked + reported' : 'Blocked'} '
                  '· ${e.incidentId} · by ${e.blockedBy} · ${e.whenLabel}',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ),
              TextButton(
                onPressed: () {
                  BlocklistStore.unblock(e.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${e.sender} unblocked — it can reach you again.',
                      ),
                    ),
                  );
                },
                child: const Text('Undo'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
