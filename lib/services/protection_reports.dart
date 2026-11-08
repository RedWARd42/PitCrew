import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../contracts.dart';
import '../core/redactor.dart';

/// A deliberately small local record. No sender, draft, request body or links
/// are copied from the conversation into saved history.
class ProtectionReport {
  const ProtectionReport({
    required this.id,
    required this.savedAt,
    required this.channel,
    required this.verdict,
    required this.riskScore,
    required this.confidence,
    required this.summary,
    required this.findings,
    this.focusDrone,
  });

  final String id, channel, verdict, summary;
  final DateTime savedAt;
  final int riskScore;
  final double confidence;
  final List<ReportFinding> findings;
  final String? focusDrone;

  String get source => channel == 'email' ? 'Gmail' : 'Google Messages';

  factory ProtectionReport.fromScan(
    ScanResult result,
    ScanRequest? request, {
    String? focusDrone,
  }) {
    final redactor = Redactor();
    String clean(String value) {
      final redacted = redactor.redact(value).text;
      return redacted.length > 1600
          ? '${redacted.substring(0, 1600)}…'
          : redacted;
    }

    return ProtectionReport(
      id: sha256.convert(utf8.encode(result.requestId)).toString(),
      savedAt: DateTime.now().toUtc(),
      channel: request?.channel == 'email' ? 'email' : 'sms',
      verdict: result.verdict,
      riskScore: result.riskScore,
      confidence: result.confidence,
      summary: clean(result.summary),
      focusDrone: focusDrone,
      findings: [
        for (final finding in result.findings.take(12))
          ReportFinding(
            drone: finding.drone,
            title: clean(finding.title),
            explanation: clean(finding.explanation),
            uncertainty: finding.whatWouldChangeMyMind == null
                ? null
                : clean(finding.whatWouldChangeMyMind!),
          ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'savedAt': savedAt.toIso8601String(),
    'channel': channel,
    'verdict': verdict,
    'riskScore': riskScore,
    'confidence': confidence,
    'summary': summary,
    'focusDrone': focusDrone,
    'findings': [for (final finding in findings) finding.toJson()],
  };

  factory ProtectionReport.fromJson(Map<String, dynamic> json) =>
      ProtectionReport(
        id: json['id'] as String,
        savedAt: DateTime.parse(json['savedAt'] as String),
        channel: json['channel'] as String,
        verdict: json['verdict'] as String,
        riskScore: json['riskScore'] as int,
        confidence: (json['confidence'] as num).toDouble(),
        summary: json['summary'] as String,
        focusDrone: json['focusDrone'] as String?,
        findings: [
          for (final finding in json['findings'] as List)
            ReportFinding.fromJson(Map<String, dynamic>.from(finding as Map)),
        ],
      );
}

class ReportFinding {
  const ReportFinding({
    required this.drone,
    required this.title,
    required this.explanation,
    this.uncertainty,
  });
  final String drone, title, explanation;
  final String? uncertainty;
  Map<String, dynamic> toJson() => {
    'drone': drone,
    'title': title,
    'explanation': explanation,
    'uncertainty': uncertainty,
  };
  factory ReportFinding.fromJson(Map<String, dynamic> json) => ReportFinding(
    drone: json['drone'] as String,
    title: json['title'] as String,
    explanation: json['explanation'] as String,
    uncertainty: json['uncertainty'] as String?,
  );
}

class ProtectionReportStore {
  static const storageKey = 'swat.protectionReports.v1';
  static const limit = 20;
  static final revision = ValueNotifier<int>(0);

  static Future<List<ProtectionReport>> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // overlay and activity use separate Flutter engines
    final reports = <ProtectionReport>[];
    for (final raw in prefs.getStringList(storageKey) ?? <String>[]) {
      try {
        reports.add(
          ProtectionReport.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        // One corrupt record must not hide the rest of the user's history.
      }
    }
    reports.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return reports.take(limit).toList();
  }

  static Future<void> save(ProtectionReport report) async {
    final reports = await load();
    reports.removeWhere((item) => item.id == report.id);
    reports.insert(0, report);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setStringList(storageKey, [
      for (final item in reports.take(limit)) jsonEncode(item.toJson()),
    ])) {
      throw StateError('Report could not be saved');
    }
    revision.value++;
  }

  static Future<void> delete(String id) async {
    final reports = await load();
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setStringList(storageKey, [
      for (final item in reports)
        if (item.id != id) jsonEncode(item.toJson()),
    ])) {
      throw StateError('Report could not be deleted');
    }
    revision.value++;
  }
}

/// Intent handoff carries only an opaque ID. The report stays in app-private
/// preferences, including when Android starts a fresh activity/engine.
class ReportHandoff {
  static const channel = MethodChannel('swat/reports');
  static final pending = ValueNotifier<String?>(null);
  static bool _started = false;

  static bool validId(String id) => RegExp(r'^[a-f0-9]{64}$').hasMatch(id);

  static Future<void> start() async {
    if (_started) return;
    _started = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'reportAvailable') await _takePending();
    });
    await _takePending();
  }

  static Future<void> _takePending() async {
    try {
      final id = await channel.invokeMethod<String>('takePendingReport');
      if (id != null && validId(id)) pending.value = id;
    } on MissingPluginException {
      // History remains usable on platforms without Android intent support.
    } on PlatformException {
      // No pending intent; the user can still open Reports directly.
    }
  }

  static Future<bool> openInApp(ProtectionReport report) async {
    await ProtectionReportStore.save(
      report,
    ); // finish persistence before launch
    try {
      return await channel.invokeMethod<bool>('openReport', {
            'reportId': report.id,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> returnToSource(String source) async {
    try {
      return await channel.invokeMethod<bool>('openSource', {
            'channel': source,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
