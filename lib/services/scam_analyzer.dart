/// The Swat detection engine.
///
/// Pure Dart, no Flutter imports: every drone is a function from a
/// [ChatMessage] to a list of [Finding]s, so the whole engine is unit
/// tested in `test/scam_analyzer_test.dart` and runs identically on a real
/// SMS pulled from the Android SMS store and on the synthetic demo inbox.
///
/// Design rules (from the T-Mobile "Safe Signal" prompt):
///  * Detection is a core piece, not the whole product — findings carry
///    plain-English explanations and next steps, not just a score.
///  * Honest confidence — clean checks are reported too (0-point findings),
///    and the confidence number reflects how many independent signals agree.
///  * Synthetic data only — nothing here sends message content anywhere.
library;

import '../models/message.dart';

/// A brand that scammers impersonate, with the domains it actually uses.
class Brand {
  const Brand({
    required this.name,
    required this.officialDomains,
    required this.officialShortCodes,
    required this.aliases,
  });

  final String name;
  final Set<String> officialDomains;
  final Set<String> officialShortCodes;
  final List<String> aliases;
}

const List<Brand> knownBrands = [
  Brand(
    name: 'T-Mobile',
    officialDomains: {
      't-mobile.com',
      'tmobile.com',
      't-mobile.mymobileapp.com',
    },
    officialShortCodes: {'456', '2294', '4629'},
    aliases: ['t-mobile', 'tmobile', 't mobile'],
  ),
  Brand(
    name: 'Chase',
    officialDomains: {'chase.com', 'jpmorganchase.com'},
    officialShortCodes: {'24273', '33748'},
    aliases: ['chase', 'jpmorgan'],
  ),
  Brand(
    name: 'Bank of America',
    officialDomains: {'bankofamerica.com', 'bofa.com'},
    officialShortCodes: {'692632'},
    aliases: ['bank of america', 'bofa'],
  ),
  Brand(
    name: 'USPS',
    officialDomains: {'usps.com'},
    officialShortCodes: {'28777'},
    aliases: ['usps', 'u.s. postal', 'postal service'],
  ),
  Brand(
    name: 'UPS',
    officialDomains: {'ups.com'},
    officialShortCodes: {'69877'},
    aliases: ['ups'],
  ),
  Brand(
    name: 'FedEx',
    officialDomains: {'fedex.com'},
    officialShortCodes: {'29372'},
    aliases: ['fedex'],
  ),
  Brand(
    name: 'Amazon',
    officialDomains: {'amazon.com', 'amazon.co.uk'},
    officialShortCodes: {'262966'},
    aliases: ['amazon'],
  ),
  Brand(
    name: 'Apple',
    officialDomains: {'apple.com', 'icloud.com'},
    officialShortCodes: {},
    aliases: ['apple', 'icloud'],
  ),
  Brand(
    name: 'IRS',
    officialDomains: {'irs.gov'},
    officialShortCodes: {},
    aliases: ['irs', 'internal revenue'],
  ),
];

const Set<String> urlShorteners = {
  'bit.ly',
  'tinyurl.com',
  't.co',
  'goo.gl',
  'rb.gy',
  'is.gd',
  'cutt.ly',
  'shorturl.at',
};

class ScamAnalyzer {
  const ScamAnalyzer();

  /// Run the whole fleet over one message.
  MessageAnalysis analyze(ChatMessage message) {
    final findings = <Finding>[
      ...angler(message),
      ...link(message),
      ...scanner(message),
      ...pressure(message),
      ...impersonator(message),
      ...swap(message),
    ];

    final (riskScore, confidence) = scoreFindings(findings);
    return MessageAnalysis(
      message: message,
      findings: findings,
      riskScore: riskScore,
      confidence: confidence,
    );
  }

  /// Shared aggregation, also used by the email analyzer: the strongest
  /// flag counts in full, the rest at a discount, so one loud tell can't
  /// fake a consensus and independent tells stack. Confidence reflects
  /// how many *different* drones flagged something.
  static (int, int) scoreFindings(List<Finding> findings) {
    final flagPoints =
        findings.where((f) => f.isFlag).map((f) => f.points).toList()
          ..sort((a, b) => b.compareTo(a));
    var risk = 0.0;
    for (var i = 0; i < flagPoints.length; i++) {
      risk += flagPoints[i] * (i == 0 ? 1.0 : (i == 1 ? 0.7 : 0.45));
    }
    final riskScore = risk.round().clamp(0, 100);

    final flagging = findings
        .where((f) => f.isFlag)
        .map((f) => f.drone)
        .toSet()
        .length;
    final confidence = flagging == 0
        ? 92 // several independent clean checks still say a lot
        : (55 + flagging * 12).clamp(55, 97);
    return (riskScore, confidence);
  }

  // ---------------------------------------------------------------- Angler
  /// Sender spoofing: does the sender match who the message claims to be?
  List<Finding> angler(ChatMessage m) {
    final brand = claimedBrand(m);
    final sender = m.sender.trim();
    final isShortCode = RegExp(r'^\d{3,6}$').hasMatch(sender);
    final isLongNumber = RegExp(r'^\+?\d[\d\s\-()]{6,}$').hasMatch(sender);

    if (brand != null && brand.officialShortCodes.contains(sender)) {
      return [
        Finding(
          drone: DroneId.angler,
          title: 'Verified sender',
          detail:
              'This came from $sender, a registered ${brand.name} short code. '
              'Carriers verify who can send from a short code, so this is a '
              'strong sign the message is really from ${brand.name}.',
          points: 0,
        ),
      ];
    }
    if (brand != null && isLongNumber) {
      return [
        Finding(
          drone: DroneId.angler,
          title: 'Spoofed sender',
          detail:
              'The message claims to be ${brand.name}, but it came from an '
              'ordinary phone number ($sender). ${brand.name} sends account '
              'alerts from a registered short code'
              '${brand.officialShortCodes.isEmpty ? '' : ' (e.g. ${brand.officialShortCodes.first})'}, '
              'not from a random number. Scammers rent numbers like this by '
              'the thousand.',
          points: 34,
          spanStart: 0,
          spanEnd: 0,
        ),
      ];
    }
    if (brand != null && !isShortCode) {
      return [
        Finding(
          drone: DroneId.angler,
          title: 'Unverified sender name',
          detail:
              'The sender shows as "$sender", but display names can be set '
              'to anything — they are not verified by the carrier.',
          points: 18,
        ),
      ];
    }
    return [
      const Finding(
        drone: DroneId.angler,
        title: 'Sender check passed',
        detail:
            'Nothing about the sender contradicts who the message claims '
            'to be.',
        points: 0,
      ),
    ];
  }

  // ------------------------------------------------------------------ Link
  static final RegExp _urlPattern = RegExp(
    r'((?:https?://)?(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(?:/[^\s]*)?)',
  );

  List<String> extractUrls(String text) {
    final urls = <String>[];
    for (final match in _urlPattern.allMatches(text)) {
      var url = match.group(0)!;
      // The pattern can swallow a leading word like "at" in "at t-mobile.com"
      // only when glued; trailing punctuation is the common case.
      url = url.replaceAll(RegExp(r'[.,;:!?\)\]]+$'), '');
      if (url.contains('.') && !url.startsWith(' ')) urls.add(url);
    }
    return urls;
  }

  String hostOf(String url) {
    var u = url.toLowerCase();
    u = u.replaceFirst(RegExp(r'^https?://'), '');
    return u.split('/').first.split('?').first;
  }

  bool _isOfficial(String host, Brand brand) =>
      brand.officialDomains.any((d) => host == d || host.endsWith('.$d'));

  Finding _judgeUrl(ChatMessage m, String url, int start, DroneId drone) {
    final host = hostOf(url);
    final brand = claimedBrand(m);

    if (urlShorteners.contains(host)) {
      return Finding(
        drone: drone,
        title: 'Shortened link hides its destination',
        detail:
            '"$host" is a link shortener — the real destination is hidden '
            'until you tap. Legit account alerts almost never hide where a '
            'link goes.',
        points: 22,
        spanStart: start,
        spanEnd: start + url.length,
        evidence: url,
      );
    }
    if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host)) {
      return Finding(
        drone: drone,
        title: 'Link goes to a raw IP address',
        detail:
            'The link points at a bare IP address instead of a company '
            'domain. Real companies do not run login pages on raw IPs.',
        points: 30,
        spanStart: start,
        spanEnd: start + url.length,
        evidence: url,
      );
    }
    if (host.contains('xn--')) {
      return Finding(
        drone: drone,
        title: 'Lookalike characters in domain',
        detail:
            'This domain uses encoded characters (punycode) that can render '
            'as letters that look like a real brand but are not.',
        points: 28,
        spanStart: start,
        spanEnd: start + url.length,
        evidence: url,
      );
    }
    if (brand != null) {
      if (_isOfficial(host, brand)) {
        return Finding(
          drone: drone,
          title: 'Official domain',
          detail:
              '$host is a real ${brand.name} domain. Links in genuine alerts '
              'stay on the company\'s own domain.',
          points: 0,
          spanStart: start,
          spanEnd: start + url.length,
          evidence: url,
        );
      }
      final squashed = host.replaceAll('-', '').replaceAll('.', '');
      final brandSquashed = brand.name.toLowerCase().replaceAll(
        RegExp(r'[^a-z]'),
        '',
      );
      if (squashed.contains(brandSquashed) ||
          brand.aliases.any(
            (a) =>
                host.contains(a.replaceAll(' ', '-')) ||
                host.contains(a.replaceAll(' ', '')),
          )) {
        return Finding(
          drone: drone,
          title: 'Lookalike domain',
          detail:
              '"$host" is built to look like ${brand.name}, but it is NOT a '
              '${brand.name} domain. The real one is '
              '${brand.officialDomains.first}. One extra word or hyphen in '
              'the domain means a completely different — and fake — site.',
          points: 36,
          spanStart: start,
          spanEnd: start + url.length,
          evidence: url,
        );
      }
      return Finding(
        drone: drone,
        title: 'Off-brand domain',
        detail:
            'The message claims to be ${brand.name} but links to "$host", '
            'which is not a ${brand.name} domain.',
        points: 30,
        spanStart: start,
        spanEnd: start + url.length,
        evidence: url,
      );
    }
    return Finding(
      drone: drone,
      title: 'Link present',
      detail:
          'This message contains a link to $host. No brand is claimed, so '
          'judge it by whether you were expecting it.',
      points: 6,
      spanStart: start,
      spanEnd: start + url.length,
      evidence: url,
    );
  }

  List<Finding> link(ChatMessage m) {
    final urls = extractUrls(m.body);
    if (urls.isEmpty) {
      return [
        const Finding(
          drone: DroneId.link,
          title: 'No links',
          detail:
              'There is no link in this message to tap — a scam\'s '
              'favorite trap is missing.',
          points: 0,
        ),
      ];
    }
    return [
      for (final url in urls)
        _judgeUrl(m, url, m.body.indexOf(url), DroneId.link),
    ];
  }

  // --------------------------------------------------------------- Scanner
  List<Finding> scanner(ChatMessage m) {
    final findings = <Finding>[];
    if (m.hasQr) {
      // The payload is not part of the message body, so the finding keeps
      // the decoded URL as evidence but carries no body span.
      findings.add(
        _judgeUrl(
          m,
          m.qrPayload!,
          -1,
          DroneId.scanner,
        ).copyTitle('QR code decodes to this'),
      );
    }
    final qrMention = RegExp(
      r'scan (the )?(qr|code)',
      caseSensitive: false,
    ).firstMatch(m.body);
    if (qrMention != null) {
      findings.add(
        Finding(
          drone: DroneId.scanner,
          title: 'Pushes you to scan a QR code',
          detail:
              'The message tells you to scan a QR code. A QR code hides its '
              'destination even better than a link — you cannot read where it '
              'goes before it opens. Carriers and banks do not ask you to scan '
              'QR codes from a text to "verify" an account.',
          points: m.hasQr ? 16 : 12,
          spanStart: qrMention.start,
          spanEnd: qrMention.end,
          evidence: qrMention.group(0)!,
        ),
      );
    }
    if (findings.isEmpty) {
      findings.add(
        const Finding(
          drone: DroneId.scanner,
          title: 'No QR code',
          detail: 'No QR code attached to or mentioned in this message.',
          points: 0,
        ),
      );
    }
    return findings;
  }

  // -------------------------------------------------------------- Pressure
  static const List<(String, String)> _pressurePhrases = [
    ('within 24 hours', 'a hard 24-hour deadline'),
    ('within 12 hours', 'a hard 12-hour deadline'),
    ('suspended', 'a threat to suspend the account/line'),
    ('will be closed', 'a threat to close the account'),
    ('will be locked', 'a threat to lock the account/card'),
    ('immediately', '"immediately"'),
    ('act now', '"act now"'),
    ('urgent', '"urgent"'),
    ('final notice', '"final notice"'),
    ('verify now', '"verify now"'),
    ('expires today', 'a same-day expiry'),
    ('last chance', '"last chance"'),
  ];

  List<Finding> pressure(ChatMessage m) {
    final lower = m.body.toLowerCase();
    final hits = <(int, int, String, String)>[]; // start, end, phrase, label
    for (final (phrase, label) in _pressurePhrases) {
      final idx = lower.indexOf(phrase);
      if (idx >= 0) hits.add((idx, idx + phrase.length, phrase, label));
    }
    if (hits.isEmpty) {
      return [
        const Finding(
          drone: DroneId.pressure,
          title: 'Calm tone',
          detail:
              'No deadlines, threats, or rush language. Real notices tell '
              'you what happened; scams tell you to hurry.',
          points: 0,
        ),
      ];
    }
    hits.sort((a, b) => a.$1.compareTo(b.$1));
    final capsRatio = _capsRatio(m.body);
    final points = (hits.length * 9 + (capsRatio > 0.25 ? 6 : 0)).clamp(0, 30);
    final first = hits.first;
    return [
      Finding(
        drone: DroneId.pressure,
        title: 'Pressure tactics (${hits.length})',
        detail:
            'This message rushes you with ${hits.map((h) => h.$4).join(', ')}. '
            'That is deliberate: the FTC\'s scam script always adds pressure '
            'so you act before you think. A real company gives you time and '
            'other ways to reach them.',
        points: points,
        spanStart: first.$1,
        spanEnd: first.$2,
        evidence: m.body.substring(first.$1, first.$2),
      ),
    ];
  }

  double _capsRatio(String text) {
    final letters = text.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (letters.isEmpty) return 0;
    final caps = letters.replaceAll(RegExp(r'[^A-Z]'), '').length;
    return caps / letters.length;
  }

  // ---------------------------------------------------------- Impersonator
  List<Finding> impersonator(ChatMessage m) {
    final findings = <Finding>[];
    final lower = m.body.toLowerCase();

    final credentialAsk = RegExp(
      r'(account pin|your pin|password|social security|ssn|card number|cvv)',
      caseSensitive: false,
    ).firstMatch(m.body);
    if (credentialAsk != null &&
        RegExp(
          r'(enter|confirm|verify|share|send|provide|reply)',
          caseSensitive: false,
        ).hasMatch(lower)) {
      findings.add(
        Finding(
          drone: DroneId.impersonator,
          title: 'Asks for a secret only you should know',
          detail:
              'The message asks you to hand over a '
              '"${credentialAsk.group(0)}". No carrier or bank will ever ask '
              'for that by text — the request itself is the scam, whoever it '
              'claims to be from.',
          points: 32,
          spanStart: credentialAsk.start,
          spanEnd: credentialAsk.end,
          evidence: credentialAsk.group(0)!,
        ),
      );
    }

    final paymentAsk = RegExp(
      r'(gift card|wire transfer|western union|bitcoin|crypto|zelle.*stranger)',
      caseSensitive: false,
    ).firstMatch(m.body);
    if (paymentAsk != null) {
      findings.add(
        Finding(
          drone: DroneId.impersonator,
          title: 'Unusual payment method demanded',
          detail:
              'It steers you toward paying by ${paymentAsk.group(0)} — the '
              'payment rail scammers use because it cannot be reversed.',
          points: 30,
          spanStart: paymentAsk.start,
          spanEnd: paymentAsk.end,
          evidence: paymentAsk.group(0)!,
        ),
      );
    }

    if (findings.isEmpty) {
      final brand = claimedBrand(m);
      findings.add(
        Finding(
          drone: DroneId.impersonator,
          title: brand == null
              ? 'No impersonation tells'
              : 'Identity claim checked',
          detail: brand == null
              ? 'The message does not pretend to be a company or official.'
              : 'The message claims to be ${brand.name}. Read with Angler\'s '
                    'sender check and Link\'s domain check — an impersonator '
                    'usually fails at least one of them.',
          points: 0,
        ),
      );
    }
    return findings;
  }

  // ------------------------------------------------------------------ Swap
  List<Finding> swap(ChatMessage m) {
    final findings = <Finding>[];
    final codeAsk = RegExp(
      r'(6-digit code|verification code|one-time code|the code we (sent|texted))',
      caseSensitive: false,
    ).firstMatch(m.body);
    if (codeAsk != null &&
        RegExp(
          r'(send|share|enter|confirm|reply|give)',
          caseSensitive: false,
        ).hasMatch(m.body.toLowerCase())) {
      findings.add(
        Finding(
          drone: DroneId.swap,
          title: 'Verification-code fishing',
          detail:
              'It fishes for a verification code. Those codes are how a '
              'scammer takes over your number (a SIM-swap / port-out): they '
              'trigger a code to your phone, then talk you into handing it '
              'over. Never share a code that a text message itself sent you '
              'with anyone who asks for it.',
          points: 34,
          spanStart: codeAsk.start,
          spanEnd: codeAsk.end,
          evidence: codeAsk.group(0)!,
        ),
      );
    }
    final simTalk = RegExp(
      r'(sim (card )?(will|swap|replace)|port (out|your number)|keep your number active|line will be)',
      caseSensitive: false,
    ).firstMatch(m.body);
    if (simTalk != null) {
      findings.add(
        Finding(
          drone: DroneId.swap,
          title: 'Number-takeover framing',
          detail:
              'The message talks about your line/number being changed or '
              'deactivated. That framing primes you for a SIM-swap pitch. '
              'Your real protection: a SIM-swap lock and account PIN set '
              'inside the official app — never through a texted link.',
          points: 18,
          spanStart: simTalk.start,
          spanEnd: simTalk.end,
          evidence: simTalk.group(0)!,
        ),
      );
    }
    if (findings.isEmpty) {
      findings.add(
        const Finding(
          drone: DroneId.swap,
          title: 'No SIM-swap tells',
          detail:
              'Nothing here fishes for a verification code or primes a '
              'number takeover.',
          points: 0,
        ),
      );
    }
    return findings;
  }

  // --------------------------------------------------------------- helpers
  /// The brand this message claims (or appears) to be from, if any.
  Brand? claimedBrand(ChatMessage m) {
    final text = '${m.sender} ${m.body}'.toLowerCase();
    for (final brand in knownBrands) {
      if (brand.aliases.any((a) => text.contains(a))) return brand;
    }
    return null;
  }
}

extension on Finding {
  Finding copyTitle(String title) => Finding(
    drone: drone,
    title: title,
    detail: detail,
    points: points,
    spanStart: spanStart,
    spanEnd: spanEnd,
    evidence: evidence,
  );
}
