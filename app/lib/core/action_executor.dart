import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'bridge.dart';
import 'scan_client.dart';

/// What an action needs from the current scan (kept in RAM by the controller).
class ActionContext {
  final String requestId, senderRaw, originalText, categoryId;
  final int riskScore;
  const ActionContext({this.requestId = '', this.senderRaw = '', this.originalText = '', this.categoryId = 'unknown', this.riskScore = 0});
}

typedef UriLauncher = Future<bool> Function(Uri uri);

Future<bool> _defaultLaunch(Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);

class ActionExecutor {
  final SwarmBridge bridge;
  final ScanClient client;
  final UriLauncher launch;
  ActionExecutor({required this.bridge, required this.client, UriLauncher? launch}) : launch = launch ?? _defaultLaunch;

  static const guardianAliasKey = 'swarm.guardianAlias';
  static const _saltKey = 'swarm.salt', _safeKey = 'swarm.safeSenders';

  /// Runs the action and returns a short, honest status line for the UI.
  Future<String> run(String id, ActionContext ctx, {Map<String, String>? payload}) async {
    try {
      return await _run(id, ctx, payload);
    } catch (_) {
      return 'That did not work on this phone. Please try again.'; // never surface raw errors (may echo content)
    }
  }

  Future<String> _run(String id, ActionContext ctx, Map<String, String>? payload) async {
    switch (id) {
      case 'report_7726':
        // The user still has to press send in their SMS app.
        final ok = await launch(Uri.parse('sms:7726?body=${Uri.encodeComponent(ctx.originalText)}'));
        return ok ? 'Opened a text to 7726 with the message. Press send to report it.' : 'Could not open your SMS app.';
      case 'call_official':
        final n = payload?['number'];
        if (n == null || n.isEmpty) return 'No official number available for this sender.';
        final ok = await launch(Uri(scheme: 'tel', path: n)); // dial screen only
        return ok ? 'Opened the dialer. Press call when ready.' : 'Could not open the dialer.';
      case 'alert_guardian':
        final p = await SharedPreferences.getInstance();
        final phone = p.getString('guardian_phone');
        if (phone == null || phone.isEmpty) return 'Set up a guardian first.';
        final alias = p.getString(guardianAliasKey) ?? 'your family member'; // the protected user's name, shown to the guardian
        final sent = await client.guardianAlert(requestId: ctx.requestId, category: ctx.categoryId, riskScore: ctx.riskScore, userAlias: alias, to: phone);
        return sent ? 'Your guardian was alerted. No message content was shared.' : 'Could not reach your guardian right now.';
      case 'block_sender':
        await bridge.action(id, payload, ctx.requestId);
        return "Android doesn't let apps block numbers. Opening settings: in Messages, open the chat menu and choose Block & report spam.";
      case 'mark_safe':
        await markSafe(ctx.senderRaw);
        return 'Marked as safe. We will not scan this sender again on this phone.';
      case 'dont_send':
      case 'send_anyway':
      case 'delete':
        await bridge.action(id, payload, ctx.requestId);
        return 'Done.';
      default:
        return 'Unknown action.';
    }
  }

  Future<String> _hash(SharedPreferences p, String sender) async {
    var salt = p.getString(_saltKey);
    if (salt == null) {
      final r = Random.secure();
      salt = base64Url.encode(List.generate(16, (_) => r.nextInt(256)));
      await p.setString(_saltKey, salt);
    }
    return sha256.convert(utf8.encode('$salt|${sender.trim().toLowerCase()}')).toString();
  }

  Future<void> markSafe(String sender) async {
    final p = await SharedPreferences.getInstance();
    final l = p.getStringList(_safeKey) ?? [];
    final h = await _hash(p, sender);
    if (!l.contains(h)) await p.setStringList(_safeKey, [...l, h]);
  }

  Future<bool> isMarkedSafe(String sender) async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_safeKey) ?? const []).contains(await _hash(p, sender));
  }
}
