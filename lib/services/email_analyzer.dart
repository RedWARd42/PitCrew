/// The fleet, over email.
///
/// Reuses the text-message engine for everything email and SMS share
/// (links, QR payloads, pressure language, credential asks, code fishing)
/// by adapting an [EmailMessage] into a [ChatMessage] whose body is the
/// email's display text — so spans, walkthroughs, reports, blocking, and
/// family scan-sharing all work unchanged.
///
/// Email gets two checks of its own, both Angler/Scanner work:
///  * **Sending domain** — the display name is free text; the domain is
///    the identity. A "T-Mobile Billing" email from anywhere but a real
///    T-Mobile domain is an impersonator, and a lookalike domain is the
///    oldest trick in phishing.
///  * **Reply-To mismatch** — From looks right, but replies route to a
///    different domain: whatever you send back (the info they asked for)
///    goes to the scammer.
///  * **Attachments** — dangerous types and double extensions
///    ("invoice.pdf.exe") are Scanner's email beat.
library;

import '../models/email.dart';
import '../models/message.dart';
import 'scam_analyzer.dart';

class EmailAnalyzer {
  const EmailAnalyzer();

  static const ScamAnalyzer _text = ScamAnalyzer();

  /// Adapt the email to the shared engine. The adapter's sender is the
  /// from-address; its body is the display text (subject + body), which
  /// is exactly what the reading view renders, so spans align.
  ChatMessage adapt(EmailMessage email) => ChatMessage(
    id: email.id,
    sender: email.fromAddress,
    body: email.displayText,
    timeLabel: email.timeLabel,
    qrPayload: email.qrPayload,
  );

  MessageAnalysis analyze(EmailMessage email) {
    final adapter = adapt(email);
    final findings = <Finding>[
      ...anglerEmail(email),
      ..._text.link(adapter),
      ...scannerEmail(email, adapter),
      ..._text.pressure(adapter),
      ..._text.impersonator(adapter),
      ..._text.swap(adapter),
    ];
    final (riskScore, confidence) = ScamAnalyzer.scoreFindings(findings);
    return MessageAnalysis(
      message: adapter,
      findings: findings,
      riskScore: riskScore,
      confidence: confidence,
    );
  }

  // ------------------------------------------------------- email's Angler
  List<Finding> anglerEmail(EmailMessage email) {
    final findings = <Finding>[];
    final probe = ChatMessage(
      id: email.id,
      sender: email.fromAddress,
      body: '${email.fromName} ${email.subject} ${email.body}',
      timeLabel: email.timeLabel,
    );
    final brand = _text.claimedBrand(probe);
    final domain = email.fromDomain;

    if (brand != null) {
      final official = brand.officialDomains.any(
        (d) => domain == d || domain.endsWith('.$d'),
      );
      if (official) {
        findings.add(
          Finding(
            drone: DroneId.angler,
            title: 'Verified sending domain',
            detail:
                'This email really was sent from $domain, an official '
                '${brand.name} domain. In email, the domain is the identity — '
                'the display name ("${email.fromName}") is just text anyone '
                'can type.',
            points: 0,
            evidence: email.fromAddress,
          ),
        );
      } else {
        final squashed = domain.replaceAll('-', '').replaceAll('.', '');
        final brandSquashed = brand.name.toLowerCase().replaceAll(
          RegExp(r'[^a-z]'),
          '',
        );
        final lookalike =
            squashed.contains(brandSquashed) ||
            brand.aliases.any(
              (a) =>
                  domain.contains(a.replaceAll(' ', '-')) ||
                  domain.contains(a.replaceAll(' ', '')),
            );
        findings.add(
          Finding(
            drone: DroneId.angler,
            title: lookalike
                ? 'Lookalike sending domain'
                : 'Wrong sending domain',
            detail:
                'The email claims to be ${brand.name} ("${email.fromName}"), '
                'but it was sent from $domain — not a ${brand.name} domain '
                '(the real one is ${brand.officialDomains.first}). The '
                'display name is free text; always read the domain after '
                'the @.',
            points: lookalike ? 36 : 28,
            evidence: email.fromAddress,
          ),
        );
      }
    } else {
      findings.add(
        const Finding(
          drone: DroneId.angler,
          title: 'No brand claimed',
          detail: 'The sender does not claim to be a known company.',
          points: 0,
        ),
      );
    }

    final replyTo = email.replyTo;
    if (replyTo != null && replyTo.isNotEmpty) {
      final at = replyTo.lastIndexOf('@');
      final replyDomain = at >= 0
          ? replyTo.substring(at + 1).toLowerCase()
          : '';
      if (replyDomain != domain) {
        findings.add(
          Finding(
            drone: DroneId.angler,
            title: 'Reply-To goes somewhere else',
            detail:
                'Hit reply and your answer goes to $replyTo — a different '
                'domain from the sender. That is how a phish collects the '
                'details it asks for while the From line looks tidy.',
            points: 24,
            evidence: replyTo,
          ),
        );
      }
    }
    return findings;
  }

  // ------------------------------------------------------ email's Scanner
  List<Finding> scannerEmail(EmailMessage email, ChatMessage adapter) {
    final findings = <Finding>[..._text.scanner(adapter)];
    final name = email.attachmentName;
    if (name != null && name.isNotEmpty) {
      final lower = name.toLowerCase();
      if (RegExp(r'\.(exe|scr|bat|cmd|js|jar)$').hasMatch(lower)) {
        findings.add(
          Finding(
            drone: DroneId.scanner,
            title: 'Dangerous attachment type',
            detail:
                '"$name" is a program, not a document — '
                '${lower.split('.').last} files run code. No payroll or '
                'billing department sends those.',
            points: 34,
            evidence: name,
          ),
        );
      } else if (RegExp(
        r'\.(pdf|doc|docx|jpg|png)\.(zip|exe|scr)$',
      ).hasMatch(lower)) {
        findings.add(
          Finding(
            drone: DroneId.scanner,
            title: 'Double-extension attachment',
            detail:
                '"$name" hides its real type behind a friendly one — the '
                'part after the last dot is what actually opens.',
            points: 28,
            evidence: name,
          ),
        );
      } else {
        findings.add(
          Finding(
            drone: DroneId.scanner,
            title: 'Attachment present',
            detail:
                '"$name" — an attachment is only as safe as the sender. '
                'Read it together with Angler\'s domain check before '
                'opening.',
            points: 6,
            evidence: name,
          ),
        );
      }
    }
    return findings;
  }
}
