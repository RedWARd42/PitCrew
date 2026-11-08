import '../contracts.dart';

enum PrefilterVerdict { localSafe, escalate }

class PrefilterResult {
  final PrefilterVerdict verdict;
  final String reason;
  const PrefilterResult(this.verdict, this.reason);
  bool get isLocalSafe => verdict == PrefilterVerdict.localSafe;
}

class Prefilter {
  static final _url = RegExp(r'https?://|www\.|\b[a-z0-9-]+\.(?:com|net|org|co|io|info|biz|xyz|top|me|us|ly|gl)\b', caseSensitive: false);
  static final _risky = RegExp(
      r'\$\s?\d|\b(?:usd|dollars?|payment|pay|bank|wire|refund|prize|winner|gift\s?card|bitcoin|crypto|invoice|'
      r'password|passcode|verify|verification|login|log in|sign in|code|pin|otp|ssn|social security|account|confirm|'
      r'urgent|urgently|immediately|asap|suspend(?:ed)?|expire[sd]?|final notice|last chance|act now|locked|unauthorized)\b',
      caseSensitive: false);
  static final _otp = RegExp(r'(?<!\d)\d{4,8}(?!\d)');

  /// Email: skip the network only for a saved contact with no links, no attachments and no risky words.
  PrefilterResult checkEmail(Sender sender, String subject, String body, {required int links, required int attachments}) {
    if (!sender.isContact) return const PrefilterResult(PrefilterVerdict.escalate, 'sender_not_contact');
    if (links > 0 || _url.hasMatch(body)) return const PrefilterResult(PrefilterVerdict.escalate, 'has_url');
    if (attachments > 0) return const PrefilterResult(PrefilterVerdict.escalate, 'has_attachment');
    if (_risky.hasMatch('$subject $body')) return const PrefilterResult(PrefilterVerdict.escalate, 'risky_keyword');
    return const PrefilterResult(PrefilterVerdict.localSafe, 'Known contact, no links, attachments, or money or credential words.');
  }

  PrefilterResult check(Sender sender, String text) {
    if (!sender.isContact) return const PrefilterResult(PrefilterVerdict.escalate, 'sender_not_contact');
    if (sender.kind == 'short_code' && _otp.hasMatch(text)) return const PrefilterResult(PrefilterVerdict.escalate, 'short_code_otp');
    if (_url.hasMatch(text)) return const PrefilterResult(PrefilterVerdict.escalate, 'has_url');
    if (_risky.hasMatch(text)) return const PrefilterResult(PrefilterVerdict.escalate, 'risky_keyword');
    return const PrefilterResult(PrefilterVerdict.localSafe, 'Known contact, no links, no money or credential words.');
  }
}
