/// The conversational brain behind "talk to a drone".
///
/// Pure Dart and fully on-device: answers are composed from (a) this
/// drone's actual findings on the message being discussed — points,
/// evidence spans, verdict, confidence — and (b) a small built-in base of
/// scam-safety knowledge per specialty. It is deliberately NOT a general
/// chatbot: if a question is outside what the scan and its specialty can
/// support, the drone says so and points back to what it does know. That
/// keeps every claim it makes checkable against the scan on screen.
///
/// House style (Ryan's direction): short and to the point. Answers lead
/// with the verdict or the evidence and stop — most run 15–40 words.
library;

import '../models/message.dart';
import 'scam_analyzer.dart';

class DroneBrain {
  const DroneBrain();

  /// The line the drone opens with when the conversation starts.
  String greeting(DroneId drone, MessageAnalysis analysis) {
    final points = analysis.pointsFor(drone);
    final flagCount = analysis
        .findingsFor(drone)
        .where((f) => f.isFlag)
        .length;
    final verdictWord = switch (analysis.verdict) {
      Verdict.dangerous => 'dangerous',
      Verdict.caution => 'be careful with it',
      Verdict.safe => 'looks legitimate',
    };
    final myPart = points > 0
        ? 'I flagged $flagCount ${flagCount == 1 ? 'thing' : 'things'} '
              'myself (+$points).'
        : 'I found nothing wrong in my area.';
    return 'I\'m ${drone.label}. I check ${drone.specialty.toLowerCase()}. '
        'Fleet score: ${analysis.riskScore}/100 — $verdictWord. $myPart '
        'Ask me why.';
  }

  /// Tappable starter questions, tuned to what this drone found.
  List<String> suggestions(DroneId drone, MessageAnalysis analysis) {
    final hasFlags = analysis.pointsFor(drone) > 0;
    return [
      if (hasFlags) 'Why did you flag this?' else 'What did you check?',
      'What should I do?',
      'How can I spot this myself?',
    ];
  }

  /// Answers one user question, in character, grounded in [analysis].
  String answer({
    required DroneId drone,
    required MessageAnalysis analysis,
    required String question,
  }) {
    final q = question.toLowerCase().trim();
    final message = analysis.message;
    final brand = _claimedBrand(message);
    final myFlags = analysis.findingsFor(drone).where((f) => f.isFlag).toList();
    final myPoints = analysis.pointsFor(drone);

    if (q.isEmpty) {
      return 'Didn\'t catch that — try "why did you flag this?"';
    }

    // --- greetings / identity -------------------------------------------
    if (_isGreeting(q)) {
      return 'Hello! I\'m ${drone.label}, the '
          '${drone.specialty.toLowerCase()} specialist. On this message '
          'I ${_stance(myPoints)} What do you want to know?';
    }
    if (q.contains('who are you') ||
        q.contains('what do you do') ||
        q.contains('your job')) {
      return 'I\'m ${drone.label} — I check '
          '${drone.specialty.toLowerCase()}. On this message '
          'I ${_stance(myPoints)}';
    }

    // --- "what should I do" / action safety ------------------------------
    if (q.contains('what should i do') ||
        q.contains('what do i do') ||
        q.contains('should i') ||
        q.contains('is it ok to') ||
        q.contains('can i trust')) {
      return _actionAdvice(drone, analysis, brand);
    }

    // --- why / what did you find ----------------------------------------
    if (q.contains('why') ||
        q.contains('what did you find') ||
        q.contains('evidence') ||
        q.contains('flag') ||
        q.contains('suspicious')) {
      if (myFlags.isEmpty) {
        final checks = analysis
            .findingsFor(drone)
            .map((f) => f.title.toLowerCase())
            .take(3)
            .toList();
        return 'I didn\'t flag anything. I checked '
            '${checks.isEmpty ? drone.specialty.toLowerCase() : checks.join(', ')} '
            '— all clean. One reason the score is ${analysis.riskScore}/100.';
      }
      final parts = [
        for (final f in myFlags)
          '${f.title} (+${f.points})'
              '${f.evidence.isNotEmpty ? ': "${f.evidence}"' : ''}'
              ' — ${f.detail}',
      ];
      return 'I flagged ${myFlags.length} '
          '${myFlags.length == 1 ? 'thing' : 'things'}. ${parts.join(' ')} '
          'That\'s $myPoints of the ${analysis.riskScore} points.';
    }

    // --- is it safe / a scam ---------------------------------------------
    if (q.contains('safe') ||
        q.contains('scam') ||
        q.contains('legit') ||
        q.contains('real') ||
        q.contains('dangerous')) {
      return switch (analysis.verdict) {
        Verdict.dangerous =>
          'It\'s a scam — ${analysis.riskScore}/100, '
              '${analysis.confidence}% confidence. '
              '${analysis.flaggingDrones.length} of 6 drones flagged it. '
              'Don\'t use anything in the text; open the official app '
              'instead.',
        Verdict.caution =>
          'Be careful — ${analysis.riskScore}/100. '
              '${analysis.flaggingDrones.length} of 6 drones flagged '
              'something. Check through the official app before doing '
              'anything.',
        Verdict.safe =>
          'Looks legitimate — ${analysis.riskScore}/100, '
              '${analysis.confidence}% confidence. All six drones '
              'cleared it.',
      };
    }

    // --- the rest of the fleet -------------------------------------------
    if (q.contains('other drone') ||
        q.contains('fleet') ||
        q.contains('team') ||
        q.contains('everyone')) {
      if (analysis.flaggingDrones.isEmpty) {
        return 'Nobody flagged it — all six drones cleared it. '
            'Confidence ${analysis.confidence}%.';
      }
      final parts = [
        for (final d in analysis.flaggingDrones)
          '${d.label} +${analysis.pointsFor(d)}',
      ];
      return 'Fleet scoreboard: ${parts.join(', ')} — total '
          '${analysis.riskScore}/100.';
    }

    // --- blocking / reporting --------------------------------------------
    if (q.contains('block') || q.contains('report')) {
      return 'Tap Block & Report under the message. It blocks '
          '${message.sender}, files the report, and shares the block '
          'with your trusted contact.';
    }

    // --- teach me: per-drone expertise ------------------------------------
    final lesson = _lesson(drone, q, brand);
    if (lesson != null) return lesson;

    // --- fallback ----------------------------------------------------------
    if (myFlags.isNotEmpty) {
      return 'Outside my specialty — I know '
          '${drone.specialty.toLowerCase()} and this scan. My biggest '
          'finding: "${myFlags.first.title}" — ${myFlags.first.detail}';
    }
    return 'Outside my specialty — I know '
        '${drone.specialty.toLowerCase()}. I checked this message and '
        'found nothing wrong. Ask me "what did you check?"';
  }

  String _stance(int points) => points > 0
      ? 'flagged concerns worth $points points.'
      : 'found nothing wrong.';

  bool _isGreeting(String q) {
    final words = q.replaceAll(RegExp(r'[^a-z ]'), '').split(' ');
    return words.length <= 3 &&
        (words.contains('hi') ||
            words.contains('hello') ||
            words.contains('hey'));
  }

  Brand? _claimedBrand(ChatMessage message) {
    final haystack = '${message.sender} ${message.body}'.toLowerCase();
    for (final brand in knownBrands) {
      if (haystack.contains(brand.name.toLowerCase())) return brand;
      for (final alias in brand.aliases) {
        if (haystack.contains(alias.toLowerCase())) return brand;
      }
    }
    return null;
  }

  String _actionAdvice(DroneId drone, MessageAnalysis analysis, Brand? brand) {
    final company = brand?.name ?? 'the company';
    final official = brand != null && brand.officialDomains.isNotEmpty
        ? ' (${brand.officialDomains.first})'
        : '';
    final base = switch (analysis.verdict) {
      Verdict.dangerous =>
        'Do not tap the link, scan anything, or reply — never share '
            'a PIN, password, or code. ',
      Verdict.caution =>
        'Pause. Don\'t use its link or number until you\'ve checked '
            'another way. ',
      Verdict.safe =>
        'It checked out. Still, prefer the official app over links in '
            'texts. ',
    };
    final droneTip = switch (drone) {
      DroneId.swap =>
        'No carrier ever asks for a code — asking is the SIM-swap '
            'tell. ',
      DroneId.scanner => 'A QR code is a link you can\'t read — '
            'don\'t scan it. ',
      _ => '',
    };
    return '$base${droneTip}Use $company\'s app$official or the '
        'number on your card. Then Block & Report.';
  }

  /// Per-drone teaching answers. Returns null when the question is not
  /// about this drone's topic, so the caller's fallback can take over.
  String? _lesson(DroneId drone, String q, Brand? brand) {
    bool has(List<String> words) => words.any(q.contains);
    switch (drone) {
      case DroneId.angler:
        if (has(['spoof', 'sender', 'number', 'short code', 'who sent'])) {
          return 'Numbers can be faked — that\'s spoofing. Real '
              'companies use short codes: ${brand?.name ?? 'carrier'} '
              'notices come from '
              '${brand?.officialShortCodes.isNotEmpty == true ? brand!.officialShortCodes.first : '456'}, '
              'not random 10-digit numbers pushing links.';
        }
      case DroneId.link:
        if (has(['link', 'domain', 'url', 'website', 'address'])) {
          final official = brand != null
              ? '${brand.name}\'s real domains are '
                    '${brand.officialDomains.join(', ')}'
              : 'the real domain is the one on your card or bill';
          return 'Read a link letter by letter, up to the first slash. '
              'Lookalikes add a word or swap a letter. $official — '
              'anything else is a costume.';
        }
      case DroneId.scanner:
        if (has(['qr', 'scan', 'code'])) {
          return 'A QR code is a link you can\'t read — exactly why '
              'scammers use them. Never scan one from an unexpected '
              'text, especially to pay. We decode it first and check '
              'where it goes.';
        }
      case DroneId.pressure:
        if (has([
          'urgent',
          'pressure',
          'threat',
          'suspend',
          'hurry',
          'scare',
        ])) {
          return 'Urgency is the trick: "within 24 hours", "final '
              'notice". Real companies don\'t panic you into acting in '
              'minutes. If a message makes your heart race, slow down '
              '— that feeling is the warning.';
        }
      case DroneId.impersonator:
        if (has([
          'gift card',
          'boss',
          'ceo',
          'pretend',
          'impersonat',
          'pin',
          'password',
        ])) {
          return 'Impersonators borrow trust — a "boss" wanting gift '
              'cards, a "bank" wanting your PIN. No real bank asks for '
              'a PIN by text. Verify people on a number you already '
              'have, not the one in the message.';
        }
      case DroneId.swap:
        if (has([
          'sim',
          'code',
          'verification',
          '6-digit',
          'six digit',
          'pin',
        ])) {
          return 'Those codes are keys to your accounts. In a SIM-swap, '
              'a scammer tricks you into reading one out, takes your '
              'number, and resets your passwords. Nobody legitimate '
              'ever asks — asking is confessing.';
        }
    }
    if (has(['spot', 'sign', 'tell', 'myself', 'learn', 'teach'])) {
      return 'My specialty is ${drone.specialty.toLowerCase()}: '
          '${_spotLesson(drone)}';
    }
    return null;
  }

  String _spotLesson(DroneId drone) => switch (drone) {
    DroneId.angler =>
      'check who really sent it — real companies use short codes; a '
          'random long number claiming to be your carrier is a costume.',
    DroneId.link =>
      'read every link letter by letter up to the first slash, and '
          'compare it with the real domain on your card or bill.',
    DroneId.scanner =>
      'treat every QR code as a link you can\'t read — if it arrived '
          'unexpectedly, don\'t scan it.',
    DroneId.pressure =>
      'notice when a message tries to rush or frighten you; urgency is '
          'manufactured to stop you thinking.',
    DroneId.impersonator =>
      'ask whether the request makes sense — real banks never ask for '
          'PINs, and real bosses don\'t need gift cards by text.',
    DroneId.swap =>
      'guard your 6-digit codes like house keys — nobody legitimate '
          'will ever ask you to share one.',
  };
}
