// Table-driven PII redactor. Runs before ANY network call. URLs and the sender are kept.
class RedactResult {
  final String text;
  final Map<String, int> counts;
  const RedactResult(this.text, this.counts);
  List<Map<String, dynamic>> toRedactions() => [for (final e in counts.entries) {'type': e.key, 'count': e.value}];
}

bool luhnValid(String digits) {
  if (digits.length < 13 || digits.length > 19) return false;
  var sum = 0, alt = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    var d = digits.codeUnitAt(i) - 48;
    if (alt) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    alt = !alt;
  }
  return sum % 10 == 0;
}

class _Rule {
  final String type;
  final RegExp re;
  // Returns the replacement, or null to leave the match untouched.
  final String? Function(Match m) replace;
  const _Rule(this.type, this.re, this.replace);
}

class Redactor {
  static final _url = RegExp(r'(?:https?://|www\.)\S+|(?<![@\w.-])[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|net|org|co|io|info|biz|xyz|top|me|us|ly|gl)\b(?:/\S*)?', caseSensitive: false);
  static final _email = RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false);

  // Order matters: earlier rules replace text with digit-free placeholders so later rules cannot re-match.
  static final List<_Rule> _rules = [
    _Rule('EMAIL', _email, (_) => '<EMAIL>'),
    _Rule('CARD', RegExp(r'(?<![\d-])\d(?:[ -]?\d){12,18}(?![\d-])'), (m) => luhnValid(m[0]!.replaceAll(RegExp(r'\D'), '')) ? '<CARD>' : null),
    _Rule('SSN', RegExp(r'(?<![\d-])\d{3}-\d{2}-\d{4}(?![\d-])'), (_) => '<SSN>'),
    _Rule(
        'ADDR',
        RegExp(r'\b\d{1,5}\s+(?:[a-z]+\.?\s+){1,3}(?:street|st|avenue|ave|road|rd|boulevard|blvd|drive|dr|lane|ln|court|ct|way|parkway|pkwy|place|pl)\b\.?', caseSensitive: false),
        (_) => '<ADDR>'),
    // Standalone 4-8 digit codes; not part of phone numbers, money, times, decimals.
    _Rule('CODE', RegExp(r'(?<![\d\-.$,/:+])\d{4,8}(?![\d\-.,/:%])(?!\s?(?:am|pm)\b)', caseSensitive: false), (m) => '<CODE:${m[0]!.length}>'),
  ];

  /// [contactNames] are replaced by CONTACT (case-insensitive, whole word).
  RedactResult redact(String input, {Iterable<String> contactNames = const []}) {
    final counts = <String, int>{};
    void bump(String t) => counts[t] = (counts[t] ?? 0) + 1;

    // Park URLs behind digit-free tokens so no rule touches them.
    final urls = <String>[];
    var text = input.replaceAllMapped(_url, (m) {
      urls.add(m[0]!);
      return '\u0001${String.fromCharCode(0xE100 + urls.length - 1)}\u0001';
    });

    final names = contactNames.map((n) => n.trim()).where((n) => n.length > 1).toList()..sort((a, b) => b.length.compareTo(a.length));
    if (names.isNotEmpty) {
      final re = RegExp('(?<![A-Za-z])(?:${names.map(RegExp.escape).join('|')})(?![A-Za-z])', caseSensitive: false);
      text = text.replaceAllMapped(re, (_) {
        bump('CONTACT');
        return 'CONTACT';
      });
    }
    for (final r in _rules) {
      text = text.replaceAllMapped(r.re, (m) {
        final rep = r.replace(m);
        if (rep == null) return m[0]!;
        bump(r.type);
        return rep;
      });
    }
    text = text.replaceAllMapped(RegExp('\u0001([-])\u0001'), (m) => urls[m[1]!.codeUnitAt(0) - 0xE100]);
    return RedactResult(text, counts);
  }
}
