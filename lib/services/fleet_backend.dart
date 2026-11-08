import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/message.dart';
import 'account_store.dart';
import 'walkthrough.dart';

/// The fleet backend client — shared blocklist + report store in
/// **MongoDB Atlas** ([MLH] Best Use of MongoDB Atlas), served by the
/// Node service in `backend/`.
///
/// Optional and invisible when unset: Block & Report mirrors the
/// incident to the backend only when a URL is supplied at run time:
///
///   flutter run --dart-define=FLEET_BACKEND_URL=http://host:8787
///
/// The on-device block + report always happen regardless; a failed
/// sync never blocks or changes the in-app result.
const String kFleetBackendUrl = String.fromEnvironment('FLEET_BACKEND_URL');

bool get fleetBackendConfigured => kFleetBackendUrl.isNotEmpty;

/// The JSON document the backend stores for one filed report — the
/// same fields the Atlas `reports` collection validates server-side.
Map<String, dynamic> reportPayload(
  MessageAnalysis a, {
  String? accountName,
}) {
  final report = buildReport(a, accountName: accountName);
  return {
    'incidentId': report.incidentId,
    'sender': a.message.sender,
    'riskScore': a.riskScore,
    'verdict': a.verdict.label,
    'topFlags': [
      for (final d in a.flaggingDrones)
        for (final f in a.findingsFor(d).where((f) => f.isFlag))
          '${d.label}: ${f.title}',
    ],
    'account': accountName ?? AccountStore.displayName,
  };
}

class FleetBackend {
  /// Mirror one filed report to the backend. Returns whether it
  /// landed; callers treat this as fire-and-forget.
  static Future<bool> syncReport(
    MessageAnalysis analysis, {
    String? accountName,
    http.Client? client,
  }) async {
    if (!fleetBackendConfigured) return false;
    final c = client ?? http.Client();
    try {
      final res = await c
          .post(
            Uri.parse('$kFleetBackendUrl/reports'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(
              reportPayload(analysis, accountName: accountName),
            ),
          )
          .timeout(const Duration(seconds: 8));
      return res.statusCode == 201;
    } catch (_) {
      return false;
    } finally {
      if (client == null) c.close();
    }
  }
}
