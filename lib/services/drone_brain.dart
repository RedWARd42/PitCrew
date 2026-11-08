/// The conversational brain behind "talk to a drone".
///
/// Pure Dart and fully on-device: answers are composed from (a) this
/// drone's actual findings on the message being discussed — points,
/// evidence spans, verdict, confidence — and (b) a small built-in base of
/// scam-safety knowledge per specialty. It is deliberately NOT a general
/// chatbot: if a question is outside what the scan and its specialty can
/// support, the drone says so and points back to what it does know. That
/// keeps every claim it makes checkable against the scan on screen.
library;

import '../models/message.dart';
import 'scam_analyzer.dart';

class DroneBrain {
  const DroneBrain();

  /// The line the drone opens with when the conversation starts.
  String greeting(DroneId drone, MessageAnalysis analysis) {
    final points = analysis.pointsFor(drone);
    final verdictLine = switch (analysis.verdict) {
      Verdict.dangerous =>
        'The fleet scored this message ${analysis.riskScore} out of 100 — '
            'dangerous.',
      Verdict.caution =>
        'The fleet scored this message ${analysis.riskScore} out of 100 — '
            'be careful with it.',
      Verdict.safe =>
        'The fleet scored this message ${analysis.riskScore} out of 100 — '
            'it looks legitimate.',
    };
    final myPart = points > 0
        ? 'I flagged ${analysis.findingsFor(drone).where((f) => f.isFlag).length} '
              'thing(s) myself, worth $points risk points.'
        : 'I checked my area and found nothing wrong.';
    return 'Hi, I\'m ${drone.label}. I watch for ${drone.specialty.toLowerCase()}. '
        '$verdictLine $myPart Ask me anything about this message — tap the '
        'microphone and speak, or type below.';
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
      return 'I didn\'t catch that. Ask me why I flagged this message, or '
          'what you should do next.';
    }

    // --- greetings / identity -------------------------------------------
    if (_isGreeting(q)) {
      return 'Hello! I\'m ${drone.label}, the fleet\'s ${drone.specialty.toLowerCase()} '
          'specialist. On this message I ${_stance(myPoints)}. What would '
          'you like to know?';
    }
    if (q.contains('who are you') ||
        q.contains('what do you do') ||
        q.contains('your job')) {
      return 'I\'m ${drone.label}, one of six specialists. My whole job is '
          '${drone.specialty.toLowerCase()} — I fly to the exact words in a '
          'message that match my specialty and check them. On this message '
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
            .toList();
        return 'I didn\'t flag anything in my area. I checked '
            '${checks.isEmpty ? drone.specialty.toLowerCase() : checks.join(', ')} '
            'and it held up. That is one reason the fleet\'s score is '
            '${analysis.riskScore} out of 100.';
      }
      final parts = [
        for (final f in myFlags)
          '${f.title} (+${f.points}): ${f.detail}'
              '${f.evidence.isNotEmpty ? ' The exact words were "${f.evidence}".' : ''}',
      ];
      return 'Here is what I found in this message. ${parts.join(' ')} '
          'Together that is $myPoints of the ${analysis.riskScore} risk '
          'points.';
    }

    // --- is it safe / a scam ---------------------------------------------
    if (q.contains('safe') ||
        q.contains('scam') ||
        q.contains('legit') ||
        q.contains('real') ||
        q.contains('dangerous')) {
      final verdict = switch (analysis.verdict) {
        Verdict.dangerous =>
          'No — treat this one as a scam. The fleet scored it '
              '${analysis.riskScore} out of 100 with ${analysis.confidence}% '
              'confidence',
        Verdict.caution =>
          'Be careful — the fleet scored it ${analysis.riskScore} out of '
              '100, which lands in "be careful" territory',
        Verdict.safe =>
          'This one looks legitimate — the fleet scored it '
              '${analysis.riskScore} out of 100',
      };
      return '$verdict. ${analysis.flaggingDrones.length} of the 6 drones '
          'flagged something. I ${_stance(myPoints)} If you are ever '
          'unsure, reach the company through its official app or the number '
          'on your card — never through a link in a text.';
    }

    // --- the rest of the fleet -------------------------------------------
    if (q.contains('other drone') ||
        q.contains('fleet') ||
        q.contains('team') ||
        q.contains('everyone')) {
      if (analysis.flaggingDrones.isEmpty) {
        return 'Nobody on the fleet flagged this message. All six of us '
            'checked our specialties and it held up — that is why the '
            'confidence is ${analysis.confidence}%.';
      }
      final parts = [
        for (final d in analysis.flaggingDrones)
          '${d.label} +${analysis.pointsFor(d)}',
      ];
      return 'Here is the fleet\'s scoreboard on this message: '
          '${parts.join(', ')}. Total risk ${analysis.riskScore} out of '
          '100. Tap any of us to hear our part.';
    }

    // --- blocking / reporting --------------------------------------------
    if (q.contains('block') || q.contains('report')) {
      return 'Use the Block & Report button under the message. That blocks '
          'the sender (${message.sender}), files an incident report written '
          'from our findings, and adds the sender to the block list you '
          'share with your trusted contact. It is the safest ending for a '
          'message like this.';
    }

    // --- teach me: per-drone expertise ------------------------------------
    final lesson = _lesson(drone, q, brand);
    if (lesson != null) return lesson;

    // --- fallback ----------------------------------------------------------
    final lead = myFlags.isNotEmpty
        ? 'My biggest finding here is "${myFlags.first.title}" — '
              '${myFlags.first.detail}'
        : 'I checked ${drone.specialty.toLowerCase()} on this message and '
              'found nothing wrong.';
    return 'That one is a bit outside my specialty — I know '
        '${drone.specialty.toLowerCase()} and what I found in this message. '
        '$lead Ask me "why did you flag this", "what should I do", or "how '
        'can I spot this myself?"';
  }

  String _stance(int points) => points > 0
      ? 'flagged concerns worth $points risk points.'
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
        ? ' (their real site is ${brand.officialDomains.first})'
        : '';
    final base = switch (analysis.verdict) {
      Verdict.dangerous =>
        'Do not click the link, do not scan the code, do not reply, and '
            'never send a PIN, password, or 6-digit code from a message '
            'like this. ',
      Verdict.caution =>
        'Pause before doing anything this message asks. Do not use its '
            'link or phone number until you have checked it another way. ',
      Verdict.safe =>
        'This one checked out, so following it is reasonable — but the '
            'habits below are still the safe way to handle any message. ',
    };
    final channel =
        'If you need to reach $company, open their official app or type '
        'their address yourself$official, or call the number printed on '
        'your card or bill. Then use Block & Report here so the sender '
        'cannot try again.';
    final droneTip = switch (drone) {
      DroneId.swap =>
        ' And from me specifically: no real carrier will ever ask you to '
            'read them a code — the moment a message asks for one, it is a '
            'SIM-swap attempt. ',
      DroneId.scanner =>
        ' And from me specifically: a QR code hides its destination, so '
            'treat scanning one from a text like clicking a link you cannot '
            'read. ',
      _ => '',
    };
    return '$base$droneTip$channel';
  }

  /// Per-drone teaching answers. Returns null when the question is not
  /// about this drone's topic, so the caller's fallback can take over.
  String? _lesson(DroneId drone, String q, Brand? brand) {
    bool has(List<String> words) => words.any(q.contains);
    switch (drone) {
      case DroneId.angler:
        if (has(['spoof', 'sender', 'number', 'short code', 'who sent'])) {
          return 'Phone numbers can be faked — that is called spoofing. A '
              'scammer can make a text look like it comes from almost any '
              'number. What cannot be faked so easily is a carrier short '
              'code: ${brand?.name ?? 'companies'} send real notices from '
              'short codes like ${brand?.officialShortCodes.isNotEmpty == true ? brand!.officialShortCodes.first : '456'}, '
              'not from ordinary 10-digit numbers that also ask you to '
              'click links.';
        }
      case DroneId.link:
        if (has(['link', 'domain', 'url', 'website', 'address'])) {
          final official = brand != null
              ? '${brand.name}\'s real domains are '
                    '${brand.officialDomains.join(', ')}'
              : 'the company\'s real domain is the one printed on your '
                    'card or bill';
          return 'Read a link letter by letter, right up to the first '
              'slash. Scammers register lookalikes — an extra word, a '
              'swapped letter, or a different ending like .xyz. For '
              'reference, $official. Anything else, even if it contains '
              'the company\'s name, is a costume.';
        }
      case DroneId.scanner:
        if (has(['qr', 'scan', 'code'])) {
          return 'A QR code is a link you cannot read, which is exactly '
              'why scammers love them — and many phone cameras open the '
              'site the moment you scan. The fleet decodes the code first '
              'and checks where it really goes before you ever visit it. '
              'Rule of thumb: never scan a code that arrived in an '
              'unexpected text or email, especially one asking you to pay.';
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
          return 'Urgency is the scammer\'s main tool. "Within 24 hours", '
              '"final notice", "your line will be suspended" — real '
              'companies send bills and reminders, but they do not panic '
              'you into acting in minutes. When a message tries to make '
              'your heart race, that feeling itself is the warning sign. '
              'Slow down; a real problem will still be there after you '
              'check through the official app.';
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
          return 'Impersonators borrow trust: a boss asking for gift '
              'cards, a "bank" asking for your PIN. Two rules stop almost '
              'all of it. One: no real company or bank will ever ask for '
              'your PIN or password by text. Two: if someone claims to be '
              'a person you know, check with them on a number you already '
              'have — not the one in the message.';
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
          return 'The 6-digit codes companies text you are keys to your '
              'accounts. In a SIM-swap attack, the scammer first tricks '
              'you into reading them a code, then takes over your number '
              'and resets your passwords. Nobody legitimate — not your '
              'carrier, not your bank — will ever ask you to send or read '
              'them a code. A message that asks is confessing.';
        }
    }
    if (has(['spot', 'sign', 'tell', 'myself', 'learn', 'teach'])) {
      return 'Happy to teach. My specialty is ${drone.specialty.toLowerCase()}: '
          '${_spotLesson(drone)} Try asking me about that, or tap "Walk me '
          'through it" and I will show you on this exact message.';
    }
    return null;
  }

  String _spotLesson(DroneId drone) => switch (drone) {
    DroneId.angler =>
      'check who really sent it — real companies use short codes, and a '
          'random long number claiming to be your carrier is a costume.',
    DroneId.link =>
      'read every link letter by letter up to the first slash, and '
          'compare it with the real domain on your card or bill.',
    DroneId.scanner =>
      'treat every QR code as a link you cannot read — if it arrived '
          'unexpectedly, do not scan it.',
    DroneId.pressure =>
      'notice when a message tries to rush or frighten you; urgency is '
          'manufactured to stop you thinking.',
    DroneId.impersonator =>
      'ask whether the request itself makes sense — real banks never ask '
          'for PINs, and real bosses do not need gift cards by text.',
    DroneId.swap =>
      'guard your 6-digit codes like house keys — nobody legitimate will '
          'ever ask you to share one.',
  };
}
