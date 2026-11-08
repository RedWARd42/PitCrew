import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../contracts.dart';

class ScanException implements Exception {
  final String reason;
  ScanException(this.reason);
  @override
  String toString() => 'ScanException($reason)';
}

class ScanClient {
  String baseUrl, apiKey;
  final Duration timeout; // first attempt; retries use at most 4s, so a scan is bounded by ~timeout + 8s
  http.Client _http;
  final http.Client Function()? _factory; // non-null => we own the client and may replace it
  final Map<String, int> _gen = {}; // threadKey -> latest scan generation
  final Map<String, ScanResult> _cache = {}; // messageId -> result (session RAM)

  ScanClient({this.baseUrl = 'http://127.0.0.1:8000', this.apiKey = 'dev-key', http.Client? client, http.Client Function()? clientFactory, this.timeout = const Duration(seconds: 6)})
      : _factory = client == null ? (clientFactory ?? http.Client.new) : clientFactory,
        _http = client ?? (clientFactory ?? http.Client.new)();

  Duration get _retryTimeout => timeout < const Duration(seconds: 4) ? timeout : const Duration(seconds: 4);

  void _renewClient() {
    final f = _factory;
    if (f == null) return;
    final old = _http;
    _http = f();
    old.close();
  }

  Map<String, String> get _headers => {'Content-Type': 'application/json', 'X-Swarm-Key': apiKey};

  ScanResult? cached(String messageId) => _cache[messageId];

  /// Returns null when a newer scan for [threadKey] superseded this one.
  /// shortcut: superseded requests still finish on the wire (result dropped); use AbortableRequest if bandwidth matters.
  Future<ScanResult?> scan(ScanRequest req, {required String threadKey, bool useCache = true}) async {
    final isIncoming = req.mode == 'incoming';
    if (isIncoming && useCache) {
      final c = _cache[req.targetMessageId];
      if (c != null) return c;
    }
    final g = _gen[threadKey] = (_gen[threadKey] ?? 0) + 1;
    final body = jsonEncode(req.toJson());
    Object? lastErr;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (_gen[threadKey] != g) return null;
      try {
        final r = await _http.post(Uri.parse('$baseUrl/v1/scan'), headers: _headers, body: body).timeout(attempt == 0 ? timeout : _retryTimeout);
        if (_gen[threadKey] != g) return null;
        if (r.statusCode == 200) {
          final res = ScanResult.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map);
          if (isIncoming) _cache[req.targetMessageId] = res;
          return res;
        }
        lastErr = 'http_${r.statusCode}';
        if (r.statusCode < 500) break; // client errors will not improve on retry
      } on TimeoutException {
        lastErr = 'timeout';
      } catch (e) {
        lastErr = e.runtimeType.toString(); // never use e.toString(): may echo payload
        _renewClient(); // a stale keep-alive connection (adb reverse) fails fast; retry on a fresh socket
      }
    }
    if (_gen[threadKey] != g) return null;
    throw ScanException('$lastErr');
  }

  Future<bool> guardianAlert({required String requestId, required String category, required int riskScore, required String userAlias, String? to}) async {
    try {
      final r = await _http
          .post(Uri.parse('$baseUrl/v1/guardian/alert'), headers: _headers, body: jsonEncode({'requestId': requestId, 'category': category, 'riskScore': riskScore, 'userAlias': userAlias, if (to != null && to.isNotEmpty) 'to': to}))
          .timeout(timeout);
      return r.statusCode == 200 && (jsonDecode(r.body) as Map)['sent'] == true;
    } catch (_) {
      return false;
    }
  }
}
